; ChatGPT-TitleSync - ChatGPT title synchronization helper.
#Requires AutoHotkey v2.0
#SingleInstance Off
; Normal resident launch configures per-user sign-in startup; isolated modes do not.
; Requires AutoHotkey v2. Normal launch checks the foreground every 2 seconds; cached background repair + 5-second source refresh; tray Exit restores.
; --read-only --once --output report.json : read headers once, never change captions.
; --check : parse/CLI check only. --self-test : own hidden window + COM only.
; Native captions supply the individual window/taskbar caption; shell grouping is OS-controlled.
; No C# helper dependency. UIA is isolated in this script's --read-worker process.
; COM indices follow Microsoft's UIAutomationClient.h (IUIAutomation / Element / TreeWalker).
; https://learn.microsoft.com/windows/win32/api/uiautomationclient/
; https://www.autohotkey.com/docs/v2/lib/ComCall.htm

global G := {States: Map(), Busy: false, Closing: false, Child: 0, Mutex: 0, StopEvent: 0,
    ReadOnly: HasArg("--read-only"), Rotation: 0,
    LogDir: EnvGet("LOCALAPPDATA") "\TdxChatGptTitles", Recent: Map()} ; Keep the existing log directory for compatibility.

G.AutoStartAllowed:=false,G.AutoStartEnabled:=false,G.AutoStartUnknown:=false,G.AutoStartMenuReady:=false,G.AutoStartTesting:=false

if HasArg("--dispatch-probe") {
    A_IconHidden := true
    Sleep(150)
    Emit(Map("Success",1,"Token",Arg("--dispatch-probe"),"Payload","中文😀"),Arg("--output"))
    ExitApp()
}
if HasArg("--icon-self-test") {
    A_IconHidden:=true
    ThemeSelfTest()
    ExitApp()
}
if HasArg("--autostart-self-test") {
    A_IconHidden:=true
    AutoStartSelfTest()
    ExitApp()
}
if HasArg("--settings-self-test") {
    A_IconHidden:=true
    SettingsSelfTest()
    ExitApp()
}
if HasArg("--stop") {
    stopHandle := DllCall("OpenEventW", "uint", 2, "int", 0,
        "str", "Local\TdxChatGptTitleStandalone.Stop", "ptr") ; Keep legacy shared IPC to prevent concurrent old/new writers.
    if stopHandle {
        DllCall("SetEvent", "ptr", stopHandle)
        DllCall("CloseHandle", "ptr", stopHandle)
    }
    ExitApp()
}
if HasArg("--check") {
    Emit(Map("Success", 1, "Mode", "check", "AutoHotkey", A_AhkVersion, "PointerBits", A_PtrSize * 8), Arg("--output"))
    ExitApp()
}
if HasArg("--self-test") {
    A_IconHidden := true
    SelfTest()
    ExitApp()
}
if HasArg("--read-worker") {
    A_IconHidden := true
    Worker()
    ExitApp()
}

try {
    G.Mutex := DllCall("CreateMutexW", "ptr", 0, "int", 1,
        "str", "Local\TdxChatGptTitleStandalone", "ptr") ; Keep legacy shared IPC to prevent concurrent old/new writers.
    if !G.Mutex || A_LastError = 183 {
        if G.Mutex
            DllCall("CloseHandle", "ptr", G.Mutex)
        G.Mutex := 0
        Emit(Map("Success", 0, "Error", "StandaloneAlreadyRunning"), Arg("--output"))
        ExitApp(2)
    }
    G.StopEvent := DllCall("CreateEventW", "ptr", 0, "int", 1, "int", 0,
        "str", "Local\TdxChatGptTitleStandalone.Stop", "ptr") ; Keep legacy shared IPC to prevent concurrent old/new writers.
    if !G.StopEvent
        throw Error("StopEventUnavailable")
    DllCall("ResetEvent", "ptr", G.StopEvent)
    OnExit(ExitRestore)
    SetTimer(CheckStop, 200)
    iconPath := A_ScriptDir "\..\..\assets\chatgpt-titlesync.ico"
    if FileExist(iconPath) {
        try TraySetIcon(iconPath)
    }
    A_TrayMenu.Delete()
    A_TrayMenu.Add("扫描间隔设置…", (*) => ShowIntervalSettings())
    A_TrayMenu.Add("开机自启动",TrayAutoStart)
    A_TrayMenu.Disable("开机自启动")
    G.AutoStartMenuReady:=true
    A_TrayMenu.Add("退出并恢复窗口标题", (*) => ExitApp())
    A_IconTip := "ChatGPT 标题同步助手（AHK v2）`n同步对话名到窗口标题"
    interval := Arg("--interval", "2")
    if !RegExMatch(interval, "^\d+(?:\.\d+)?$") || interval < 1 || interval > 3600
        throw Error("IntervalMustBeAtLeastOneSecond")
    G.IntervalMs := Round(interval * 1000)
    backgroundInterval := Arg("--background-interval", "5")
    if !RegExMatch(backgroundInterval,"^\d+(?:\.\d+)?$") || backgroundInterval < 5 || backgroundInterval > 3600
        throw Error("BackgroundIntervalMustBe5To3600Seconds")
    G.BackgroundMs := Round(backgroundInterval*1000), G.BgBusy := false, G.NativeBusy := false, G.NextNative := 0, G.BgChild := 0
    G.SettingsFile:=EnvGet("LOCALAPPDATA") "\ChatGPT-title\ahk-v2\settings.ini", G.SettingsRevision:=0 ; Keep legacy settings so existing user preferences continue to load.
    LoadIntervalSettings()
    G.AutoStartAllowed:=!G.ReadOnly && !HasArg("--once")
    if G.AutoStartAllowed {
        try AutoStartInitialize()
        catch as startupError {
            MsgBox(startupError.Message,"ChatGPT-TitleSync - Start at sign-in",16)
            throw startupError
        }
    } else SyncAutoStart()
    if G.AutoStartAllowed {
        try ThemeInitialize()
        catch as iconInitFailure
            ThemeError("initialize")
        try ThemeFinish(ThemeStage(ThemeId()))
        catch as iconInitFailure
            ThemeError("initial_load")
    }
    SetTimer(BackgroundPoll, 1000)
    SetTimer(Poll, G.IntervalMs)
    Poll()
    if HasArg("--once")
        ExitApp()
    Persistent()
} catch {
    Emit(Map("Success", 0, "Error", "StartupFailed"), Arg("--output"))
    ExitApp(1)
}

