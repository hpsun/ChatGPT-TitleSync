; ChatGPT-TitleSync - ChatGPT title synchronization helper.
#Requires AutoHotkey v1.1.33+
#NoEnv
#SingleInstance Off
SetBatchLines, -1
; LOCAL DRAFT. Unicode AutoHotkey v1.1.33+ only, 32/64-bit. Not v1.0 Basic.
; Normal resident launch configures per-user sign-in startup; isolated modes do not.
; Normal launch: 2-second fresh foreground check; cached background repair + 5-second source refresh; tray Exit / --stop restores owned captions.
; --check: no target access. --self-test: own hidden GUI only.
; --read-only --once --output report.json: explicit single read, no caption writes.
; UIA only reads raw DIRECT renderer children Document[RootWebArea].Name.
; The native UIA reader is independent; optional name rules use the shared Unicode companion.

global NR := 0
global G := {States:{}, Busy:false, Closing:false, Child:0, Mutex:0, StopEvent:0
    , ReadOnly:HasArg("--read-only"), Rotation:0, Recent:{}}
G.AutoStartAllowed:=false,G.AutoStartEnabled:=false,G.AutoStartUnknown:=false,G.AutoStartMenuReady:=false,G.AutoStartTesting:=false
EnvGet, localData, LOCALAPPDATA
G.LogDir := localData "\TdxChatGptTitles" ; Keep the existing log directory for compatibility.
if (!A_IsUnicode) {
    Emit({Success:0, Error:"UnicodeInterpreterRequired"}, Arg("--output"))
    ExitApp, 2
}
if HasArg("--dispatch-probe") {
    Menu, Tray, NoIcon
    Sleep, 150
    Emit({Success:1,Token:Arg("--dispatch-probe"),Payload:"中文😀"},Arg("--output"))
    ExitApp
}
if HasArg("--icon-self-test") {
    Menu, Tray, NoIcon
    ThemeSelfTest()
    ExitApp
}
if HasArg("--autostart-self-test") {
    Menu, Tray, NoIcon
    AutoStartSelfTest()
    ExitApp
}
if HasArg("--settings-self-test") {
    Menu, Tray, NoIcon
    SettingsSelfTest()
    ExitApp
}
if HasArg("--stop") {
    h := DllCall("OpenEventW", "UInt", 2, "Int", 0, "WStr", "Local\TdxChatGptTitleStandalone.Stop", "Ptr") ; Keep legacy shared IPC to prevent concurrent old/new writers.
    if h {
        DllCall("SetEvent", "Ptr", h)
        DllCall("CloseHandle", "Ptr", h)
    }
    ExitApp
}
if HasArg("--check") {
    Emit({Success:1, Mode:"check", AutoHotkey:A_AhkVersion, PointerBits:A_PtrSize*8}, Arg("--output"))
    ExitApp
}
if HasArg("--self-test") {
    Menu, Tray, NoIcon
    SelfTest()
    ExitApp
}
if HasArg("--read-worker") {
    Menu, Tray, NoIcon
    Worker()
    ExitApp
}
try {
    G.Mutex := DllCall("CreateMutexW", "Ptr", 0, "Int", 1, "WStr", "Local\TdxChatGptTitleStandalone", "Ptr") ; Keep legacy shared IPC to prevent concurrent old/new writers.
    if (!G.Mutex || A_LastError=183) {
        if G.Mutex
            DllCall("CloseHandle", "Ptr", G.Mutex)
        G.Mutex := 0
        Emit({Success:0, Error:"StandaloneAlreadyRunning"}, Arg("--output"))
        ExitApp, 2
    }
    G.StopEvent := DllCall("CreateEventW", "Ptr", 0, "Int", 1, "Int", 0
        , "WStr", "Local\TdxChatGptTitleStandalone.Stop", "Ptr") ; Keep legacy shared IPC to prevent concurrent old/new writers.
    if !G.StopEvent
        throw Exception("StopEventUnavailable")
    DllCall("ResetEvent", "Ptr", G.StopEvent)
    OnExit("ExitRestore")
    iconPath := A_ScriptDir "\..\..\assets\chatgpt-titlesync.ico"
    if FileExist(iconPath) {
        try {
            Menu, Tray, Icon, % iconPath
        }
    }
    Menu, Tray, NoStandard
    Menu, Tray, Add, 扫描间隔设置…, TraySettings
    Menu, Tray, Add, 名称替换…, TrayNameReplacement
    Menu, Tray, Add, 开机自启动, TrayAutoStart
    Menu, Tray, Disable, 开机自启动
    G.AutoStartMenuReady:=true
    Menu, Tray, Add, 退出并恢复窗口标题, TrayExit
    Menu, Tray, Tip, ChatGPT 标题同步助手（AHK v1.1）`n同步对话名到窗口标题
    SetTimer, CheckStopTimer, 200
    interval:=Arg("--interval","2")
    if (!RegExMatch(interval,"^\d+(?:\.\d+)?$") || interval<1 || interval>3600)
        throw Exception("IntervalMustBeAtLeastOneSecond")
    G.IntervalMs:=Round(interval*1000)
    backgroundInterval:=Arg("--background-interval","5")
    if (!RegExMatch(backgroundInterval,"^\d+(?:\.\d+)?$") || backgroundInterval<5 || backgroundInterval>3600)
        throw Exception("BackgroundIntervalMustBe5To3600Seconds")
    G.BackgroundMs:=Round(backgroundInterval*1000), G.BgBusy:=false, G.NativeBusy:=false, G.NextNative:=0, G.BgChild:=0
    G.SettingsFile:=localData "\ChatGPT-title\ahk-v11\settings.ini", G.SettingsRevision:=0 ; Keep legacy settings so existing user preferences continue to load.
    LoadIntervalSettings()
    if !HasArg("--once") {
        RulesInit("","","",true)
        SetTimer, NameRulesTimer, 50
    }
    G.AutoStartAllowed:=!G.ReadOnly && !HasArg("--once")
    if G.AutoStartAllowed {
        try AutoStartInitialize()
        catch error {
            MsgBox, 16, ChatGPT-TitleSync - Start at sign-in, % error.Message
            throw error
        }
    } else
        SyncAutoStart()
    if G.AutoStartAllowed {
        try ThemeInitialize()
        catch themeError
            ThemeError("initialize")
        try ThemeFinish(ThemeStage(ThemeId()))
        catch themeError
            ThemeError("initial_load")
    }
    SetTimer, BackgroundTimer, 1000
    period:=G.IntervalMs
    SetTimer, PollTimer, %period%
    Poll()
    if HasArg("--once")
        ExitApp
} catch e {
    Emit({Success:0, Error:"StartupFailed"}, Arg("--output"))
    ExitApp, 1
}
return

TrayAutoStart:
if (!G.AutoStartAllowed || !G.HasKey("AutoRunKey"))
    return
try AutoStartApply(!G.AutoStartEnabled)
catch error {
    SyncAutoStart()
    MsgBox, 16, ChatGPT-TitleSync - Start at sign-in, % error.Message
}
return
TraySettings:
ShowIntervalSettings()
return
CxtSettingsSave:
Gui, Settings:Submit, NoHide
try {
    ThemeSave(CxtForeground,CxtBackground,CxtAutoStart,CxtIconMode=1?"fixed":"random",44+CxtFixedIcon,CxtIconPeriod=1?"day":CxtIconPeriod=2?"hour":"5min")
    Gui, Settings:Destroy
    G.SettingsHwnd:=0
} catch e {
    if G.AutoStartTesting {
        G.AutoStartTestError:=e.Message
        return
    }
    MsgBox, 16, ChatGPT-TitleSync - Scan intervals, % e.Message
}
return
CxtThemeChanged:
ThemeFields()
return
CxtSettingsClose:
CxtSettingsEscape:
Gui, Settings:Destroy
G.SettingsHwnd:=0
return
TrayNameReplacement:
RulesEditor()
return
NameRulesTimer:
RulesTick()
return
TrayExit:
ExitApp
PollTimer:
Poll()
return
BackgroundTimer:
BackgroundPoll()
return
CheckStopTimer:
CheckStop()
return

WorkerExecutable() {
    return A_IsCompiled ? A_ScriptFullPath : A_AhkPath
}
WorkerIdentityPath() {
    own:=ProcessIdentity(DllCall("GetCurrentProcessId"))
    return IsObject(own) ? own.ExePath : WorkerExecutable()
}
WorkerCommand(args) {
    return A_IsCompiled ? Q(A_ScriptFullPath) " " args : Q(A_AhkPath) " /ErrorStdOut " Q(A_ScriptFullPath) " " args
}
DispatchSmoke() {
    token:=DllCall("GetCurrentProcessId") "-" Tick()
    file:=A_Temp "\tdx_dispatch_" token ".json"
    h:=0
    try {
        command:=WorkerCommand("--dispatch-probe " Q(token) " --output " Q(file))
        Run, %command%,, Hide, pid
        h:=DllCall("OpenProcess","UInt",0x101001,"Int",0,"UInt",pid,"Ptr")
        if !h
            throw Exception("DispatchHandleUnavailable")
        identity:=IdentityFromHandle(h,pid)
        if (!IsObject(identity) || Lower(identity.ExePath)!=Lower(WorkerIdentityPath()))
            throw Exception("DispatchIdentityMismatch expected=" . WorkerIdentityPath() . " actual=" . (IsObject(identity)?identity.ExePath:"unavailable"))
        if (DllCall("WaitForSingleObject","Ptr",h,"UInt",4000,"UInt")!=0)
            throw Exception("DispatchTimeout")
        FileRead, data, % "*P65001 " file
        if (JsonField(data,"Success")!=1 || JsonField(data,"Token")!=token || JsonField(data,"Payload")!="中文😀")
            throw Exception("DispatchReplyMismatch")
    } finally {
        if h {
            if (DllCall("WaitForSingleObject","Ptr",h,"UInt",0,"UInt")=258)
                DllCall("TerminateProcess","Ptr",h,"UInt",124)
            DllCall("CloseHandle","Ptr",h)
        }
        if FileExist(file)
            FileDelete, %file%
        if FileExist(file ".tmp")
            FileDelete, % file ".tmp"
    }
}

HasArg(flag) {
    for index, value in A_Args
        if (value=flag)
            return true
    return false
}
Arg(flag, fallback:="") {
    for index, value in A_Args
        if (value=flag && index<A_Args.Length())
            return A_Args[index+1]
    return fallback
}
Tick() {
    return DllCall("GetTickCount64", "UInt64")
}
CheckStop() {
    global G
    ThemeTick()
    if (G.StopEvent && DllCall("WaitForSingleObject", "Ptr", G.StopEvent, "UInt", 0, "UInt")=0)
        ExitApp
    NativeMaintenance()
}
Repeat(text, count) {
    result := ""
    Loop, % count
        result .= text
    return result
}
Q(value) {
    out := Chr(34), slashes := 0
    Loop, Parse, value
    {
        c := A_LoopField
        if (c="\") {
            slashes++
            continue
        }
        if (c=Chr(34))
            out .= Repeat("\", slashes*2+1) c
        else
            out .= Repeat("\", slashes) c
        slashes := 0
    }
    return out Repeat("\", slashes*2) Chr(34)
}
ClassName(hwnd) {
    VarSetCapacity(text, 512, 0)
    return DllCall("GetClassNameW", "Ptr", hwnd, "Ptr", &text, "Int", 256, "Int") ? StrGet(&text, "UTF-16") : ""
}
ProcessIdentity(pid, access:=0x1000) {
    h := DllCall("OpenProcess", "UInt", access, "Int", 0, "UInt", pid, "Ptr")
    if !h
        return 0
    try {
        return IdentityFromHandle(h, pid)
    } finally {
        DllCall("CloseHandle", "Ptr", h)
    }
}
IdentityFromHandle(h, pid) {
    VarSetCapacity(times, 32, 0), size:=32768, VarSetCapacity(path, size*2, 0)
    if !DllCall("GetProcessTimes", "Ptr", h, "Ptr", &times, "Ptr", &times+8, "Ptr", &times+16, "Ptr", &times+24)
        return 0
    if !DllCall("QueryFullProcessImageNameW", "Ptr", h, "UInt", 0, "Ptr", &path, "UIntP", size)
        return 0
    return {Pid:pid, Start:Format("{:016X}", NumGet(times,0,"UInt64")), ExePath:StrGet(&path,"UTF-16")}
}
Capture(hwnd, targetOnly:=true) {
    if (!DllCall("IsWindow", "Ptr", hwnd) || DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")!=hwnd)
        return 0
    pid:=0
    DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UIntP", pid)
    id:=ProcessIdentity(pid), cls:=ClassName(hwnd)
    if !IsObject(id)
        return 0
    if (targetOnly && (cls!="Chrome_WidgetWin_1" || !RegExMatch(id.ExePath, "i)\\ChatGPT\.exe$")))
        return 0
    id.Hwnd:=hwnd, id.ClassName:=cls
    return id
}
Lower(value) {
    StringLower, result, value
    return result
}
Same(id) {
    current:=Capture(id.Hwnd,false)
    return IsObject(current) && current.Pid=id.Pid && current.Start=id.Start
        && current.ClassName=id.ClassName && Lower(current.ExePath)=Lower(id.ExePath)
}
Key(id) {
    return id.Hwnd "|" id.Pid "|" id.Start "|" Lower(id.ExePath)
}
Caption(hwnd) {
    VarSetCapacity(text,4096,0)
    DllCall("GetWindowTextW", "Ptr", hwnd, "Ptr", &text, "Int", 2048)
    return StrGet(&text,"UTF-16")
}
WriteCaption(id,text) {
    if (!Same(id) || StrLen(text)>1024)
        return false
    result:=0
    sent:=DllCall("SendMessageTimeoutW", "Ptr", id.Hwnd, "UInt", 0xC, "Ptr", 0, "WStr", text
        , "UInt", 0x23, "UInt", 300, "PtrP", result, "Ptr")
    return sent && result && Same(id) && Caption(id.Hwnd)==text
}
Active(id) {
    return DllCall("GetForegroundWindow","Ptr")=id.Hwnd && Same(id)
}
EnumerateTargets() {
    id:=Capture(DllCall("GetForegroundWindow","Ptr"))
    return IsObject(id) && Active(id) ? [id] : []
}
Poll() {
    global G
    if (G.Busy || G.Closing)
        return
    G.Busy:=true, output:=[], started:=Tick()
    try {
        windows:=EnumerateTargets(), count:=windows.Length()
        if !count
            G.ActiveKey:=""
        offset:=count ? Mod(G.Rotation++,count) : 0
        Loop, % count
        {
            if (G.Closing || 8000-(Tick()-started)<3000)
                break
            id:=windows[Mod(A_Index-1+offset,count)+1], key:=Key(id)
            if !G.States.HasKey(key)
                G.States[key]:={Id:id,Original:"",Last:"",Owned:false,Retry:0}
            state:=G.States[key]
            if (G.HasKey("BgTarget") && G.BgTarget=key)
                StopChild(true)
            if (!G.HasKey("ActiveKey") || G.ActiveKey!=key) {
                G.ActiveKey:=key
                if (!state.HasKey("RetryCustom") || !state.RetryCustom)
                    state.Retry:=0
            }
            if !Active(id)
                continue
            before:=Caption(id.Hwnd)
            if (Lower(Trim(before))="chatgpt")
                state.Retry:=0, state.RetryCustom:=false, state.ProtectedCustom:=false
            if (state.Owned && before!=state.Last) {
                state.Owned:=false, state.Original:="", state.Last:=""
                state.RetryCustom:=Lower(Trim(before))!="chatgpt"
                state.Retry:=state.RetryCustom ? Tick()+30000 : 0
                if state.RetryCustom {
                    state.ProtectedCustom:=true
                    LogEvent("Skipped",id,"ExternalCustomCaptionChanged")
                }
            }
            result:=ReadIsolated(id,Min(4000,8000-(Tick()-started)))
            if !result.Success {
                if !Active(id) {
                    state.Retry:=0
                    continue
                }
                state.RetryCustom:=false
                state.Retry:=0
                LogEvent("ReadFailed",id,result.Error)
                output.Push({Hwnd:id.Hwnd,Success:0,Error:result.Error})
                continue
            }
            if !Active(id)
                continue
            title:=RegExReplace(result.Title,"[\x00-\x1F\x7F]"), desired:=RulesCaption(title)
            output.Push({Hwnd:id.Hwnd,Success:1,Title:title})
            state.VerifiedTitle:=title, state.NextBackground:=Tick()+G.BackgroundMs
            if (G.ReadOnly || (state.HasKey("ProtectedCustom") && state.ProtectedCustom))
                continue
            if (!Trim(title) || Lower(Trim(title))="chatgpt") {
                if Active(id)
                    RestoreOne(state)
                continue
            }
            if (StrLen(title)>240 || !Active(id))
                continue
            latest:=Caption(id.Hwnd)
            if (latest!=before) {
                state.Owned:=false, state.Original:="", state.Last:=""
                state.RetryCustom:=Lower(Trim(latest))!="chatgpt"
                state.Retry:=0, state.ProtectedCustom:=state.RetryCustom
                continue
            }
            if (latest==desired)
                continue
            if !state.Owned
                state.Original:=latest
            if !Active(id)
                continue
            written:=WriteCaption(id,desired)
            if (Same(id) && Caption(id.Hwnd)==desired)
                state.Owned:=true, state.Last:=desired
            if written
                LogEvent("Changed",id,"CaptionReadbackVerified")
            else
                state.Retry:=Tick()+30000
        }
        if HasArg("--once")
            Emit({Success:1,ReadOnly:G.ReadOnly?1:0,Windows:{__Array:output}},Arg("--output"))
    } catch e {
        LogEvent("Failed",0,"PollException")
    } finally {
        G.Busy:=false
    }
}
NativeMaintenance() {
    global G
    if (!G.HasKey("NextNative") || G.Closing || G.NativeBusy || Tick()<G.NextNative)
        return
    G.NextNative:=Tick()+1000, G.NativeBusy:=true, removed:=[]
    try {
        for stateKey,state in G.States {
            id:=state.Id
            if !Same(id) {
                removed.Push(stateKey)
                continue
            }
            if (Active(id) || G.ReadOnly || !state.HasKey("VerifiedTitle"))
                continue
            title:=state.VerifiedTitle
            if (!Trim(title) || Lower(Trim(title))="chatgpt")
                continue
            current:=Caption(id.Hwnd)
            if (state.Owned && current=state.Last)
                continue
            if state.Owned
                state.Owned:=false, state.Original:="", state.Last:=""
            if (Lower(Trim(current))!="chatgpt") {
                state.ProtectedCustom:=true
                continue
            }
            if (Active(id) || !Same(id) || Caption(id.Hwnd)!=current)
                continue
            desired:=RulesCaption(title)
            if WriteCaption(id,desired) {
                state.Original:=current, state.Last:=desired, state.Owned:=true, state.ProtectedCustom:=false
                LogEvent("BackgroundCacheRestored",id,"NativeGenericReset")
            }
        }
        for index,stateKey in removed
            G.States.Delete(stateKey)
    } finally {
        G.NativeBusy:=false
    }
}
BackgroundPoll() {
    global G
    if (G.Closing || G.BgBusy || G.Busy || HasArg("--once"))
        return
    G.BgBusy:=true
    try {
        WinGet, list, List, ahk_class Chrome_WidgetWin_1
        Loop, %list%
        {
            hwnd:=list%A_Index%, id:=Capture(hwnd)
            if (!IsObject(id) || Active(id))
                continue
            stateKey:=Key(id)
            if !G.States.HasKey(stateKey)
                G.States[stateKey]:={Id:id,Original:"",Last:"",Owned:false,Retry:0}
            state:=G.States[stateKey]
            if (state.HasKey("NextBackground") && Tick()<state.NextBackground)
                continue
            state.NextBackground:=Tick()+G.BackgroundMs, G.BgTarget:=stateKey
            result:=ReadIsolated(id,4000,true)
            if (!result.Success || !Same(id) || Active(id))
                break
            title:=RegExReplace(result.Title,"[\x00-\x1F\x7F]")
            if (!Trim(title) || StrLen(title)>240)
                break
            state.VerifiedTitle:=title
            if G.ReadOnly
                break
            current:=Caption(hwnd)
            if (Lower(Trim(title))="chatgpt") {
                RestoreOne(state)
                break
            }
            if (Lower(Trim(current))!="chatgpt" && !(state.Owned && current=state.Last)) {
                state.Owned:=false, state.Original:="", state.Last:="", state.ProtectedCustom:=true
                break
            }
            desired:=RulesCaption(title)
            if (current=desired)
                break
            original:=state.Owned && current=state.Last ? state.Original : current
            if (!Active(id) && Same(id) && Caption(hwnd)=current && WriteCaption(id,desired))
                state.Original:=original, state.Last:=desired, state.Owned:=true, state.ProtectedCustom:=false
            break
        }
    } finally {
        G.BgTarget:="", G.BgBusy:=false
    }
}

ReadIsolated(id,timeout,background:=false) {
    global G
    settingsRevision:=G.HasKey("SettingsRevision")?G.SettingsRevision:0
    Random, suffix, 100000, 999999
    file:=A_Temp "\tdx_chatgpt_" DllCall("GetCurrentProcessId") "_" Tick() "_" suffix ".json"
    command:=WorkerCommand("--read-worker --hwnd " id.Hwnd " --output " Q(file) (background ? " --background" : ""))
    h:=0
    try {
        Run, % command,, Hide, pid
        h:=DllCall("OpenProcess","UInt",0x101001,"Int",0,"UInt",pid,"Ptr")
        if !h
            return {Success:0,Error:"OwnHelperUnavailable"}
        identity:=IdentityFromHandle(h,pid)
        if (!IsObject(identity) || Lower(identity.ExePath)!=Lower(WorkerIdentityPath()))
            return {Success:0,Error:"HelperIdentityMismatch"}
        if background
            G.BgChild:={Handle:h,Id:identity}
        else
            G.Child:={Handle:h,Id:identity}
        started:=Tick()
        while (DllCall("WaitForSingleObject","Ptr",h,"UInt",40,"UInt")=258) {
            if (G.Closing || (G.HasKey("SettingsRevision")?G.SettingsRevision:0)!=settingsRevision || Tick()-started>=timeout) {
                StopChild(background)
                return {Success:0,Error:"ReaderTimeout"}
            }
            CheckStop()
            if (background ? Active(id) || !Same(id) : !Active(id)) {
                StopChild(background)
                return {Success:0,Error:"ForegroundChanged"}
            }
            Sleep, 1
        }
        if ((G.HasKey("SettingsRevision")?G.SettingsRevision:0)!=settingsRevision)
            return {Success:0,Error:"SettingsChanged"}
        FileGetSize, size, % file
        if (!FileExist(file) || size>65536)
            return {Success:0,Error:"ReaderOutputUnavailable"}
        FileRead, data, % "*P65001 " file
        if (JsonField(data,"Success")!=1)
            return {Success:0,Error:"HeaderUnavailable"}
        for index, field in ["Hwnd","Pid","Start","ClassName","ExePath"]
            if (JsonField(data,field)!=id[field])
                return {Success:0,Error:"ReaderIdentityMismatch"}
        if (!Same(id) || JsonField(data,"Locator")!="RawDirect/RootView/NonClientView/ChromeNodeFrameView/ChromeNodeClientView/View/Chrome_WidgetWin_1/Chrome_RenderWidgetHostHWND/Document[RootWebArea].Name")
            return {Success:0,Error:"ReaderIdentityMismatch"}
        return {Success:1,Title:JsonField(data,"Title")}
    } catch e {
        StopChild(background)
        return {Success:0,Error:"ReaderException"}
    } finally {
        if background
            G.BgChild:=0
        else
            G.Child:=0
        if h
            DllCall("CloseHandle","Ptr",h)
        if FileExist(file)
            if FileExist(file)
            FileDelete, %file%
        if FileExist(file ".tmp")
            FileDelete, % file ".tmp"
    }
}
StopChild(background:=false) {
    global G
    if !IsObject(background ? G.BgChild : G.Child)
        return
    child:=background ? G.BgChild : G.Child
    actual:=IdentityFromHandle(child.Handle,child.Id.Pid)
    if (IsObject(actual) && actual.Start=child.Id.Start && Lower(actual.ExePath)=Lower(WorkerIdentityPath())) {
        DllCall("TerminateProcess","Ptr",child.Handle,"UInt",1)
        DllCall("WaitForSingleObject","Ptr",child.Handle,"UInt",800)
    }
}
RestoreOne(state) {
    if (state.Owned && Same(state.Id) && Caption(state.Id.Hwnd)==state.Last) {
        if WriteCaption(state.Id,state.Original)
            state.Owned:=false, state.Last:="", state.Original:=""
    }
}
ExitRestore(reason:="",code:=0) {
    global G
    SetTimer, NameRulesTimer, Off
    RulesClose()
    ThemeDispose()
    G.Closing:=true
    SetTimer, PollTimer, Off
    SetTimer, CheckStopTimer, Off
    SetTimer, BackgroundTimer, Off
    StopChild(true)
    StopChild()
    for key, state in G.States {
        try RestoreOne(state)
    }
    if G.StopEvent
        DllCall("CloseHandle","Ptr",G.StopEvent)
    if G.Mutex {
        DllCall("ReleaseMutex","Ptr",G.Mutex)
        DllCall("CloseHandle","Ptr",G.Mutex)
    }
    G.StopEvent:=0, G.Mutex:=0
    return 0
}
Worker() {
    hwnd:=Arg("--hwnd","0")+0, result:={Success:0,Error:"HeaderUnavailable"}
    try {
        identity:=Capture(hwnd)
        if (!IsObject(identity) || (HasArg("--background") ? Active(identity) : !Active(identity)))
            throw Exception("TargetIdentityUnavailable")
        title:=ReadDocumentName(hwnd)
        if (!Same(identity) || (HasArg("--background") ? Active(identity) : !Active(identity)))
            throw Exception("TargetIdentityChanged")
        result:=identity.Clone(), result.Success:=1, result.Title:=title, result.Error:=""
        result.Locator:="RawDirect/RootView/NonClientView/ChromeNodeFrameView/ChromeNodeClientView/View/Chrome_WidgetWin_1/Chrome_RenderWidgetHostHWND/Document[RootWebArea].Name"
    } catch e {
        result:={Success:0,Error:"HeaderUnavailable"}
    }
    Emit(result,Arg("--output"))
}
ReadDocumentName(hwnd) {
    ; Only the verified RawView DIRECT-child path; never descend into the document.
    uia:=ComObjCreate("{FF48DBA4-60EF-4201-AA87-54103EEF594E}","{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
    if !uia
        throw Exception("UIAutomationUnavailable")
    walker:=0, element:=0, doc:=0
    try {
        CallHR(16,uia,"PtrP",walker)
        CallHR(6,uia,"Ptr",hwnd,"PtrP",element)
        for index, expected in ["RootView","NonClientView","ChromeNodeFrameView","ChromeNodeClientView"
            ,"View","Chrome_WidgetWin_1","Chrome_RenderWidgetHostHWND"] {
            next:=FindDirect(walker,element,expected)
            ObjRelease(element), element:=next
        }
        kind:=0
        CallHR(21,element,"IntP",kind)
        if (kind=50030 && UiaText(element,29)="RootWebArea")
            ObjAddRef(element), doc:=element
        else
            doc:=FindDirect(walker,element,"",true,16)
        title:=UiaText(doc,23)
        if (StrLen(title)>512)
            throw Exception("TitleLengthLimit")
        return title
    } finally {
        if doc
            ObjRelease(doc)
        if element
            ObjRelease(element)
        if walker
            ObjRelease(walker)
        ObjRelease(uia)
    }
}
FindDirect(walker,parent,expectedClass:="",document:=false,limit:=32) {
    child:=0, found:=0, returned:=false, count:=0
    try {
        CallHR(4,walker,"Ptr",parent,"PtrP",child)
        while child {
            if (++count>limit)
                throw Exception("DirectSiblingLimit")
            if document {
                kind:=0
                CallHR(21,child,"IntP",kind)
                match:=kind=50030 && UiaText(child,29)="RootWebArea"
            } else
                match:=UiaText(child,30)=expectedClass
            if match {
                if found
                    throw Exception("VerifiedPathAmbiguous")
                ObjAddRef(child), found:=child
            }
            next:=0
            CallHR(6,walker,"Ptr",child,"PtrP",next)
            ObjRelease(child), child:=next
        }
        if !found
            throw Exception("VerifiedPathUnavailable")
        returned:=true
        return found
    } finally {
        if child
            ObjRelease(child)
        if (found && !returned)
            ObjRelease(found)
    }
}
; PtrP/IntP require ByRef propagation: use fixed helpers instead of variadic copies.
CallHR(index,interface,type1:="",ByRef value1:="",type2:="",ByRef value2:="") {
    address:=NumGet(NumGet(interface+0,0,"Ptr")+index*A_PtrSize,0,"Ptr")
    if (type2!="")
        hr:=DllCall(address,"Ptr",interface,type1,value1,type2,value2,"Int")
    else if (type1!="")
        hr:=DllCall(address,"Ptr",interface,type1,value1,"Int")
    else
        hr:=DllCall(address,"Ptr",interface,"Int")
    if (hr<0)
        throw Exception("UIAutomationHRESULT")
    return hr
}
UiaText(element,index) {
    value:=0
    CallHR(index,element,"PtrP",value)
    try {
        return value ? StrGet(value,"UTF-16") : ""
    } finally {
        if value
            DllCall("oleaut32\SysFreeString","Ptr",value)
    }
}
JS(value) {
    out:=Chr(34)
    Loop, Parse, value
    {
        c:=A_LoopField, code:=Asc(c)
        if (c=Chr(34) || c="\")
            out.="\" c
        else if (code<32)
            out.=Format("\u{:04X}",code)
        else
            out.=c
    }
    return out Chr(34)
}
Json(value,field:="") {
    if IsObject(value) {
        out:="", array:=value.HasKey("__Array"), items:=array ? value.__Array : value
        for key,item in items
            out.=(out!="" ? "," : "") (array ? "" : JS(key) ":") Json(item,key)
        return array ? "[" out "]" : "{" out "}"
    }
    if (field="Success" || field="ReadOnly" || field="RealChatGptAccessed" || field="OwnedCaptionWriteRestore"
        || field="OwnedUiaNameComCall" || field="JsonUnicodeRoundtrip" || field="RawDirectChildCom" || field="PointerBits")
        return value+0
    return JS(value)
}
JsonField(data,field) {
    pattern:=Chr(34) field Chr(34) "\s*:\s*" Chr(34) "((?:\\.|[^" Chr(34) "\\])*)" Chr(34)
    if !RegExMatch(data,pattern,found) {
        if RegExMatch(data,Chr(34) field Chr(34) "\s*:\s*(-?\d+)",number)
            return number1
        return ""
    }
    text:=found1, out:="", i:=1
    while (i<=StrLen(text)) {
        c:=SubStr(text,i++,1)
        if (c!="\") {
            out.=c
            continue
        }
        c:=SubStr(text,i++,1)
        if (c="u")
            out.=Chr("0x" SubStr(text,i,4)), i+=4
        else if (c="n")
            out.="`n"
        else if (c="r")
            out.="`r"
        else if (c="t")
            out.="`t"
        else
            out.=c
    }
    return out
}
Emit(value,file:="") {
    text:=Json(value)
    if !file {
        try FileAppend, % text "`n", *, UTF-8
        return true
    }
    temporary:=file "." DllCall("GetCurrentProcessId") ".tmp"
    try {
        if InStr(FileExist(file),"D")
            throw Exception("OutputPathIsDirectory")
        SplitPath, file,, directory
        if directory
            FileCreateDir, % directory
        if FileExist(temporary)
            FileDelete, % temporary
        FileAppend, % text, % temporary, UTF-8-RAW
        FileMove, % temporary, % file, 1
        return true
    } catch e {
        diagnostic:=Json({Success:0,Error:"OutputWriteFailed",Path:file,Detail:e.Message}) "`n"
        try FileAppend, % diagnostic, **, UTF-8
        return false
    } finally {
        if FileExist(temporary) {
            try FileDelete, % temporary
        }
    }
}

