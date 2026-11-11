; Icon policy uses only five named HKCU values. No title read or process helper is started.
; The existing metadata timer supplies cheap slot checks. Tests inject local time,
; UTC offset, picker and private registry/assets, never the production preference key.
ThemeDefaults() {
    return {IconMode:"fixed",FixedIcon:45,IconPeriod:"day",RandomIcon:45,IconSlot:""}
}
ThemeNames() {
    return ["IconMode","FixedIcon","IconPeriod","RandomIcon","IconSlot"]
}
ThemeEnsure() {
    global G
    if !G.HasKey("Theme")
        G.Theme:={State:ThemeDefaults(),Allowed:false,Key:"",Root:"",Icon:0,Current:0,Testing:false,Now:"",Offset:"",Pick:0,Next:0,ErrorSlot:"",Errors:0}
    return G.Theme
}
ThemeOffset() {
    VarSetCapacity(zone,172,0)
    mode:=DllCall("GetTimeZoneInformation","Ptr",&zone,"UInt"),bias:=NumGet(zone,0,"Int")
    if (mode=1)
        bias+=NumGet(zone,84,"Int")
    else if (mode=2)
        bias+=NumGet(zone,168,"Int")
    minutes:=-bias
    return (minutes<0?"-":"+") Format("{:02}{:02}",Abs(minutes)//60,Mod(Abs(minutes),60))
}
ThemeSlot(period,now:="",offset:="") {
    if (now="")
        now:=A_Now
    if (offset="")
        offset:=ThemeOffset()
    if (period="day")
        return SubStr(now,1,8)
    if (period="hour")
        return SubStr(now,1,10) offset
    if (period="5min")
        return SubStr(now,1,10) Format("{:02}",Floor(SubStr(now,11,2)/5)) offset
    throw Exception("Icon period must be day, hour or 5min.")
}
ThemePath(id) {
    t:=ThemeEnsure()
    return t.Root "\" id ".ico"
}
ThemeLoad(id) {
    path:=ThemePath(id)
    handle:=DllCall("LoadImageW","Ptr",0,"WStr",path,"UInt",1,"Int",32,"Int",32,"UInt",0x10,"Ptr")
    if !handle
        throw Exception("Unable to load icon asset " id)
    return handle
}
ThemeValidate(mode,fixed,period) {
    if ((mode!="fixed" && mode!="random") || fixed<45 || fixed>52 || fixed!=Floor(fixed) || (period!="day" && period!="hour" && period!="5min"))
        throw Exception("Invalid icon mode, fixed palette or random period.")
    Loop, % mode="random"?8:1 {
        id:=mode="random"?44+A_Index:fixed,handle:=ThemeLoad(id)
        DllCall("DestroyIcon","Ptr",handle)
    }
}
ThemeSnapshot() {
    t:=ThemeEnsure(),values:={}
    for _,name in ThemeNames()
        values[name]:=AutoRegRead(t.Key,name)
    return {Values:values,State:t.State.Clone()}
}
ThemeRestore(snapshot) {
    t:=ThemeEnsure(),failures:=""
    for name,item in snapshot.Values {
        current:=AutoRegRead(t.Key,name)
        if !AutoRegEqual(current,item) {
            status:=AutoRegWrite(t.Key,name,item)
            if status
                failures.=name ":" status " "
        }
    }
    if (failures!="")
        throw Exception("Icon rollback failed: " failures)
    t.State:=snapshot.State.Clone()
}
ThemePrepare(mode,fixed,period) {
    t:=ThemeEnsure(),s:=t.State,plan:=s.Clone()
    ThemeValidate(mode,fixed,period)
    plan.IconMode:=mode,plan.FixedIcon:=fixed,plan.IconPeriod:=period
    if (mode="random") {
        slot:=ThemeSlot(period,t.Now,t.Offset)
        if (s.IconMode!="random" || s.IconPeriod!=period || s.IconSlot!=slot) {
            if t.Pick
                selected:=t.Pick
            else {
                Loop {
                    Random, selected, 45, 52
                    if (selected!=s.RandomIcon)
                        break
                }
            }
            if (selected<45 || selected>52 || selected=s.RandomIcon)
                throw Exception("Injected icon picker repeated or left the palette.")
            plan.RandomIcon:=selected,plan.IconSlot:=slot
        }
    }
    return plan
}
ThemeCommit(plan,failName:="") {
    t:=ThemeEnsure(),before:=ThemeSnapshot()
    ThemeValidate(plan.IconMode,plan.FixedIcon,plan.IconPeriod)
    if (plan.RandomIcon<45 || plan.RandomIcon>52)
        throw Exception("Invalid persisted random icon.")
    try {
        for _,name in ThemeNames() {
            desired:=AutoRegValue((name="FixedIcon" || name="RandomIcon")?4:1,plan[name])
            if !AutoRegEqual(before.Values[name],desired) {
                status:=name=failName?5:AutoRegWrite(t.Key,name,desired)
                if status
                    throw Exception("Icon preference write failed: " name "=" status)
            }
        }
    } catch error {
        ThemeRestore(before)
        throw error
    }
    t.State:=plan.Clone(),t.ErrorSlot:=""
}
ThemeId(state:="") {
    t:=ThemeEnsure(),s:=IsObject(state)?state:t.State
    return s.IconMode="fixed"?s.FixedIcon:s.RandomIcon
}
ThemeInitializeInner(key:="",root:="",testing:=false) {
    t:=ThemeEnsure(),t.Allowed:=true,t.Testing:=testing
    t.Key:=key!=""?key:"Software\ChatGPT-TitleSync"
    t.Root:=root!=""?root:(A_IsCompiled?A_ScriptDir "\assets\themes":A_ScriptDir "\..\..\assets\themes")
    loaded:=ThemeDefaults()
    for _,name in ThemeNames() {
        raw:=AutoRegRead(t.Key,name)
        if !raw.Exists
            continue
        kind:=(name="FixedIcon" || name="RandomIcon")?4:1
        if (raw.Type!=kind || (kind=4 && raw.Size!=4) || (kind=1 && (raw.Size<2 || Mod(raw.Size,2) || NumGet(raw.GetAddress("Bytes"),raw.Size-2,"UShort"))))
            throw Exception("Invalid persisted icon type: " name)
        loaded[name]:=kind=4?NumGet(raw.GetAddress("Bytes"),0,"UInt"):StrGet(raw.GetAddress("Bytes"),raw.Size//2-1,"UTF-16")
    }
    ThemeValidate(loaded.IconMode,loaded.FixedIcon,loaded.IconPeriod)
    if (loaded.RandomIcon<45 || loaded.RandomIcon>52)
        throw Exception("Invalid persisted random icon.")
    t.State:=loaded
    if (loaded.IconMode="random") {
        plan:=ThemePrepare(loaded.IconMode,loaded.FixedIcon,loaded.IconPeriod)
        if (plan.RandomIcon!=loaded.RandomIcon || plan.IconSlot!=loaded.IconSlot)
            ThemeCommit(plan)
    }
}
ThemeWindowIcons(handle) {
    global G
    for _,hwnd in [A_ScriptHwnd,G.HasKey("SettingsHwnd")?G.SettingsHwnd:0] {
        if hwnd {
            DllCall("SendMessageW","Ptr",hwnd,"UInt",0x80,"Ptr",0,"Ptr",handle)
            DllCall("SendMessageW","Ptr",hwnd,"UInt",0x80,"Ptr",1,"Ptr",handle)
        }
    }
}
ThemeStage(id) {
    t:=ThemeEnsure()
    if (id=t.Current)
        return 0
    handle:=ThemeLoad(id),stage:={Old:t.Icon,OldId:t.Current,New:handle,NewId:id}
    try {
        if !t.Testing {
            path:=ThemePath(id)
            Menu, Tray, Icon, %path%
        }
        ThemeWindowIcons(handle)
    } catch error {
        DllCall("DestroyIcon","Ptr",handle)
        throw error
    }
    t.Icon:=handle,t.Current:=id
    return stage
}
ThemeFinish(stage) {
    if (IsObject(stage) && stage.Old)
        DllCall("DestroyIcon","Ptr",stage.Old)
}
ThemeUndo(stage) {
    if !IsObject(stage)
        return
    t:=ThemeEnsure()
    if !t.Testing {
        spec:=stage.Old?"HICON:*" stage.Old:ThemePath(45)
        Menu, Tray, Icon, %spec%
    }
    ThemeWindowIcons(stage.Old),t.Icon:=stage.Old,t.Current:=stage.OldId
    DllCall("DestroyIcon","Ptr",stage.New)
}
ThemeDispose() {
    t:=ThemeEnsure()
    if t.Icon {
        ThemeWindowIcons(0)
        DllCall("DestroyIcon","Ptr",t.Icon)
        t.Icon:=0,t.Current:=0
    }
}
ThemeError(slot) {
    t:=ThemeEnsure(),t.ErrorSlot:=slot,t.Errors+=1
    if !t.Testing
        LogEvent("icon_rotation_failed",0,slot)
}
ThemeTickInner() {
    t:=ThemeEnsure()
    if (!t.Allowed || Tick()<t.Next)
        return
    t.Next:=Tick()+1000
    if (t.State.IconMode!="random")
        return
    slot:=ThemeSlot(t.State.IconPeriod,t.Now,t.Offset)
    if (slot=t.State.IconSlot || slot=t.ErrorSlot)
        return
    stage:=0
    try {
        plan:=ThemePrepare("random",t.State.FixedIcon,t.State.IconPeriod)
        stage:=ThemeStage(ThemeId(plan)),ThemeCommit(plan),ThemeFinish(stage)
    } catch error {
        try ThemeUndo(stage)
        ThemeError(slot)
    }
}
ThemeSaveInner(first,second,enabled,mode,fixed,period) {
    global G
    t:=ThemeEnsure()
    if !t.Allowed {
        ApplySettingsWithAutoStart(first,second,enabled)
        return
    }
    if !ValidIntervals(first,second)
        throw Exception("Foreground: 1..3600; background: 5..3600 seconds.")
    plan:=ThemePrepare(mode,fixed,period),before:=ThemeSnapshot(),prior:=G.AutoStartEnabled
    oldRun:=AutoRegRead(G.AutoRunKey,"ChatGPT-TitleSync"),oldPref:=AutoRegRead(G.AutoPrefKey,"AutoStartEnabled"),stage:=0
    try {
        stage:=ThemeStage(ThemeId(plan))
        AutoStartApply(enabled),ThemeCommit(plan),ApplyIntervals(first,second),ThemeFinish(stage)
    } catch error {
        problems:=""
        try ThemeRestore(before)
        catch rollback
            problems.=rollback.Message
        firstStatus:=AutoRegWrite(G.AutoRunKey,"ChatGPT-TitleSync",oldRun),secondStatus:=AutoRegWrite(G.AutoPrefKey,"AutoStartEnabled",oldPref)
        if (firstStatus || secondStatus)
            problems.=" startup rollback failed"
        else
            G.AutoStartEnabled:=prior,SyncAutoStart()
        try ThemeUndo(stage)
        catch rollback
            problems.=rollback.Message
        throw Exception(error.Message (problems!=""?"; " problems:""))
    }
}
ThemeAddControls() {
    global G,CxtIconMode,CxtFixedIcon,CxtIconPeriod
    t:=ThemeEnsure(),s:=t.State
    Gui, Settings:Add, Text, x10 y165 w120, Icon mode
    Gui, Settings:Add, DropDownList, % "vCxtIconMode AltSubmit gCxtThemeChanged x140 y160 w170 Choose" (s.IconMode="fixed"?1:2), Fixed|Random
    Gui, Settings:Add, Text, x10 y205 w120, Fixed palette
    Gui, Settings:Add, DropDownList, % "vCxtFixedIcon AltSubmit x140 y200 w170 Choose" (s.FixedIcon-44), 45|46|47|48|49|50|51|52
    Gui, Settings:Add, Text, x10 y245 w120, Random period
    Gui, Settings:Add, DropDownList, % "vCxtIconPeriod AltSubmit x140 y240 w170 Choose" (s.IconPeriod="day"?1:s.IconPeriod="hour"?2:3), Daily|Hourly|Every 5 minutes
    GuiControl, Settings:Move, Save, x80 y290
    GuiControl, Settings:Move, Cancel, x190 y290
    ThemeFields()
    if t.Icon
        ThemeWindowIcons(t.Icon)
}
ThemeFields() {
    t:=ThemeEnsure()
    GuiControlGet, mode, Settings:, CxtIconMode
    action:=t.Allowed?"Enable":"Disable"
    GuiControl, Settings:%action%, CxtIconMode
    action:=t.Allowed && mode=1?"Enable":"Disable"
    GuiControl, Settings:%action%, CxtFixedIcon
    action:=t.Allowed && mode=2?"Enable":"Disable"
    GuiControl, Settings:%action%, CxtIconPeriod
}
ThemeAssert(name,passed) {
    t:=ThemeEnsure()
    if !passed
        throw Exception(name)
    t.Checks.Push(name)
}
ThemeSameSnapshot(a,b) {
    for _,name in ThemeNames()
        if !AutoRegEqual(a.Values[name],b.Values[name])
            return false
    return Json(a.State)=Json(b.State)
}
ThemeSelfTest() {
    global G
    base:="Software\ChatGPT-TitleSync-SelfTest\icon_v11_" DllCall("GetCurrentProcessId") "_" A_TickCount
    originalRoot:=Arg("--icon-test-assets",A_IsCompiled?A_ScriptDir "\assets\themes":A_ScriptDir "\..\..\assets\themes")
    ownRoot:=A_Temp "\titlesync_theme_v11_" DllCall("GetCurrentProcessId")
    FileCreateDir, %ownRoot%
    t:=ThemeEnsure(),t.Testing:=true,t.Now:="20261111120459",t.Offset:="+0800",t.Checks:=[]
    success:=false,problem:=""
    try {
        Loop, 8 {
            source:=originalRoot "\" (44+A_Index) ".ico",target:=ownRoot "\" (44+A_Index) ".ico"
            FileCopy, %source%, %target%, 1
            if ErrorLevel
                throw Exception("OwnIconFixtureCopy")
        }
        ThemeInitialize(base "\Preferences",ownRoot,true)
        missing:=true
        for _,name in ThemeNames()
            if AutoRegRead(t.Key,name).Exists
                missing:=false
        ThemeAssert("Missing_defaults_fixed45_without_registry_writes",missing && ThemeId()=45 && t.State.IconMode="fixed")
        Loop, 8 {
            id:=44+A_Index,ThemeCommit(ThemePrepare("fixed",id,"day"))
            ThemeAssert("Fixed_palette_" id,ThemeId()=id)
        }
        before:=ThemeSnapshot(),bad:=false
        try ThemePrepare("invalid",45,"day")
        catch error
            bad:=true
        ThemeAssert("Invalid_selection_preserves_all_values",bad && ThemeSameSnapshot(before,ThemeSnapshot()))
        t.Pick:=46,plan:=ThemePrepare("random",45,"day")
        ThemeAssert("Prepared_cancel_does_not_commit",ThemeSameSnapshot(before,ThemeSnapshot()))
        ThemeCommit(plan)
        ThemeAssert("Enable_random_immediate_and_nonrepeating",ThemeId()=46 && t.State.IconSlot="20261111")
        before:=ThemeSnapshot(),t.Pick:=46
        ThemeInitialize(t.Key,ownRoot,true)
        ThemeAssert("Same_slot_restart_keeps_color",ThemeSameSnapshot(before,ThemeSnapshot()))
        ThemeAssert("Exact_daily_slot",ThemeSlot("day","20261111235959","+0800")="20261111")
        ThemeAssert("Exact_hourly_offset_slot",ThemeSlot("hour","20261111125959","+0800")="2026111112+0800")
        ThemeAssert("Exact_five_minute_slot",ThemeSlot("5min","20261111130500","+0800")="202611111301+0800")
        ThemeAssert("Offset_disambiguates_repeated_local_hour",ThemeSlot("hour","20261101010000","-0400")!=ThemeSlot("hour","20261101010000","-0500"))
        t.Now:="20261111125959",t.Pick:=47,ThemeCommit(ThemePrepare("random",45,"hour"))
        t.Now:="20261111130000",t.Pick:=48,t.Next:=0,ThemeTick()
        ThemeAssert("Hour_boundary_rotates_without_adjacent_repeat",ThemeId()=48 && t.State.IconSlot="2026111113+0800")
        t.Pick:=49,ThemeCommit(ThemePrepare("random",45,"5min")),t.Now:="20261111130500",t.Pick:=50,t.Next:=0,ThemeTick()
        ThemeAssert("Five_minute_boundary_rotates",ThemeId()=50 && t.State.IconSlot="202611111301+0800")
        t.Pick:=51,ThemeCommit(ThemePrepare("random",45,"day")),t.Now:="20261112000000",t.Pick:=52,t.Next:=0,ThemeTick()
        ThemeAssert("Day_boundary_rotates",ThemeId()=52 && t.State.IconSlot="20261112")
        ThemeCommit(ThemePrepare("fixed",45,"day")),before:=ThemeSnapshot(),t.Now:="20270101000000",t.Next:=0,ThemeTick()
        ThemeAssert("Fixed_mode_never_rotates",ThemeSameSnapshot(before,ThemeSnapshot()))
        t.Pick:=46,ThemeCommit(ThemePrepare("random",45,"hour")),before:=ThemeSnapshot()
        FileDelete, % ownRoot "\52.ico"
        t.Now:="20270101010000",t.Pick:=47,t.Next:=0,ThemeTick(),count:=t.Errors,t.Next:=0,ThemeTick()
        ThemeAssert("Missing_rotation_asset_preserves_and_logs_once",ThemeSameSnapshot(before,ThemeSnapshot()) && t.Errors=count && count=1)
        source:=originalRoot "\52.ico",target:=ownRoot "\52.ico"
        FileCopy, %source%, %target%, 1
        t.Now:="20270101020000",t.Next:=0,ThemeTick()
        ThemeAssert("Later_slot_recovers_after_asset_return",ThemeId()=47)
        before:=ThemeSnapshot(),t.Pick:=48,bad:=false
        try ThemeCommit(ThemePrepare("random",45,"5min"),"IconPeriod")
        catch error
            bad:=true
        ThemeAssert("Failed_named_write_restores_five_raw_values",bad && ThemeSameSnapshot(before,ThemeSnapshot()))
        G.AutoStartTesting:=true,G.AutoStartAllowed:=true,G.IntervalMs:=2000,G.BackgroundMs:=5000,G.SettingsRevision:=0,G.BgChild:=0
        G.SettingsFile:=ownRoot "\intervals.ini"
        AutoStartInitialize(base "\Run",t.Key,Q("C:\Own app\Helper.exe"))
        ShowIntervalSettings(false)
        GuiControlGet, modeH, Settings:Hwnd, CxtIconMode
        GuiControlGet, fixedH, Settings:Hwnd, CxtFixedIcon
        GuiControlGet, periodH, Settings:Hwnd, CxtIconPeriod
        GuiControlGet, saveH, Settings:Hwnd, Save
        modeId:=DllCall("GetDlgCtrlID","Ptr",modeH),fixedId:=DllCall("GetDlgCtrlID","Ptr",fixedH),periodId:=DllCall("GetDlgCtrlID","Ptr",periodH)
        ThemeAssert("Dropdowns_created_and_existing_save_id_retained",modeH && fixedH && periodH && DllCall("GetDlgCtrlID","Ptr",saveH)=9)
        ThemeAssert("Random_disables_fixed_dropdown",!DllCall("IsWindowEnabled","Ptr",fixedH) && DllCall("IsWindowEnabled","Ptr",periodH))
        GuiControl, Settings:Choose, CxtIconMode, 1
        ThemeFields()
        ThemeAssert("Fixed_disables_period_dropdown",DllCall("IsWindowEnabled","Ptr",fixedH) && !DllCall("IsWindowEnabled","Ptr",periodH))
        before:=ThemeSnapshot()
        Gui, Settings:Destroy
        G.SettingsHwnd:=0
        ThemeAssert("Gui_cancel_keeps_preferences",ThemeSameSnapshot(before,ThemeSnapshot()))
        ShowIntervalSettings(false)
        GuiControl, Settings:Choose, CxtIconMode, 1
        GuiControl, Settings:Choose, CxtFixedIcon, 6
        GuiControlGet, saveH, Settings:Hwnd, Save
        DllCall("PostMessageW","Ptr",saveH,"UInt",0xF5,"Ptr",0,"Ptr",0)
        started:=A_TickCount
        while (G.SettingsHwnd && A_TickCount-started<900)
            Sleep, 10
        SetTimer, PollTimer, Off
        ThemeAssert("Native_Save_commits_fixed50",!G.SettingsHwnd && ThemeId()=50)
        before:=ThemeSnapshot(),priorStartup:=G.AutoStartEnabled,oldFile:=G.SettingsFile,oldIcon:=t.Icon
        G.SettingsFile:=ownRoot,bad:=false
        try ThemeSave(3,10,!priorStartup,"fixed",51,"day")
        catch error
            bad:=true
        G.SettingsFile:=oldFile
        copy:=DllCall("CopyIcon","Ptr",t.Icon,"Ptr")
        ThemeAssert("Interval_save_failure_restores_icon_startup_and_values",bad && ThemeSameSnapshot(before,ThemeSnapshot()) && G.AutoStartEnabled=priorStartup && G.IntervalMs=2000 && G.BackgroundMs=5000 && t.Icon=oldIcon && copy)
        if copy
            DllCall("DestroyIcon","Ptr",copy)
        success:=true
    } catch error {
        problem:=error.Message " at " error.Line
    }
    SetTimer, PollTimer, Off
    Gui, Settings:Destroy
    ThemeDispose()
    RegDelete, HKEY_CURRENT_USER, %base%
    Loop, 8
        FileDelete, % ownRoot "\" (44+A_Index) ".ico"
    FileDelete, % G.SettingsFile
    FileRemoveDir, %ownRoot%
    Emit({Success:success?1:0,Passed:t.Checks.MaxIndex(),Checks:t.Checks,Error:problem,RealRunKeyAccessed:0,RealChatGptAccessed:0,SharedIpcUsed:0,ModeId:modeId,FixedId:fixedId,PeriodId:periodId},Arg("--output"))
}

ThemeTick() {
    priorCritical:=A_IsCritical
    Critical, On
    try return ThemeTickInner()
    finally {
        Critical, %priorCritical%
    }
}

ThemeInitialize(key:="",root:="",testing:=false) {
    priorCritical:=A_IsCritical
    Critical, On
    try return ThemeInitializeInner(key,root,testing)
    finally {
        Critical, %priorCritical%
    }
}

ThemeSave(first,second,enabled,mode,fixed,period) {
    priorCritical:=A_IsCritical
    Critical, On
    try return ThemeSaveInner(first,second,enabled,mode,fixed,period)
    finally {
        Critical, %priorCritical%
    }
}