WorkerExecutable() => A_IsCompiled ? A_ScriptFullPath : A_AhkPath
WorkerIdentityPath() {
    own := ProcessIdentity(DllCall("GetCurrentProcessId"))
    return own ? own["ExePath"] : WorkerExecutable()
}
WorkerCommand(args) => A_IsCompiled ? Q(A_ScriptFullPath) " " args : Q(A_AhkPath) " /ErrorStdOut " Q(A_ScriptFullPath) " " args
DispatchSmoke() {
    token := DllCall("GetCurrentProcessId") "-" Tick()
    file := A_Temp "\tdx_dispatch_" token ".json"
    handle := 0
    try {
        Run(WorkerCommand("--dispatch-probe " Q(token) " --output " Q(file)), , "Hide", &pid)
        handle := DllCall("OpenProcess","uint",0x101001,"int",0,"uint",pid,"ptr")
        if !handle
            throw Error("DispatchHandleUnavailable")
        identity := IdentityFromHandle(handle,pid)
        if !identity || StrLower(identity["ExePath"]) != StrLower(WorkerIdentityPath())
            throw Error("DispatchIdentityMismatch expected=" WorkerIdentityPath() " actual=" (identity?identity["ExePath"]:"unavailable"))
        if DllCall("WaitForSingleObject","ptr",handle,"uint",4000,"uint") != 0
            throw Error("DispatchTimeout")
        data := FileRead(file,"UTF-8")
        if !RegExMatch(data, '"Success"\s*:\s*1') || JsonField(data,"Token") != token || JsonField(data,"Payload") != "中文😀"
            throw Error("DispatchReplyMismatch")
    } finally {
        if handle {
            if DllCall("WaitForSingleObject","ptr",handle,"uint",0,"uint") = 258
                DllCall("TerminateProcess","ptr",handle,"uint",124)
            DllCall("CloseHandle","ptr",handle)
        }
        try FileDelete(file)
        try FileDelete(file ".tmp")
    }
}

