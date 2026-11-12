//! OS Unicode companion client. No regex/JSON crate or source-read scheduling lives here.
use std::{
    collections::{BTreeSet, HashMap},
    fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        mpsc, Arc, Mutex,
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
const MAX_BYTES: usize = 131072;
const MAX_UNITS: usize = 512;
static NONCE: AtomicU64 = AtomicU64::new(1);
#[derive(Clone, Debug)]
pub struct Memo {
    pub value: String,
    pub status: String,
}
struct Job {
    raw: String,
    epoch: u64,
    rules: Vec<u8>,
    missing: bool,
    cancel: Arc<AtomicBool>,
    helper: Option<PathBuf>,
}
struct Answer {
    raw: String,
    epoch: u64,
    memo: Memo,
}
pub(crate) type Runner =
    Arc<dyn Fn(&AtomicBool, &Path, Option<&Path>, &[u8], bool, &str) -> Memo + Send + Sync>;
pub struct Client {
    pub epoch: u64,
    rules_path: PathBuf,
    state: PathBuf,
    helper: Option<PathBuf>,
    auto_resolve: bool,
    helper_signature: String,
    bytes: Vec<u8>,
    missing: bool,
    failure: String,
    initialized: bool,
    next_poll: Instant,
    memo: HashMap<String, Memo>,
    pending: HashMap<String, bool>,
    jobs: mpsc::SyncSender<Job>,
    answers: mpsc::Receiver<Answer>,
    quit: Arc<AtomicBool>,
    epoch_cancel: Arc<AtomicBool>,
    workers: Vec<JoinHandle<()>>,
    sources: Vec<u8>,
    pub source_set_key: String,
    published_source_set_key: String,
}
fn absolute(p: &Path) -> PathBuf {
    if p.is_absolute() {
        p.to_path_buf()
    } else {
        std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join(p)
    }
}
pub fn rules_path() -> PathBuf {
    #[cfg(windows)]
    {
        let base = std::env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                PathBuf::from(std::env::var_os("USERPROFILE").unwrap_or_default())
                    .join("AppData/Local")
            });
        base.join("ChatGPT-TitleSync/title-rules.json")
    }
    #[cfg(not(windows))]
    {
        PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
            .join("Library/Application Support/ChatGPT-TitleSync/title-rules.json")
    }
}
pub fn companion_paths(exe: &Path) -> (Option<PathBuf>, Option<PathBuf>) {
    let dir = exe.parent().unwrap_or(Path::new("."));
    let (platform, name) = if cfg!(windows) {
        ("windows", "ChatGPT-TitleSync.Rules.exe")
    } else {
        ("macos", "chatgpt-titlesync-rules")
    };
    let helper = [
        dir.to_path_buf(),
        dir.join("../shared").join(platform),
        dir.join("../../../shared").join(platform),
        dir.join("shared").join(platform),
    ]
    .into_iter()
    .map(|p| p.join(name))
    .find(|p| p.is_file())
    .map(|p| absolute(&p));
    let help = [dir.to_path_buf(), dir.join(".."), dir.join("../../..")]
        .into_iter()
        .map(|p| p.join("docs/name-replacement.html"))
        .find(|p| p.is_file())
        .map(|p| absolute(&p));
    (helper, help)
}
impl Client {
    pub fn new(state: PathBuf) -> Self {
        let exe = std::env::current_exe().unwrap_or_default();
        let (helper, _) = companion_paths(&exe);
        let mut client = Self::at(state, rules_path(), helper, Arc::new(format_worker));
        client.auto_resolve = true;
        client
    }
    pub(crate) fn at(
        state: PathBuf,
        rules_path: PathBuf,
        helper: Option<PathBuf>,
        runner: Runner,
    ) -> Self {
        let state = absolute(&state);
        let rules_path = absolute(&rules_path);
        let (tx, rx) = mpsc::sync_channel::<Job>(256);
        let (at, ar) = mpsc::channel::<Answer>();
        let rx = Arc::new(Mutex::new(rx));
        let quit = Arc::new(AtomicBool::new(false));
        let mut workers = Vec::new();
        for _ in 0..4 {
            let (rx, answer, stop, run, state) = (
                rx.clone(),
                at.clone(),
                quit.clone(),
                runner.clone(),
                state.clone(),
            );
            workers.push(thread::spawn(move || {
                while !stop.load(Ordering::Relaxed) {
                    let job = { rx.lock().unwrap().recv_timeout(Duration::from_millis(30)) };
                    if let Ok(job) = job {
                        if job.cancel.load(Ordering::Relaxed) {
                            continue;
                        }
                        let memo = run(
                            &job.cancel,
                            &state,
                            job.helper.as_deref(),
                            &job.rules,
                            job.missing,
                            &job.raw,
                        );
                        let _ = answer.send(Answer {
                            raw: job.raw,
                            epoch: job.epoch,
                            memo,
                        });
                    }
                }
            }));
        }
        Self {
            epoch: 0,
            rules_path,
            state,
            helper,
            auto_resolve: false,
            helper_signature: String::new(),
            bytes: Vec::new(),
            missing: true,
            failure: String::new(),
            initialized: false,
            next_poll: Instant::now(),
            memo: HashMap::new(),
            pending: HashMap::new(),
            jobs: tx,
            answers: ar,
            quit,
            epoch_cancel: Arc::new(AtomicBool::new(false)),
            workers,
            sources: Vec::new(),
            source_set_key: String::new(),
            published_source_set_key: String::new(),
        }
    }
    #[cfg(test)]
    pub(crate) fn refresh_now(&mut self) {
        self.next_poll = Instant::now();
    }
    pub fn close(&mut self) {
        self.quit.store(true, Ordering::Relaxed);
        self.epoch_cancel.store(true, Ordering::Relaxed);
        for worker in self.workers.drain(..) {
            let _ = worker.join();
        }
    }
    pub fn poll(&mut self, names: &[String]) {
        if !self.initialized || Instant::now() >= self.next_poll {
            if self.auto_resolve {
                self.helper = std::env::current_exe()
                    .ok()
                    .and_then(|exe| companion_paths(&exe).0);
            }
            let helper_signature = match self.helper.as_deref() {
                Some(path) => match fs::metadata(path) {
                    Ok(m) => format!(
                        "{}|{:?}|{}|{}",
                        path.display(),
                        m.modified(),
                        m.len(),
                        m.is_file()
                    ),
                    Err(_) => format!("{}|missing", path.display()),
                },
                None => "missing".into(),
            };
            let (bytes, missing, failure) = match read_bounded(&self.rules_path, MAX_BYTES) {
                Ok(bytes) => (bytes, false, String::new()),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                    (Vec::new(), true, String::new())
                }
                Err(e) => (
                    Vec::new(),
                    false,
                    if e.kind() == std::io::ErrorKind::InvalidData {
                        "RulesTooLarge"
                    } else {
                        "RulesReadError"
                    }
                    .into(),
                ),
            };
            if !self.initialized
                || bytes != self.bytes
                || missing != self.missing
                || failure != self.failure
                || helper_signature != self.helper_signature
            {
                self.epoch_cancel.store(true, Ordering::Relaxed);
                self.epoch_cancel = Arc::new(AtomicBool::new(false));
                self.epoch += 1;
                self.bytes = bytes;
                self.missing = missing;
                self.failure = failure;
                self.helper_signature = helper_signature;
                self.initialized = true;
                self.memo.clear();
                self.pending.clear();
            }
            self.next_poll = Instant::now() + Duration::from_secs(1);
        }
        while let Ok(a) = self.answers.try_recv() {
            if a.epoch == self.epoch {
                self.pending.remove(&a.raw);
                self.memo.insert(a.raw, a.memo);
            }
        }
        let live: BTreeSet<String> = names.iter().cloned().collect();
        self.memo.retain(|name, _| live.contains(name));
        self.publish_sources(names);
    }
    pub fn display(&mut self, raw: &str) -> Option<String> {
        if !self.initialized {
            self.poll(&[raw.to_owned()]);
        }
        if self.missing || !self.failure.is_empty() {
            return Some(raw.to_owned());
        }
        if let Some(v) = self.memo.get(raw) {
            return Some(v.value.clone());
        }
        if !self.pending.contains_key(raw) {
            let job = Job {
                raw: raw.into(),
                epoch: self.epoch,
                rules: self.bytes.clone(),
                missing: self.missing,
                cancel: self.epoch_cancel.clone(),
                helper: self.helper.clone(),
            };
            match self.jobs.try_send(job) {
                Ok(()) => {
                    self.pending.insert(raw.into(), true);
                }
                Err(_) => return Some(raw.into()),
            }
        }
        None
    }
    fn publish_sources(&mut self, names: &[String]) {
        let mut names: Vec<_> = names.iter().filter(|s| !s.is_empty()).collect();
        names.sort();
        let mut packet = b"CTS1\0\0\0\0".to_vec();
        let mut count = 0u32;
        for raw in names {
            if let Ok(bytes) = encode_packet(raw) {
                if count >= 128 || packet.len() + 4 + bytes.len() > MAX_BYTES {
                    break;
                }
                packet.extend_from_slice(&((bytes.len() / 2) as u32).to_le_bytes());
                packet.extend(bytes);
                count += 1;
            }
        }
        packet[4..8].copy_from_slice(&count.to_le_bytes());
        if packet == self.sources && self.source_set_key == self.published_source_set_key {
            return;
        }
        if fs::create_dir_all(&self.state).is_err() {
            return;
        }
        let temp = self.state.join(format!(
            "title-rule-sources-{}-{}.tmp",
            std::process::id(),
            NONCE.fetch_add(1, Ordering::Relaxed)
        ));
        let result = (|| -> Result<(), String> {
            let mut f = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temp)
                .map_err(|e| e.to_string())?;
            f.write_all(&packet).map_err(|e| e.to_string())?;
            f.sync_all().map_err(|e| e.to_string())?;
            drop(f);
            replace(&temp, &self.state.join("title-rule-sources.bin"))
        })();
        let _ = fs::remove_file(&temp);
        if result.is_ok() {
            self.sources = packet;
            self.published_source_set_key = self.source_set_key.clone()
        }
    }
}
impl Drop for Client {
    fn drop(&mut self) {
        self.close();
    }
}
fn read_bounded(path: &Path, max: usize) -> std::io::Result<Vec<u8>> {
    let f = fs::File::open(path)?;
    let mut b = Vec::new();
    f.take((max + 1) as u64).read_to_end(&mut b)?;
    if b.len() > max {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "bounded file",
        ));
    }
    Ok(b)
}
fn encode_packet(s: &str) -> Result<Vec<u8>, String> {
    let units: Vec<_> = s.encode_utf16().collect();
    if units.len() > MAX_UNITS {
        return Err("units".into());
    }
    Ok(units.into_iter().flat_map(u16::to_le_bytes).collect())
}
fn decode_packet(b: &[u8]) -> Result<String, String> {
    if b.len() % 2 != 0 || b.len() > MAX_UNITS * 2 {
        return Err("packet".into());
    }
    let u: Vec<_> = b
        .chunks_exact(2)
        .map(|x| u16::from_le_bytes([x[0], x[1]]))
        .collect();
    String::from_utf16(&u).map_err(|_| "surrogate".into())
}
fn valid_display(s: &str) -> bool {
    !s.trim().is_empty()
        && !s.trim().eq_ignore_ascii_case("ChatGPT")
        && !s.chars().any(char::is_control)
        && s.encode_utf16().count() <= MAX_UNITS
}
fn owned_cleanup(state: &Path, dir: &Path) {
    if dir.is_absolute()
        && dir.parent() == Some(state)
        && dir
            .file_name()
            .and_then(|x| x.to_str())
            .map(|x| x.starts_with("title-rule-worker-"))
            .unwrap_or(false)
    {
        let _ = fs::remove_dir_all(dir);
    }
}
fn format_worker(
    cancel: &AtomicBool,
    state: &Path,
    helper: Option<&Path>,
    rules: &[u8],
    missing: bool,
    raw: &str,
) -> Memo {
    let fallback = |code: &str| Memo {
        value: raw.into(),
        status: format!("fallback:{code}"),
    };
    let input = match encode_packet(raw) {
        Ok(x) => x,
        Err(_) => return fallback("InvalidRaw"),
    };
    let helper = match helper {
        Some(p) => p,
        None => return fallback("CompanionMissing"),
    };
    if fs::create_dir_all(state).is_err() {
        return fallback("WorkerIO");
    }
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let dir = state.join(format!(
        "title-rule-worker-{}-{}-{}",
        std::process::id(),
        now,
        NONCE.fetch_add(1, Ordering::Relaxed)
    ));
    if fs::create_dir(&dir).is_err() {
        return fallback("WorkerIO");
    }
    let result = (|| {
        let rp = dir.join("rules.json");
        let ip = dir.join("input.bin");
        let op = dir.join("output.bin");
        let sp = dir.join("status.txt");
        if !missing && fs::write(&rp, rules).is_err() {
            return fallback("WorkerIO");
        }
        if fs::write(&ip, input).is_err() {
            return fallback("WorkerIO");
        }
        let mut command = Command::new(helper);
        command
            .args(["--format", "--rules"])
            .arg(&rp)
            .arg("--input")
            .arg(&ip)
            .arg("--output")
            .arg(&op)
            .arg("--status")
            .arg(&sp)
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x08000000);
        }
        let mut child = match command.spawn() {
            Ok(c) => c,
            Err(_) => return fallback("WorkerFailed"),
        };
        let start = Instant::now();
        let status = loop {
            match child.try_wait() {
                Ok(Some(s)) => break s,
                Err(_) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return fallback("WorkerFailed");
                }
                _ => {}
            }
            if cancel.load(Ordering::Relaxed) || start.elapsed() >= Duration::from_millis(1500) {
                let _ = child.kill();
                let _ = child.wait();
                return fallback("WorkerTimeout");
            }
            thread::sleep(Duration::from_millis(10));
        };
        let status_bytes = match read_bounded(&sp, 128) {
            Ok(b) => b,
            Err(_) => return fallback("WorkerProtocol"),
        };
        if !status_bytes.is_ascii() {
            return fallback("WorkerProtocol");
        }
        let code = String::from_utf8_lossy(&status_bytes).trim().to_owned();
        let value = match read_bounded(&op, MAX_UNITS * 2).and_then(|b| {
            decode_packet(&b)
                .map_err(|_| std::io::Error::new(std::io::ErrorKind::InvalidData, "packet"))
        }) {
            Ok(s) => s,
            Err(_) => return fallback("WorkerProtocol"),
        };
        if status.code() == Some(2) && code.starts_with("fallback:") && value == raw {
            return Memo {
                value: raw.into(),
                status: code,
            };
        }
        if status.code() != Some(0) || code != "ok" || !valid_display(&value) {
            return fallback("WorkerProtocol");
        }
        Memo {
            value,
            status: code,
        }
    })();
    owned_cleanup(state, &dir);
    result
}
#[cfg(windows)]
fn replace(a: &Path, b: &Path) -> Result<(), String> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "kernel32")]
    extern "system" {
        fn MoveFileExW(a: *const u16, b: *const u16, flags: u32) -> i32;
    }
    let a: Vec<_> = a.as_os_str().encode_wide().chain(Some(0)).collect();
    let b: Vec<_> = b.as_os_str().encode_wide().chain(Some(0)).collect();
    if unsafe { MoveFileExW(a.as_ptr(), b.as_ptr(), 1 | 8) } == 0 {
        Err(std::io::Error::last_os_error().to_string())
    } else {
        Ok(())
    }
}
#[cfg(not(windows))]
fn replace(a: &Path, b: &Path) -> Result<(), String> {
    fs::rename(a, b).map_err(|e| e.to_string())
}
pub fn open_editor(state: &Path) -> Result<(), String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let (helper, help) = companion_paths(&exe);
    let (helper, help) = (
        helper.ok_or("packaged name-replacement companion unavailable")?,
        help.ok_or("packaged name-replacement help unavailable")?,
    );
    let mut child = Command::new(helper)
        .arg("--edit")
        .arg("--rules")
        .arg(rules_path())
        .arg("--sources")
        .arg(absolute(state).join("title-rule-sources.bin"))
        .arg("--help")
        .arg(help)
        .spawn()
        .map_err(|e| e.to_string())?;
    thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unicode_packets_and_limits() {
        let s = "Example 示例 😀";
        assert_eq!(decode_packet(&encode_packet(s).unwrap()).unwrap(), s);
        assert!(decode_packet(&[0, 0xd8]).is_err());
        assert!(encode_packet(&"a".repeat(513)).is_err());
        assert!(!valid_display("ChatGPT"));
        assert!(!valid_display("a\nb"));
    }
    #[test]
    fn missing_rules_stays_identity_without_config() {
        let dir = std::env::temp_dir().join(format!(
            "cts-rules-fixture-{}-{}",
            std::process::id(),
            NONCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&dir).unwrap();
        let rules = dir.join("missing/title-rules.json");
        let mut c = Client::at(dir.clone(), rules.clone(), None, Arc::new(format_worker));
        c.poll(&["Example".into()]);
        assert_eq!(c.display("Example"), Some("Example".into()));
        assert!(!rules.exists());
        let packet = fs::read(dir.join("title-rule-sources.bin")).unwrap();
        assert_eq!(&packet[..4], b"CTS1");
        assert_eq!(u32::from_le_bytes(packet[4..8].try_into().unwrap()), 1);
        c.close();
    }
    #[test]
    #[ignore = "requires a private owned protocol fixture executable"]
    fn owned_worker_protocol_and_hard_deadline() {
        let helper =
            PathBuf::from(std::env::var_os("CTS_RULE_TEST_HELPER").expect("private fixture path"));
        let state = std::env::temp_dir().join(format!(
            "cts-own-rule-worker-{}-{}",
            std::process::id(),
            NONCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&state).unwrap();
        let cancel = AtomicBool::new(false);
        let raw = "Example 示例 😀";
        for mode in ["pass", "fallback", "invalid"] {
            let got = format_worker(&cancel, &state, Some(&helper), mode.as_bytes(), false, raw);
            assert_eq!(got.value, raw);
            if mode == "pass" {
                assert_eq!(got.status, "ok")
            } else {
                assert!(got.status.starts_with("fallback:"))
            }
        }
        let receipt = state.join("owned-child-pid.txt");
        let mode = format!("DELAY|{}", receipt.display());
        let start = Instant::now();
        let got = format_worker(&cancel, &state, Some(&helper), mode.as_bytes(), false, raw);
        assert_eq!(got.value, raw);
        assert_eq!(got.status, "fallback:WorkerTimeout");
        assert!(start.elapsed() < Duration::from_millis(2500));
        assert!(receipt.is_file());
        assert!(!fs::read_dir(&state)
            .unwrap()
            .filter_map(Result::ok)
            .any(|x| x.path().is_dir()
                && x.file_name()
                    .to_string_lossy()
                    .starts_with("title-rule-worker-")));
    }
}
