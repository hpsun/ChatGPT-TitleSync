// Optional ChatGPT native-caption presentation. UIA is confined to its child reader.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

namespace ChatGptTitle
{
    internal sealed class ChatGptTitleWindow
    {
        internal readonly long Hwnd;
        internal readonly int Pid;
        internal readonly string ProcessStartUtc, ClassName, ExePath;
        internal ChatGptTitleWindow(long hwnd, int pid, string processStartUtc, string className, string exePath)
        { Hwnd = hwnd; Pid = pid; ProcessStartUtc = processStartUtc; ClassName = className; ExePath = exePath; }
        internal string Key { get { return Hwnd + "|" + Pid + "|" + ProcessStartUtc + "|" + ClassName + "|" + ExePath.ToUpperInvariant(); } }
    }
    internal sealed class ChatGptHeaderReadResult
    {
        internal bool Success, Pending;
        internal long Seq;
        internal string ObservedUtc, SessionId;
        internal string Title, Locator, ErrorCode;
        internal static ChatGptHeaderReadResult Fail(string code) { return new ChatGptHeaderReadResult { ErrorCode = code }; }
    }
    internal interface IChatGptHeaderReader
    {
        ChatGptHeaderReadResult Read(ChatGptTitleWindow window, int timeoutMs, WaitHandle cancel);
    }
    internal interface IChatGptTitleWindows
    {
        IList<ChatGptTitleWindow> Enumerate();
        long ForegroundHwnd { get; }
        bool IsSame(ChatGptTitleWindow window);
        string GetCaption(ChatGptTitleWindow window);
        bool SetCaption(ChatGptTitleWindow window, string caption, out string error);
    }

    internal interface IChatGptActiveHeaderReader
    {
        ChatGptHeaderReadResult PollActive(ChatGptTitleWindow window);
        void StopActive();
    }

    internal interface IChatGptTimedHeaderReader { void SetIntervalMilliseconds(int milliseconds); }

    internal interface IChatGptNameRules
    {
        string Resolve(string raw);
        void PublishSources(IDictionary<string,string> sources);
    }
    internal interface IChatGptCaptionRules : IChatGptNameRules {}
    internal sealed class ChatGptWindowTitleMonitor : IDisposable
    {
        internal IChatGptNameRules NameRules { get; set; }
        string DisplayName(string raw){string display=NameRules==null?raw:NameRules.Resolve(raw);return NameRules is IChatGptCaptionRules?display:display+" — ChatGPT";}
        void RefreshOwnedDisplay(IList<ChatGptTitleWindow> candidates,int expected)
        {
            if(NameRules==null)return;
            foreach(var window in candidates)
            {
                Tracked state;Verified source;
                if(!tracked.TryGetValue(window.Key,out state)||!verified.TryGetValue(window.Key,out source)||state.LastWritten==null||state.ManualCaption!=null)continue;
                string current=windows.GetCaption(window);
                if(current!=state.LastWritten||!windows.IsSame(window))continue;
                string desired=DisplayName(source.Title);
                if(current!=desired)WriteCaption(state,current,desired,expected,windows.ForegroundHwnd==window.Hwnd,"DisplayRulesChanged");
            }
            NameRules.PublishSources(candidates.Where(window=>verified.ContainsKey(window.Key)).ToDictionary(window=>window.Key,window=>verified[window.Key].Title));
        }