HasArg(flag) {
    for value in A_Args
        if value = flag
            return true
    return false
}
Arg(flag, fallback := "") {
    for index, value in A_Args
        if value = flag && index < A_Args.Length
            return A_Args[index + 1]
    return fallback
}
CheckStop() {
    global G
    ThemeTick()
    if G.StopEvent && DllCall("WaitForSingleObject", "ptr", G.StopEvent, "uint", 0, "uint") = 0
        ExitApp()
    NativeMaintenance()
}
Tick() => DllCall("GetTickCount64", "uint64")
Q(value) {
    ; Windows command-line quoting, not shell evaluation.
    out := Chr(34), slashes := 0
    Loop Parse value {
        c := A_LoopField
        if c = "\" {
            slashes++
            continue
        }
        if c = Chr(34)
            out .= Repeat("\", slashes * 2 + 1) c
        else
            out .= Repeat("\", slashes) c
        slashes := 0
    }
    return out Repeat("\", slashes * 2) Chr(34)
}
Repeat(text, count) {
    result := ""
    Loop count
        result .= text
    return result
}
ClassName(hwnd) {
    text := Buffer(512, 0)
    return DllCall("GetClassNameW", "ptr", hwnd, "ptr", text, "int", 256, "int") ? StrGet(text) : ""
}
ProcessIdentity(pid, access := 0x1000) {
    handle := DllCall("OpenProcess", "uint", access, "int", 0, "uint", pid, "ptr")
    if !handle
        return 0
    try {
        return IdentityFromHandle(handle, pid)
    } finally DllCall("CloseHandle", "ptr", handle)
}
IdentityFromHandle(handle, pid) {
    times := Buffer(32, 0), size := 32768, path := Buffer(size * 2, 0)
    if !DllCall("GetProcessTimes", "ptr", handle, "ptr", times, "ptr", times.Ptr + 8,
        "ptr", times.Ptr + 16, "ptr", times.Ptr + 24)
        return 0
    if !DllCall("QueryFullProcessImageNameW", "ptr", handle, "uint", 0, "ptr", path, "uint*", &size)
        return 0
    return Map("Pid", pid, "Start", Format("{:016X}", NumGet(times, 0, "uint64")), "ExePath", StrGet(path))
}
Capture(hwnd, targetOnly := true) {
    if !DllCall("IsWindow", "ptr", hwnd) || DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr") != hwnd
        return 0
    pid := 0
    DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &pid)
    process := ProcessIdentity(pid)
    if !process
        return 0
    cls := ClassName(hwnd)
    if targetOnly && (cls != "Chrome_WidgetWin_1" || !RegExMatch(process["ExePath"], "i)\\ChatGPT\.exe$"))
        return 0
    process["Hwnd"] := hwnd, process["ClassName"] := cls
    return process
}
Same(id) {
    current := Capture(id["Hwnd"], false)
    return current && current["Pid"] = id["Pid"] && current["Start"] = id["Start"]
        && current["ClassName"] = id["ClassName"] && StrLower(current["ExePath"]) = StrLower(id["ExePath"])
}
Key(id) => id["Hwnd"] "|" id["Pid"] "|" id["Start"] "|" StrLower(id["ExePath"])
Caption(hwnd) {
    text := Buffer(4096, 0)
    DllCall("GetWindowTextW", "ptr", hwnd, "ptr", text, "int", 2048)
    return StrGet(text)
}
WriteCaption(id, text) {
    if !Same(id) || StrLen(text) > 1024
        return false
    result := 0
    sent := DllCall("SendMessageTimeoutW", "ptr", id["Hwnd"], "uint", 0x000C,
        "ptr", 0, "str", text, "uint", 0x0023, "uint", 300, "ptr*", &result, "ptr")
    return sent && result && Same(id) && Caption(id["Hwnd"]) = text
}
Active(id) => DllCall("GetForegroundWindow", "ptr") = id["Hwnd"] && Same(id)
EnumerateTargets() {
    id := Capture(DllCall("GetForegroundWindow", "ptr"))
    return id && Active(id) ? [id] : []
}
Poll() {
    global G
    if G.Busy || G.Closing
        return
    G.Busy := true, output := [], started := Tick()
    try {
        windows := EnumerateTargets()
        if !windows.Length
            G.ActiveKey := ""
        offset := windows.Length ? Mod(G.Rotation++, windows.Length) : 0
        Loop windows.Length {
            if G.Closing || 8000 - (Tick() - started) < 3000
                break
            id := windows[Mod(A_Index - 1 + offset, windows.Length) + 1], stateKey := Key(id)
            if !G.States.Has(stateKey)
                G.States[stateKey] := {Id: id, Original: "", Last: "", Owned: false, Retry: 0}
            state := G.States[stateKey]
            if G.HasOwnProp("BgTarget") && G.BgTarget = stateKey
                StopChild(true)
            if !G.HasOwnProp("ActiveKey") || G.ActiveKey != stateKey {
                G.ActiveKey := stateKey
                if !state.HasOwnProp("RetryCustom") || !state.RetryCustom
                    state.Retry := 0
            }
            if !Active(id)
                continue
            before := Caption(id["Hwnd"])
            if StrLower(Trim(before)) = "chatgpt"
                state.Retry := 0, state.RetryCustom := false, state.ProtectedCustom := false
            if state.Owned && before != state.Last {
                state.Owned := false, state.Original := "", state.Last := ""
                state.RetryCustom := StrLower(Trim(before)) != "chatgpt"
                state.Retry := state.RetryCustom ? Tick() + 30000 : 0
                if state.RetryCustom {
                    state.ProtectedCustom := true
                    LogEvent("Skipped", id, "ExternalCustomCaptionChanged")
                }
            }
            result := ReadIsolated(id, Min(4000, 8000 - (Tick() - started)))
            if !result.Get("Success", 0) {
                if !Active(id) {
                    state.Retry := 0
                    continue
                }
                state.RetryCustom := false
                state.Retry := 0
                LogEvent("ReadFailed", id, result.Get("Error", "HeaderUnavailable"))
                output.Push(Map("Hwnd", id["Hwnd"], "Success", 0, "Error", result.Get("Error", "HeaderUnavailable")))
                continue
            }
            if !Active(id)
                continue
            title := RegExReplace(result["Title"], "[\x00-\x1F\x7F]"), desired := title " — ChatGPT"
            output.Push(Map("Hwnd", id["Hwnd"], "Success", 1, "Title", title))
            state.VerifiedTitle := title, state.NextBackground := Tick()+G.BackgroundMs
            if G.ReadOnly || (state.HasOwnProp("ProtectedCustom") && state.ProtectedCustom)
                continue
            if !Trim(title) || StrLower(Trim(title)) = "chatgpt" {
                if Active(id)
                    RestoreOne(state)
                continue
            }
            if StrLen(title) > 240 || !Active(id)
                continue
            latest := Caption(id["Hwnd"])
            if latest != before {
                state.Owned := false, state.Original := "", state.Last := ""
                state.RetryCustom := StrLower(Trim(latest)) != "chatgpt"
                state.Retry := 0, state.ProtectedCustom := state.RetryCustom
                continue
            }
            if latest = desired
                continue
            if !state.Owned
                state.Original := latest
            if !Active(id)
                continue
            written := WriteCaption(id, desired)
            if Same(id) && Caption(id["Hwnd"]) = desired
                state.Owned := true, state.Last := desired
            if written
                LogEvent("Changed", id, "CaptionReadbackVerified")
            else
                state.Retry := Tick() + 30000
        }
        if HasArg("--once")
            Emit(Map("Success", 1, "ReadOnly", G.ReadOnly ? 1 : 0, "Windows", output), Arg("--output"))
    } catch {
        LogEvent("Failed", 0, "PollException")
    } finally G.Busy := false
}
NativeMaintenance() {
    global G
    if !G.HasOwnProp("NextNative") || G.Closing || G.NativeBusy || Tick() < G.NextNative
        return
    G.NextNative := Tick()+1000, G.NativeBusy := true
    removed := []
    try {
        for stateKey, state in G.States {
            id := state.Id
            if !Same(id) {
                removed.Push(stateKey)
                continue
            }
            if Active(id) || G.ReadOnly || !state.HasOwnProp("VerifiedTitle")
                continue
            title := state.VerifiedTitle
            if !Trim(title) || StrLower(Trim(title)) = "chatgpt"
                continue
            current := Caption(id["Hwnd"])
            if state.Owned && current = state.Last
                continue
            if state.Owned
                state.Owned := false, state.Original := "", state.Last := ""
            if StrLower(Trim(current)) != "chatgpt" {
                state.ProtectedCustom := true
                continue
            }
            if Active(id) || !Same(id) || Caption(id["Hwnd"]) != current
                continue
            desired := title " — ChatGPT"
            if WriteCaption(id,desired) {
                state.Original := current, state.Last := desired, state.Owned := true, state.ProtectedCustom := false
                LogEvent("BackgroundCacheRestored",id,"NativeGenericReset")
            }
        }
        for stateKey in removed
            G.States.Delete(stateKey)
    } finally G.NativeBusy := false
}
BackgroundPoll() {
    global G
    if G.Closing || G.BgBusy || G.Busy || HasArg("--once")
        return
    G.BgBusy := true
    try {
        ; EnumWindows-equivalent metadata only; UIA is confined to one chosen window.
        for hwnd in WinGetList("ahk_class Chrome_WidgetWin_1") {
            id := Capture(hwnd)
            if !id || Active(id)
                continue
            stateKey := Key(id)
            if !G.States.Has(stateKey)
                G.States[stateKey] := {Id:id,Original:"",Last:"",Owned:false,Retry:0}
            state := G.States[stateKey]
            if state.HasOwnProp("NextBackground") && Tick() < state.NextBackground
                continue
            state.NextBackground := Tick()+G.BackgroundMs, G.BgTarget := stateKey
            result := ReadIsolated(id,4000,true)
            if !result.Get("Success",0) || !Same(id) || Active(id)
                break
            title := RegExReplace(result["Title"],"[\x00-\x1F\x7F]")
            if !Trim(title) || StrLen(title)>240
                break
            state.VerifiedTitle := title
            if G.ReadOnly
                break
            current := Caption(hwnd)
            if StrLower(Trim(title)) = "chatgpt" {
                RestoreOne(state)
                break
            }
            if StrLower(Trim(current)) != "chatgpt" && !(state.Owned && current = state.Last) {
                state.Owned := false, state.Original := "", state.Last := "", state.ProtectedCustom := true
                break
            }
            desired := title " — ChatGPT"
            if current = desired
                break
            original := state.Owned && current = state.Last ? state.Original : current
            if !Active(id) && Same(id) && Caption(hwnd)=current && WriteCaption(id,desired)
                state.Original := original, state.Last := desired, state.Owned := true, state.ProtectedCustom := false
            break
        }
    } finally {
        G.BgTarget := "", G.BgBusy := false
    }
}

ReadIsolated(id, timeout, background := false) {
    global G
    settingsRevision:=G.HasOwnProp("SettingsRevision")?G.SettingsRevision:0
    file := A_Temp "\tdx_chatgpt_" DllCall("GetCurrentProcessId") "_" Tick() "_" Random(100000, 999999) ".json"
    command := WorkerCommand("--read-worker --hwnd " id["Hwnd"] " --output " Q(file) (background ? " --background" : ""))
    handle := 0
    try {
        Run(command, , "Hide", &pid)
        handle := DllCall("OpenProcess", "uint", 0x101001, "int", 0, "uint", pid, "ptr")
        if !handle
            return Map("Success", 0, "Error", "OwnHelperUnavailable")
        identity := IdentityFromHandle(handle, pid)
        if !identity || StrLower(identity["ExePath"]) != StrLower(WorkerIdentityPath())
            return Map("Success", 0, "Error", "HelperIdentityMismatch")
        if background
            G.BgChild := {Handle: handle, Id: identity}
        else
            G.Child := {Handle: handle, Id: identity}
        started := Tick()
        while DllCall("WaitForSingleObject", "ptr", handle, "uint", 40, "uint") = 258 {
            if G.Closing || (G.HasOwnProp("SettingsRevision")?G.SettingsRevision:0)!=settingsRevision || Tick() - started >= timeout {
                StopChild(background)
                return Map("Success", 0, "Error", "ReaderTimeout")
            }
            CheckStop()
            if (background ? Active(id) || !Same(id) : !Active(id)) {
                StopChild(background)
                return Map("Success", 0, "Error", "ForegroundChanged")
            }
            Sleep(1)
        }
        if (G.HasOwnProp("SettingsRevision")?G.SettingsRevision:0)!=settingsRevision
            return Map("Success",0,"Error","SettingsChanged")
        if !FileExist(file) || FileGetSize(file) > 65536
            return Map("Success", 0, "Error", "ReaderOutputUnavailable")
        data := FileRead(file, "UTF-8")
        if !RegExMatch(data, '"Success"\s*:\s*1')
            return Map("Success", 0, "Error", "HeaderUnavailable")
        for field in ["Hwnd", "Pid", "Start", "ClassName", "ExePath"]
            if JsonField(data, field) != String(id[field])
                return Map("Success", 0, "Error", "ReaderIdentityMismatch")
        if !Same(id) || JsonField(data, "Locator") != "RawDirect/RootView/NonClientView/ChromeNodeFrameView/ChromeNodeClientView/View/Chrome_WidgetWin_1/Chrome_RenderWidgetHostHWND/Document[RootWebArea].Name"
            return Map("Success", 0, "Error", "ReaderIdentityMismatch")
        return Map("Success", 1, "Title", JsonField(data, "Title"))
    } catch {
        StopChild(background)
        return Map("Success", 0, "Error", "ReaderException")
    } finally {
        if background
            G.BgChild := 0
        else
            G.Child := 0
        if handle
            DllCall("CloseHandle", "ptr", handle)
        try FileDelete(file)
        try FileDelete(file ".tmp")
    }
}
StopChild(background := false) {
    global G
    if !IsObject(background ? G.BgChild : G.Child)
        return
    child := background ? G.BgChild : G.Child
    actual := IdentityFromHandle(child.Handle, child.Id["Pid"])
    if actual && actual["Start"] = child.Id["Start"] && StrLower(actual["ExePath"]) = StrLower(WorkerIdentityPath()) {
        DllCall("TerminateProcess", "ptr", child.Handle, "uint", 1)
        DllCall("WaitForSingleObject", "ptr", child.Handle, "uint", 800)
    }
}
RestoreOne(state) {
    if state.Owned && Same(state.Id) && Caption(state.Id["Hwnd"]) = state.Last {
        if WriteCaption(state.Id, state.Original)
            state.Owned := false, state.Last := "", state.Original := ""
    }
}
ExitRestore(*) {
    global G
    ThemeDispose()
    G.Closing := true
    SetTimer(Poll, 0)
    SetTimer(CheckStop, 0)
    SetTimer(BackgroundPoll, 0)
    StopChild(true)
    StopChild()
    for key, state in G.States {
        try RestoreOne(state)
    }
    if G.StopEvent {
        DllCall("CloseHandle", "ptr", G.StopEvent)
        G.StopEvent := 0
    }
    if G.Mutex {
        DllCall("ReleaseMutex", "ptr", G.Mutex)
        DllCall("CloseHandle", "ptr", G.Mutex)
        G.Mutex := 0
    }
}

Worker() {
    hwnd := Integer(Arg("--hwnd", "0")), output := Arg("--output"), identity := 0
    result := Map("Success", 0, "Error", "HeaderUnavailable")
    try {
        identity := Capture(hwnd)
        if !identity || (HasArg("--background") ? Active(identity) : !Active(identity))
            throw Error("TargetIdentityUnavailable")
        title := ReadDocumentName(hwnd)
        if !Same(identity) || (HasArg("--background") ? Active(identity) : !Active(identity))
            throw Error("TargetIdentityChanged")
        for key, value in identity
            result[key] := String(value)
        result["Title"] := title, result["Locator"] := "RawDirect/RootView/NonClientView/ChromeNodeFrameView/ChromeNodeClientView/View/Chrome_WidgetWin_1/Chrome_RenderWidgetHostHWND/Document[RootWebArea].Name"
        result["Success"] := 1, result["Error"] := ""
    } catch {
        result := Map("Success", 0, "Error", "HeaderUnavailable")
    }
    Emit(result, output)
}
ReadDocumentName(hwnd) {
    ; Follow the verified RawView DIRECT-child shell path. Never visit document children.
    uia := ComObject("{FF48DBA4-60EF-4201-AA87-54103EEF594E}", "{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
    walker := 0, element := 0, doc := 0
    try {
        ComCall(16, uia, "ptr*", &walker)
        ComCall(6, uia, "ptr", hwnd, "ptr*", &element)
        for expected in ["RootView", "NonClientView", "ChromeNodeFrameView", "ChromeNodeClientView",
            "View", "Chrome_WidgetWin_1", "Chrome_RenderWidgetHostHWND"] {
            next := FindDirect(walker, element, expected)
            ObjRelease(element), element := next
        }
        kind := 0
        ComCall(21, element, "int*", &kind)
        if kind = 50030 && UiaText(element, 29) = "RootWebArea" {
            ObjAddRef(element), doc := element
        } else
            doc := FindDirect(walker, element, "", true, 16)
        title := UiaText(doc, 23)
        if StrLen(title) > 512
            throw Error("TitleLengthLimit")
        return title
    } finally {
        if doc
            ObjRelease(doc)
        if element
            ObjRelease(element)
        if walker
            ObjRelease(walker)
    }
}
FindDirect(walker, parent, expectedClass := "", document := false, limit := 32) {
    child := 0, found := 0, returned := false, count := 0
    try {
        ComCall(4, walker, "ptr", parent, "ptr*", &child)
        while child {
            if ++count > limit
                throw Error("DirectSiblingLimit")
            if document {
                kind := 0
                ComCall(21, child, "int*", &kind)
                match := kind = 50030 && UiaText(child, 29) = "RootWebArea"
            } else
                match := UiaText(child, 30) = expectedClass
            if match {
                if found
                    throw Error("VerifiedPathAmbiguous")
                ObjAddRef(child), found := child
            }
            next := 0
            ComCall(6, walker, "ptr", child, "ptr*", &next)
            ObjRelease(child), child := next
        }
        if !found
            throw Error("VerifiedPathUnavailable")
        returned := true
        return found
    } finally {
        if child
            ObjRelease(child)
        if found && !returned
            ObjRelease(found)
    }
}
UiaText(element, method) {
    value := 0
    ComCall(method, element, "ptr*", &value)
    try return value ? StrGet(value, "UTF-16") : ""
    finally {
        if value
            DllCall("oleaut32\SysFreeString", "ptr", value)
    }
}
JsonString(value) {
    text := Chr(34)
    Loop Parse String(value) {
        c := A_LoopField, n := Ord(c)
        if c = Chr(34) || c = "\"
            text .= "\" c
        else if n < 32
            text .= Format("\u{:04X}", n)
        else
            text .= c
    }
    return text Chr(34)
}
Json(value) {
    if value is Map {
        parts := []
        for key, item in value
            parts.Push(JsonString(key) ":" Json(item))
        return "{" Join(parts) "}"
    }
    if value is Array {
        parts := []
        for item in value
            parts.Push(Json(item))
        return "[" Join(parts) "]"
    }
    if Type(value) = "Integer" || Type(value) = "Float"
        return String(value)
    return JsonString(value)
}
Join(items) {
    result := ""
    for index, item in items
        result .= (index > 1 ? "," : "") item
    return result
}
JsonField(data, field) {
    if !RegExMatch(data, '"' field '"\s*:\s*"((?:\\.|[^"\\])*)"', &found)
        return ""
    text := found[1], out := "", i := 1
    while i <= StrLen(text) {
        c := SubStr(text, i++, 1)
        if c != "\" {
            out .= c
            continue
        }
        c := SubStr(text, i++, 1)
        if c = "u" {
            out .= Chr(Integer("0x" SubStr(text, i, 4))), i += 4
        } else if c = "n"
            out .= "`n"
        else if c = "r"
            out .= "`r"
        else if c = "t"
            out .= "`t"
        else
            out .= c
    }
    return out
}
Emit(value, file := "") {
    text := Json(value)
    if !file {
        try FileAppend(text "`n", "*", "UTF-8")
        return true
    }
    temporary := file "." DllCall("GetCurrentProcessId") ".tmp"
    try {
        if InStr(FileExist(file),"D")
            throw Error("OutputPathIsDirectory")
        SplitPath(file,,&directory)
        if directory
            DirCreate(directory)
        if FileExist(temporary)
            FileDelete(temporary)
        FileAppend(text,temporary,"UTF-8-RAW")
        FileMove(temporary,file,1)
        return true
    } catch as err {
        try FileAppend(Json(Map("Success",0,"Error","OutputWriteFailed","Path",file,"Detail",err.Message)) "`n","**","UTF-8")
        return false
    } finally {
        try FileDelete(temporary)
    }
}

LogEvent(kind, id, code) {
    global G
    logKey := kind "|" (IsObject(id) ? Key(id) : "") "|" code
    if G.Recent.Has(logKey) && Tick() - G.Recent[logKey] < 30000
        return
    G.Recent[logKey] := Tick()
    try {
        DirCreate(G.LogDir)
        FileAppend(Json(Map("Utc", A_NowUTC, "Kind", kind, "Pid", IsObject(id) ? id["Pid"] : 0,
            "Hwnd", IsObject(id) ? id["Hwnd"] : 0, "Code", code)) "`n",
            G.LogDir "\standalone_ahk_" SubStr(A_Now, 1, 8) ".jsonl", "UTF-8-RAW")
    }
}
SelfTest() {
    result := Map("Success", 0, "Mode", "self-test"), testGui := 0
    try {
        testGui := Gui("+ToolWindow", "AHK owned title fixture")
        testGui.AddText(, "Self-owned UIA element only")
        testGui.Show("Hide")
        hwnd := testGui.Hwnd, id := Capture(hwnd, false)
        if !id || !WriteCaption(id, "测试😀 — own window") || Caption(hwnd) != "测试😀 — own window"
            throw Error("OwnedCaptionWriteFailed")
        if !WriteCaption(id, "AHK owned title fixture")
            throw Error("OwnedCaptionRestoreFailed")
        uia := ComObject("{FF48DBA4-60EF-4201-AA87-54103EEF594E}", "{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
        element := 0
        ComCall(6, uia, "ptr", hwnd, "ptr*", &element)
        try name := UiaText(element, 23)
        finally ObjRelease(element)
        if name != "AHK owned title fixture"
            throw Error("OwnedComNameMismatch")
        sample := Map("Title", '中文😀 "quoted" \ slash', "Pid", "123")
        if JsonField(Json(sample), "Title") != sample["Title"]
            throw Error("JsonRoundtripFailed")
        DispatchSmoke()
        result := Map("OwnedWorkerDispatch",1,"CompiledMode",A_IsCompiled?1:0,"Success", 1, "Mode", "self-test", "OwnedCaptionWriteRestore", 1,
            "OwnedUiaNameComCall", 1, "JsonUnicodeRoundtrip", 1, "RealChatGptAccessed", 0, "PointerBits", A_PtrSize * 8)
    } catch as err {
        result["Error"] := err.Message
        result["Where"] := err.What
        result["Line"] := err.Line
    } finally {
        if IsObject(testGui)
            testGui.Destroy()
    }
    Emit(result, Arg("--output"))
}


ValidIntervals(first,second) {
    return RegExMatch(first,"^\d+(?:\.\d+)?$") && RegExMatch(second,"^\d+(?:\.\d+)?$") && first>=1 && first<=3600 && second>=5 && second<=3600
}
LoadIntervalSettings() {
    global G
    first:=G.IntervalMs/1000,second:=G.BackgroundMs/1000
    if FileExist(G.SettingsFile) {
        if !HasArg("--interval")
            first:=IniRead(G.SettingsFile,"Timing","ForegroundSeconds",first)
        if !HasArg("--background-interval")
            second:=IniRead(G.SettingsFile,"Timing","BackgroundSeconds",second)
    }
    if ValidIntervals(first,second)
        G.IntervalMs:=Round(first*1000),G.BackgroundMs:=Round(second*1000)
}
ApplyIntervals(first,second,persist:=true,reschedule:=true) {
    global G
    if !ValidIntervals(first,second)
        throw Error("Foreground: 1..3600 seconds; background: 5..3600 seconds.")
    if persist {
        if InStr(FileExist(G.SettingsFile),"D")
            throw Error("SettingsPathIsDirectory")
        SplitPath(G.SettingsFile,,&directory)
        DirCreate(directory)
        temporary:=G.SettingsFile "." DllCall("GetCurrentProcessId") ".tmp"
        try {
            IniWrite(first,temporary,"Timing","ForegroundSeconds")
            IniWrite(second,temporary,"Timing","BackgroundSeconds")
            FileMove(temporary,G.SettingsFile,1)
        } finally {
            try FileDelete(temporary)
        }
    }
    G.SettingsRevision:=(G.HasOwnProp("SettingsRevision")?G.SettingsRevision:0)+1
    G.IntervalMs:=Round(first*1000),G.BackgroundMs:=Round(second*1000)
    if reschedule {
        StopChild()
        StopChild(true)
        for stateKey,state in G.States
            state.NextBackground:=0
        SetTimer(Poll,G.IntervalMs)
    }
}
ShowIntervalSettings(show:=true) {
    global G
    if G.HasOwnProp("SettingsGui") && IsObject(G.SettingsGui) {
        G.SettingsGui.Show()
        return
    }
    form:=Gui("+ToolWindow","ChatGPT 标题同步助手 - 扫描间隔设置")
    G.SettingsGui:=form,G.SettingsHwnd:=form.Hwnd
    form.AddText(,"Foreground source (seconds, 1..3600)")
    first:=form.AddEdit("w280",G.IntervalMs/1000)
    form.AddText(,"Background source (seconds, 5..3600)")
    second:=form.AddEdit("w280",G.BackgroundMs/1000)
    G.AutoCheckbox:=form.AddCheckbox("w280" (G.AutoStartEnabled?" Checked":""),"开机自启动")
    G.AutoCheckbox.Enabled:=G.AutoStartAllowed && !G.AutoStartUnknown
    form.AddText(,"Cached-title repair remains every 1 second.")
    save:=form.AddButton("w110 Default","Save")
    close:=form.AddButton("x+10 w110","Cancel")
    save.Move(80,290),close.Move(200,290)
    ThemeAddControls(form)
    dispose:=(*)=>(form.Destroy(),G.SettingsGui:=0,G.SettingsHwnd:=0)
    save.OnEvent("Click",SaveSettings)
    close.OnEvent("Click",dispose)
    form.OnEvent("Close",dispose)
    form.OnEvent("Escape",dispose)
    if show
        form.Show("AutoSize")
    SaveSettings(*) {
        try {
            ThemeSave(first.Value,second.Value,G.AutoCheckbox.Value,G.ThemeModeChoice.Value=1?"fixed":"random",44+G.ThemeFixedChoice.Value,G.ThemePeriodChoice.Value=1?"day":G.ThemePeriodChoice.Value=2?"hour":"5min")
            form.Destroy(),G.SettingsGui:=0,G.SettingsHwnd:=0
        } catch as err {
            if G.AutoStartTesting {
                G.AutoStartTestError:=err.Message
                return
            }
            MsgBox(err.Message,"ChatGPT-TitleSync - Scan intervals",16)
        }
    }
}
SettingsSelfTest() {
    global G
    G.SettingsFile:=A_Temp "\cxt_settings_v2_" DllCall("GetCurrentProcessId") "\nested\settings.ini"
    G.IntervalMs:=2000,G.BackgroundMs:=5000,G.SettingsRevision:=0
    passed:=0
    try {
        ApplyIntervals(2,15,true,false)
        if G.IntervalMs!=2000 || G.BackgroundMs!=15000 || G.SettingsRevision!=1
            throw Error("LiveValueUpdate")
        passed++
        G.IntervalMs:=2000,G.BackgroundMs:=5000
        LoadIntervalSettings()
        if G.IntervalMs!=2000 || G.BackgroundMs!=15000
            throw Error("PersistedReload")
        passed++
        for pair in [[0,30],[3601,30],[1,4],[1,3601],["nan",30]] {
            failed:=false
            try ApplyIntervals(pair[1],pair[2],true,false)
            catch
                failed:=true
            if !failed || G.IntervalMs!=2000 || G.BackgroundMs!=15000 || G.SettingsRevision!=1
                throw Error("InvalidInputChangedState")
            passed++
        }
        ShowIntervalSettings(false)
        if G.SettingsGui["Edit1"].Value+0!=2 || G.SettingsGui["Edit2"].Value+0!=15
            throw Error("SettingsGuiValues")
        G.SettingsGui.Destroy(),G.SettingsGui:=0,G.BgChild:=0,G.States:=Map("fixture",{NextBackground:123})
        passed++
        ApplyIntervals(3,20,true,true)
        SetTimer(Poll,0)
        if G.IntervalMs!=3000 || G.BackgroundMs!=20000 || G.SettingsRevision!=2 || G.States["fixture"].NextBackground!=0
            throw Error("HotScheduleReset")
        passed++
        actualSettings:=G.SettingsFile
        SplitPath(actualSettings,,&privateDirectory)
        blocked:=privateDirectory "\blocked"
        DirCreate(blocked)
        G.SettingsFile:=blocked
        failed:=false
        try ApplyIntervals(4,25,true,false)
        catch
            failed:=true
        G.SettingsFile:=actualSettings
        if !failed || G.IntervalMs!=3000 || G.SettingsRevision!=2 || FileExist(blocked "." DllCall("GetCurrentProcessId") ".tmp")
            throw Error("SaveFailureChangedStateOrLeftTemporary")
        passed++
        report:=privateDirectory "\new_reports\result.json"
        if !Emit(Map("Round",1),report) || !Emit(Map("Round",2),report) || !InStr(FileRead(report), '"Round":2')
            throw Error("OutputFirstAndSecondSave")
        if Emit(Map("ExpectedFailure",1),blocked) || FileExist(blocked "." DllCall("GetCurrentProcessId") ".tmp")
            throw Error("OutputFailureCleanup")
        passed++
        FileDelete(report)
        DirDelete(privateDirectory "\new_reports")
        DirDelete(blocked)
        Emit(Map("Success",1,"Passed",passed,"Mode","settings-self-test","RealChatGptAccessed",0),Arg("--output"))
    } catch as err {
        Emit(Map("Success",0,"Passed",passed,"Error",err.Message,"Line",err.Line),Arg("--output"))
    }
    try FileDelete(G.SettingsFile)
}


; Production startup shares the fixed HKCU contract; self-tests inject private subkeys.
AutoStartCommand(executable:="",script:="",compiled:=-1) {
    if compiled=-1
        compiled:=A_IsCompiled
    if executable=""
        executable:=compiled?A_ScriptFullPath:A_AhkPath
    if script=""
        script:=A_ScriptFullPath
    return compiled?Q(executable):Q(executable) " " Q(script)
}
AutoRegRead(path,name) {
    h:=0,status:=DllCall("advapi32\RegOpenKeyExW","ptr",-2147483647,"str",path,"uint",0,"uint",1,"ptr*",&h,"uint")
    if status=2 || status=3
        return {Exists:false}
    if status
        throw Error("Registry read failed: " status)
    try {
        kind:=0,size:=0,status:=DllCall("advapi32\RegQueryValueExW","ptr",h,"str",name,"ptr",0,"uint*",&kind,"ptr",0,"uint*",&size,"uint")
        if status=2
            return {Exists:false}
        if status
            throw Error("Registry query failed: " status)
        bytes:=Buffer(Max(size,2),0)
        status:=DllCall("advapi32\RegQueryValueExW","ptr",h,"str",name,"ptr",0,"uint*",&kind,"ptr",bytes,"uint*",&size,"uint")
        if status
            throw Error("Registry data read failed: " status)
        return {Exists:true,Type:kind,Size:size,Bytes:bytes}
    } finally DllCall("advapi32\RegCloseKey","ptr",h)
}
AutoRegValue(kind,value) {
    size:=kind=4?4:(StrLen(value)+1)*2,bytes:=Buffer(size,0)
    if kind=4
        NumPut("uint",value,bytes)
    else
        StrPut(value,bytes,"UTF-16")
    return {Exists:true,Type:kind,Size:size,Bytes:bytes}
}
AutoRegEqual(first,second) {
    if first.Exists!=second.Exists
        return false
    if !first.Exists
        return true
    if first.Type!=second.Type || first.Size!=second.Size
        return false
    Loop first.Size
        if NumGet(first.Bytes,A_Index-1,"uchar")!=NumGet(second.Bytes,A_Index-1,"uchar")
            return false
    return true
}
AutoRegWrite(path,name,item) {
    h:=0
    if item.Exists
        status:=DllCall("advapi32\RegCreateKeyExW","ptr",-2147483647,"str",path,"uint",0,"ptr",0,"uint",0,"uint",2,"ptr",0,"ptr*",&h,"ptr",0,"uint")
    else
        status:=DllCall("advapi32\RegOpenKeyExW","ptr",-2147483647,"str",path,"uint",0,"uint",2,"ptr*",&h,"uint")
    if !item.Exists && (status=2 || status=3)
        return 0
    if status
        return status
    try {
        if item.Exists
            return DllCall("advapi32\RegSetValueExW","ptr",h,"str",name,"uint",0,"uint",item.Type,"ptr",item.Bytes,"uint",item.Size,"uint")
        status:=DllCall("advapi32\RegDeleteValueW","ptr",h,"str",name,"uint")
        return status=2?0:status
    } finally DllCall("advapi32\RegCloseKey","ptr",h)
}
AutoStartInitialize(runKey:="",prefKey:="",command:="") {
    global G
    G.AutoRunKey:=runKey!=""?runKey:"Software\Microsoft\Windows\CurrentVersion\Run"
    G.AutoPrefKey:=prefKey!=""?prefKey:"Software\ChatGPT-TitleSync"
    G.AutoCommand:=command!=""?command:AutoStartCommand()
    pref:=AutoRegRead(G.AutoPrefKey,"AutoStartEnabled"),enabled:=true
    if pref.Exists {
        if pref.Type!=4 || pref.Size!=4
            throw Error("AutoStartEnabled must be a DWORD containing 0 or 1.")
        enabled:=NumGet(pref.Bytes,0,"uint")
        if enabled!=0 && enabled!=1
            throw Error("AutoStartEnabled must be 0 or 1.")
    }
    AutoStartApply(enabled)
}
AutoStartApply(enabled,failPreference:=false) {
    global G
    if enabled!=0 && enabled!=1
        throw Error("Startup state must be 0 or 1.")
    if enabled && StrLen(G.AutoCommand)>260
        throw Error("Start-at-sign-in command exceeds Windows Run's 260-character limit.")
    oldRun:=AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync"),oldPref:=AutoRegRead(G.AutoPrefKey,"AutoStartEnabled")
    wantedRun:=enabled?AutoRegValue(1,G.AutoCommand):{Exists:false},wantedPref:=AutoRegValue(4,enabled)
    status:=AutoRegEqual(oldRun,wantedRun)?0:AutoRegWrite(G.AutoRunKey,"ChatGPT-TitleSync",wantedRun)
    if !status
        status:=AutoRegEqual(oldPref,wantedPref)?0:(failPreference?5:AutoRegWrite(G.AutoPrefKey,"AutoStartEnabled",wantedPref))
    if status {
        first:=AutoRegWrite(G.AutoRunKey,"ChatGPT-TitleSync",oldRun),second:=AutoRegWrite(G.AutoPrefKey,"AutoStartEnabled",oldPref)
        if first || second
            G.AutoStartUnknown:=true
        throw Error("Startup update failed: " status "; rollback=" first "/" second)
    }
    G.AutoStartEnabled:=!!enabled,G.AutoStartUnknown:=false
    SyncAutoStart()
}
SyncAutoStart() {
    global G
    allowed:=G.AutoStartAllowed && !G.AutoStartUnknown
    if G.AutoStartMenuReady {
        if G.AutoStartEnabled
            A_TrayMenu.Check("开机自启动")
        else
            A_TrayMenu.Uncheck("开机自启动")
        if allowed
            A_TrayMenu.Enable("开机自启动")
        else
            A_TrayMenu.Disable("开机自启动")
    }
    if G.HasOwnProp("SettingsGui") && IsObject(G.SettingsGui) && G.HasOwnProp("AutoCheckbox") {
        G.AutoCheckbox.Value:=G.AutoStartEnabled,G.AutoCheckbox.Enabled:=allowed
    }
}
TrayAutoStart(*) {
    global G
    if !G.AutoStartAllowed || !G.HasOwnProp("AutoRunKey")
        return
    try AutoStartApply(!G.AutoStartEnabled)
    catch as error {
        SyncAutoStart()
        MsgBox(error.Message,"ChatGPT-TitleSync - Start at sign-in",16)
    }
}
ApplySettingsWithAutoStart(first,second,enabled) {
    global G
    if !ValidIntervals(first,second)
        throw Error("Foreground: 1..3600 seconds; background: 5..3600 seconds.")
    prior:=G.AutoStartEnabled
    if G.AutoStartAllowed
        AutoStartApply(enabled)
    try ApplyIntervals(first,second)
    catch as error {
        if G.AutoStartAllowed && enabled!=prior {
            try AutoStartApply(prior)
            catch as rollback
                throw Error(error.Message "; startup rollback failed: " rollback.Message)
        }
        throw error
    }
}
AutoMenuIsChecked() {
    menu:=A_TrayMenu.Handle,count:=DllCall("GetMenuItemCount","ptr",menu)
    Loop count {
        label:=Buffer(512,0)
        DllCall("GetMenuStringW","ptr",menu,"uint",A_Index-1,"ptr",label,"int",256,"uint",0x400)
        if StrGet(label,"UTF-16")="开机自启动"
            return !!(DllCall("GetMenuState","ptr",menu,"uint",A_Index-1,"uint",0x400)&8)
    }
    return false
}
AutoStartSelfTest() {
    global G
    base:="Software\ChatGPT-TitleSync-SelfTest\ahk_v2_" DllCall("GetCurrentProcessId") "_" A_TickCount
    G.AutoStartTesting:=true,G.AutoStartAllowed:=true,G.AutoStartMenuReady:=true,G.BgChild:=0,G.IntervalMs:=2000,G.BackgroundMs:=5000
    G.SettingsFile:=A_Temp "\titlesync_autostart_v2_" DllCall("GetCurrentProcessId") ".ini"
    A_TrayMenu.Add("开机自启动",TrayAutoStart)
    passed:=0
    try {
        AutoStartInitialize(base "\Run",base "\Preferences",Q("C:\Own app\App.exe"))
        if !G.AutoStartEnabled || !AutoMenuIsChecked()
            throw Error("DefaultOn")
        passed++
        AutoStartApply(false)
        if G.AutoStartEnabled || AutoMenuIsChecked() || AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync").Exists
            throw Error("Off")
        passed++
        AutoStartInitialize(base "\Run",base "\Preferences",Q("C:\Own app\Replacement.exe"))
        if G.AutoStartEnabled
            throw Error("ExplicitZeroNotPreserved")
        passed++
        AutoStartApply(true)
        if !AutoRegEqual(AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync"),AutoRegValue(1,G.AutoCommand))
            throw Error("AbsoluteCommandUpdate")
        passed++
        oldRun:=AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync"),oldPref:=AutoRegRead(G.AutoPrefKey,"AutoStartEnabled"),failed:=false
        try AutoStartApply(false,true)
        catch
            failed:=true
        if !failed || !G.AutoStartEnabled || !AutoRegEqual(oldRun,AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync")) || !AutoRegEqual(oldPref,AutoRegRead(G.AutoPrefKey,"AutoStartEnabled"))
            throw Error("FailedWriteRollback")
        passed++
        expected:=A_IsCompiled?Q(A_ScriptFullPath):Q(A_AhkPath) " " Q(A_ScriptFullPath)
        if AutoStartCommand()!=expected
            throw Error("StartupCommandArguments")
        passed++
        AutoStartApply(true,true)
        passed++
        normalCommand:=G.AutoCommand,part:=""
        Loop {
            boundary:=AutoStartCommand("C:\Own app\AutoHotkey.exe","C:\" part "\source.ahk",false)
            if StrLen(boundary)>=260
                break
            part.="x"
        }
        if StrLen(boundary)!=260
            throw Error("BoundaryConstruction")
        G.AutoCommand:=boundary,AutoStartApply(true)
        passed++
        beforeRun:=AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync"),beforePref:=AutoRegRead(G.AutoPrefKey,"AutoStartEnabled")
        G.AutoCommand:=AutoStartCommand("C:\Own app\AutoHotkey.exe","C:\" part "x\source.ahk",false),failed:=false
        try AutoStartApply(true)
        catch
            failed:=true
        if !failed || !AutoRegEqual(beforeRun,AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync")) || !AutoRegEqual(beforePref,AutoRegRead(G.AutoPrefKey,"AutoStartEnabled"))
            throw Error("LongSourceCommandChangedRegistry")
        passed++
        AutoStartApply(false)
        if G.AutoStartEnabled || AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync").Exists
            throw Error("LongCommandCannotTurnOff")
        passed++
        G.AutoCommand:=normalCommand,AutoStartApply(true)
        ShowIntervalSettings(false)
        checkboxId:=DllCall("GetDlgCtrlID","ptr",G.AutoCheckbox.Hwnd),saveHwnd:=G.SettingsGui["Save"].Hwnd,cancelHwnd:=G.SettingsGui["Cancel"].Hwnd
        saveId:=DllCall("GetDlgCtrlID","ptr",saveHwnd),cancelId:=DllCall("GetDlgCtrlID","ptr",cancelHwnd)
        if G.AutoCheckbox.Value!=1
            throw Error("CheckboxInitialValue")
        passed++
        AutoStartApply(false)
        if G.AutoCheckbox.Value!=0 || AutoMenuIsChecked()
            throw Error("MenuToOpenCheckboxSync")
        passed++
        G.AutoCheckbox.Value:=1,G.SettingsGui.Destroy(),G.SettingsGui:=0
        if G.AutoStartEnabled
            throw Error("UnsavedCheckboxApplied")
        passed++
        ShowIntervalSettings(false)
        G.AutoCheckbox.Value:=1,saveHwnd:=G.SettingsGui["Save"].Hwnd
        DllCall("PostMessageW","ptr",saveHwnd,"uint",0xf5,"ptr",0,"ptr",0)
        started:=A_TickCount
        while IsObject(G.SettingsGui) && A_TickCount-started<900
            Sleep(10)
        SetTimer(Poll,0)
        if !G.AutoStartEnabled || !AutoMenuIsChecked() || IsObject(G.SettingsGui)
            throw Error("SettingsSaveSync")
        passed++
        Emit(Map("Success",1,"Passed",passed,"RealRunKeyAccessed",0,"RealChatGptAccessed",0,"SharedIpcUsed",0,"CheckboxId",checkboxId,"SaveId",saveId,"CancelId",cancelId),Arg("--output"))
    } catch as error {
        Emit(Map("Success",0,"Passed",passed,"Error",error.Message,"Line",error.Line,"RealRunKeyAccessed",0),Arg("--output"))
    }
    SetTimer(Poll,0)
    if G.HasOwnProp("SettingsGui") && IsObject(G.SettingsGui)
        G.SettingsGui.Destroy()
    try FileDelete(G.SettingsFile)
    try RegDeleteKey("HKCU\" base)
}

#Include %A_ScriptDir%\IconTheme.ahk

