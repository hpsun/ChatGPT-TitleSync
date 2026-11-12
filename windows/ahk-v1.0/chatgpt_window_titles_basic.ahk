; ChatGPT-TitleSync - AutoHotkey Basic title synchronization helper.
; AutoHotkey Basic 1.0.48.05 (ANSI x86). Local draft, not installed.
; UTF-16 captions are BINARY buffers; never converted through ANSI.
; Script/runtime/output paths must be ASCII. Target executable paths may be Unicode.
; --read-only --once; --interval 2; --stop; --self-test
#NoEnv
#Persistent
#SingleInstance Off
SetBatchLines, -1
ExitStatus := 0
AutoAllowed := 0, AutoEnabled := 0, AutoUnknown := 0, AutoMenuReady := 0, AutoTesting := 0, BasicSettingsHwnd := 0
BasicThemeDefaults()
OnExit, Cleanup
Arg1 = %1%
if (A_AhkVersion != "1.0.48.05") {
    MsgBox, 16, ChatGPT-TitleSync - Unsupported runtime, Use official AutoHotkey Basic 1.0.48.05 ANSI x86.
    ExitApp, % ExitStatus := 2
}
if (Arg1 = "--dispatch-probe") {
    Menu, Tray, NoIcon
    ProbeToken = %2%
    ProbeFile = %3%
    ProbeReply := "CXT_DISPATCH " . ProbeToken
    FileAppend, %ProbeReply%, %ProbeFile%
    ExitApp
}
if (Arg1 = "--hang") {
    Menu, Tray, NoIcon
    Loop {
        Sleep, 60000
    }
}
if (Arg1 = "--worker") {
    Menu, Tray, NoIcon
    WorkerHwnd = %2%
    WorkerOutput = %3%
    WorkerBackground = %4%
    status := ReadDocument(WorkerHwnd, WorkerTitle, WorkerBytes, wp, wlo, whi, WorkerBackground)
    WritePacket(WorkerOutput, status, WorkerHwnd, wp, wlo, whi, WorkerTitle, WorkerBytes)
    ExitApp, % ExitStatus := status
}
if (Arg1 = "--check") {
    Menu, Tray, NoIcon
    text := "{" . Chr(34) . "Success" . Chr(34) . ":1," . Chr(34) . "Mode" . Chr(34) . ":" . Chr(34) . "check" . Chr(34) . "," . Chr(34) . "RealRunKeyAccessed" . Chr(34) . ":0}"
    FileAppend, %text%, *
    ExitApp
}
if (Arg1 = "--icon-self-test") {
    Menu, Tray, NoIcon
    ThemeAssetRoot = %2%
    BasicThemeSelfTest(ThemeAssetRoot)
    ExitApp, % ExitStatus
}
if (Arg1 = "--autostart-self-test") {
    Menu, Tray, NoIcon
    BasicAutoSelfTest()
    ExitApp, % ExitStatus
}
if (Arg1 = "--settings-self-test") {
    Menu, Tray, NoIcon
    BasicSettingsSelfTest()
    ExitApp, % ExitStatus
}
MutexName := "Local\TdxChatGptTitleStandalone" ; Keep legacy shared IPC to prevent concurrent old/new writers.
StopName := MutexName . ".Stop"
LogPath := A_ScriptDir . "\chatgpt_window_titles_basic.log"
if (!ASCIIOnly(A_ScriptFullPath) || (!A_IsCompiled && !ASCIIOnly(A_AhkPath))) {
    MsgBox, 16, ChatGPT-TitleSync - ANSI path limit, ChatGPT-TitleSync Basic requires ASCII script and runtime paths.
    ExitApp, % ExitStatus := 2
}
hMutex := DllCall("CreateMutexA", "UInt", 0, "Int", 0, "Str", MutexName, "UInt")
mutexError := DllCall("GetLastError", "UInt")
if (Arg1 = "--stop") {
    if (hMutex)
        DllCall("CloseHandle", "UInt", hMutex)
    hMutex := 0
    e := DllCall("OpenEventA", "UInt", 2, "Int", 0, "Str", StopName, "UInt")
    if (e) {
        DllCall("SetEvent", "UInt", e)
        DllCall("CloseHandle", "UInt", e)
    }
    ExitApp
}
if (!hMutex || mutexError = 183) {
    MsgBox, 16, ChatGPT-TitleSync - Already running, Another AHK/PowerShell/Python standalone monitor is running.
    ExitApp, % ExitStatus := 2
}
hStop := DllCall("CreateEventA", "UInt", 0, "Int", 1, "Int", 0, "Str", StopName, "UInt")
if (!hStop)
    ExitApp, % ExitStatus := 3
DllCall("ResetEvent", "UInt", hStop)
hJob := DllCall("CreateJobObjectA", "UInt", 0, "UInt", 0, "UInt")
VarSetCapacity(jobInfo, 112, 0)
NumPut(0x2000, jobInfo, 16, "UInt")
if (!hJob || !DllCall("SetInformationJobObject", "UInt", hJob, "Int", 9, "UInt", &jobInfo, "UInt", 112)) {
    Log("job_setup_failed")
    ExitApp, % ExitStatus := 3
}
BackgroundInterval := 5
Interval := 2
SettingsRevision := 0
ForegroundExplicit := 0
BackgroundExplicit := 0
ReadOnly := 0
Once := 0
SelfTest := 0
argc = %0%
Loop, %argc%
{
    value := %A_Index%
    if (value = "--read-only")
        ReadOnly := 1
    if (value = "--once")
        Once := 1
    if (value = "--self-test")
        SelfTest := 1
    if (value = "--hwnd") {
        next := A_Index + 1
        FilterHwnd := %next%
    }
    if (value = "--background-interval") {
        BackgroundExplicit := 1
        next := A_Index + 1
        BackgroundInterval := %next%
        if (!RegExMatch(BackgroundInterval,"^\d+(?:\.\d+)?$") || BackgroundInterval<5 || BackgroundInterval>3600)
            ExitApp, % ExitStatus := 2
    }
    if (value = "--interval") {
        ForegroundExplicit := 1
        next := A_Index + 1
        Interval := %next%
        if (!RegExMatch(Interval,"^\d+(?:\.\d+)?$") || Interval<1 || Interval>3600)
            ExitApp, % ExitStatus := 2
    }
}
Tracked := ""
Paused := 0
if (Arg1 = "--job-selftest") {
    Log("job_parent_test_started")
    SpawnBounded("--hang",15000)
    ExitApp
}
if (SelfTest) {
    result := RunSelfTest()
    ExitApp, % ExitStatus := result
}
; Load selected A1 for source mode; compiled mode may use its embedded icon.
iconPath := A_ScriptDir . "\..\..\assets\chatgpt-titlesync-legacy.ico"
if FileExist(iconPath) {
    Menu, Tray, UseErrorLevel
    Menu, Tray, Icon, %iconPath%
    if (ErrorLevel)
        Log("a1_tray_icon_unavailable")
    Menu, Tray, UseErrorLevel, Off
}
EnvGet, settingsRoot, LOCALAPPDATA
SettingsFile := settingsRoot . "\ChatGPT-title\ahk-basic\settings.ini" ; Keep legacy settings so existing user preferences continue to load.
BasicLoadIntervals()
Menu, Tray, NoStandard
Menu, Tray, Tip, ChatGPT-TitleSync - title synchronization helper (Basic)
Menu, Tray, Add, Scan interval settings..., BasicSettingsOpen
Menu, Tray, Add, Name replacement..., BasicRulesEditor
Menu, Tray, Add, Start at sign-in, BasicAutoToggle
Menu, Tray, Disable, Start at sign-in
AutoMenuReady := 1
Menu, Tray, Add, Pause and restore, TogglePause
Menu, Tray, Add, Exit and restore, ExitMonitor
AutoAllowed := !ReadOnly && !Once
if (AutoAllowed) {
    status := BasicAutoInitialize()
    if (status) {
        MsgBox, 16, ChatGPT-TitleSync - Start at sign-in, %AutoError%
        ExitApp, % ExitStatus := 1
    }
} else
    BasicAutoSync()