        sealed class Tracked
        {
            internal ChatGptTitleWindow Window;
            internal string Original, LastWritten, ManualCaption, ReaderSession;
            internal bool HasOriginal;
            internal long LastSequence;
            internal DateTime RequireObservedAfterUtc;
        }
        sealed class Verified
        {
            internal ChatGptTitleWindow Window;
            internal string Title, LastWritten, Original, ManualCaption;
            internal bool HasOriginal;
            internal DateTime VerifiedUtc;
        }
        readonly Config config;
        readonly Func<bool> paused;
        readonly IChatGptHeaderReader reader;
        readonly IChatGptTitleWindows windows;
        readonly Func<DateTime> clock;
        readonly string logDirectory, cacheFile;
        readonly Dictionary<string, Tracked> tracked = new Dictionary<string, Tracked>();
        readonly Dictionary<string, Verified> verified = new Dictionary<string, Verified>();
        readonly Dictionary<string, DateTime> sourceAttempts = new Dictionary<string, DateTime>();
        readonly HashSet<string> resetManualKeys = new HashSet<string>();
        readonly Dictionary<string, DateTime> recentLogs = new Dictionary<string, DateTime>();
        readonly ManualResetEvent stop = new ManualResetEvent(false), abortRead = new ManualResetEvent(false);
        readonly AutoResetEvent wake = new AutoResetEvent(false);
        readonly object changes = new object(), scans = new object(), backgroundGate = new object();
        Thread worker, backgroundWorker;
        ManualResetEvent backgroundCancel;
        ChatGptTitleWindow backgroundWindow;
        ChatGptHeaderReadResult backgroundResult;
        bool backgroundDone;
        int backgroundRevision, revision, resetHolds, resetTiming;
        string activeKey, foregroundReadyKey;
        DateTime foregroundObservedUtc, nextForegroundPollUtc;
        bool cacheDirty;
        volatile bool disposed;
        internal ChatGptWindowTitleMonitor(Config settings, Func<bool> isPaused, string helperPath, string logs)
            : this(settings, isPaused, new ChatGptProcessHeaderReader(helperPath, logs), new NativeChatGptTitleWindows(), logs, delegate { return DateTime.UtcNow; }) { }
        internal ChatGptWindowTitleMonitor(Config settings, Func<bool> isPaused, IChatGptHeaderReader headerReader,
            IChatGptTitleWindows nativeWindows, string logs, Func<DateTime> utcClock)
        {
            if (settings == null || headerReader == null || nativeWindows == null || utcClock == null) throw new ArgumentNullException();
            config=settings;paused=isPaused??delegate{return false;};reader=headerReader;windows=nativeWindows;
            // Preserve the legacy private-cache filename for existing saved identities.
            logDirectory=Path.GetFullPath(logs);cacheFile=Path.Combine(logDirectory,"chatgpt-title-cache.json");clock=utcClock;
            LoadCache();
        }
        DateTime Now(){DateTime value=clock();return value.Kind==DateTimeKind.Unspecified?DateTime.SpecifyKind(value,DateTimeKind.Utc):value.ToUniversalTime();}
        bool Enabled{get{try{return !disposed&&!stop.WaitOne(0)&&config.ChatGptWindowTitleEnabled&&!paused();}catch{return false;}}}
        internal void Start(){lock(changes){if(disposed)throw new ObjectDisposedException("ChatGptWindowTitleMonitor");if(worker!=null)return;worker=new Thread(Work){IsBackground=true,Name="ChatGPT-TitleSync"};worker.Start();}}
        internal void Wake(){lock(changes){if(disposed)return;if(!config.ChatGptWindowTitleEnabled)Interlocked.Exchange(ref resetHolds,1);revision++;Interlocked.Exchange(ref resetTiming,1);abortRead.Set();wake.Set();}}
        void StopActiveReader(){IChatGptActiveHeaderReader active=reader as IChatGptActiveHeaderReader;if(active!=null)active.StopActive();activeKey=null;foregroundReadyKey=null;foregroundObservedUtc=DateTime.MinValue;nextForegroundPollUtc=DateTime.MinValue;}
        void CancelBackground(){lock(backgroundGate){if(backgroundCancel!=null)backgroundCancel.Set();}}
        void Work()
        {
            try{while(!stop.WaitOne(0)){Stopwatch tick=Stopwatch.StartNew();try{RunOnce();}catch{Log("WorkerFailed",null,"UnhandledIteration",true);}int wait=(int)Math.Max(1,1000-tick.ElapsedMilliseconds);if(WaitHandle.WaitAny(new WaitHandle[]{stop,wake},wait)==0)break;}}
            catch{Log("WorkerFailed",null,"UnhandledWorker",true);}
            finally{try{lock(scans){StopActiveReader();CancelBackground();SaveCache();RestoreAll("Stopped");SaveCache();}}catch{Log("RestoreFailed",null,"WorkerCleanup",true);}}
        }
        internal void RunOnce()
        {
            lock(scans)
            {
                if(disposed)return;
                if(!Enabled){StopActiveReader();CancelBackground();CollectBackground(null,0);RestoreAll("DisabledOrPaused");if(!config.ChatGptWindowTitleEnabled)ClearManualHolds();SaveCache();return;}
                if(Interlocked.Exchange(ref resetHolds,0)!=0){StopActiveReader();CancelBackground();RestoreAll("Reenabled");ClearManualHolds();}
                if(Interlocked.Exchange(ref resetTiming,0)!=0){StopActiveReader();CancelBackground();sourceAttempts.Clear();}
                int expected;lock(changes){expected=revision;abortRead.Reset();}
                IList<ChatGptTitleWindow> candidates;
                try{candidates=windows.Enumerate().GroupBy(w=>w.Key).Select(g=>g.First()).ToList();}
                catch{StopActiveReader();Log("EnumerateFailed",null,"NativeEnumeration",true);return;}
                long foreground=windows.ForegroundHwnd;
                ChatGptTitleWindow front=candidates.FirstOrDefault(w=>w.Hwnd==foreground);
                string nextKey=front==null?null:front.Key;
                if(activeKey!=nextKey){StopActiveReader();activeKey=nextKey;if(front!=null)CancelBackground();}
                CollectBackground(candidates,foreground);
                var liveKeys=new HashSet<string>(candidates.Select(w=>w.Key));
                foreach(string dead in tracked.Keys.Where(k=>!liveKeys.Contains(k)&&!windows.IsSame(tracked[k].Window)).ToArray())tracked.Remove(dead);
                foreach(string dead in sourceAttempts.Keys.Where(k=>!liveKeys.Contains(k)).ToArray())sourceAttempts.Remove(dead);
                foreach(ChatGptTitleWindow window in candidates)
                {
                    if(front!=null&&window.Key==front.Key)continue;
                    MaintainBackgroundCaption(window,expected);
                }
                if(front!=null&&windows.ForegroundHwnd==foreground)
                {
                    DateTime tickNow=Now();int period=Math.Max(1000,Math.Min(3600000,config.ChatGptTitlePollMilliseconds));
                    if(reader is IChatGptActiveHeaderReader||period<=1000||tickNow>=nextForegroundPollUtc||foregroundReadyKey!=front.Key)
                    {ServiceForeground(front,expected);nextForegroundPollUtc=tickNow.AddMilliseconds(period);}
                }
                else StopActiveReader();
                if(Allowed(expected))StartBackgroundIfDue(candidates,front,expected);
                if(Allowed(expected))RefreshOwnedDisplay(candidates,expected);
                SaveCache();
            }
        }
        Tracked State(ChatGptTitleWindow window,string current)
        {
            Tracked state;
            if(tracked.TryGetValue(window.Key,out state))return state;
            state=new Tracked{Window=window};Verified cache;
            if(verified.TryGetValue(window.Key,out cache))
            {
                if(cache.LastWritten!=null&&cache.LastWritten==current){state.LastWritten=cache.LastWritten;state.Original=cache.Original;state.HasOriginal=cache.HasOriginal;}
                if(!resetManualKeys.Remove(window.Key)&&!GenericCaption(current)&&(cache.ManualCaption!=null||cache.LastWritten!=current))state.ManualCaption=current;
            }
            tracked.Add(window.Key,state);return state;
        }
        void ObserveNative(Tracked state,string current,bool foreground)
        {
            if(state.ManualCaption!=null)
            {
                if(GenericCaption(current)){state.ManualCaption=null;UpdateCachedLease(state);if(foreground)RequireFresh(state);}
                else{state.ManualCaption=current;UpdateCachedLease(state);return;}
            }
            if(state.LastWritten!=null&&current!=state.LastWritten)
            {
                ReleaseOwnership(state);
                if(GenericCaption(current)){if(foreground)RequireFresh(state);}
                else state.ManualCaption=current;
                UpdateCachedLease(state);
            }
        }
        void MaintainBackgroundCaption(ChatGptTitleWindow window,int expected)
        {
            try
            {
                if(!Allowed(expected)||windows.ForegroundHwnd==window.Hwnd||!windows.IsSame(window))return;
                string current=windows.GetCaption(window);if(current==null)return;
                Tracked state=State(window,current);ObserveNative(state,current,false);
                Verified cache;
                if(state.ManualCaption!=null||!verified.TryGetValue(window.Key,out cache))return;
                if(!GenericCaption(current)&&(state.LastWritten==null||current!=state.LastWritten))return;
                string desired=DisplayName(cache.Title);
                if(current!=desired)WriteCaption(state,current,desired,expected,false,"CacheReapplied");
            }
            catch{Log("Skipped",window,"NativeBackgroundFailed",true);}
        }
        void ServiceForeground(ChatGptTitleWindow window,int expected)
        {
            try
            {
                if(!Allowed(expected)||windows.ForegroundHwnd!=window.Hwnd||!windows.IsSame(window))return;
                string current=windows.GetCaption(window);if(current==null)return;
                Tracked state=State(window,current);ObserveNative(state,current,true);
                IChatGptTimedHeaderReader timed=reader as IChatGptTimedHeaderReader;if(timed!=null)timed.SetIntervalMilliseconds(config.ChatGptTitlePollMilliseconds);
                IChatGptActiveHeaderReader live=reader as IChatGptActiveHeaderReader;
                ChatGptHeaderReadResult result=live!=null?live.PollActive(window):reader.Read(window,4000,abortRead);
                if(!Allowed(expected)||windows.ForegroundHwnd!=window.Hwnd){StopActiveReader();if(!Enabled)RestoreAll("DisabledOrPaused");return;}
                if(result!=null&&result.Pending)
                {if(foregroundReadyKey!=window.Key)CancelBackground();return;}
                if(result==null||!result.Success||String.IsNullOrWhiteSpace(result.Locator))
                {foregroundReadyKey=null;CancelBackground();Log("Skipped",window,ReaderFailure(result),true);return;}
                DateTime observed=Now();
                if(live!=null)
                {
                    if(String.IsNullOrEmpty(result.SessionId)||result.Seq<=0)return;
                    if(state.ReaderSession!=result.SessionId){state.ReaderSession=result.SessionId;state.LastSequence=0;}
                    if(result.Seq<=state.LastSequence)return;
                    DateTimeOffset instant;
                    if(!DateTimeOffset.TryParse(result.ObservedUtc,out instant)||instant.UtcDateTime<state.RequireObservedAfterUtc||instant.UtcDateTime<Now().AddSeconds(-4)||instant.UtcDateTime>Now().AddSeconds(5))return;
                    observed=instant.UtcDateTime;state.LastSequence=result.Seq;
                }
                foregroundReadyKey=window.Key;foregroundObservedUtc=observed;sourceAttempts[window.Key]=Now();
                string title=CleanTitle(result.Title);
                if(GenericTitle(title)){ForgetVerified(window.Key);RestoreOne(window.Key,"GenericHome");return;}
                if(!ValidTitle(title)){Log("Skipped",window,"HeaderInvalid",true);return;}
                RememberVerified(window,title,observed);
                if(state.ManualCaption!=null)return;
                WriteCaption(state,current,DisplayName(title),expected,true,"Changed");
            }
            catch{foregroundReadyKey=null;CancelBackground();Log("Skipped",window,"ReaderException",true);}
        }
        void WriteCaption(Tracked state,string expectedCaption,string desired,int expectedRevision,bool foreground,string kind)
        {
            lock(changes)
            {
                if(!Allowed(expectedRevision)||((windows.ForegroundHwnd==state.Window.Hwnd)!=foreground)||!windows.IsSame(state.Window))return;
                string latest=windows.GetCaption(state.Window);
                if(latest!=expectedCaption){ObserveNative(state,latest,foreground);if(!GenericCaption(latest)){ReleaseOwnership(state);state.ManualCaption=latest;UpdateCachedLease(state);}else if(foreground)RequireFresh(state);return;}
                if(!foreground&&!GenericCaption(latest)&&(state.LastWritten==null||latest!=state.LastWritten))return;
                if(state.ManualCaption!=null||latest==desired)return;
                if(!state.HasOriginal){state.Original=latest;state.HasOriginal=true;}
                if((windows.ForegroundHwnd==state.Window.Hwnd)!=foreground)return;
                string error;bool ok=windows.SetCaption(state.Window,desired,out error);string back=windows.GetCaption(state.Window);
                if(back==desired){state.LastWritten=desired;state.RequireObservedAfterUtc=DateTime.MinValue;UpdateCachedLease(state);}
                if(!ok||back!=desired){Log("Skipped",state.Window,"NativeWriteFailed",true);return;}
                Log(kind,state.Window,Fingerprint(desired),false);
            }
        }
        void StartBackgroundIfDue(IList<ChatGptTitleWindow> candidates,ChatGptTitleWindow foreground,int expected)
        {
            if(foreground!=null&&(foregroundReadyKey!=foreground.Key||windows.ForegroundHwnd!=foreground.Hwnd))return;
            if(foreground==null&&candidates.Any(w=>w.Hwnd==windows.ForegroundHwnd))return;
            lock(backgroundGate)
            {
                if(backgroundWorker!=null)return;
                int interval=Math.Max(5,Math.Min(3600,config.ChatGptTitleBackgroundRefreshSeconds));DateTime now=Now();
                long actualForeground=windows.ForegroundHwnd;
                ChatGptTitleWindow window=candidates.Where(w=>(foreground==null||w.Key!=foreground.Key)&&w.Hwnd!=actualForeground)
                    .Where(w=>!sourceAttempts.ContainsKey(w.Key)||(now-sourceAttempts[w.Key]).TotalSeconds>=interval)
                    .OrderBy(w=>sourceAttempts.ContainsKey(w.Key)?sourceAttempts[w.Key]:DateTime.MinValue).FirstOrDefault();
                if(window==null)return;
                sourceAttempts[window.Key]=now;backgroundWindow=window;backgroundRevision=expected;backgroundResult=null;backgroundDone=false;
                ManualResetEvent cancel=new ManualResetEvent(false);backgroundCancel=cancel;
                backgroundWorker=new Thread(delegate()
                {
                    ChatGptHeaderReadResult result;
                    try{result=reader.Read(window,10000,cancel);}catch{result=ChatGptHeaderReadResult.Fail("ReaderException");}
                    lock(backgroundGate){backgroundResult=result;backgroundDone=true;}
                }){IsBackground=true,Name="ChatGPT background title snapshot"};
                backgroundWorker.Start();
            }
        }
        void CollectBackground(IList<ChatGptTitleWindow> candidates,long foreground)
        {
            ChatGptTitleWindow window=null;ChatGptHeaderReadResult result=null;bool cancelled=false;int version=0;
            lock(backgroundGate)
            {
                if(backgroundWorker==null||!backgroundDone||backgroundWorker.IsAlive)return;
                window=backgroundWindow;result=backgroundResult;version=backgroundRevision;cancelled=backgroundCancel.WaitOne(0);
                backgroundCancel.Dispose();backgroundCancel=null;backgroundWorker=null;backgroundWindow=null;backgroundResult=null;backgroundDone=false;
            }
            if(cancelled||!Enabled||version!=Interlocked.CompareExchange(ref revision,0,0)||candidates==null||window==null||window.Hwnd==foreground)return;
            if(!candidates.Any(w=>w.Key==window.Key)||!windows.IsSame(window))return;
            if(result==null||!result.Success||String.IsNullOrWhiteSpace(result.Locator)){Log("Skipped",window,"BackgroundHeaderUnavailable",true);return;}
            DateTimeOffset resultTime;
            if(!String.IsNullOrEmpty(result.ObservedUtc)&&(!DateTimeOffset.TryParse(result.ObservedUtc,out resultTime)||resultTime.UtcDateTime<Now().AddSeconds(-15)||resultTime.UtcDateTime>Now().AddSeconds(5)))return;
            string title=CleanTitle(result.Title);
            if(GenericTitle(title)){ForgetVerified(window.Key);RestoreOne(window.Key,"BackgroundGenericHome");return;}
            if(!ValidTitle(title))return;
            DateTime observed=Now();DateTimeOffset stamp;
            if(!String.IsNullOrEmpty(result.ObservedUtc)&&DateTimeOffset.TryParse(result.ObservedUtc,out stamp))observed=stamp.UtcDateTime;
            RememberVerified(window,title,observed);
        }
        void RememberVerified(ChatGptTitleWindow window,string title,DateTime observed)
        {
            Verified item;
            if(!verified.TryGetValue(window.Key,out item)){item=new Verified{Window=window};verified.Add(window.Key,item);cacheDirty=true;}
            if(item.Title!=title){item.Title=title;cacheDirty=true;}
            item.VerifiedUtc=observed;
            while(verified.Count>512){string oldest=verified.OrderBy(x=>x.Value.VerifiedUtc).First().Key;verified.Remove(oldest);cacheDirty=true;}
        }
        void UpdateCachedLease(Tracked state)
        {
            Verified item;if(!verified.TryGetValue(state.Window.Key,out item))return;
            if(item.LastWritten!=state.LastWritten||item.Original!=state.Original||item.HasOriginal!=state.HasOriginal||item.ManualCaption!=state.ManualCaption)
            {item.LastWritten=state.LastWritten;item.Original=state.Original;item.HasOriginal=state.HasOriginal;item.ManualCaption=state.ManualCaption;cacheDirty=true;}
        }
        void ForgetVerified(string key){if(verified.Remove(key))cacheDirty=true;}
        void ClearManualHolds(){foreach(Tracked state in tracked.Values)state.ManualCaption=null;foreach(Verified item in verified.Values){resetManualKeys.Add(item.Window.Key);if(item.ManualCaption!=null){item.ManualCaption=null;cacheDirty=true;}}}
        void LoadCache()
        {
            try
            {
                if(!File.Exists(cacheFile)||new FileInfo(cacheFile).Length>2097152)return;
                var data=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(cacheFile,Encoding.UTF8));
                if(data==null||!data.ContainsKey("Entries"))return;
                var entries=data["Entries"] as System.Collections.IEnumerable;if(entries==null)return;
                foreach(object value in entries)
                {
                    var row=value as Dictionary<string,object>;if(row==null||verified.Count>=512)continue;
                    long hwnd=Convert.ToInt64(row["Hwnd"]);int pid=Convert.ToInt32(row["Pid"]);string born=Convert.ToString(row["ProcessStartUtc"]),cls=Convert.ToString(row["ClassName"]),path=Convert.ToString(row["ExePath"]),title=Convert.ToString(row["Title"]);DateTimeOffset at,created;
                    if(hwnd<=0||pid<=0||cls!="Chrome_WidgetWin_1"||!String.Equals(Path.GetFileName(path),"ChatGPT.exe",StringComparison.OrdinalIgnoreCase)||!DateTimeOffset.TryParse(born,out created)||!ValidTitle(title)||GenericTitle(title))continue;
                    var window=new ChatGptTitleWindow(hwnd,pid,born,cls,path);var item=new Verified{Window=window,Title=title,VerifiedUtc=DateTime.MinValue};
                    if(row.ContainsKey("VerifiedUtc")&&DateTimeOffset.TryParse(Convert.ToString(row["VerifiedUtc"]),out at))item.VerifiedUtc=at.UtcDateTime;
                    item.LastWritten=row.ContainsKey("LastWritten")?Convert.ToString(row["LastWritten"]):null;
                    item.Original=row.ContainsKey("Original")?Convert.ToString(row["Original"]):null;
                    item.ManualCaption=row.ContainsKey("ManualCaption")?Convert.ToString(row["ManualCaption"]):null;
                    item.HasOriginal=row.ContainsKey("HasOriginal")&&Convert.ToBoolean(row["HasOriginal"]);
                    if(String.IsNullOrEmpty(item.LastWritten))item.LastWritten=null;if(String.IsNullOrEmpty(item.ManualCaption))item.ManualCaption=null;
                    verified[window.Key]=item;
                }
            }
            catch{Log("CacheLoadFailed",null,"InvalidCache",true);}
        }
        void SaveCache()
        {
            if(!cacheDirty)return;
            try
            {
                Directory.CreateDirectory(logDirectory);string temp=cacheFile+".tmp";
                var entries=verified.Values.Select(v=>new{v.Window.Hwnd,v.Window.Pid,v.Window.ProcessStartUtc,v.Window.ClassName,v.Window.ExePath,v.Title,VerifiedUtc=v.VerifiedUtc.ToString("o"),v.LastWritten,v.Original,v.HasOriginal,v.ManualCaption}).ToArray();
                File.WriteAllText(temp,new JavaScriptSerializer().Serialize(new{Version=1,Entries=entries}),new UTF8Encoding(false));
                if(File.Exists(cacheFile))File.Replace(temp,cacheFile,null);else File.Move(temp,cacheFile);cacheDirty=false;
            }
            catch{Log("CacheSaveFailed",null,"CacheWriteFailed",true);}
        }
        void RequireFresh(Tracked state){state.RequireObservedAfterUtc=Now();}
        static string CleanTitle(string title){return new String((title??"").Where(c=>!Char.IsControl(c)).ToArray());}
        static bool GenericTitle(string title){return String.IsNullOrWhiteSpace(title)||String.Equals(title.Trim(),"ChatGPT",StringComparison.OrdinalIgnoreCase);}
        static bool GenericCaption(string caption){return String.Equals((caption??"").Trim(),"ChatGPT",StringComparison.OrdinalIgnoreCase);}
        bool Allowed(int expected){return Enabled&&!abortRead.WaitOne(0)&&expected==Interlocked.CompareExchange(ref revision,0,0);}
        static string ReaderFailure(ChatGptHeaderReadResult r){string code=r==null?null:r.ErrorCode;switch(code){case "ReaderTimeout":case "ReaderIdentityOrHeaderUnavailable":case "ReaderFailed":case "ReaderOutputTooLarge":case "ReaderException":case "Cancelled":case "HelperMissing":return code;default:return "HeaderUnavailable";}}
        static bool ValidTitle(string title){return !String.IsNullOrWhiteSpace(title)&&title.Length<=240&&!title.Any(Char.IsControl);}
        static void ReleaseOwnership(Tracked state){state.LastWritten=null;state.Original=null;state.HasOriginal=false;}
        void RestoreAll(string reason){foreach(string key in tracked.Keys.ToArray())RestoreOne(key,reason);}
        void RestoreOne(string key,string reason)
        {
            Tracked state;if(!tracked.TryGetValue(key,out state))return;
            try
            {
                if(!state.HasOriginal||state.LastWritten==null||!windows.IsSame(state.Window)){tracked.Remove(key);return;}
                string current=windows.GetCaption(state.Window);
                if(current!=state.LastWritten){ReleaseOwnership(state);state.ManualCaption=GenericCaption(current)?null:current;UpdateCachedLease(state);Log("RestoreSkipped",state.Window,"ExternalCaptionChanged",true);tracked.Remove(key);return;}
                string error;if(windows.SetCaption(state.Window,state.Original,out error)&&windows.GetCaption(state.Window)==state.Original){Log("Restored",state.Window,reason,false);tracked.Remove(key);}else Log("RestoreFailed",state.Window,"NativeWriteFailed",true);
            }
            catch{Log("RestoreFailed",state.Window,"NativeException",true);}
        }
        static string Fingerprint(string caption){using(SHA256 hash=SHA256.Create())return BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(caption))).Replace("-","").Substring(0,16);}
        void Log(string kind,ChatGptTitleWindow window,string code,bool deduplicate)
        {
            try{DateTime now=Now();string key=kind+"|"+(window==null?"":window.Key)+"|"+code;DateTime last;if(deduplicate&&recentLogs.TryGetValue(key,out last)&&(now-last).TotalSeconds<30)return;recentLogs[key]=now;Directory.CreateDirectory(logDirectory);string file=Path.Combine(logDirectory,"chatgpt-window-title_"+now.AddHours(8).ToString("yyyyMMdd",CultureInfo.InvariantCulture)+".jsonl");string json=new JavaScriptSerializer().Serialize(new{Utc=now.ToString("o"),Kind=kind,Pid=window==null?0:window.Pid,Hwnd=window==null?0:window.Hwnd,Code=code});File.AppendAllText(file,json+Environment.NewLine,new UTF8Encoding(false));}catch{}
        }
        public void Dispose()
        {
            Thread running,bg;lock(changes){if(disposed)return;stop.Set();abortRead.Set();wake.Set();running=worker;}CancelBackground();
            if(running!=null&&running!=Thread.CurrentThread&&!running.Join(12000))return;
            lock(backgroundGate){bg=backgroundWorker;}if(bg!=null&&bg!=Thread.CurrentThread)bg.Join(2000);
            lock(scans){StopActiveReader();SaveCache();RestoreAll("Disposed");SaveCache();disposed=true;}
            lock(backgroundGate){if(backgroundWorker==null||!backgroundWorker.IsAlive){if(backgroundCancel!=null)backgroundCancel.Dispose();backgroundCancel=null;backgroundWorker=null;}}
            stop.Dispose();abortRead.Dispose();wake.Dispose();
        }
    }
    internal sealed class NativeChatGptTitleWindows : IChatGptTitleWindows
    {
        delegate bool EnumCallback(IntPtr window,IntPtr state);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumCallback callback,IntPtr state);
        [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
        [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint flags);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int length);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int length);
        [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, string text, uint flags, uint timeout, out UIntPtr result);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        public long ForegroundHwnd { get { return GetForegroundWindow().ToInt64(); } }
        [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessTimes(IntPtr process, out long created, out long exited, out long kernel, out long user);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder path, ref int length);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        sealed class ProcessIdentity { internal string Born, Image; }
        static ProcessIdentity ReadProcess(uint pid)
        {
            // Query the held process directly; module enumeration is unnecessary here.
            IntPtr handle=OpenProcess(0x1000,false,pid);
            if(handle==IntPtr.Zero)return null;
            try
            {
                long born,exited,kernel,user;
                if(!GetProcessTimes(handle,out born,out exited,out kernel,out user)||born<=0||exited!=0)return null;
                StringBuilder path=new StringBuilder(32768);int length=path.Capacity;
                if(!QueryFullProcessImageName(handle,0,path,ref length)||length<=0)return null;
                return new ProcessIdentity{Born=DateTime.FromFileTimeUtc(born).ToString("o",CultureInfo.InvariantCulture),Image=Path.GetFullPath(path.ToString())};
            }
            finally{CloseHandle(handle);}
        }
        internal ChatGptTitleWindow Capture(long handle){return Capture(handle,null);}
        ChatGptTitleWindow Capture(long handle,Dictionary<uint,ProcessIdentity> frame)
        {
            IntPtr window=new IntPtr(handle);
            if(!IsWindow(window)||GetAncestor(window,2)!=window)return null;
            uint pid;GetWindowThreadProcessId(window,out pid);
            StringBuilder name=new StringBuilder(256);
            if(pid==0||GetClassName(window,name,name.Capacity)<=0)return null;
            ProcessIdentity process;
            if(frame==null)process=ReadProcess(pid);
            else if(!frame.TryGetValue(pid,out process)){process=ReadProcess(pid);frame[pid]=process;}
            if(process==null)return null;
            uint after;GetWindowThreadProcessId(window,out after);
            if(after!=pid||!IsWindow(window))return null;
            return new ChatGptTitleWindow(handle,(int)pid,process.Born,name.ToString(),process.Image);
        }
        public IList<ChatGptTitleWindow> Enumerate()
        {
            List<ChatGptTitleWindow> found=new List<ChatGptTitleWindow>();
            Dictionary<uint,ProcessIdentity> frame=new Dictionary<uint,ProcessIdentity>();
            EnumWindows(delegate(IntPtr handle,IntPtr ignored)
            {
                try
                {
                    if(!IsWindowVisible(handle))return true;
                    StringBuilder cls=new StringBuilder(256);GetClassName(handle,cls,cls.Capacity);
                    if(cls.ToString()!="Chrome_WidgetWin_1")return true;
                    ChatGptTitleWindow identity=Capture(handle.ToInt64(),frame);
                    if(identity!=null&&String.Equals(Path.GetFileName(identity.ExePath),"ChatGPT.exe",StringComparison.OrdinalIgnoreCase))found.Add(identity);
                }
                catch { }
                return true;
            },IntPtr.Zero);
            return found;
        }
        public bool IsSame(ChatGptTitleWindow window)
        {
            try { ChatGptTitleWindow current = Capture(window.Hwnd); return current != null && current.Key == window.Key; }
            catch { return false; }
        }
        public string GetCaption(ChatGptTitleWindow window)
        {
            if (!IsSame(window)) return null;
            StringBuilder text = new StringBuilder(2048);
            GetWindowText(new IntPtr(window.Hwnd), text, text.Capacity);
            return text.ToString();
        }
        public bool SetCaption(ChatGptTitleWindow window, string caption, out string error)
        {
            error = null;
            if (caption == null || caption.Length > 1024 || !IsSame(window)) { error = "IdentityOrCaptionInvalid"; return false; }
            UIntPtr result;
            IntPtr sent = SendMessageTimeout(new IntPtr(window.Hwnd), 0x000C, UIntPtr.Zero, caption, 0x0023, 300, out result);
            if (sent == IntPtr.Zero || result == UIntPtr.Zero) { error = "SetTextRejectedOrTimedOut"; return false; }
            if (!IsSame(window) || GetCaption(window) != caption) { error = "SetTextReadbackMismatch"; return false; }
            return true;
        }
    }

    internal sealed class ChatGptProcessHeaderReader : IChatGptHeaderReader, IChatGptActiveHeaderReader, IChatGptTimedHeaderReader
    {
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessTimes(IntPtr handle, out long created, out long exited, out long kernel, out long user);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr handle, uint flags, StringBuilder path, ref int length);
        [DllImport("kernel32.dll", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr handle, out uint code);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateProcess(IntPtr handle, uint code);
        [DllImport("kernel32.dll", EntryPoint="CreateFileW", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenImageFile(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern uint GetFinalPathNameByHandle(IntPtr handle, StringBuilder path, uint length, uint flags);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        static string CanonicalImage(string path)
        {
            IntPtr file = OpenImageFile(path, 0, 7, IntPtr.Zero, 3, 0, IntPtr.Zero);
            if (file == new IntPtr(-1)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            try
            {
                StringBuilder name = new StringBuilder(32768);
                uint length = GetFinalPathNameByHandle(file, name, (uint)name.Capacity, 0);
                if (length == 0 || length >= name.Capacity) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                string value = name.ToString();
                if (value.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) return @"\\" + value.Substring(8);
                return value.StartsWith(@"\\?\", StringComparison.Ordinal) ? value.Substring(4) : value;
            }
            finally { CloseHandle(file); }
        }
        readonly string helperPath, workDirectory;
        internal ChatGptProcessHeaderReader(string helper, string logs)
        // Keep the legacy worker directory to preserve private runtime-path compatibility.
        { helperPath = Path.GetFullPath(helper); workDirectory = Path.Combine(Path.GetFullPath(logs), "chatgpt-title-readers"); }
        readonly object activeGate = new object();
        Process activeChild;
        IntPtr activeHandle = IntPtr.Zero, activeJob = IntPtr.Zero;
        ChatGptTitleWindow activeWindow;
        string activeOutput, activeSession;
        long activeSequence, activeHeartbeatSequence;
        int sourceIntervalMilliseconds=2000;
        public void SetIntervalMilliseconds(int milliseconds){int value=Math.Max(1000,Math.Min(3600000,milliseconds));lock(activeGate){if(sourceIntervalMilliseconds!=value){StopActiveCore();sourceIntervalMilliseconds=value;}}}
        bool activeReady, activeTimedOut;
        Stopwatch activeProgress;
        Timer activeDeadline;
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr security, string name);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref JobLimits information, uint length);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [StructLayout(LayoutKind.Sequential)] struct JobBasicLimits
        { internal long ProcessTime, JobTime; internal uint Flags; internal UIntPtr MinWorkingSet, MaxWorkingSet; internal uint ActiveProcesses; internal UIntPtr Affinity; internal uint Priority, Scheduling; }
        [StructLayout(LayoutKind.Sequential)] struct JobIoCounters
        { internal ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
        [StructLayout(LayoutKind.Sequential)] struct JobLimits
        { internal JobBasicLimits Basic; internal JobIoCounters Io; internal UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory; }
        internal static string ActiveWatchMode { get { return "foreground-fresh-with-native-background-cache"; } }
        int ActiveDeadlineMilliseconds { get { return activeReady ? 4000 : 10000; } }
        public ChatGptHeaderReadResult PollActive(ChatGptTitleWindow window)
        {
            lock (activeGate)
            {
                if (window == null) { StopActiveCore(); return PendingResult(); }
                try
                {
                    if (activeWindow == null || activeWindow.Key != window.Key)
                    { StopActiveCore(); StartActive(window); }
                    ObserveHeartbeat();
                    if (activeTimedOut || activeProgress.ElapsedMilliseconds >= ActiveDeadlineMilliseconds)
                    { StopActiveCore(); return ChatGptHeaderReadResult.Fail("ReaderTimeout"); }
                    if (WaitForSingleObject(activeHandle, 0) == 0)
                    { uint exit; bool normal=GetExitCodeProcess(activeHandle,out exit)&&exit==0; StopActiveCore(); return normal?PendingResult():ChatGptHeaderReadResult.Fail("ReaderFailed"); }
                    if (!File.Exists(activeOutput)) return PendingResult();
                    string json;
                    try
                    {
                        using (FileStream stream = new FileStream(activeOutput, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                        {
                            if (stream.Length > 32768) { StopActiveCore(); return ChatGptHeaderReadResult.Fail("ReaderOutputTooLarge"); }
                            using (StreamReader text = new StreamReader(stream, Encoding.UTF8)) json = text.ReadToEnd();
                        }
                    }
                    catch (IOException) { return PendingResult(); }
                    Dictionary<string, object> value;
                    try { value = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(json); }
                    catch (ArgumentException) { return PendingResult(); }
                    DateTimeOffset expected, observedIdentity, observed;
                    if (value == null || !value.ContainsKey("Seq") || !value.ContainsKey("ObservedUtc") ||
                        Convert.ToInt64(value["Hwnd"]) != window.Hwnd || Convert.ToInt32(value["Pid"]) != window.Pid ||
                        Convert.ToString(value["ClassName"]) != window.ClassName ||
                        !DateTimeOffset.TryParse(window.ProcessStartUtc, out expected) ||
                        !DateTimeOffset.TryParse(Convert.ToString(value["ProcessStartUtc"]), out observedIdentity) || expected != observedIdentity ||
                        !DateTimeOffset.TryParse(Convert.ToString(value["ObservedUtc"]), out observed))
                    { StopActiveCore(); return ChatGptHeaderReadResult.Fail("ReaderIdentityOrHeaderUnavailable"); }
                    long seq = Convert.ToInt64(value["Seq"]);
                    long sourceSeq=value.ContainsKey("SourceSeq")?Convert.ToInt64(value["SourceSeq"]):seq;
                    double age = (DateTimeOffset.UtcNow - observed).TotalMilliseconds;
                    if (sourceSeq <= activeSequence || sourceSeq <= 0 || age > 4000 || age < -5000) return PendingResult();
                    activeSequence = sourceSeq;
                    bool success = value.ContainsKey("Success") && Convert.ToBoolean(value["Success"]);
                    bool pending = value.ContainsKey("Pending") && Convert.ToBoolean(value["Pending"]);
                    if (success || (activeReady && !pending))
                    { activeReady |= success; if(seq>activeHeartbeatSequence){activeHeartbeatSequence=seq;activeProgress.Restart();} }
                    if (pending) return PendingResult();
                    if (!success) return ChatGptHeaderReadResult.Fail("HeaderUnavailable");
                    if (!value.ContainsKey("Title") || !value.ContainsKey("Locator") || String.IsNullOrWhiteSpace(Convert.ToString(value["Locator"])))
                        return ChatGptHeaderReadResult.Fail("HeaderUnavailable");
                    return new ChatGptHeaderReadResult { Success=true, Title=Convert.ToString(value["Title"]), Locator=Convert.ToString(value["Locator"]),
                        Seq=sourceSeq, ObservedUtc=observed.ToUniversalTime().ToString("o"), SessionId=activeSession };
                }
                catch
                { StopActiveCore(); return ChatGptHeaderReadResult.Fail("ReaderException"); }
            }
        }
        ChatGptHeaderReadResult PendingResult()
        { return new ChatGptHeaderReadResult { Pending=true, SessionId=activeSession }; }
        void StartActive(ChatGptTitleWindow window)
        {
            if (!File.Exists(helperPath)) throw new FileNotFoundException("Reader helper unavailable");
            Directory.CreateDirectory(workDirectory);
            long ownerBorn, exited, kernel, user; int ownerPid;
            using (Process owner = Process.GetCurrentProcess())
            {
                ownerPid=owner.Id;
                if (!GetProcessTimes(owner.Handle, out ownerBorn, out exited, out kernel, out user)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            }
            activeSession=Guid.NewGuid().ToString("N"); activeOutput=Path.Combine(workDirectory,activeSession+".json");
            activeWindow=window; activeSequence=0; activeHeartbeatSequence=0; activeReady=false; activeTimedOut=false; activeProgress=Stopwatch.StartNew();
            activeJob=CreateJobObject(IntPtr.Zero,null);
            if (activeJob==IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            JobLimits limits=new JobLimits(); limits.Basic.Flags=0x2000;
            if (!SetInformationJobObject(activeJob,9,ref limits,(uint)Marshal.SizeOf(typeof(JobLimits)))) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            ProcessStartInfo info=new ProcessStartInfo(helperPath,"--watch --hwnd "+window.Hwnd.ToString(CultureInfo.InvariantCulture)+
                " --output "+Quote(activeOutput)+" --owner-pid "+ownerPid.ToString(CultureInfo.InvariantCulture)+" --owner-born "+ownerBorn.ToString(CultureInfo.InvariantCulture)+" --interval-ms "+sourceIntervalMilliseconds.ToString(CultureInfo.InvariantCulture));
            info.UseShellExecute=false;info.CreateNoWindow=true;info.WindowStyle=ProcessWindowStyle.Hidden;
            activeChild=Process.Start(info);activeHandle=activeChild.Handle;
            if (!AssignProcessToJobObject(activeJob,activeHandle)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            long born;
            if (!GetProcessTimes(activeHandle,out born,out exited,out kernel,out user)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            StringBuilder image=new StringBuilder(32768);int length=image.Capacity;
            if (!QueryFullProcessImageName(activeHandle,0,image,ref length) || born<=0 ||
                !String.Equals(CanonicalImage(image.ToString()),CanonicalImage(helperPath),StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Started reader identity differs");
            string session=activeSession;
            activeDeadline=new Timer(delegate(object ignored)
            {
                lock(activeGate)
                {
                    if(activeSession!=session||activeHandle==IntPtr.Zero||activeProgress==null)return;
                    ObserveHeartbeat();
                    if(activeProgress.ElapsedMilliseconds<ActiveDeadlineMilliseconds)return;
                    activeTimedOut=true;TerminateProcess(activeHandle,1);
                }
            },null,500,500);
        }
        void ObserveHeartbeat()
        {
            try
            {
                if (activeOutput==null || !File.Exists(activeOutput)) return;
                Dictionary<string,object> value;
                using(FileStream stream=new FileStream(activeOutput,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
                {
                    if(stream.Length>32768)return;
                    using(StreamReader text=new StreamReader(stream,Encoding.UTF8))value=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(text.ReadToEnd());
                }
                DateTimeOffset expected,born,observed;
                if(value==null||!value.ContainsKey("Seq")||!value.ContainsKey("ObservedUtc")||
                    Convert.ToInt64(value["Hwnd"])!=activeWindow.Hwnd||Convert.ToInt32(value["Pid"])!=activeWindow.Pid||
                    Convert.ToString(value["ClassName"])!=activeWindow.ClassName||
                    !DateTimeOffset.TryParse(activeWindow.ProcessStartUtc,out expected)||
                    !DateTimeOffset.TryParse(Convert.ToString(value["ProcessStartUtc"]),out born)||expected!=born||
                    !DateTimeOffset.TryParse(Convert.ToString(value.ContainsKey("HeartbeatUtc")?value["HeartbeatUtc"]:value["ObservedUtc"]),out observed))return;
                long seq=Convert.ToInt64(value["Seq"]);double age=(DateTimeOffset.UtcNow-observed).TotalMilliseconds;
                bool success=value.ContainsKey("Success")&&Convert.ToBoolean(value["Success"]);
                bool pending=value.ContainsKey("Pending")&&Convert.ToBoolean(value["Pending"]);
                if(seq>activeHeartbeatSequence&&seq>0&&age<=4000&&age>=-5000&&(success||(activeReady&&!pending)))
                {activeReady|=success;activeHeartbeatSequence=seq;activeProgress.Restart();}
            }
            catch { }
        }
        public void StopActive() { lock(activeGate)StopActiveCore(); }
        void StopActiveCore()
        {
            if(activeDeadline!=null){activeDeadline.Dispose();activeDeadline=null;}
            if(activeHandle!=IntPtr.Zero&&WaitForSingleObject(activeHandle,0)==258)TerminateProcess(activeHandle,1);
            if(activeJob!=IntPtr.Zero){CloseHandle(activeJob);activeJob=IntPtr.Zero;}
            if(activeChild!=null){activeChild.Dispose();activeChild=null;}
            activeHandle=IntPtr.Zero;activeWindow=null;activeSequence=0;activeHeartbeatSequence=0;activeReady=false;activeTimedOut=false;activeProgress=null;activeSession=null;
            string output=activeOutput;activeOutput=null;
            if(output!=null){try{if(File.Exists(output))File.Delete(output);if(File.Exists(output+".tmp"))File.Delete(output+".tmp");}catch{}}
        }
        public ChatGptHeaderReadResult Read(ChatGptTitleWindow window, int timeoutMs, WaitHandle cancel)
        {
            if (cancel.WaitOne(0)) return ChatGptHeaderReadResult.Fail("Cancelled");
            if (!File.Exists(helperPath)) return ChatGptHeaderReadResult.Fail("HelperMissing");
            Directory.CreateDirectory(workDirectory);
            string output = Path.Combine(workDirectory, Guid.NewGuid().ToString("N") + ".json");
            Process child = null; IntPtr ownedHandle = IntPtr.Zero, ownedJob = IntPtr.Zero;
            Stopwatch watch = Stopwatch.StartNew(); int timeout = Math.Max(1, Math.Min(10000, timeoutMs));
            try
            {
                ProcessStartInfo info = new ProcessStartInfo(helperPath,
                    "--direct --hwnd " + window.Hwnd.ToString(CultureInfo.InvariantCulture) + " --output " + Quote(output));
                info.UseShellExecute = false; info.CreateNoWindow = true; info.WindowStyle = ProcessWindowStyle.Hidden;
                ownedJob=CreateJobObject(IntPtr.Zero,null);
                if(ownedJob==IntPtr.Zero)throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                JobLimits limits=new JobLimits();limits.Basic.Flags=0x2000;
                if(!SetInformationJobObject(ownedJob,9,ref limits,(uint)Marshal.SizeOf(typeof(JobLimits))))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                child = Process.Start(info);
                // This handle comes only from the Process object we just created, never a PID lookup.
                // Keep the object alive until all cancellation and output work has finished.
                ownedHandle = child.Handle;
                if(!AssignProcessToJobObject(ownedJob,ownedHandle))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                long created, exited, kernel, user;
                if (!GetProcessTimes(ownedHandle, out created, out exited, out kernel, out user))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                StringBuilder image = new StringBuilder(32768); int length = image.Capacity;
                if (!QueryFullProcessImageName(ownedHandle, 0, image, ref length))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                if (created <= 0 || !String.Equals(CanonicalImage(image.ToString()), CanonicalImage(helperPath), StringComparison.OrdinalIgnoreCase))
                    return ChatGptHeaderReadResult.Fail("ReaderIdentityOrHeaderUnavailable");
                uint wait;
                while ((wait = WaitForSingleObject(ownedHandle, 50)) == 258)
                {
                    if (cancel.WaitOne(0) || watch.ElapsedMilliseconds >= timeout)
                        return ChatGptHeaderReadResult.Fail(cancel.WaitOne(0) ? "Cancelled" : "ReaderTimeout");
                }
                if (wait != 0) return ChatGptHeaderReadResult.Fail("ReaderFailed");
                if (cancel.WaitOne(0)) return ChatGptHeaderReadResult.Fail("Cancelled");
                if (watch.ElapsedMilliseconds >= timeout) return ChatGptHeaderReadResult.Fail("ReaderTimeout");
                uint exitCode;
                if (!GetExitCodeProcess(ownedHandle, out exitCode) || exitCode != 0 || !File.Exists(output)) return ChatGptHeaderReadResult.Fail("ReaderFailed");
                if (new FileInfo(output).Length > 32768) return ChatGptHeaderReadResult.Fail("ReaderOutputTooLarge");
                Dictionary<string, object> value = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(output, Encoding.UTF8));
                DateTimeOffset expected, observed;
                if (value == null || !Convert.ToBoolean(value["Success"]) || Convert.ToInt64(value["Hwnd"]) != window.Hwnd ||
                    Convert.ToInt32(value["Pid"]) != window.Pid || Convert.ToString(value["ClassName"]) != window.ClassName ||
                    !DateTimeOffset.TryParse(window.ProcessStartUtc, out expected) || !DateTimeOffset.TryParse(Convert.ToString(value["ProcessStartUtc"]), out observed) || expected != observed)
                    return ChatGptHeaderReadResult.Fail("ReaderIdentityOrHeaderUnavailable");
                string title = Convert.ToString(value["Title"]), locator = Convert.ToString(value["Locator"]);
                if (!value.ContainsKey("Title") || String.IsNullOrWhiteSpace(locator)) return ChatGptHeaderReadResult.Fail("HeaderUnavailable");
                return new ChatGptHeaderReadResult { Success = true, Title = title, Locator = locator, ObservedUtc = value.ContainsKey("ObservedUtc") ? Convert.ToString(value["ObservedUtc"]) : null };
            }
            catch { return ChatGptHeaderReadResult.Fail("ReaderException"); }
            finally
            {
                KillOwned(ownedHandle);
                if(ownedJob!=IntPtr.Zero)CloseHandle(ownedJob);
                if (child != null) child.Dispose();
                try { if (File.Exists(output)) File.Delete(output); } catch { }
            }
        }
        // A retained kernel handle cannot be redirected by PID reuse. Never reopen by PID here.
        static void KillOwned(IntPtr ownedHandle)
        {
            if (ownedHandle == IntPtr.Zero) return;
            try
            {
                if (WaitForSingleObject(ownedHandle, 0) == 258)
                { TerminateProcess(ownedHandle, 1); WaitForSingleObject(ownedHandle, 1000); }
            }
            catch { }
        }
        static string Quote(string value)
        {
            StringBuilder text = new StringBuilder("\""); int slashes = 0;
            foreach (char c in value)
            {
                if (c == '\\') { slashes++; continue; }
                if (c == '"') { text.Append('\\', slashes * 2 + 1); text.Append(c); }
                else { text.Append('\\', slashes); text.Append(c); }
                slashes = 0;
            }
            text.Append('\\', slashes * 2); text.Append('"'); return text.ToString();
        }
    }
}
