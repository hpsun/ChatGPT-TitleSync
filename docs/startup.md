# Start at sign-in

[简体中文](startup.zh-CN.md) · [HTML](startup.html) · [Project home](../README.md) · [Support matrix](../support-matrix.md)

**Start at sign-in is on by default.** A normal resident registers the current user's selected implementation when it first runs successfully. This means launch after that user signs in, not a system service before login. The current Windows startup revision is being retested; earlier nine-runtime results do not establish that this revision has completed all real cases. macOS startup source remains Experimental and has not been compiled or run on a Mac.

## Contents

- [Change the choice](#controls)
- [Windows: current-user Run entry](#windows)
- [macOS: Experimental per-user LaunchAgent](#macos)
- [Verification boundary](#verification)

<a id="controls"></a>
## Change the choice

| Entry | When it applies |
| --- | --- |
| Tray/menu **开机自启动 / Start at sign-in** | Immediately after a successful change |
| Settings checkbox with **Save** | Commits the choice; also updates an already-open tray/menu |
| Settings **Cancel** | Leaves the saved choice unchanged |
| **Exit and restore titles** | Exits this run; does not cancel the next login launch |

The two controls represent the same preference and synchronize after successful changes, including an already-open settings window. A failed update reports an error rather than showing success. Missing preference means on; a stored off choice remains off across restarts and supported language variants. Keep one normal resident at a time. Read-only probes, workers, one-pass checks, and settings/stop control invocations do not register startup; only the normal resident after acquiring its singleton may do so. Supported diagnostic/control modes differ by branch.

<a id="windows"></a>
## Windows: current-user Run entry

All Windows implementations use these fixed shared values:

| Item | Location / value |
| --- | --- |
| Login command | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` → `ChatGPT-TitleSync` (`REG_SZ`) |
| Shared preference | `HKCU\Software\ChatGPT-TitleSync` → `AutoStartEnabled` (`DWORD`: 1 on, 0 off) |

The selected normal resident writes its own runnable absolute command, quoting executable, interpreter and script paths as appropriate. It does not carry test log locations or interval overrides into the login command. C# keeps its reader beside the main executable; source/interpreted and frozen-directory implementations keep their documented companions. Each implementation guide provides its exact launch form.

The complete Run command, including quotes and arguments, must be **at most 260 characters**. Enabling an overlong command is rejected before changing the Run value or preference; move the program/script to a shorter stable path. Turning it off is still allowed. When command and preference already match, no rewrite is needed. Failures attempt to retain/restore prior values, are reported, and do not count as successful registration. No administrator permission, service or scheduled task is involved; turning it off removes only this product's Run value. Windows may delay login startup; it is not an instant-response guarantee. See [Microsoft's Run/RunOnce documentation](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys).

<a id="macos"></a>
## macOS: Experimental per-user LaunchAgent

The Swift, Objective-C and Go/Rust menu-companion sources share `NSUserDefaults` suite `io.github.hpsun.ChatGPTTitleSync`, key `AutoStartEnabled`. Missing means on. The draft registration is `~/Library/LaunchAgents/io.github.hpsun.ChatGPTTitleSync.plist`, using the same label, an absolute executable in `ProgramArguments`, `RunAtLoad=true`, and `KeepAlive=false`.

Enabling prepares the selected executable for the next login; it does not bootstrap another resident immediately. Disabling removes that product plist. Exiting the current app leaves the login choice intact. Go/Rust also expose `autostart_enabled` in their saved settings/menu contract. These are source-level designs only: actual Mac SDK compilation, login behavior, permissions and AX/title operation remain unverified. See the [Mac guide](../macos/README.md), [Go guide](../go/README.md), and [Rust guide](../rust/README.md).

<a id="verification"></a>
## Verification boundary

Owned Windows tests use GUID registry keys and never-shown controls rather than the real Run entry. They check default on, shared off persistence, cancellation, two-control synchronization, overlong-command rejection and failed-write handling. Current real Windows retesting is in progress. Login-after-reboot behavior, long-term reliability and native Mac acceptance must be recorded separately; neither old timings nor a source fixture proves those results.