if (AutoAllowed) {
    themeStatus := BasicThemeInit()
    if (themeStatus)
        BasicThemeError("initialize")
    if (BasicThemeStage(BasicThemeId(),oldIcon,oldIconId,iconChanged))
        BasicThemeError("initial_load")
    else
        BasicThemeFinish(oldIcon,iconChanged)
}
if (!Once) {
    BasicRulesInit()
    SetTimer, BasicRulesTimer, 50
}
Log("started readonly=" . ReadOnly . " interval=" . Interval)
SetTimer, CheckStop, 200
SetTimer, BasicBackgroundTimer, 1000
period := Interval * 1000
SetTimer, ScanTimer, %period%
Gosub, ScanTimer
if (Once)
    ExitApp
Return

BasicRulesTimer:
BasicRulesTick()
Return
BasicRulesEditor:
BasicRulesOpenEditor()
Return
BasicBackgroundTimer:
BasicBackgroundRefresh()
Return
CheckStop:
BasicThemeTick()
BasicNativeMaintenance()
if (DllCall("WaitForSingleObject", "UInt", hStop, "UInt", 0) = 0)
    ExitApp
Return
BasicAutoToggle:
if (!AutoAllowed || AutoRunKey="")
    Return
status := BasicAutoApply(!AutoEnabled)
if (status) {
    BasicAutoSync()
    MsgBox, 16, ChatGPT-TitleSync - Start at sign-in, %AutoError%
}
Return
BasicSettingsOpen:
BasicShowSettings()
Return
BasicSettingsSave:
Gui, 2:Submit, NoHide
if (BasicThemeSave(BasicForeground,BasicBackground,BasicAutoStartup,BasicIconMode=1 ? "fixed" : "random",44+BasicFixedIcon,BasicIconPeriod=1 ? "day" : BasicIconPeriod=2 ? "hour" : "5min")) {
    Gui, 2:Destroy
    BasicSettingsHwnd := 0
} else {
    if (AutoTesting)
        Return
    MsgBox, 16, ChatGPT-TitleSync - Settings, %AutoError%
}
Return
BasicThemeChanged:
BasicThemeFields()
Return
2GuiClose:
2GuiEscape:
Gui, 2:Destroy
BasicSettingsHwnd := 0
Return
TogglePause:
Paused := !Paused
if (Paused) {
    RestoreAll()
    Menu, Tray, Check, Pause and restore
} else {
    Menu, Tray, Uncheck, Pause and restore
}
Return
ExitMonitor:
ExitApp
Return
ScanTimer:
if (Paused || Busy)
    Return
Busy := 1
WindowList := ""
activeHwnd := DllCall("GetForegroundWindow","UInt")
if ((!FilterHwnd || activeHwnd=FilterHwnd) && GetIdentity(activeHwnd,p,l,h,path,pb,cls,cb) && Eligible(path,pb,cls))
    WindowList := activeHwnd . "|"
if (LastActiveHwnd!=activeHwnd) {
    LastActiveHwnd := activeHwnd
    if (!Rec%activeHwnd%_RetryCustom)
        Rec%activeHwnd%_Retry := 0
}
Loop, Parse, WindowList, |
{
    hwnd := A_LoopField
    if (!hwnd)
        Continue
    if (DllCall("WaitForSingleObject", "UInt", hStop, "UInt", 0) = 0)
        Break
    if (DllCall("GetForegroundWindow","UInt")!=hwnd)
        Continue
    if (!GetIdentity(hwnd, pid, lo, hi, ipath, plen, iclass, clen))
        Continue
    if (ReadCaption(hwnd,earlyCaption,earlyBytes) && WideEqualsASCII(&earlyCaption,"ChatGPT"))
        Rec%hwnd%_Retry := 0, Rec%hwnd%_RetryCustom := 0
    packet := A_ScriptDir . "\basic_worker_" . DllCall("GetCurrentProcessId") . ".bin"
    cmd := "--worker " . hwnd . " " . Quote(packet)
    FileDelete, %packet%
    if (BgTarget=hwnd && hBgWorker)
        DllCall("TerminateProcess","UInt",hBgWorker,"UInt",126)
    ActiveReadHwnd := hwnd
    childStatus := SpawnBounded(cmd, 4000)
    ActiveReadHwnd := 0
    if (DllCall("GetForegroundWindow","UInt")!=hwnd)
        Continue
    if (childStatus != 0 || !ReadPacket(packet, hwnd, pid, lo, hi, Title, titleBytes)) {
        Log("read_failed hwnd=" . hwnd . " pid=" . pid . " status=" . childStatus)
        Continue
    }
    if (ReadOnly)
        FileCopy, %packet%, %A_ScriptDir%\basic_last_readonly.bin, 1
    FileDelete, %packet%
    if (!GetIdentity(hwnd, pid2, lo2, hi2, ipath2, plen2, iclass2, clen2) || pid != pid2 || lo != lo2 || hi != hi2 || !BinaryEqual(ipath,plen,ipath2,plen2))
        Continue
    RememberTitleBasic(hwnd,Title,titleBytes,pid,lo,hi)
    if (ReadOnly) {
        Log("read_ok hwnd=" . hwnd . " pid=" . pid . " utf16bytes=" . titleBytes)
        Continue
    }
    if (WideEqualsASCII(&Title,"ChatGPT")) {
        RestoreOneBasic(hwnd)
        Continue
    }
    if (!ReadCaption(hwnd, current, currentBytes))
        Continue
    if (Rec%hwnd%_RetryCustom && !WideEqualsASCII(&current,"ChatGPT"))
        Continue
    BuildWanted(Title, titleBytes, Wanted, wantedBytes)
    if (BinaryEqual(current,currentBytes,Wanted,wantedBytes))
        Continue
    if (Rec%hwnd%_Owned && !MatchesRecord(hwnd)) {
        Rec%hwnd%_Owned := 0
        Log("window_identity_changed hwnd=" . hwnd)
    }
    if (Rec%hwnd%_Owned && !BinaryEqual(current,currentBytes,Rec%hwnd%_Last,Rec%hwnd%_LastBytes)) {
        Rec%hwnd%_Owned := 0
        Rec%hwnd%_RetryCustom := !WideEqualsASCII(&current,"ChatGPT")
        Rec%hwnd%_Retry := Rec%hwnd%_RetryCustom  ?  A_TickCount+30000  :  0
        Log("external_caption_change hwnd=" . hwnd)
        if (Rec%hwnd%_RetryCustom)
            Continue
    }
    if (!Rec%hwnd%_Owned) {
        if (!StoreIdentity(hwnd,pid,lo,hi))
            Continue
        CopyBinary(Rec%hwnd%_Original, current, currentBytes)
        Rec%hwnd%_OriginalBytes := currentBytes
    }
    if (DllCall("GetForegroundWindow","UInt")!=hwnd || !MatchesRecord(hwnd))
        Continue
    if (SetCaptionChecked(hwnd, Wanted, wantedBytes) && MatchesRecord(hwnd)) {
        CopyBinary(Rec%hwnd%_Last, Wanted, wantedBytes)
        Rec%hwnd%_LastBytes := wantedBytes
        Rec%hwnd%_Owned := 1
        if (!InStr("|" . Tracked . "|", "|" . hwnd . "|"))
            Tracked .= hwnd . "|"
        Log("caption_updated hwnd=" . hwnd . " pid=" . pid)
    } else {
        Log("write_failed hwnd=" . hwnd)
    }
}
Busy := 0
Return
Cleanup:
SetTimer, BasicRulesTimer, Off
BasicRulesClose()
BasicThemeDispose()
if (hBgWorker) {
    DllCall("TerminateProcess","UInt",hBgWorker,"UInt",125)
    DllCall("WaitForSingleObject","UInt",hBgWorker,"UInt",1000)
    DllCall("CloseHandle","UInt",hBgWorker)
    hBgWorker := 0
}
if (hWorker) {
    DllCall("TerminateProcess", "UInt", hWorker, "UInt", 125)
    DllCall("WaitForSingleObject", "UInt", hWorker, "UInt", 1000)
    DllCall("CloseHandle", "UInt", hWorker)
    hWorker := 0
}
RestoreAll()
if (hJob)
    DllCall("CloseHandle", "UInt", hJob)
if (hStop)
    DllCall("CloseHandle", "UInt", hStop)
if (hMutex)
    DllCall("CloseHandle", "UInt", hMutex)
ExitApp, %ExitStatus%

