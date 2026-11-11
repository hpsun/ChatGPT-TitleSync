// Windows baseline icon packaging. No external build crate or SDK resource compiler.
use std::{env, path::PathBuf, process::Command};
fn main() {
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }
    if env::var("CARGO_CFG_TARGET_ARCH").as_deref() != Ok("x86_64") {
        panic!("The Windows icon resource build currently supports x64 only.")
    }
    let manifest = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("manifest directory"));
    let script = manifest.join("../tools/Make-IconResource.ps1");
    let icon = manifest.join("../assets/chatgpt-titlesync.ico");
    println!("cargo:rerun-if-changed={}", script.display());
    println!("cargo:rerun-if-changed={}", icon.display());
    let object = PathBuf::from(env::var_os("OUT_DIR").expect("build output directory"))
        .join("baseline45.obj");
    let host = PathBuf::from(env::var_os("WINDIR").unwrap_or_else(|| "C:/Windows".into()))
        .join("System32/WindowsPowerShell/v1.0/powershell.exe");
    let output = Command::new(host)
        .arg("-NoProfile")
        .arg("-NonInteractive")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-File")
        .arg(&script)
        .arg("-IconPath")
        .arg(&icon)
        .arg("-OutputObject")
        .arg(&object)
        .output()
        .expect("Windows PowerShell is required for baseline icon resources");
    if !output.status.success() {
        panic!(
            "Windows baseline icon resource generation failed: {} {}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        )
    }
    println!("cargo:rustc-link-arg={}", object.display());
}