LogEvent(kind,id,code) {
    global G
    key:=kind "|" (IsObject(id)?Key(id):"") "|" code
    if (G.Recent.HasKey(key) && Tick()-G.Recent[key]<30000)
        return
    G.Recent[key]:=Tick()
    try {
        FileCreateDir, % G.LogDir
        text:=Json({Utc:A_NowUTC,Kind:kind,Pid:IsObject(id)?id.Pid:0,Hwnd:IsObject(id)?id.Hwnd:0,Code:code}) "`n"
        file:=G.LogDir "\standalone_ahk_v1_" SubStr(A_Now,1,8) ".jsonl"
        FileAppend, % text, % file, UTF-8-RAW
    }
}
SelfTest() {
    result:={Success:0,Mode:"self-test"}, hwnd:=0
    try {
        Gui, Test:New, +ToolWindow +Hwndhwnd, AHK owned title fixture
        Gui, Test:Add, Text,, Self-owned UIA element only
        Gui, Test:Show, Hide
        id:=Capture(hwnd,false)
        if (!IsObject(id) || !WriteCaption(id,"测试😀 — own window"))
            throw Exception("OwnedCaptionWriteFailed")
        if !WriteCaption(id,"AHK owned title fixture")
            throw Exception("OwnedCaptionRestoreFailed")
        uia:=ComObjCreate("{FF48DBA4-60EF-4201-AA87-54103EEF594E}","{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
        element:=0
        try {
            CallHR(6,uia,"Ptr",hwnd,"PtrP",element)
            name:=UiaText(element,23)
        } finally {
            if element
                ObjRelease(element)
            ObjRelease(uia)
        }
        if (name!="AHK owned title fixture")
            throw Exception("OwnedComNameMismatch")
        sample:="中文😀 " Chr(34) "quoted" Chr(34) " \ slash"
        if (JsonField(Json({Title:sample}),"Title")!=sample)
            throw Exception("JsonRoundtripFailed")
        DispatchSmoke()
        result:={OwnedWorkerDispatch:1,CompiledMode:A_IsCompiled?1:0,Success:1,Mode:"self-test",OwnedCaptionWriteRestore:1,OwnedUiaNameComCall:1
            ,JsonUnicodeRoundtrip:1,RealChatGptAccessed:0,PointerBits:A_PtrSize*8}
    } catch e {
        result.Error:=e.Message, result.Where:=e.What, result.Line:=e.Line
    } finally {
        Gui, Test:Destroy
    }
    Emit(result,Arg("--output"))
}

ValidIntervals(first,second) {
    return RegExMatch(first,"^\d+(?:\.\d+)?$") && RegExMatch(second,"^\d+(?:\.\d+)?$") && first>=1 && first<=3600 && second>=5 && second<=3600
}
LoadIntervalSettings() {
    global G
    first:=G.IntervalMs/1000, second:=G.BackgroundMs/1000
    if FileExist(G.SettingsFile) {
        if !HasArg("--interval")
            IniRead, first, % G.SettingsFile, Timing, ForegroundSeconds, %first%
        if !HasArg("--background-interval")
            IniRead, second, % G.SettingsFile, Timing, BackgroundSeconds, %second%
    }
    if ValidIntervals(first,second)
        G.IntervalMs:=Round(first*1000), G.BackgroundMs:=Round(second*1000)
}
ApplyIntervals(first,second,persist:=true,reschedule:=true) {
    global G
    if !ValidIntervals(first,second)
        throw Exception("Foreground: 1..3600 seconds; background: 5..3600 seconds.")
    if persist {
        if InStr(FileExist(G.SettingsFile),"D")
            throw Exception("SettingsPathIsDirectory")
        SplitPath, % G.SettingsFile,, directory
        FileCreateDir, %directory%
        temporary:=G.SettingsFile "." DllCall("GetCurrentProcessId") ".tmp"
        try {
            IniWrite, %first%, %temporary%, Timing, ForegroundSeconds
            IniWrite, %second%, %temporary%, Timing, BackgroundSeconds
            FileMove, %temporary%, % G.SettingsFile, 1
        } finally {
            if FileExist(temporary) {
                try FileDelete, %temporary%
            }
        }
    }
    G.SettingsRevision:=(G.HasKey("SettingsRevision")?G.SettingsRevision:0)+1
    G.IntervalMs:=Round(first*1000), G.BackgroundMs:=Round(second*1000)
    if reschedule {
        StopChild()
        StopChild(true)
        for stateKey,state in G.States
            state.NextBackground:=0
        period:=G.IntervalMs
        SetTimer, PollTimer, %period%
    }
}
ShowIntervalSettings(show:=true) {
    global G, CxtForeground, CxtBackground, CxtAutoStart
    if (G.HasKey("SettingsHwnd") && DllCall("IsWindow","Ptr",G.SettingsHwnd)) {
        Gui, Settings:Show
        return
    }
    Gui, Settings:New, +ToolWindow +HwndsettingsHwnd +LabelCxtSettings, ChatGPT 标题同步助手 - 扫描间隔设置
    G.SettingsHwnd:=settingsHwnd
    Gui, Settings:Add, Text,, Foreground source (seconds, 1..3600)
    Gui, Settings:Add, Edit, vCxtForeground w200, % G.IntervalMs/1000
    Gui, Settings:Add, Text,, Background source (seconds, 5..3600)
    Gui, Settings:Add, Edit, vCxtBackground w200, % G.BackgroundMs/1000
    option:="vCxtAutoStart w280" (G.AutoStartEnabled?" Checked":"")
    if (!G.AutoStartAllowed || G.AutoStartUnknown)
        option.=" Disabled"
    Gui, Settings:Add, Checkbox, %option%, 开机自启动
    Gui, Settings:Add, Text,, Cached-title repair remains every 1 second.
    Gui, Settings:Add, Button, gCxtSettingsSave Default w90, Save
    Gui, Settings:Add, Button, gCxtSettingsClose x+10 w90, Cancel
    ThemeAddControls()
    Gui, Settings:Add, Button, gTrayNameReplacement x20 y335 w280, Name replacement...
    if show
        Gui, Settings:Show, AutoSize
}
SettingsSelfTest() {
    global G
    G.SettingsFile:=A_Temp "\cxt_settings_v11_" DllCall("GetCurrentProcessId") "\nested\settings.ini"
    G.IntervalMs:=2000, G.BackgroundMs:=5000, G.SettingsRevision:=0
    passed:=0
    try {
        ApplyIntervals(2,15,true,false)
        if (G.IntervalMs!=2000 || G.BackgroundMs!=15000 || G.SettingsRevision!=1)
            throw Exception("LiveValueUpdate")
        passed++
        G.IntervalMs:=2000,G.BackgroundMs:=5000
        LoadIntervalSettings()
        if (G.IntervalMs!=2000 || G.BackgroundMs!=15000)
            throw Exception("PersistedReload")
        passed++
        for _,pair in [[0,30],[3601,30],[1,4],[1,3601],["nan",30]] {
            failed:=false
            try ApplyIntervals(pair[1],pair[2],true,false)
            catch e
                failed:=true
            if (!failed || G.IntervalMs!=2000 || G.BackgroundMs!=15000 || G.SettingsRevision!=1)
                throw Exception("InvalidInputChangedState")
            passed++
        }
        ShowIntervalSettings(false)
        GuiControlGet, currentFirst, Settings:, CxtForeground
        GuiControlGet, currentSecond, Settings:, CxtBackground
        if (currentFirst!=2 || currentSecond!=15)
            throw Exception("SettingsGuiValues")
        Gui, Settings:Destroy
        G.SettingsHwnd:=0, G.BgChild:=0, G.States:={fixture:{NextBackground:123}}
        passed++
        ApplyIntervals(3,20,true,true)
        SetTimer, PollTimer, Off
        if (G.IntervalMs!=3000 || G.BackgroundMs!=20000 || G.SettingsRevision!=2 || G.States.fixture.NextBackground!=0)
            throw Exception("HotScheduleReset")
        passed++
        actualSettings:=G.SettingsFile
        SplitPath, actualSettings,, privateDirectory
        blocked:=privateDirectory "\blocked"
        FileCreateDir, %blocked%
        G.SettingsFile:=blocked
        failed:=false
        try ApplyIntervals(4,25,true,false)
        catch e
            failed:=true
        G.SettingsFile:=actualSettings
        if (!failed || G.IntervalMs!=3000 || G.SettingsRevision!=2 || FileExist(blocked "." DllCall("GetCurrentProcessId") ".tmp"))
            throw Exception("SaveFailureChangedStateOrLeftTemporary")
        passed++
        report:=privateDirectory "\new_reports\result.json"
        if (!Emit({Round:1},report) || !Emit({Round:2},report))
            throw Exception("OutputFirstAndSecondSave")
        FileRead, savedOutput, %report%
        if !InStr(savedOutput,"""Round"":""2""")
            throw Exception("OutputDidNotReplace")
        if (Emit({ExpectedFailure:1},blocked) || FileExist(blocked "." DllCall("GetCurrentProcessId") ".tmp"))
            throw Exception("OutputFailureCleanup")
        passed++
        FileDelete, %report%
        FileRemoveDir, % privateDirectory "\new_reports"
        FileRemoveDir, %blocked%
        Emit({Success:1,Passed:passed,Mode:"settings-self-test",RealChatGptAccessed:0},Arg("--output"))
    } catch e {
        Emit({Success:0,Passed:passed,Error:e.Message,Line:e.Line},Arg("--output"))
    }
    FileDelete, % G.SettingsFile
}


; The only production autostart contract is shared HKCU state. Tests inject private paths.
AutoStartCommand(executable:="",script:="",compiled:=-1) {
    if (compiled=-1)
        compiled:=A_IsCompiled
    if (executable="")
        executable:=compiled?A_ScriptFullPath:A_AhkPath
    if (script="")
        script:=A_ScriptFullPath
    return compiled?Q(executable):Q(executable) " " Q(script)
}
AutoRegRead(path,name) {
    h:=0,status:=DllCall("advapi32\RegOpenKeyExW","Ptr",-2147483647,"WStr",path,"UInt",0,"UInt",1,"Ptr*",h,"UInt")
    if (status=2 || status=3)
        return {Exists:false}
    if status
        throw Exception("Registry read failed: " status)
    try {
        kind:=0,size:=0,status:=DllCall("advapi32\RegQueryValueExW","Ptr",h,"WStr",name,"Ptr",0,"UInt*",kind,"Ptr",0,"UInt*",size,"UInt")
        if (status=2)
            return {Exists:false}
        if status
            throw Exception("Registry query failed: " status)
        item:={Exists:true,Type:kind,Size:size}
        item.SetCapacity("Bytes",Max(size,2))
        status:=DllCall("advapi32\RegQueryValueExW","Ptr",h,"WStr",name,"Ptr",0,"UInt*",kind,"Ptr",item.GetAddress("Bytes"),"UInt*",size,"UInt")
        if status
            throw Exception("Registry data read failed: " status)
        item.Type:=kind,item.Size:=size
        return item
    } finally DllCall("advapi32\RegCloseKey","Ptr",h)
}
AutoRegValue(kind,value) {
    size:=kind=4?4:(StrLen(value)+1)*2,item:={Exists:true,Type:kind,Size:size}
    item.SetCapacity("Bytes",size)
    if (kind=4)
        NumPut(value,item.GetAddress("Bytes"),0,"UInt")
    else
        StrPut(value,item.GetAddress("Bytes"),"UTF-16")
    return item
}
AutoRegEqual(first,second) {
    if (first.Exists!=second.Exists)
        return false
    if !first.Exists
        return true
    if (first.Type!=second.Type || first.Size!=second.Size)
        return false
    Loop, % first.Size
        if (NumGet(first.GetAddress("Bytes"),A_Index-1,"UChar")!=NumGet(second.GetAddress("Bytes"),A_Index-1,"UChar"))
            return false
    return true
}
AutoRegWrite(path,name,item) {
    h:=0
    if item.Exists
        status:=DllCall("advapi32\RegCreateKeyExW","Ptr",-2147483647,"WStr",path,"UInt",0,"Ptr",0,"UInt",0,"UInt",2,"Ptr",0,"Ptr*",h,"Ptr",0,"UInt")
    else
        status:=DllCall("advapi32\RegOpenKeyExW","Ptr",-2147483647,"WStr",path,"UInt",0,"UInt",2,"Ptr*",h,"UInt")
    if (!item.Exists && (status=2 || status=3))
        return 0
    if status
        return status
    try {
        if item.Exists
            return DllCall("advapi32\RegSetValueExW","Ptr",h,"WStr",name,"UInt",0,"UInt",item.Type,"Ptr",item.GetAddress("Bytes"),"UInt",item.Size,"UInt")
        status:=DllCall("advapi32\RegDeleteValueW","Ptr",h,"WStr",name,"UInt")
        return status=2?0:status
    } finally DllCall("advapi32\RegCloseKey","Ptr",h)
}
AutoStartInitialize(runKey:="",prefKey:="",command:="") {
    global G
    G.AutoRunKey:=runKey!=""?runKey:"Software\Microsoft\Windows\CurrentVersion\Run"
    G.AutoPrefKey:=prefKey!=""?prefKey:"Software\ChatGPT-TitleSync"
    G.AutoCommand:=command!=""?command:AutoStartCommand()
    pref:=AutoRegRead(G.AutoPrefKey,"AutoStartEnabled"),enabled:=true
    if pref.Exists {
        if (pref.Type!=4 || pref.Size!=4)
            throw Exception("AutoStartEnabled must be a DWORD containing 0 or 1.")
        enabled:=NumGet(pref.GetAddress("Bytes"),0,"UInt")
        if (enabled!=0 && enabled!=1)
            throw Exception("AutoStartEnabled must be 0 or 1.")
    }
    AutoStartApply(enabled)
}
AutoStartApply(enabled,failPreference:=false) {
    global G
    if (enabled!=0 && enabled!=1)
        throw Exception("Startup state must be 0 or 1.")
    if (enabled && StrLen(G.AutoCommand)>260)
        throw Exception("Start-at-sign-in command exceeds Windows Run's 260-character limit.")
    oldRun:=AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync"),oldPref:=AutoRegRead(G.AutoPrefKey,"AutoStartEnabled")
    wantedRun:=enabled?AutoRegValue(1,G.AutoCommand):{Exists:false},wantedPref:=AutoRegValue(4,enabled)
    status:=AutoRegEqual(oldRun,wantedRun)?0:AutoRegWrite(G.AutoRunKey,"ChatGPT-TitleSync",wantedRun)
    if !status
        status:=AutoRegEqual(oldPref,wantedPref)?0:(failPreference?5:AutoRegWrite(G.AutoPrefKey,"AutoStartEnabled",wantedPref))
    if status {
        first:=AutoRegWrite(G.AutoRunKey,"ChatGPT-TitleSync",oldRun),second:=AutoRegWrite(G.AutoPrefKey,"AutoStartEnabled",oldPref)
        if (first || second)
            G.AutoStartUnknown:=true
        throw Exception("Startup update failed: " status "; rollback=" first "/" second)
    }
    G.AutoStartEnabled:=!!enabled,G.AutoStartUnknown:=false
    SyncAutoStart()
}
SyncAutoStart() {
    global G
    enabled:=G.HasKey("AutoStartEnabled") && G.AutoStartEnabled
    allowed:=G.HasKey("AutoStartAllowed") && G.AutoStartAllowed && !G.AutoStartUnknown
    if (G.HasKey("AutoStartMenuReady") && G.AutoStartMenuReady) {
        action:=enabled?"Check":"Uncheck"
        Menu, Tray, %action%, 开机自启动
        action:=allowed?"Enable":"Disable"
        Menu, Tray, %action%, 开机自启动
    }
    if (G.HasKey("SettingsHwnd") && DllCall("IsWindow","Ptr",G.SettingsHwnd)) {
        GuiControl, Settings:, CxtAutoStart, % enabled
        action:=allowed?"Enable":"Disable"
        GuiControl, Settings:%action%, CxtAutoStart
    }
}
ApplySettingsWithAutoStart(first,second,enabled) {
    global G
    if !ValidIntervals(first,second)
        throw Exception("Foreground: 1..3600 seconds; background: 5..3600 seconds.")
    allowed:=G.HasKey("AutoStartAllowed") && G.AutoStartAllowed,prior:=G.AutoStartEnabled
    if allowed
        AutoStartApply(enabled)
    try ApplyIntervals(first,second)
    catch error {
        if (allowed && enabled!=prior) {
            try AutoStartApply(prior)
            catch rollback
                throw Exception(error.Message "; startup rollback failed: " rollback.Message)
        }
        throw error
    }
}
AutoMenuIsChecked() {
    menu:=MenuGetHandle("Tray"),count:=DllCall("GetMenuItemCount","Ptr",menu)
    Loop, %count% {
        VarSetCapacity(label,512,0)
        DllCall("GetMenuStringW","Ptr",menu,"UInt",A_Index-1,"Ptr",&label,"Int",256,"UInt",0x400)
        if (StrGet(&label,"UTF-16")="开机自启动")
            return !!(DllCall("GetMenuState","Ptr",menu,"UInt",A_Index-1,"UInt",0x400)&8)
    }
    return false
}
AutoStartSelfTest() {
    global G
    base:="Software\ChatGPT-TitleSync-SelfTest\ahk_v11_" DllCall("GetCurrentProcessId") "_" A_TickCount
    G.AutoStartTesting:=true,G.AutoStartAllowed:=true,G.AutoStartMenuReady:=true,G.BgChild:=0,G.IntervalMs:=2000,G.BackgroundMs:=5000
    G.SettingsFile:=A_Temp "\titlesync_autostart_v11_" DllCall("GetCurrentProcessId") ".ini"
    Menu, Tray, Add, 开机自启动, TrayAutoStart
    passed:=0
    try {
        AutoStartInitialize(base "\Run",base "\Preferences",Q("C:\Own app\App.exe"))
        if (!G.AutoStartEnabled || !AutoMenuIsChecked())
            throw Exception("DefaultOn")
        passed++
        AutoStartApply(false)
        if (G.AutoStartEnabled || AutoMenuIsChecked() || AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync").Exists)
            throw Exception("Off")
        passed++
        AutoStartInitialize(base "\Run",base "\Preferences",Q("C:\Own app\Replacement.exe"))
        if G.AutoStartEnabled
            throw Exception("ExplicitZeroNotPreserved")
        passed++
        AutoStartApply(true)
        if !AutoRegEqual(AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync"),AutoRegValue(1,G.AutoCommand))
            throw Exception("AbsoluteCommandUpdate")
        passed++
        oldRun:=AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync"),oldPref:=AutoRegRead(G.AutoPrefKey,"AutoStartEnabled"),failed:=false
        try AutoStartApply(false,true)
        catch e
            failed:=true
        if (!failed || !G.AutoStartEnabled || !AutoRegEqual(oldRun,AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync")) || !AutoRegEqual(oldPref,AutoRegRead(G.AutoPrefKey,"AutoStartEnabled")))
            throw Exception("FailedWriteRollback")
        passed++
        expected:=A_IsCompiled?Q(A_ScriptFullPath):Q(A_AhkPath) " " Q(A_ScriptFullPath)
        if (AutoStartCommand()!=expected)
            throw Exception("StartupCommandArguments")
        passed++
        AutoStartApply(true,true)
        passed++
        normalCommand:=G.AutoCommand,part:=""
        Loop {
            boundary:=AutoStartCommand("C:\Own app\AutoHotkey.exe","C:\" part "\source.ahk",false)
            if (StrLen(boundary)>=260)
                break
            part.="x"
        }
        if (StrLen(boundary)!=260)
            throw Exception("BoundaryConstruction")
        G.AutoCommand:=boundary,AutoStartApply(true)
        passed++
        beforeRun:=AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync"),beforePref:=AutoRegRead(G.AutoPrefKey,"AutoStartEnabled")
        G.AutoCommand:=AutoStartCommand("C:\Own app\AutoHotkey.exe","C:\" part "x\source.ahk",false),failed:=false
        try AutoStartApply(true)
        catch e
            failed:=true
        if (!failed || !AutoRegEqual(beforeRun,AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync")) || !AutoRegEqual(beforePref,AutoRegRead(G.AutoPrefKey,"AutoStartEnabled")))
            throw Exception("LongSourceCommandChangedRegistry")
        passed++
        AutoStartApply(false)
        if (G.AutoStartEnabled || AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync").Exists)
            throw Exception("LongCommandCannotTurnOff")
        passed++
        G.AutoCommand:=normalCommand,AutoStartApply(true)
        ShowIntervalSettings(false)
        GuiControlGet, checkHwnd, Settings:Hwnd, CxtAutoStart
        GuiControlGet, saveHwnd, Settings:Hwnd, Save
        GuiControlGet, cancelHwnd, Settings:Hwnd, Cancel
        checkboxId:=DllCall("GetDlgCtrlID","Ptr",checkHwnd),saveId:=DllCall("GetDlgCtrlID","Ptr",saveHwnd),cancelId:=DllCall("GetDlgCtrlID","Ptr",cancelHwnd)
        GuiControlGet, checkValue, Settings:, CxtAutoStart
        if (checkValue!=1)
            throw Exception("CheckboxInitialValue")
        passed++
        AutoStartApply(false)
        GuiControlGet, checkValue, Settings:, CxtAutoStart
        if (checkValue!=0 || AutoMenuIsChecked())
            throw Exception("MenuToOpenCheckboxSync")
        passed++
        GuiControl, Settings:, CxtAutoStart, 1
        Gui, Settings:Destroy
        G.SettingsHwnd:=0
        if G.AutoStartEnabled
            throw Exception("UnsavedCheckboxApplied")
        passed++
        ShowIntervalSettings(false)
        GuiControl, Settings:, CxtAutoStart, 1
        GuiControlGet, saveHwnd, Settings:Hwnd, Save
        DllCall("PostMessageW","Ptr",saveHwnd,"UInt",0xF5,"Ptr",0,"Ptr",0)
        started:=A_TickCount
        while (G.SettingsHwnd && A_TickCount-started<900)
            Sleep, 10
        SetTimer, PollTimer, Off
        if (!G.AutoStartEnabled || !AutoMenuIsChecked() || G.SettingsHwnd)
            throw Exception("SettingsSaveSync")
        passed++
        Emit({Success:1,Passed:passed,RealRunKeyAccessed:0,RealChatGptAccessed:0,SharedIpcUsed:0,CheckboxId:checkboxId,SaveId:saveId,CancelId:cancelId},Arg("--output"))
    } catch e {
        Emit({Success:0,Passed:passed,Error:e.Message,Line:e.Line,RealRunKeyAccessed:0},Arg("--output"))
    }
    SetTimer, PollTimer, Off
    Gui, Settings:Destroy
    FileDelete, % G.SettingsFile
    RegDelete, HKEY_CURRENT_USER, %base%
}

#Include %A_ScriptDir%\IconTheme.ahk

#Include %A_ScriptDir%\NameReplacement.ahk