RememberTitleBasic(hwnd, ByRef title, bytes, pid, lo, hi) {
    global
    if (Rec%hwnd%_Pid && !MatchesRecord(hwnd))
        Rec%hwnd%_Owned := 0, Rec%hwnd%_RetryCustom := 0, Rec%hwnd%_Retry := 0, Rec%hwnd%_CachedBytes := 0
    if (!StoreIdentity(hwnd,pid,lo,hi))
        return 0
    CopyBinary(Rec%hwnd%_Cached,title,bytes)
    Rec%hwnd%_CachedBytes := bytes
    Rec%hwnd%_NextBackground := A_TickCount+BackgroundInterval*1000
    if (!InStr("|" . Tracked . "|", "|" . hwnd . "|"))
        Tracked .= hwnd . "|"
    return 1
}
BasicNativeMaintenance() {
    global
    local hwnd,current,cb,wanted,wb
    if (Paused || NativeBusy || A_TickCount<NextNative)
        return
    NativeBusy := 1, NextNative := A_TickCount+1000
    Loop, Parse, Tracked, |
    {
        hwnd := A_LoopField
        if (!hwnd)
            Continue
        if (!MatchesRecord(hwnd)) {
            Rec%hwnd%_Owned := 0, Rec%hwnd%_CachedBytes := 0, Rec%hwnd%_RetryCustom := 0, Rec%hwnd%_Retry := 0, Rec%hwnd%_NextBackground := 0
            Continue
        }
        if (ReadOnly || DllCall("GetForegroundWindow","UInt")=hwnd || !Rec%hwnd%_CachedBytes || WideEqualsASCII(&Rec%hwnd%_Cached,"ChatGPT"))
            Continue
        if (!ReadCaption(hwnd,current,cb))
            Continue
        if (Rec%hwnd%_Owned && BinaryEqual(current,cb,Rec%hwnd%_Last,Rec%hwnd%_LastBytes))
            Continue
        Rec%hwnd%_Owned := 0
        if (!WideEqualsASCII(&current,"ChatGPT")) {
            Rec%hwnd%_RetryCustom := 1
            Continue
        }
        BuildWanted(Rec%hwnd%_Cached,Rec%hwnd%_CachedBytes,wanted,wb)
        if (DllCall("GetForegroundWindow","UInt")=hwnd || !MatchesRecord(hwnd))
            Continue
        if (SetCaptionChecked(hwnd,wanted,wb) && MatchesRecord(hwnd)) {
            CopyBinary(Rec%hwnd%_Original,current,cb), Rec%hwnd%_OriginalBytes := cb
            CopyBinary(Rec%hwnd%_Last,wanted,wb), Rec%hwnd%_LastBytes := wb
            Rec%hwnd%_Owned := 1, Rec%hwnd%_RetryCustom := 0
            Log("background_cache_restored hwnd=" . hwnd)
        }
    }
    NativeBusy := 0
}
BasicBackgroundRefresh() {
    global
    local list,hwnd,p,l,h,path,pb,cls,cb,packet,cmd,status,title,tb,p2,l2,h2,path2,pb2,cls2,cb2,current,bytes,wanted,wb,previousOwned,previousOriginal,previousBytes
    if (Paused || Busy || BgBusy || Once)
        return
    BgBusy := 1
    WinGet, list, List, ahk_class Chrome_WidgetWin_1
    Loop, %list%
    {
        hwnd := list%A_Index%
        if ((FilterHwnd && hwnd!=FilterHwnd) || DllCall("GetForegroundWindow","UInt")=hwnd || !GetIdentity(hwnd,p,l,h,path,pb,cls,cb) || !Eligible(path,pb,cls))
            Continue
        if (Rec%hwnd%_NextBackground && A_TickCount<Rec%hwnd%_NextBackground)
            Continue
        Rec%hwnd%_NextBackground := A_TickCount+BackgroundInterval*1000
        packet := A_ScriptDir . "\basic_bg_worker_" . DllCall("GetCurrentProcessId") . ".bin"
        FileDelete, %packet%
        BgTarget := hwnd
        cmd := "--worker " . hwnd . " " . Quote(packet) . " 1"
        status := SpawnBounded(cmd,4000,1)
        if (status!=0 || DllCall("GetForegroundWindow","UInt")=hwnd || !ReadPacket(packet,hwnd,p,l,h,title,tb))
            Break
        FileDelete, %packet%
        if (!GetIdentity(hwnd,p2,l2,h2,path2,pb2,cls2,cb2) || p2!=p || l2!=l || h2!=h || !BinaryEqual(path,pb,path2,pb2))
            Break
        if (!RememberTitleBasic(hwnd,title,tb,p,l,h) || ReadOnly)
            Break
        if (WideEqualsASCII(&title,"ChatGPT")) {
            RestoreOneBasic(hwnd,1)
            Break
        }
        if (!ReadCaption(hwnd,current,bytes))
            Break
        previousOwned := Rec%hwnd%_Owned && BinaryEqual(current,bytes,Rec%hwnd%_Last,Rec%hwnd%_LastBytes)
        if (!WideEqualsASCII(&current,"ChatGPT") && !previousOwned) {
            Rec%hwnd%_Owned := 0, Rec%hwnd%_RetryCustom := 1
            Break
        }
        if (previousOwned) {
            CopyBinary(previousOriginal,Rec%hwnd%_Original,Rec%hwnd%_OriginalBytes)
            previousBytes := Rec%hwnd%_OriginalBytes
        } else {
            CopyBinary(previousOriginal,current,bytes), previousBytes := bytes
        }
        BuildWanted(title,tb,wanted,wb)
        if (BinaryEqual(current,bytes,wanted,wb))
            Break
        if (DllCall("GetForegroundWindow","UInt")!=hwnd && MatchesRecord(hwnd) && SetCaptionChecked(hwnd,wanted,wb)) {
            CopyBinary(Rec%hwnd%_Original,previousOriginal,previousBytes), Rec%hwnd%_OriginalBytes := previousBytes
            CopyBinary(Rec%hwnd%_Last,wanted,wb), Rec%hwnd%_LastBytes := wb
            Rec%hwnd%_Owned := 1, Rec%hwnd%_RetryCustom := 0
        }
        Break
    }
    BgTarget := 0, BgBusy := 0
}

