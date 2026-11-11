; ANSI Basic policy: only ASCII preference names/values, binary UTF-16 registry snapshots.
; No title access is performed. Production initialization follows the controller mutex;
; isolated tests inject an owned HKCU key, local clock, offset and random palette ID.
BasicThemeDefaults() {
    global TMode,TFixed,TPeriod,TRandom,TSlot,TAllowed,TKey,TRoot,TTesting,TNow,TOffset,TPick,TNext,TErrorSlot,TErrors,TIcon,TCurrent,TUnknown
    TMode:="fixed",TFixed:=45,TPeriod:="day",TRandom:=45,TSlot:="",TAllowed:=0,TKey:="",TRoot:="",TTesting:=0,TNow:="",TOffset:="",TPick:=0,TNext:=0,TErrorSlot:="",TErrors:=0,TIcon:=0,TCurrent:=0,TUnknown:=0
}
BasicThemeName(i) {
    names:="IconMode|FixedIcon|IconPeriod|RandomIcon|IconSlot"
    Loop, Parse, names, |
        if (A_Index=i)
            return A_LoopField
}
BasicThemeState() {
    global TMode,TFixed,TPeriod,TRandom,TSlot
    return TMode . "|" . TFixed . "|" . TPeriod . "|" . TRandom . "|" . TSlot
}
BasicThemeSetState(state) {
    global TMode,TFixed,TPeriod,TRandom,TSlot
    Loop, Parse, state, |
    {
        if (A_Index=1)
            TMode:=A_LoopField
        if (A_Index=2)
            TFixed:=A_LoopField+0
        if (A_Index=3)
            TPeriod:=A_LoopField
        if (A_Index=4)
            TRandom:=A_LoopField+0
        if (A_Index=5)
            TSlot:=A_LoopField
    }
}
BasicThemeOffset() {
    VarSetCapacity(zone,172,0)
    mode:=DllCall("GetTimeZoneInformation","UInt",&zone,"UInt"),bias:=NumGet(zone,0,"Int")
    if (mode=1)
        bias+=NumGet(zone,84,"Int")
    else if (mode=2)
        bias+=NumGet(zone,168,"Int")
    minutes:=-bias,hours:=Floor(Abs(minutes)/60),rest:=Mod(Abs(minutes),60)
    return (minutes<0 ? "-" : "+") . SubStr("0" . hours,-1) . SubStr("0" . rest,-1)
}
BasicThemeSlot(period,now="",offset="") {
    if (now="")
        now:=A_Now
    if (offset="")
        offset:=BasicThemeOffset()
    if (period="day")
        return SubStr(now,1,8)
    if (period="hour")
        return SubStr(now,1,10) . offset
    if (period="5min")
        return SubStr(now,1,10) . SubStr("0" . Floor(SubStr(now,11,2)/5),-1) . offset
    return ""
}
BasicThemePath(id) {
    global TRoot
    return TRoot . "\" . id . "-legacy.ico"
}
BasicThemeLoad(id) {
    path:=BasicThemePath(id)
    ToWide(path,wide)
    return DllCall("LoadImageW","UInt",0,"UInt",&wide,"UInt",1,"Int",32,"Int",32,"UInt",0x10,"UInt")
}
BasicThemeValidate(mode,fixed,period) {
    global TError
    if ((mode!="fixed" && mode!="random") || fixed<45 || fixed>52 || fixed!=Floor(fixed) || (period!="day" && period!="hour" && period!="5min")) {
        TError:="Invalid icon mode, fixed palette or random period."
        return 13
    }
    count:=mode="random" ? 8 : 1
    Loop, %count%
    {
        id:=mode="random" ? 44+A_Index : fixed,handle:=BasicThemeLoad(id)
        if (!handle) {
            TError:="Unable to load icon asset " . id
            return 2
        }
        DllCall("DestroyIcon","UInt",handle)
    }
    return 0
}
BasicThemeRead(name,kind,fallback,ByRef value) {
    global TKey
    value:=fallback,status:=BasicAutoRead(TKey,name,exists,actual,data,size)
    if (status || !exists)
        return status
    if (actual!=kind || (kind=4 && size!=4) || (kind=1 && (size<2 || Mod(size,2) || NumGet(data,size-2,"UShort"))))
        return 13
    if (kind=4) {
        value:=NumGet(data,0,"UInt")
        return 0
    }
    value:="",count:=size/2-1
    Loop, %count%
    {
        code:=NumGet(data,(A_Index-1)*2,"UShort")
        if (code>127)
            return 13
        value.=Chr(code)
    }
    return 0
}
BasicThemeSnapshot(prefix) {
    global
    local i,name,status,exists,kind,raw,size,v,evar,kvar,nvar,dvar,statevar
    Loop, 5
    {
        i:=A_Index,name:=BasicThemeName(i),status:=BasicAutoRead(TKey,name,exists,kind,raw,size)
        if (status)
            return status
        v:=prefix . i,evar:=v . "_Exists",kvar:=v . "_Kind",nvar:=v . "_Size",dvar:=v . "_Data"
        %evar%:=exists,%kvar%:=kind,%nvar%:=size
        CopyBinary(%dvar%,raw,size)
    }
    statevar:=prefix . "_State",%statevar%:=BasicThemeState()
    return 0
}
BasicThemeRestore(prefix) {
    global
    local i,name,status,failure,v,evar,kvar,nvar,dvar,statevar
    failure:=0
    Loop, 5
    {
        i:=A_Index,name:=BasicThemeName(i),v:=prefix . i,evar:=v . "_Exists",kvar:=v . "_Kind",nvar:=v . "_Size",dvar:=v . "_Data"
        status:=BasicAutoWrite(TKey,name,%evar%,%kvar%,%dvar%,%nvar%)
        if (status)
            failure:=status
    }
    if (!failure) {
        statevar:=prefix . "_State"
        BasicThemeSetState(%statevar%)
    } else
        TUnknown:=1
    return failure
}
BasicThemePlan(mode,fixed,period,ByRef plan) {
    global TMode,TFixed,TPeriod,TRandom,TSlot,TNow,TOffset,TPick,TError
    status:=BasicThemeValidate(mode,fixed,period)
    if (status)
        return status
    selected:=TRandom,slot:=TSlot
    if (mode="random") {
        slot:=BasicThemeSlot(period,TNow,TOffset)
        if (TMode!="random" || TPeriod!=period || TSlot!=slot) {
            if (TPick)
                selected:=TPick
            else {
                Loop {
                    Random, selected, 45, 52
                    if (selected!=TRandom)
                        Break
                }
            }
            if (selected<45 || selected>52 || selected=TRandom) {
                TError:="Icon picker repeated or left the palette."
                return 13
            }
        }
    }
    plan:=mode . "|" . fixed . "|" . period . "|" . selected . "|" . slot
    return 0
}
BasicThemeCommit(plan,failName="") {
    global TKey,TError,TErrorSlot
    status:=BasicThemeSnapshot("BTInner")
    if (status)
        return status
    Loop, Parse, plan, |
    {
        name:=BasicThemeName(A_Index),kind:=(A_Index=2 || A_Index=4) ? 4 : 1,value:=A_LoopField
        if (kind=4) {
            VarSetCapacity(wanted,4,0),NumPut(value+0,wanted,0,"UInt"),wantedSize:=4
        } else {
            ToWide(value,wanted),wantedSize:=(StrLen(value)+1)*2
        }
        status:=BasicAutoRead(TKey,name,exists,oldKind,old,size)
        if (!status && (!exists || oldKind!=kind || !BinaryEqual(old,size,wanted,wantedSize)))
            status:=name=failName ? 5 : BasicAutoWrite(TKey,name,1,kind,wanted,wantedSize)
        if (status) {
            rollback:=BasicThemeRestore("BTInner")
            TError:="Icon preference write failed: " . name . "=" . status . "; rollback=" . rollback
            return status
        }
    }
    BasicThemeSetState(plan),TErrorSlot:=""
    return 0
}
BasicThemeId(plan="") {
    global TMode,TFixed,TRandom
    if (plan="")
        return TMode="fixed" ? TFixed : TRandom
    Loop, Parse, plan, |
    {
        if (A_Index=1)
            mode:=A_LoopField
        if (A_Index=2)
            fixed:=A_LoopField+0
        if (A_Index=4)
            random:=A_LoopField+0
    }
    return mode="fixed" ? fixed : random
}
BasicThemeInitInner(key="",root="",testing=0) {
    global TKey,TRoot,TAllowed,TTesting,TMode,TFixed,TPeriod,TRandom,TSlot,TError
    TAllowed:=1,TTesting:=testing,TKey:=key!="" ? key : "Software\ChatGPT-TitleSync"
    TRoot:=root!="" ? root : (A_IsCompiled ? A_ScriptDir . "\assets\themes" : A_ScriptDir . "\..\..\assets\themes")
    status:=BasicThemeRead("IconMode",1,"fixed",mode)
    if (!status)
        status:=BasicThemeRead("FixedIcon",4,45,fixed)
    if (!status)
        status:=BasicThemeRead("IconPeriod",1,"day",period)
    if (!status)
        status:=BasicThemeRead("RandomIcon",4,45,random)
    if (!status)
        status:=BasicThemeRead("IconSlot",1,"",slot)
    if (!status)
        status:=BasicThemeValidate(mode,fixed,period)
    if (status || random<45 || random>52) {
        TError:="Invalid or unavailable persisted icon settings."
        return status ? status : 13
    }
    BasicThemeSetState(mode . "|" . fixed . "|" . period . "|" . random . "|" . slot)
    if (mode="random") {
        status:=BasicThemePlan(mode,fixed,period,plan)
        if (!status && plan!=BasicThemeState())
            status:=BasicThemeCommit(plan)
    }
    return status
}
BasicThemeWindows(handle) {
    global BasicSettingsHwnd,TMainWindow
    if (!TMainWindow) {
        previous:=A_DetectHiddenWindows,pid:=DllCall("GetCurrentProcessId")
        DetectHiddenWindows, On
        WinGet, own, List, ahk_pid %pid%
        Loop, %own%
        {
            hwnd:=own%A_Index%
            WinGetClass, klass, ahk_id %hwnd%
            if (klass="AutoHotkey") {
                TMainWindow:=hwnd
                Break
            }
        }
        DetectHiddenWindows, %previous%
    }
    Loop, 2
    {
        hwnd:=A_Index=1 ? TMainWindow : BasicSettingsHwnd
        if (hwnd) {
            DllCall("SendMessageW","UInt",hwnd,"UInt",0x80,"UInt",0,"UInt",handle)
            DllCall("SendMessageW","UInt",hwnd,"UInt",0x80,"UInt",1,"UInt",handle)
        }
    }
}
BasicThemeStage(id,ByRef oldHandle,ByRef oldId,ByRef changed) {
    global TIcon,TCurrent,TTesting,TError
    changed:=0,oldHandle:=TIcon,oldId:=TCurrent
    if (id=TCurrent)
        return 0
    handle:=BasicThemeLoad(id)
    if (!handle) {
        TError:="Unable to load selected icon."
        return 2
    }
    if (!TTesting) {
        path:=BasicThemePath(id)
        Menu, Tray, UseErrorLevel
        Menu, Tray, Icon, %path%
        failed:=ErrorLevel
        Menu, Tray, UseErrorLevel, Off
        if (failed) {
            DllCall("DestroyIcon","UInt",handle)
            TError:="Unable to update tray icon."
            return 13
        }
    }
    BasicThemeWindows(handle),TIcon:=handle,TCurrent:=id,changed:=1
    return 0
}
BasicThemeFinish(oldHandle,changed) {
    if (changed && oldHandle)
        DllCall("DestroyIcon","UInt",oldHandle)
}
BasicThemeUndo(oldHandle,oldId,changed) {
    global TTesting,TIcon,TCurrent
    if (!changed)
        return 0
    failure:=0
    if (!TTesting) {
        path:=BasicThemePath(oldId ? oldId : 45)
        Menu, Tray, UseErrorLevel
        Menu, Tray, Icon, %path%
        failure:=ErrorLevel
        Menu, Tray, UseErrorLevel, Off
    }
    BasicThemeWindows(oldHandle),DllCall("DestroyIcon","UInt",TIcon),TIcon:=oldHandle,TCurrent:=oldId
    return failure
}
BasicThemeDispose() {
    global TIcon,TCurrent
    if (TIcon) {
        BasicThemeWindows(0),DllCall("DestroyIcon","UInt",TIcon),TIcon:=0,TCurrent:=0
    }
}
BasicThemeError(slot) {
    global TErrorSlot,TErrors,TTesting
    TErrorSlot:=slot,TErrors:=TErrors+1
    if (!TTesting)
        Log("icon_rotation_failed slot=" . slot)
}
BasicThemeTickInner() {
    global TAllowed,TMode,TPeriod,TFixed,TSlot,TNow,TOffset,TNext,TErrorSlot
    if (!TAllowed || A_TickCount<TNext)
        return
    TNext:=A_TickCount+1000
    if (TMode!="random")
        return
    slot:=BasicThemeSlot(TPeriod,TNow,TOffset)
    if (("s" . slot)=("s" . TSlot) || ("s" . slot)=("s" . TErrorSlot))
        return
    status:=BasicThemePlan("random",TFixed,TPeriod,plan)
    changed:=0
    if (!status)
        status:=BasicThemeStage(BasicThemeId(plan),oldHandle,oldId,changed)
    if (!status)
        status:=BasicThemeCommit(plan)
    if (status) {
        BasicThemeUndo(oldHandle,oldId,changed)
        BasicThemeError(slot)
    } else
        BasicThemeFinish(oldHandle,changed)
}
BasicThemeSaveInner(first,second,enabled,mode,fixed,period) {
    global TAllowed,TError,AutoError,AutoRunKey,AutoPrefKey,AutoEnabled
    if (!TAllowed)
        return BasicApplySettingsWithStartup(first,second,enabled)
    if (!BasicValidIntervals(first,second)) {
        AutoError:="Foreground: 1..3600, background: 5..3600 seconds."
        return 0
    }
    status:=BasicThemePlan(mode,fixed,period,plan)
    if (!status)
        status:=BasicThemeSnapshot("BTOuter")
    if (status) {
        AutoError:=TError
        return 0
    }
    prior:=AutoEnabled
    status:=BasicAutoRead(AutoRunKey,"ChatGPT-TitleSync",runExists,runKind,runData,runSize)
    if (!status)
        status:=BasicAutoRead(AutoPrefKey,"AutoStartEnabled",prefExists,prefKind,prefData,prefSize)
    if (status) {
        AutoError:="Unable to read startup registration before saving."
        return 0
    }
    changed:=0
    if (!status)
        status:=BasicThemeStage(BasicThemeId(plan),oldHandle,oldId,changed)
    if (!status)
        status:=BasicAutoApply(enabled)
    if (!status)
        status:=BasicThemeCommit(plan)
    if (!status && !BasicApplyIntervals(first,second))
        status:=5
    if (status) {
        a:=BasicThemeRestore("BTOuter"),b:=BasicAutoWrite(AutoRunKey,"ChatGPT-TitleSync",runExists,runKind,runData,runSize),c:=BasicAutoWrite(AutoPrefKey,"AutoStartEnabled",prefExists,prefKind,prefData,prefSize)
        if (!b && !c)
            AutoEnabled:=prior,BasicAutoSync()
        d:=BasicThemeUndo(oldHandle,oldId,changed)
        AutoError:="Unable to save icon/interval/startup settings: " . status . "; rollback=" . a . "/" . b . "/" . c . "/" . d
        return 0
    }
    BasicThemeFinish(oldHandle,changed)
    return 1
}
BasicThemeAddControls() {
    global TMode,TFixed,TPeriod,TIcon,BasicIconMode,BasicFixedIcon,BasicIconPeriod
    Gui, 2:Add, Text, x10 y165 w120, Icon mode
    option:="vBasicIconMode AltSubmit gBasicThemeChanged x140 y160 w170 Choose" . (TMode="fixed" ? 1 : 2)
    Gui, 2:Add, DropDownList, %option%, Fixed|Random
    Gui, 2:Add, Text, x10 y205 w120, Fixed palette
    option:="vBasicFixedIcon AltSubmit x140 y200 w170 Choose" . (TFixed-44)
    Gui, 2:Add, DropDownList, %option%, 45|46|47|48|49|50|51|52
    Gui, 2:Add, Text, x10 y245 w120, Random period
    option:="vBasicIconPeriod AltSubmit x140 y240 w170 Choose" . (TPeriod="day" ? 1 : TPeriod="hour" ? 2 : 3)
    Gui, 2:Add, DropDownList, %option%, Daily|Hourly|Every 5 minutes
    GuiControl, 2:Move, Save, x80 y290
    GuiControl, 2:Move, Cancel, x200 y290
    BasicThemeFields()
    if (TIcon)
        BasicThemeWindows(TIcon)
}
BasicThemeFields() {
    global TAllowed,TUnknown
    GuiControlGet, mode, 2:, BasicIconMode
    action:=TAllowed && !TUnknown ? "Enable" : "Disable"
    GuiControl, 2:%action%, BasicIconMode
    action:=TAllowed && !TUnknown && mode=1 ? "Enable" : "Disable"
    GuiControl, 2:%action%, BasicFixedIcon
    action:=TAllowed && !TUnknown && mode=2 ? "Enable" : "Disable"
    GuiControl, 2:%action%, BasicIconPeriod
}
BasicThemeSame(prefix) {
    global
    local name,status,exists,kind,raw,size,v,evar,kvar,nvar,dvar,statevar
    Loop, 5
    {
        name:=BasicThemeName(A_Index),status:=BasicAutoRead(TKey,name,exists,kind,raw,size),v:=prefix . A_Index
        evar:=v . "_Exists",kvar:=v . "_Kind",nvar:=v . "_Size",dvar:=v . "_Data"
        if (status || exists!=%evar% || (exists && (kind!=%kvar% || !BinaryEqual(raw,size,%dvar%,%nvar%))))
            return 0
    }
    statevar:=prefix . "_State"
    return BasicThemeState()=%statevar%
}
BasicThemeAssert(name,passed) {
    global TTestChecks,TTestFailed,TTestNames
    TTestChecks:=TTestChecks+1
    if (!passed)
        TTestFailed.=name . " "
    TTestNames.=(TTestChecks>1 ? "," : "") . Chr(34) . name . Chr(34)
}
BasicThemeSelfTest(originalRoot="") {
    global
    local base,ownRoot,source,target,id,missing,name,exists,kind,data,size,status,plan,before,oldErrors,modeH,fixedH,periodH,saveH,modeId,fixedId,periodId,started,prior,oldFile,oldIcon,copy,success,text
    if (originalRoot="")
        originalRoot:=A_IsCompiled ? A_ScriptDir . "\assets\themes" : A_ScriptDir . "\..\..\assets\themes"
    base:="Software\ChatGPT-TitleSync-SelfTest\icon_basic_" . DllCall("GetCurrentProcessId") . "_" . A_TickCount
    ownRoot:=A_Temp . "\titlesync_theme_basic_" . DllCall("GetCurrentProcessId") . "_" . A_TickCount
    FileCreateDir, %ownRoot%
    TTesting:=1,TNow:="20261111120459",TOffset:="+0800",TTestChecks:=0,TTestFailed:="",TTestNames:=""
    Loop, 8
    {
        source:=originalRoot . "\" . (44+A_Index) . "-legacy.ico",target:=ownRoot . "\" . (44+A_Index) . "-legacy.ico"
        FileCopy, %source%, %target%, 1
        if (ErrorLevel)
            TTestFailed.="OwnIconFixtureCopy "
    }
    status:=BasicThemeInit(base . "\Preferences",ownRoot,1),missing:=1
    Loop, 5
    {
        name:=BasicThemeName(A_Index),status:=status ? status : BasicAutoRead(TKey,name,exists,kind,data,size)
        if (exists)
            missing:=0
    }
    BasicThemeAssert("Missing_defaults_fixed45_without_writes",!status && missing && BasicThemeId()=45)
    Loop, 8
    {
        id:=44+A_Index,status:=BasicThemePlan("fixed",id,"day",plan)
        if (!status)
            status:=BasicThemeCommit(plan)
        BasicThemeAssert("Fixed_palette_" . id,!status && BasicThemeId()=id)
    }
    BasicThemeSnapshot("BTCheck"),status:=BasicThemePlan("invalid",45,"day",plan)
    BasicThemeAssert("Invalid_selection_preserves_values",status && BasicThemeSame("BTCheck"))
    TPick:=46,status:=BasicThemePlan("random",45,"day",plan)
    BasicThemeAssert("Prepared_cancel_does_not_commit",!status && BasicThemeSame("BTCheck"))
    status:=BasicThemeCommit(plan)
    BasicThemeAssert("Random_enable_immediate_nonrepeat",!status && BasicThemeId()=46 && TSlot="20261111")
    BasicThemeSnapshot("BTCheck"),status:=BasicThemeInit(TKey,ownRoot,1)
    BasicThemeAssert("Same_slot_restart_keeps_color",!status && BasicThemeSame("BTCheck"))
    BasicThemeAssert("Exact_daily_slot",BasicThemeSlot("day","20261111235959","+0800")="20261111")
    BasicThemeAssert("Exact_hourly_slot",BasicThemeSlot("hour","20261111125959","+0800")="2026111112+0800")
    BasicThemeAssert("Exact_five_minute_slot",BasicThemeSlot("5min","20261111130500","+0800")="202611111301+0800")
    BasicThemeAssert("Offset_disambiguates_repeated_hour",BasicThemeSlot("hour","20261101010000","-0400")!=BasicThemeSlot("hour","20261101010000","-0500"))
    TNow:="20261111125959",TPick:=47,status:=BasicThemePlan("random",45,"hour",plan),status:=status ? status : BasicThemeCommit(plan)
    TNow:="20261111130000",TPick:=48,TNext:=0,BasicThemeTick()
    BasicThemeAssert("Hour_boundary_rotates_without_repeat",!status && BasicThemeId()=48 && TSlot="2026111113+0800")
    TPick:=49,status:=BasicThemePlan("random",45,"5min",plan),status:=status ? status : BasicThemeCommit(plan)
    TNow:="20261111130500",TPick:=50,TNext:=0,BasicThemeTick()
    BasicThemeAssert("Five_minute_boundary_rotates",!status && BasicThemeId()=50 && TSlot="202611111301+0800")
    TPick:=51,status:=BasicThemePlan("random",45,"day",plan),status:=status ? status : BasicThemeCommit(plan)
    TNow:="20261112000000",TPick:=52,TNext:=0,BasicThemeTick()
    BasicThemeAssert("Day_boundary_rotates",!status && BasicThemeId()=52 && TSlot="20261112")
    status:=BasicThemePlan("fixed",45,"day",plan),status:=status ? status : BasicThemeCommit(plan),BasicThemeSnapshot("BTCheck")
    TNow:="20270101000000",TNext:=0,BasicThemeTick()
    BasicThemeAssert("Fixed_mode_never_rotates",!status && BasicThemeSame("BTCheck"))
    TPick:=46,status:=BasicThemePlan("random",45,"hour",plan),status:=status ? status : BasicThemeCommit(plan),BasicThemeSnapshot("BTCheck")
    FileDelete, % ownRoot . "\52-legacy.ico"
    TNow:="20270101010000",TPick:=47,TNext:=0,BasicThemeTick(),oldErrors:=TErrors,TNext:=0,BasicThemeTick()
    BasicThemeAssert("Missing_asset_keeps_icon_and_error_is_bounded",BasicThemeSame("BTCheck") && oldErrors=1 && TErrors=oldErrors)
    source:=originalRoot . "\52-legacy.ico",target:=ownRoot . "\52-legacy.ico"
    FileCopy, %source%, %target%, 1
    TNow:="20270101020000",TNext:=0,BasicThemeTick()
    BasicThemeAssert("Later_slot_recovers_after_asset_return",BasicThemeId()=47)
    BasicThemeSnapshot("BTCheck"),TPick:=48,status:=BasicThemePlan("random",45,"5min",plan)
    if (!status)
        status:=BasicThemeCommit(plan,"IconPeriod")
    BasicThemeAssert("Failed_named_write_restores_raw_values",status && BasicThemeSame("BTCheck"))
    AutoTesting:=1,AutoAllowed:=1,Interval:=2,BackgroundInterval:=5,SettingsRevision:=0,SettingsFile:=ownRoot . "\intervals.ini"
    status:=BasicAutoInitialize(base . "\Run",TKey,Quote("C:\Own app\Helper.exe"))
    BasicShowSettings(0)
    GuiControlGet, modeH, 2:Hwnd, BasicIconMode
    GuiControlGet, fixedH, 2:Hwnd, BasicFixedIcon
    GuiControlGet, periodH, 2:Hwnd, BasicIconPeriod
    GuiControlGet, saveH, 2:Hwnd, Save
    modeId:=DllCall("GetDlgCtrlID","UInt",modeH),fixedId:=DllCall("GetDlgCtrlID","UInt",fixedH),periodId:=DllCall("GetDlgCtrlID","UInt",periodH)
    BasicThemeAssert("Dropdowns_created_save_id_retained",!status && modeId=12 && fixedId=14 && periodId=16 && DllCall("GetDlgCtrlID","UInt",saveH)=9)
    BasicThemeAssert("Random_disables_fixed_dropdown",!DllCall("IsWindowEnabled","UInt",fixedH) && DllCall("IsWindowEnabled","UInt",periodH))
    GuiControl, 2:Choose, BasicIconMode, 1
    BasicThemeFields()
    BasicThemeAssert("Fixed_disables_period_dropdown",DllCall("IsWindowEnabled","UInt",fixedH) && !DllCall("IsWindowEnabled","UInt",periodH))
    BasicThemeSnapshot("BTCheck")
    Gui, 2:Destroy
    BasicSettingsHwnd:=0
    BasicThemeAssert("Gui_cancel_keeps_preferences",BasicThemeSame("BTCheck"))
    BasicShowSettings(0)
    GuiControl, 2:Choose, BasicIconMode, 1
    GuiControl, 2:Choose, BasicFixedIcon, 6
    GuiControlGet, saveH, 2:Hwnd, Save
    DllCall("PostMessageW","UInt",saveH,"UInt",0xF5,"UInt",0,"UInt",0)
    started:=A_TickCount
    while (BasicSettingsHwnd && A_TickCount-started<900) {
        Sleep, 10
    }
    SetTimer, ScanTimer, Off
    BasicThemeAssert("Native_save_commits_fixed50",!BasicSettingsHwnd && BasicThemeId()=50)
    BasicThemeSnapshot("BTCheck"),prior:=AutoEnabled,oldFile:=SettingsFile,oldIcon:=TIcon,SettingsFile:=ownRoot
    status:=BasicThemeSave(3,10,!prior,"fixed",51,"day"),SettingsFile:=oldFile,copy:=DllCall("CopyIcon","UInt",TIcon,"UInt")
    BasicThemeAssert("Interval_failure_restores_startup_icon_and_values",!status && BasicThemeSame("BTCheck") && AutoEnabled=prior && Interval=2 && BackgroundInterval=5 && TIcon=oldIcon && copy)
    if (copy)
        DllCall("DestroyIcon","UInt",copy)
    SetTimer, ScanTimer, Off
    Gui, 2:Destroy
    BasicSettingsHwnd:=0
    BasicThemeDispose()
    RegDelete, HKEY_CURRENT_USER, %base%
    Loop, 8
        FileDelete, % ownRoot . "\" . (44+A_Index) . "-legacy.ico"
    FileDelete, %SettingsFile%
    FileRemoveDir, %ownRoot%
    success:=TTestFailed="" ? 1 : 0,ExitStatus:=success ? 0 : 1
    text:="{" . Chr(34) . "Success" . Chr(34) . ":" . success . "," . Chr(34) . "Passed" . Chr(34) . ":" . TTestChecks . "," . Chr(34) . "Failed" . Chr(34) . ":" . Chr(34) . TTestFailed . Chr(34) . "," . Chr(34) . "Checks" . Chr(34) . ":[" . TTestNames . "]," . Chr(34) . "RealRunKeyAccessed" . Chr(34) . ":0," . Chr(34) . "RealChatGptAccessed" . Chr(34) . ":0," . Chr(34) . "SharedIpcUsed" . Chr(34) . ":0," . Chr(34) . "ModeId" . Chr(34) . ":" . modeId . "," . Chr(34) . "FixedId" . Chr(34) . ":" . fixedId . "," . Chr(34) . "PeriodId" . Chr(34) . ":" . periodId . "}"
    FileAppend, %text%, *
}





BasicThemeTick() {
    previousCritical:=A_IsCritical
    Critical, On
    result:=BasicThemeTickInner()
    Critical, %previousCritical%
    return result
}

BasicThemeInit(key="",root="",testing=0) {
    previousCritical:=A_IsCritical
    Critical, On
    result:=BasicThemeInitInner(key,root,testing)
    Critical, %previousCritical%
    return result
}

BasicThemeSave(first,second,enabled,mode,fixed,period) {
    previousCritical:=A_IsCritical
    Critical, On
    result:=BasicThemeSaveInner(first,second,enabled,mode,fixed,period)
    Critical, %previousCritical%
    return result
}