Quote(s) {
    return Chr(34) . s . Chr(34)
}
ASCIIOnly(s) {
    Loop, Parse, s
        if (Asc(A_LoopField) > 127)
            return 0
    return 1
}
Log(s) {
    global LogPath
    if (LogPath = "")
        return
    FormatTime, now,, yyyy-MM-dd HH:mm:ss
    line := now . " " . s . Chr(13) . Chr(10)
    FileAppend, %line%, %LogPath%
}
CopyBinary(ByRef dst, ByRef src, bytes) {
    VarSetCapacity(dst, bytes+2, 0)
    if (bytes)
        DllCall("RtlMoveMemory", "UInt", &dst, "UInt", &src, "UInt", bytes)
}
BinaryEqual(ByRef a, alen, ByRef b, blen) {
    return alen=blen && (!alen || DllCall("ntdll\RtlCompareMemory","UInt",&a,"UInt",&b,"UInt",alen,"UInt")=alen)
}
WideEqualsASCII(ptr, ascii) {
    len := StrLen(ascii)
    Loop, %len%
        if (NumGet(ptr+2*(A_Index-1),0,"UShort") != Asc(SubStr(ascii,A_Index,1)))
            return 0
    return NumGet(ptr+2*len,0,"UShort")=0
}
ToWide(ascii, ByRef buf) {
    len := StrLen(ascii)
    VarSetCapacity(buf,(len+1)*2,0)
    Loop, %len%
        NumPut(Asc(SubStr(ascii,A_Index,1)),buf,2*(A_Index-1),"UShort")
}
GetIdentity(hwnd, ByRef pid, ByRef lo, ByRef hi, ByRef path, ByRef pathBytes, ByRef cls, ByRef classBytes) {
    if (!DllCall("IsWindow","UInt",hwnd))
        return 0
    pid := 0
    DllCall("GetWindowThreadProcessId","UInt",hwnd,"UIntP",pid)
    VarSetCapacity(cls,512,0)
    chars := DllCall("GetClassNameW","UInt",hwnd,"UInt",&cls,"Int",256)
    classBytes := chars*2
    ph := DllCall("OpenProcess","UInt",0x1000,"Int",0,"UInt",pid,"UInt")
    if (!ph)
        return 0
    VarSetCapacity(created,8,0), VarSetCapacity(ended,8,0), VarSetCapacity(kernel,8,0), VarSetCapacity(user,8,0)
    ok := DllCall("GetProcessTimes","UInt",ph,"UInt",&created,"UInt",&ended,"UInt",&kernel,"UInt",&user)
    lo := NumGet(created,0,"UInt"), hi := NumGet(created,4,"UInt")
    VarSetCapacity(path,65536,0)
    chars := 32768
    ok2 := DllCall("QueryFullProcessImageNameW","UInt",ph,"UInt",0,"UInt",&path,"UIntP",chars)
    DllCall("CloseHandle","UInt",ph)
    pathBytes := chars*2
    return ok && ok2 && classBytes>0
}
Eligible(ByRef path, bytes, ByRef cls) {
    if (!WideEqualsASCII(&cls,"Chrome_WidgetWin_1"))
        return 0
    suffix := "\chatgpt.exe"
    n := StrLen(suffix)
    if (bytes<n*2)
        return 0
    Loop, %n%
{
        c := NumGet(path,bytes-n*2+(A_Index-1)*2,"UShort")
        if (c>=65 && c<=90)
            c += 32
        if (c != Asc(SubStr(suffix,A_Index,1)))
            return 0
    }
    return 1
}
StoreIdentity(hwnd, expectedPid=0, expectedLo=0, expectedHi=0) {
    global
    local p,l,h,path,pb,cls,cb
    if (!GetIdentity(hwnd,p,l,h,path,pb,cls,cb))
        return 0
    if (expectedPid && (p!=expectedPid || l!=expectedLo || h!=expectedHi || !Eligible(path,pb,cls)))
        return 0
    Rec%hwnd%_Pid := p, Rec%hwnd%_Lo := l, Rec%hwnd%_Hi := h
    CopyBinary(Rec%hwnd%_Path,path,pb), Rec%hwnd%_PathBytes := pb
    CopyBinary(Rec%hwnd%_Class,cls,cb), Rec%hwnd%_ClassBytes := cb
    return 1
}
MatchesRecord(hwnd) {
    global
    local p,l,h,path,pb,cls,cb
    return GetIdentity(hwnd,p,l,h,path,pb,cls,cb) && p=Rec%hwnd%_Pid && l=Rec%hwnd%_Lo && h=Rec%hwnd%_Hi && BinaryEqual(path,pb,Rec%hwnd%_Path,Rec%hwnd%_PathBytes) && BinaryEqual(cls,cb,Rec%hwnd%_Class,Rec%hwnd%_ClassBytes)
}
ReadCaption(hwnd, ByRef buf, ByRef bytes) {
    if (!DllCall("IsWindow","UInt",hwnd))
        return 0
    chars := DllCall("GetWindowTextLengthW","UInt",hwnd,"Int")
    if (chars<0 || chars>4096)
        return 0
    VarSetCapacity(buf,(chars+1)*2,0)
    n := DllCall("GetWindowTextW","UInt",hwnd,"UInt",&buf,"Int",chars+1,"Int")
    bytes := n*2
    return 1
}
SetCaptionChecked(hwnd, ByRef text, bytes) {
    result := 0
    DllCall("SetLastError","UInt",0)
    ok := DllCall("SendMessageTimeoutW","UInt",hwnd,"UInt",0xC,"UInt",0,"UInt",&text,"UInt",0x23,"UInt",500,"UIntP",result,"UInt")
    return ok && result && ReadCaption(hwnd,back,blen) && BinaryEqual(text,bytes,back,blen)
}
BuildWanted(ByRef title, bytes, ByRef wanted, ByRef wb) {
    BasicRulesDisplay(title,bytes,display,displayBytes)
    BuildRawWanted(display,displayBytes,wanted,wb)
}
BuildRawWanted(ByRef title, bytes, ByRef wanted, ByRef wb) {
    VarSetCapacity(wanted,bytes+22,0)
    if (bytes)
        DllCall("RtlMoveMemory","UInt",&wanted,"UInt",&title,"UInt",bytes)
    NumPut(32,wanted,bytes,"UShort"), NumPut(0x2014,wanted,bytes+2,"UShort"), NumPut(32,wanted,bytes+4,"UShort")
    suffix := "ChatGPT"
    Loop, 7
        NumPut(Asc(SubStr(suffix,A_Index,1)),wanted,bytes+4+A_Index*2,"UShort")
    wb := bytes+20
}
RestoreOneBasic(hwnd,background=0) {
    global
    local current,cb
    if (!background && DllCall("GetForegroundWindow","UInt")!=hwnd)
        return
    if (background && DllCall("GetForegroundWindow","UInt")=hwnd)
        return
    if (Rec%hwnd%_Owned && MatchesRecord(hwnd) && ReadCaption(hwnd,current,cb) && BinaryEqual(current,cb,Rec%hwnd%_Last,Rec%hwnd%_LastBytes)) {
        if (SetCaptionChecked(hwnd,Rec%hwnd%_Original,Rec%hwnd%_OriginalBytes))
            Rec%hwnd%_Owned := 0
    }
}
RestoreAll() {
    global
    local hwnd,current,cb
    Loop, Parse, Tracked, |
    {
        hwnd := A_LoopField
        if (!hwnd || !Rec%hwnd%_Owned)
            Continue
        if (!MatchesRecord(hwnd) || !ReadCaption(hwnd,current,cb) || !BinaryEqual(current,cb,Rec%hwnd%_Last,Rec%hwnd%_LastBytes)) {
            Log("restore_skipped_identity_or_external hwnd=" . hwnd)
            Continue
        }
        if (SetCaptionChecked(hwnd,Rec%hwnd%_Original,Rec%hwnd%_OriginalBytes)) {
            Rec%hwnd%_Owned := 0
            Log("restored hwnd=" . hwnd)
        } else {
            Log("restore_failed hwnd=" . hwnd)
        }
    }
}
WorkerCommandBasic(executable,script,args,compiled) {
    return compiled  ?  Quote(executable) . " " . args  :  Quote(executable) . " /ErrorStdOut " . Quote(script) . " " . args
}
SpawnBounded(args, limit, background=0) {
    global hJob, hWorker, hBgWorker, ActiveReadHwnd, BgTarget, SettingsRevision
    settingsRevisionAtStart := SettingsRevision
    executable := A_IsCompiled  ?  A_ScriptFullPath  :  A_AhkPath
    command := WorkerCommandBasic(executable,A_ScriptFullPath,args,A_IsCompiled)
    VarSetCapacity(si,68,0), VarSetCapacity(pi,16,0)
    NumPut(68,si,0,"UInt")
    ok := DllCall("CreateProcessA","Str",executable,"Str",command,"UInt",0,"UInt",0,"Int",0,"UInt",0x08000004,"UInt",0,"Str",A_ScriptDir,"UInt",&si,"UInt",&pi)
    if (!ok)
        return 101
    childHandle := NumGet(pi,0,"UInt")
    if (background)
        hBgWorker := childHandle
    else
        hWorker := childHandle
    thread := NumGet(pi,4,"UInt")
    if (!DllCall("AssignProcessToJobObject","UInt",hJob,"UInt",childHandle)) {
        DllCall("TerminateProcess","UInt",childHandle,"UInt",102)
        DllCall("CloseHandle","UInt",thread), DllCall("CloseHandle","UInt",childHandle)
        childHandle := 0
        if (background)
            hBgWorker := 0
        else
            hWorker := 0
        return 102
    }
    Log("child_started pid=" . NumGet(pi,8,"UInt"))
    DllCall("ResumeThread","UInt",thread)
    DllCall("CloseHandle","UInt",thread)
    started := A_TickCount
    wait := 258
    focusLost := 0
    while (wait=258) {
        ; Recheck completion before elapsed time: an AHK timer may have suspended this thread.
        wait := DllCall("WaitForSingleObject","UInt",childHandle,"UInt",40,"UInt")
        if (wait!=258 || SettingsRevision!=settingsRevisionAtStart || A_TickCount-started>=limit)
            Break
        if ((background && DllCall("GetForegroundWindow","UInt")=BgTarget) || (!background && ActiveReadHwnd && DllCall("GetForegroundWindow","UInt")!=ActiveReadHwnd)) {
            focusLost := 1
            Break
        }
    }
    if (wait=258 && !focusLost)
        wait := DllCall("WaitForSingleObject","UInt",childHandle,"UInt",0,"UInt")
    if (wait=258 || focusLost) {
        DllCall("TerminateProcess","UInt",childHandle,"UInt",124)
        DllCall("WaitForSingleObject","UInt",childHandle,"UInt",1000)
        status := focusLost  ?  126  :  124
    } else if (wait=0) {
        DllCall("GetExitCodeProcess","UInt",childHandle,"UIntP",status)
    } else {
        DllCall("TerminateProcess","UInt",childHandle,"UInt",103)
        status := 103
    }
    DllCall("CloseHandle","UInt",childHandle)
    if (background)
        hBgWorker := 0
    else
        hWorker := 0
    if (SettingsRevision!=settingsRevisionAtStart)
        status := 127
    return status
}
ComFn(ptr,index) {
    return NumGet(NumGet(ptr+0,0,"UInt")+index*4,0,"UInt")
}
Release(ptr) {
    if (ptr)
        DllCall(ComFn(ptr,2),"UInt",ptr,"UInt")
}
GetBstr(ptr,index, ByRef value) {
    value := 0
    return DllCall(ComFn(ptr,index),"UInt",ptr,"UIntP",value,"Int")
}
FreeBstr(ptr) {
    if (ptr)
        DllCall("OleAut32\SysFreeString","UInt",ptr)
}
FirstChild(walker,parent,cache,ByRef child) {
    child := 0
    return DllCall(ComFn(walker,10),"UInt",walker,"UInt",parent,"UInt",cache,"UIntP",child,"Int")
}
NextChild(walker,previous,cache,ByRef child) {
    child := 0
    return DllCall(ComFn(walker,12),"UInt",walker,"UInt",previous,"UInt",cache,"UIntP",child,"Int")
}
FindClass(parent,walker,cache,ascii,ByRef selected) {
    selected := 0
    count := 0
    if (FirstChild(walker,parent,cache,child)<0)
        return 0
    Loop, 32
{
        if (!child)
            Break
        hr := NextChild(walker,child,cache,next)
        GetBstr(child,62,bstr)
        match := bstr && WideEqualsASCII(bstr,ascii)
        FreeBstr(bstr)
        if (match) {
            count++
            if (count=1)
                selected := child
            else
                Release(child)
        } else {
            Release(child)
        }
        child := next
        if (hr<0)
            Break
    }
    if (child || hr<0 || count!=1) {
        Release(child), Release(selected)
        selected := 0
        return 0
    }
    return 1
}
ReadDocument(hwnd, ByRef title, ByRef bytes, ByRef pid, ByRef lo, ByRef hi, background=0) {
    bytes := 0
    if ((background && DllCall("GetForegroundWindow","UInt")=hwnd) || (!background && DllCall("GetForegroundWindow","UInt")!=hwnd))
        return 15
    if (!GetIdentity(hwnd,pid,lo,hi,path,pb,cls,cb) || !Eligible(path,pb,cls))
        return 10
    hr := DllCall("Ole32\CoInitializeEx","UInt",0,"UInt",0,"Int")
    if (hr<0)
        return 11
    ToWide("{FF48DBA4-60EF-4201-AA87-54103EEF594E}",cs)
    ToWide("{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}",is)
    VarSetCapacity(clsid,16,0), VarSetCapacity(iid,16,0)
    DllCall("Ole32\CLSIDFromString","UInt",&cs,"UInt",&clsid)
    DllCall("Ole32\CLSIDFromString","UInt",&is,"UInt",&iid)
    api := 0, walker := 0, cache := 0, node := 0, doc := 0
    status := 12
    if (DllCall("Ole32\CoCreateInstance","UInt",&clsid,"UInt",0,"UInt",1,"UInt",&iid,"UIntP",api,"Int")>=0) {
        if (DllCall(ComFn(api,16),"UInt",api,"UIntP",walker,"Int")>=0 && DllCall(ComFn(api,20),"UInt",api,"UIntP",cache,"Int")>=0) {
            DllCall(ComFn(cache,7),"UInt",cache,"Int",1,"Int")
            properties := "30003|30005|30011|30012|30019"
            Loop, Parse, properties, |
                DllCall(ComFn(cache,3),"UInt",cache,"Int",A_LoopField,"Int")
            if (DllCall(ComFn(api,10),"UInt",api,"UInt",hwnd,"UInt",cache,"UIntP",node,"Int")>=0) {
                status := 13
                classes := "RootView|NonClientView|ChromeNodeFrameView|ChromeNodeClientView|View|Chrome_WidgetWin_1|Chrome_RenderWidgetHostHWND"
                pathOK := 1
                Loop, Parse, classes, |
                {
                    if (!FindClass(node,walker,cache,A_LoopField,selected)) {
                        pathOK := 0
                        Break
                    }
                    Release(node)
                    node := selected
                }
                if (pathOK && FirstChild(walker,node,cache,child)>=0) {
                    count := 0
                    Loop, 16
{
                        if (!child)
                            Break
                        hr := NextChild(walker,child,cache,next)
                        ctype := 0, password := 0
                        DllCall(ComFn(child,53),"UInt",child,"IntP",ctype,"Int")
                        GetBstr(child,61,bid)
                        match := ctype=50030 && bid && WideEqualsASCII(bid,"RootWebArea")
                        FreeBstr(bid)
                        if (match) {
                            count++
                            if (count=1)
                                doc := child
                            else
                                Release(child)
                        } else {
                            Release(child)
                        }
                        child := next
                        if (hr<0)
                            Break
                    }
                    if (!child && hr>=0 && count=1) {
                        DllCall(ComFn(doc,67),"UInt",doc,"IntP",password,"Int")
                        if (!password && GetBstr(doc,55,bname)>=0 && bname) {
                            chars := DllCall("OleAut32\SysStringLen","UInt",bname,"UInt")
                            if (chars>0 && chars<=512) {
                                bytes := chars*2
                                VarSetCapacity(title,bytes+2,0)
                                DllCall("RtlMoveMemory","UInt",&title,"UInt",bname,"UInt",bytes)
                                status := 0
                            }
                            FreeBstr(bname)
                        }
                    }
                    Release(child)
                }
            }
        }
    }
    Release(doc), Release(node), Release(cache), Release(walker), Release(api)
    DllCall("Ole32\CoUninitialize")
    if ((background && DllCall("GetForegroundWindow","UInt")=hwnd) || (!background && DllCall("GetForegroundWindow","UInt")!=hwnd))
        status := 15
    if (!GetIdentity(hwnd,p2,l2,h2,path2,pb2,cls2,cb2) || p2!=pid || l2!=lo || h2!=hi || !BinaryEqual(path,pb,path2,pb2))
        status := 14
    return status
}
WritePacket(file,status,hwnd,pid,lo,hi,ByRef title,bytes) {
    if (status)
        bytes := 0
    VarSetCapacity(header,32,0)
    NumPut(0x31545843,header,0,"UInt"), NumPut(status,header,4,"UInt")
    NumPut(hwnd+0,header,8,"UInt"), NumPut(pid,header,12,"UInt"), NumPut(lo,header,16,"UInt"), NumPut(hi,header,20,"UInt"), NumPut(bytes,header,24,"UInt")
    f := DllCall("CreateFileA","Str",file,"UInt",0x40000000,"UInt",1,"UInt",0,"UInt",2,"UInt",0x80,"UInt",0,"UInt")
    if (f=0xFFFFFFFF)
        return 0
    DllCall("WriteFile","UInt",f,"UInt",&header,"UInt",32,"UIntP",written,"UInt",0)
    if (bytes)
        DllCall("WriteFile","UInt",f,"UInt",&title,"UInt",bytes,"UIntP",written,"UInt",0)
    DllCall("CloseHandle","UInt",f)
    return 1
}
ReadPacket(file,hwnd,pid,lo,hi,ByRef title,ByRef bytes) {
    f := DllCall("CreateFileA","Str",file,"UInt",0x80000000,"UInt",1,"UInt",0,"UInt",3,"UInt",0x80,"UInt",0,"UInt")
    if (f=0xFFFFFFFF)
        return 0
    size := DllCall("GetFileSize","UInt",f,"UInt",0,"UInt")
    if (size<32 || size>1056) {
        DllCall("CloseHandle","UInt",f)
        return 0
    }
    VarSetCapacity(packet,size,0)
    ok := DllCall("ReadFile","UInt",f,"UInt",&packet,"UInt",size,"UIntP",got,"UInt",0)
    DllCall("CloseHandle","UInt",f)
    bytes := NumGet(packet,24,"UInt")
    if (!ok || got!=size || NumGet(packet,0,"UInt")!=0x31545843 || NumGet(packet,4,"UInt") || NumGet(packet,8,"UInt")!=hwnd || NumGet(packet,12,"UInt")!=pid || NumGet(packet,16,"UInt")!=lo || NumGet(packet,20,"UInt")!=hi || bytes<2 || bytes>1024 || Mod(bytes,2) || size!=32+bytes)
        return 0
    VarSetCapacity(title,bytes+2,0)
    DllCall("RtlMoveMemory","UInt",&title,"UInt",&packet+32,"UInt",bytes)
    return 1
}
RunSelfTest() {
    global
    resultFile := A_ScriptDir . "\basic_selftest_result.txt"
    FileDelete, %resultFile%
    ToWide("STATIC",fixtureClass)
    ToWide("Basic own Unicode fixture",fixtureInitial)
    hwnd := DllCall("CreateWindowExW","UInt",0x80,"UInt",&fixtureClass,"UInt",&fixtureInitial,"UInt",0x10CF0000,"Int",-32000,"Int",-32000,"Int",180,"Int",80,"UInt",0,"UInt",0,"UInt",0,"UInt",0,"UInt")
    VarSetCapacity(original,10,0)
    NumPut(0x4E2D,original,0,"UShort"), NumPut(0x6587,original,2,"UShort"), NumPut(0xD83D,original,4,"UShort"), NumPut(0xDE00,original,6,"UShort")
    VarSetCapacity(changed,10,0)
    NumPut(0x4F1A,changed,0,"UShort"), NumPut(0x8BDD,changed,2,"UShort"), NumPut(0xD83D,changed,4,"UShort"), NumPut(0xDE80,changed,6,"UShort")
    ok := 1
    Loop, 2
{
        if (A_Index=2)
            DllCall("ShowWindow","UInt",hwnd,"Int",0)
        expectedVisible := A_Index=1  ?  1  :  0
        ok := ok && DllCall("IsWindowVisible","UInt",hwnd)=expectedVisible
        ok := ok && SetCaptionChecked(hwnd,original,8)
        StoreIdentity(hwnd)
        CopyBinary(Rec%hwnd%_Original,original,8), Rec%hwnd%_OriginalBytes := 8
        BuildWanted(changed,8,wanted,wb)
        ok := ok && SetCaptionChecked(hwnd,wanted,wb)
        CopyBinary(Rec%hwnd%_Last,wanted,wb), Rec%hwnd%_LastBytes := wb
        Rec%hwnd%_Owned := 1
        Tracked := hwnd . "|"
        RestoreAll()
        ok := ok && ReadCaption(hwnd,back,bb) && BinaryEqual(back,bb,original,8)
    }
    SetCaptionChecked(hwnd,wanted,wb)
    Rec%hwnd%_Owned := 1
    SetCaptionChecked(hwnd,changed,8)
    RestoreAll()
    externalOK := ReadCaption(hwnd,back,bb) && BinaryEqual(back,bb,changed,8)
    GetIdentity(hwnd,p,l,h,pp,pb,cc,cb)
    fixturePacket := A_ScriptDir . "\basic_fixture_packet.bin"
    WritePacket(fixturePacket,0,hwnd,p,l,h,changed,8)
    packetOK := ReadPacket(fixturePacket,hwnd,p,l,h,decoded,db) && BinaryEqual(decoded,db,changed,8)
    before := A_TickCount
    childStatus := SpawnBounded("--hang",4000)
    watchdogOK := childStatus=124 && A_TickCount-before>=3900
    ActiveReadHwnd := hwnd
    cancelStatus := SpawnBounded("--hang",4000)
    ActiveReadHwnd := 0
    cancelOK := cancelStatus=126
    dispatchFile := A_ScriptDir . "\basic_dispatch_smoke.txt"
    FileDelete, %dispatchFile%
    dispatchToken := DllCall("GetCurrentProcessId") . "-" . A_TickCount
    dispatchStatus := SpawnBounded("--dispatch-probe " . dispatchToken . " " . Quote(dispatchFile),4000)
    FileRead, dispatchReply, %dispatchFile%
    dispatchOK := dispatchStatus=0 && dispatchReply="CXT_DISPATCH " . dispatchToken
    sampleExe := "C:\own app\Own.exe"
    sampleScript := "C:\own app\Own.ahk"
    sampleArgs := "--worker 7 " . Quote("C:\output data\title.bin")
    compiledLine := WorkerCommandBasic(sampleExe,sampleScript,sampleArgs,1)
    sourceLine := WorkerCommandBasic(sampleExe,sampleScript,sampleArgs,0)
    argvOK := compiledLine=Quote(sampleExe) . " " . sampleArgs && sourceLine=Quote(sampleExe) . " /ErrorStdOut " . Quote(sampleScript) . " " . sampleArgs
    DllCall("DestroyWindow","UInt",hwnd)
    summary := "runtime=" . A_AhkVersion . " binaryUnicodeVisibleHidden=" . ok . " externalChangeSkipped=" . externalOK . " binaryPacket=" . packetOK . " compiled=" . A_IsCompiled . " argv=" . argvOK . " dispatch=" . dispatchOK . " focusCancel=" . cancelOK . " childWatchdog=" . watchdogOK . " status=" . childStatus . Chr(13) . Chr(10)
    FileAppend, %summary%, %resultFile%
    if (!ok || !externalOK || !watchdogOK || !packetOK || !cancelOK || !dispatchOK || !argvOK)
        return 1
    return 0
}


BasicValidIntervals(first,second) {
    return RegExMatch(first,"^\d+(?:\.\d+)?$") && RegExMatch(second,"^\d+(?:\.\d+)?$") && first>=1 && first<=3600 && second>=5 && second<=3600
}
BasicLoadIntervals() {
    global Interval, BackgroundInterval, SettingsFile, ForegroundExplicit, BackgroundExplicit
    first := Interval, second := BackgroundInterval
    if FileExist(SettingsFile) {
        if (!ForegroundExplicit)
            IniRead, first, %SettingsFile%, Timing, ForegroundSeconds, %first%
        if (!BackgroundExplicit)
            IniRead, second, %SettingsFile%, Timing, BackgroundSeconds, %second%
    }
    if (BasicValidIntervals(first,second))
        Interval := first, BackgroundInterval := second
}
BasicApplyIntervals(first,second,persist=1,reschedule=1) {
    global
    local directory,temporary,hwnd,period
    if (!BasicValidIntervals(first,second))
        return 0
    if (persist) {
        if InStr(FileExist(SettingsFile),"D")
            return 0
        SplitPath, SettingsFile,, directory
        FileCreateDir, %directory%
        temporary := SettingsFile . "." . DllCall("GetCurrentProcessId") . ".tmp"
        IniWrite, %first%, %temporary%, Timing, ForegroundSeconds
        if (ErrorLevel) {
            FileDelete, %temporary%
            return 0
        }
        IniWrite, %second%, %temporary%, Timing, BackgroundSeconds
        if (ErrorLevel) {
            FileDelete, %temporary%
            return 0
        }
        FileMove, %temporary%, %SettingsFile%, 1
        if (ErrorLevel) {
            FileDelete, %temporary%
            return 0
        }
    }
    Interval := first, BackgroundInterval := second, SettingsRevision := SettingsRevision+1
    if (reschedule) {
        if (hWorker)
            DllCall("TerminateProcess","UInt",hWorker,"UInt",127)
        if (hBgWorker)
            DllCall("TerminateProcess","UInt",hBgWorker,"UInt",127)
        Loop, Parse, Tracked, |
        {
            hwnd := A_LoopField
            if (hwnd)
                Rec%hwnd%_NextBackground := 0
        }
        period := Round(Interval*1000)
        SetTimer, ScanTimer, %period%
    }
    return 1
}
BasicShowSettings(show=1) {
    global Interval, BackgroundInterval, BasicForeground, BasicBackground, BasicAutoStartup, AutoEnabled, AutoAllowed, AutoUnknown, BasicSettingsHwnd, TIcon
    Gui, 2:Destroy
    Gui, 2:+ToolWindow
    Gui, 2:Add, Text,, Foreground source (seconds, 1..3600)
    Gui, 2:Add, Edit, vBasicForeground w280, %Interval%
    Gui, 2:Add, Text,, Background source (seconds, 5..3600)
    Gui, 2:Add, Edit, vBasicBackground w280, %BackgroundInterval%
    option := "vBasicAutoStartup w280" . (AutoEnabled  ?  " Checked"  :  "")
    if (!AutoAllowed || AutoUnknown)
        option .= " Disabled"
    Gui, 2:Add, Checkbox, %option%, Start at sign-in
    Gui, 2:Add, Text,, Cached-title repair remains every 1 second.
    Gui, 2:Add, Button, gBasicSettingsSave Default w100, Save
    Gui, 2:Add, Button, g2GuiClose x+10 w100, Cancel
    BasicThemeAddControls()
    Gui, 2:Add, Button, gBasicRulesEditor x20 y335 w280, Name replacement...
    Gui, 2:+LastFound
    BasicSettingsHwnd := WinExist()
    if (TIcon)
        BasicThemeWindows(TIcon)
    if (show)
        Gui, 2:Show, AutoSize, ChatGPT-TitleSync - Scan intervals
}
BasicSettingsSelfTest() {
    global SettingsFile, Interval, BackgroundInterval, SettingsRevision, ExitStatus
    SettingsFile := A_Temp . "\cxt_settings_basic_" . DllCall("GetCurrentProcessId") . "\nested\settings.ini"
    Interval := 2, BackgroundInterval := 5, SettingsRevision := 0
    passed := 0
    if (BasicApplyIntervals(2,15,1,0) && Interval=2 && BackgroundInterval=15 && SettingsRevision=1)
        passed++
    Interval := 2, BackgroundInterval := 5
    BasicLoadIntervals()
    if (Interval=2 && BackgroundInterval=15)
        passed++
    if (!BasicApplyIntervals(0,30,1,0) && !BasicApplyIntervals(3601,30,1,0) && !BasicApplyIntervals(1,4,1,0) && !BasicApplyIntervals(1,3601,1,0) && !BasicApplyIntervals("nan",30,1,0) && Interval=2 && BackgroundInterval=15 && SettingsRevision=1)
        passed++
    BasicShowSettings(0)
    GuiControlGet, currentFirst, 2:, BasicForeground
    GuiControlGet, currentSecond, 2:, BasicBackground
    if (currentFirst=2 && currentSecond=15)
        passed++
    Gui, 2:Destroy
    if (BasicApplyIntervals(3,20,1,1) && Interval=3 && BackgroundInterval=20 && SettingsRevision=2)
        passed++
    SetTimer, ScanTimer, Off
    actualSettings := SettingsFile
    SplitPath, SettingsFile,, privateDirectory
    blocked := privateDirectory . "\blocked"
    FileCreateDir, %blocked%
    SettingsFile := blocked
    if (!BasicApplyIntervals(4,25,1,0) && Interval=3 && SettingsRevision=2 && !FileExist(blocked . "." . DllCall("GetCurrentProcessId") . ".tmp"))
        passed++
    SettingsFile := actualSettings
    FileRemoveDir, %blocked%
    text := "{Platform:Basic,Passed:" . passed . ",Expected:6,RealChatGptAccessed:0}"
    FileAppend, %text%, *
    FileDelete, %SettingsFile%
    if (passed!=6)
        ExitStatus := 1
}


; Startup uses the fixed shared HKCU contract. Tests supply private subkeys only.
BasicAutoCommand(executable="",script="",compiled=-1) {
    if (compiled=-1)
        compiled := A_IsCompiled
    if (executable="")
        executable := compiled  ?  A_ScriptFullPath  :  A_AhkPath
    if (script="")
        script := A_ScriptFullPath
    return compiled  ?  Quote(executable)  :  Quote(executable) . " " . Quote(script)
}
BasicAutoRead(path,name,ByRef exists,ByRef kind,ByRef data,ByRef size) {
    exists := 0, kind := 0, size := 0, h := 0
    ToWide(path,wp), ToWide(name,wn)
    status := DllCall("advapi32\RegOpenKeyExW","UInt",0x80000001,"UInt",&wp,"UInt",0,"UInt",1,"UIntP",h,"UInt")
    if (status=2 || status=3)
        return 0
    if (status)
        return status
    status := DllCall("advapi32\RegQueryValueExW","UInt",h,"UInt",&wn,"UInt",0,"UIntP",kind,"UInt",0,"UIntP",size,"UInt")
    if (status=2) {
        DllCall("advapi32\RegCloseKey","UInt",h)
        return 0
    }
    if (!status) {
        VarSetCapacity(data,size+2,0)
        status := DllCall("advapi32\RegQueryValueExW","UInt",h,"UInt",&wn,"UInt",0,"UIntP",kind,"UInt",&data,"UIntP",size,"UInt")
        if (!status)
            exists := 1
    }
    DllCall("advapi32\RegCloseKey","UInt",h)
    return status
}
BasicAutoWrite(path,name,exists,kind,ByRef data,size) {
    h := 0
    ToWide(path,wp), ToWide(name,wn)
    if (exists)
        status := DllCall("advapi32\RegCreateKeyExW","UInt",0x80000001,"UInt",&wp,"UInt",0,"UInt",0,"UInt",0,"UInt",2,"UInt",0,"UIntP",h,"UInt",0,"UInt")
    else
        status := DllCall("advapi32\RegOpenKeyExW","UInt",0x80000001,"UInt",&wp,"UInt",0,"UInt",2,"UIntP",h,"UInt")
    if (!exists && (status=2 || status=3))
        return 0
    if (status)
        return status
    if (exists)
        status := DllCall("advapi32\RegSetValueExW","UInt",h,"UInt",&wn,"UInt",0,"UInt",kind,"UInt",&data,"UInt",size,"UInt")
    else {
        status := DllCall("advapi32\RegDeleteValueW","UInt",h,"UInt",&wn,"UInt")
        if (status=2)
            status := 0
    }
    DllCall("advapi32\RegCloseKey","UInt",h)
    return status
}
BasicAutoInitialize(runKey="",prefKey="",command="") {
    global AutoRunKey,AutoPrefKey,AutoCommand,AutoError
    AutoRunKey := runKey!=""  ?  runKey  :  "Software\Microsoft\Windows\CurrentVersion\Run"
    AutoPrefKey := prefKey!=""  ?  prefKey  :  "Software\ChatGPT-TitleSync"
    AutoCommand := command!=""  ?  command  :  BasicAutoCommand()
    status := BasicAutoRead(AutoPrefKey,"AutoStartEnabled",exists,kind,data,size)
    if (status) {
        AutoError := "Unable to read startup preference: " . status
        return status
    }
    enabled := 1
    if (exists) {
        if (kind!=4 || size!=4) {
            AutoError := "AutoStartEnabled must be a DWORD containing 0 or 1."
            return 13
        }
        enabled := NumGet(data,0,"UInt")
        if (enabled!=0 && enabled!=1) {
            AutoError := "AutoStartEnabled must be 0 or 1."
            return 13
        }
    }
    return BasicAutoApply(enabled)
}
BasicAutoApply(enabled,failPreference=0) {
    global AutoRunKey,AutoPrefKey,AutoCommand,AutoEnabled,AutoUnknown,AutoError
    if (enabled!=0 && enabled!=1) {
        AutoError := "Startup state must be 0 or 1."
        return 13
    }
    if (enabled && StrLen(AutoCommand)>260) {
        AutoError := "Start-at-sign-in command exceeds Windows Run 260-character limit."
        return 206
    }
    status := BasicAutoRead(AutoRunKey,"ChatGPT-TitleSync",oldRunExists,oldRunKind,oldRun,oldRunSize)
    if (!status)
        status := BasicAutoRead(AutoPrefKey,"AutoStartEnabled",oldPrefExists,oldPrefKind,oldPref,oldPrefSize)
    if (status) {
        AutoError := "Unable to read startup registration: " . status
        return status
    }
    ToWide(AutoCommand,wantedRun),wantedRunSize := (StrLen(AutoCommand)+1)*2
    VarSetCapacity(wantedPref,4,0), NumPut(enabled,wantedPref,0,"UInt")
    sameRun := enabled  ?  (oldRunExists && oldRunKind=1 && BinaryEqual(oldRun,oldRunSize,wantedRun,wantedRunSize))  :  !oldRunExists
    status := sameRun  ?  0  :  BasicAutoWrite(AutoRunKey,"ChatGPT-TitleSync",enabled,1,wantedRun,wantedRunSize)
    if (!status) {
        samePref := oldPrefExists && oldPrefKind=4 && BinaryEqual(oldPref,oldPrefSize,wantedPref,4)
        status := samePref  ?  0  :  (failPreference  ?  5  :  BasicAutoWrite(AutoPrefKey,"AutoStartEnabled",1,4,wantedPref,4))
    }
    if (status) {
        first := BasicAutoWrite(AutoRunKey,"ChatGPT-TitleSync",oldRunExists,oldRunKind,oldRun,oldRunSize)
        second := BasicAutoWrite(AutoPrefKey,"AutoStartEnabled",oldPrefExists,oldPrefKind,oldPref,oldPrefSize)
        AutoError := "Startup update failed: " . status . "; rollback=" . first . "/" . second
        if (first || second)
            AutoUnknown := 1
        return status
    }
    AutoEnabled := !!enabled, AutoUnknown := 0, AutoError := ""
    BasicAutoSync()
    return 0
}
BasicAutoSync() {
    global AutoEnabled,AutoAllowed,AutoUnknown,AutoMenuReady,BasicSettingsHwnd
    if (AutoMenuReady) {
        if (AutoEnabled)
            Menu, Tray, Check, Start at sign-in
        else
            Menu, Tray, Uncheck, Start at sign-in
        if (AutoAllowed && !AutoUnknown)
            Menu, Tray, Enable, Start at sign-in
        else
            Menu, Tray, Disable, Start at sign-in
    }
    if (BasicSettingsHwnd && DllCall("IsWindow","UInt",BasicSettingsHwnd)) {
        GuiControl, 2:, BasicAutoStartup, %AutoEnabled%
        if (AutoAllowed && !AutoUnknown)
            GuiControl, 2:Enable, BasicAutoStartup
        else
            GuiControl, 2:Disable, BasicAutoStartup
    }
}
BasicApplySettingsWithStartup(first,second,enabled) {
    global AutoAllowed,AutoEnabled,AutoError
    if (!BasicValidIntervals(first,second)) {
        AutoError := "Foreground must be 1..3600 seconds and background 5..3600."
        return 0
    }
    prior := AutoEnabled
    if (AutoAllowed && BasicAutoApply(enabled))
        return 0
    if (!BasicApplyIntervals(first,second)) {
        if (AutoAllowed && enabled!=prior) {
            status := BasicAutoApply(prior)
            if (status)
                return 0
        }
        AutoError := "Unable to save scan intervals; startup was rolled back."
        return 0
    }
    return 1
}
BasicAutoSelfTest() {
    global AutoAllowed,AutoEnabled,AutoUnknown,AutoMenuReady,AutoTesting,AutoRunKey,AutoPrefKey,AutoCommand,AutoError,ExitStatus,SettingsFile,Interval,BackgroundInterval,SettingsRevision,BasicSettingsHwnd
    base := "Software\ChatGPT-TitleSync-SelfTest\basic_" . DllCall("GetCurrentProcessId") . "_" . A_TickCount
    AutoAllowed := 1, AutoTesting := 1, AutoMenuReady := 1, AutoUnknown := 0
    Interval := 2, BackgroundInterval := 5, SettingsRevision := 0
    SettingsFile := A_Temp . "\titlesync_basic_startup_" . DllCall("GetCurrentProcessId") . ".ini"
    Menu, Tray, Add, Start at sign-in, BasicAutoToggle
    passed := 0
    command := Quote("C:\Own app\App.exe")
    if (!BasicAutoInitialize(base . "\Run",base . "\Preferences",command) && AutoEnabled)
        passed++
    if (!BasicAutoApply(0) && !AutoEnabled) {
        BasicAutoRead(AutoRunKey,"ChatGPT-TitleSync",exists,kind,data,size)
        if (!exists)
            passed++
    }
    if (!BasicAutoInitialize(base . "\Run",base . "\Preferences",Quote("C:\Own app\Replacement.exe")) && !AutoEnabled)
        passed++
    if (!BasicAutoApply(1) && AutoEnabled) {
        BasicAutoRead(AutoRunKey,"ChatGPT-TitleSync",exists,kind,data,size)
        ToWide(AutoCommand,expected)
        if (exists && kind=1 && BinaryEqual(data,size,expected,(StrLen(AutoCommand)+1)*2))
            passed++
    }
    if (BasicAutoApply(0,1) && AutoEnabled) {
        BasicAutoRead(AutoPrefKey,"AutoStartEnabled",exists,kind,data,size)
        if (exists && kind=4 && NumGet(data,0,"UInt")=1)
            passed++
    }
    expectedCommand := A_IsCompiled  ?  Quote(A_ScriptFullPath)  :  Quote(A_AhkPath) . " " . Quote(A_ScriptFullPath)
    if (BasicAutoCommand()=expectedCommand)
        passed++
    if (!BasicAutoApply(1,1))
        passed++
    normalCommand := AutoCommand, part := ""
    Loop {
        boundary := BasicAutoCommand("C:\Own app\AutoHotkey.exe","C:\" . part . "\source.ahk",0)
        if (StrLen(boundary)>=260)
            Break
        part .= "x"
    }
    AutoCommand := boundary
    if (StrLen(boundary)=260 && !BasicAutoApply(1))
        passed++
    BasicAutoRead(AutoRunKey,"ChatGPT-TitleSync",beforeExists,beforeKind,beforeData,beforeSize)
    AutoCommand := BasicAutoCommand("C:\Own app\AutoHotkey.exe","C:\" . part . "x\source.ahk",0)
    rejected := BasicAutoApply(1)
    BasicAutoRead(AutoRunKey,"ChatGPT-TitleSync",exists,kind,data,size)
    if (rejected && exists=beforeExists && kind=beforeKind && BinaryEqual(data,size,beforeData,beforeSize))
        passed++
    if (!BasicAutoApply(0) && !AutoEnabled)
        passed++
    AutoCommand := normalCommand
    BasicAutoApply(1)
    BasicShowSettings(0)
    GuiControlGet, checkHwnd, 2:Hwnd, BasicAutoStartup
    GuiControlGet, saveHwnd, 2:Hwnd, Save
    GuiControlGet, cancelHwnd, 2:Hwnd, Cancel
    checkboxId := DllCall("GetDlgCtrlID","UInt",checkHwnd), saveId := DllCall("GetDlgCtrlID","UInt",saveHwnd), cancelId := DllCall("GetDlgCtrlID","UInt",cancelHwnd)
    GuiControlGet, current, 2:, BasicAutoStartup
    if (current=1)
        passed++
    BasicAutoApply(0)
    GuiControlGet, current, 2:, BasicAutoStartup
    if (current=0)
        passed++
    GuiControl, 2:, BasicAutoStartup, 1
    Gui, 2:Destroy
    BasicSettingsHwnd := 0
    if (!AutoEnabled)
        passed++
    BasicShowSettings(0)
    GuiControl, 2:, BasicAutoStartup, 1
    GuiControlGet, saveHwnd, 2:Hwnd, Save
    DllCall("PostMessageW","UInt",saveHwnd,"UInt",0xF5,"UInt",0,"UInt",0)
    started := A_TickCount
    while (BasicSettingsHwnd && A_TickCount-started<900) {
        Sleep, 10
    }
    SetTimer, ScanTimer, Off
    if (AutoEnabled && !BasicSettingsHwnd)
        passed++
    success := passed=14  ?  1  :  0
    text := "{" . Chr(34) . "Success" . Chr(34) . ":" . success . "," . Chr(34) . "Passed" . Chr(34) . ":" . passed . "," . Chr(34) . "RealRunKeyAccessed" . Chr(34) . ":0," . Chr(34) . "RealChatGptAccessed" . Chr(34) . ":0," . Chr(34) . "SharedIpcUsed" . Chr(34) . ":0," . Chr(34) . "CheckboxId" . Chr(34) . ":" . checkboxId . "," . Chr(34) . "SaveId" . Chr(34) . ":" . saveId . "," . Chr(34) . "CancelId" . Chr(34) . ":" . cancelId . "}"
    FileAppend, %text%, *
    SetTimer, ScanTimer, Off
    Gui, 2:Destroy
    FileDelete, %SettingsFile%
    RegDelete, HKEY_CURRENT_USER, %base%
    if (!success)
        ExitStatus := 1
}

#Include %A_ScriptDir%\IconThemeBasic.ahk

#Include %A_ScriptDir%\NameReplacementBasic.ahk
