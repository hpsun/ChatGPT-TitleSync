; Unicode rules client for Basic 1.0. Raw names stay UTF-16 binary buffers.
; No UIA reads, local regex engine, or preference writes occur in this module.
BasicRulesInit(rulesFile="",runtimeDir="",helper="") {
    global
    local root
    if (runtimeDir="")
        SplitPath, SettingsFile,, runtimeDir
    if (rulesFile="") {
        EnvGet, root, LOCALAPPDATA
        rulesFile := root . "\ChatGPT-TitleSync\title-rules.json"
    }
    NBRReady := 1, NBRRules := rulesFile, NBRDir := runtimeDir
    NBRSources := runtimeDir . "\title-rule-sources.bin", NBROverride := helper
    NBRSignature := "", NBRGeneration := 0, NBRDisplayRevision := 0
    NBRCount := 0, NBRDirty := 0, NBRBusy := 0, NBRNextSignature := 0
    NBRNextSources := 0, NBRSourceSignature := "", NBRSerial := 0, NBRWorker := 0
    BasicRulesSignature()
}
BasicRulesLocate() {
    global NBROverride
    if (NBROverride!="")
        return FileExist(NBROverride) ? NBROverride : ""
    path := A_ScriptDir . "\ChatGPT-TitleSync.Rules.exe"
    if (!FileExist(path))
        path := A_ScriptDir . "\..\..\shared\windows\ChatGPT-TitleSync.Rules.exe"
    if (!FileExist(path))
        return ""
    VarSetCapacity(full,32768,0)
    n := DllCall("GetFullPathNameA","Str",path,"UInt",32768,"Str",full,"UInt",0,"UInt")
    return n && n<32768 ? full : ""
}
BasicRulesSignature() {
    global
    local helper,present,signature,changed,length,i
    helper := BasicRulesLocate(), present := FileExist(NBRRules) ? 1 : 0
    signature := present ? BasicRulesHashFile(NBRRules) : "absent"
    if (helper!="") {
        FileGetTime, changed, %helper%, M
        FileGetSize, length, %helper%
        signature .= "|" . helper . "|" . changed . "|" . length
    } else
        signature .= "|companion_missing"
    NBRPresent := present, NBRHelper := helper
    if (signature!=NBRSignature) {
        NBRSignature := signature, NBRGeneration++, NBRDisplayRevision++, NBRDirty := 1
        BasicRulesAbandon()
        Loop, %NBRCount%
        {
            i := A_Index
            VarSetCapacity(NBRRaw%i%,0), VarSetCapacity(NBRDisplay%i%,0)
        }
        NBRCount := 0
    }
}
BasicRulesDisplay(ByRef raw,bytes,ByRef display,ByRef displayBytes) {
    global
    local i
    CopyBinary(display,raw,bytes), displayBytes := bytes
    if (!NBRReady || !NBRPresent)
        return
    Loop, %NBRCount%
    {
        i := A_Index
        if (BinaryEqual(raw,bytes,NBRRaw%i%,NBRRawBytes%i%)) {
            CopyBinary(display,NBRDisplay%i%,NBRDisplayBytes%i%)
            displayBytes := NBRDisplayBytes%i%
            return
        }
    }
    if (NBRCount>=128)
        return
    NBRCount++, i := NBRCount
    CopyBinary(NBRRaw%i%,raw,bytes), NBRRawBytes%i% := bytes
    CopyBinary(NBRDisplay%i%,raw,bytes), NBRDisplayBytes%i% := bytes
    NBRComplete%i% := 0, NBRItemGeneration%i% := NBRGeneration
    if (NBRHelper="")
        BasicRulesComplete(i,raw,bytes,"companion_missing")
}
BasicRulesComplete(i,ByRef display,bytes,code="") {
    global
    if (NBRItemGeneration%i%!=NBRGeneration)
        return
    CopyBinary(NBRDisplay%i%,display,bytes), NBRDisplayBytes%i% := bytes
    NBRComplete%i% := 1, NBRDisplayRevision++, NBRDirty := 1, NBRCode%i% := code
    if (code!="")
        Log("name_rules_fallback code=" . code)
}
BasicRulesAbandon() {
    global NBRWorker,NBRAbandoned
    if (NBRWorker) {
        NBRAbandoned := 1
        if (DllCall("WaitForSingleObject","UInt",NBRWorker,"UInt",0)=258)
            DllCall("TerminateProcess","UInt",NBRWorker,"UInt",125)
    }
}
BasicRulesClean() {
    global NBRWorker,NBRInput,NBROutput,NBRStatus
    BasicRulesDelete(NBRInput), BasicRulesDelete(NBROutput), BasicRulesDelete(NBRStatus)
    if (NBRWorker)
        DllCall("CloseHandle","UInt",NBRWorker)
    NBRWorker := 0
}
BasicRulesDelete(path) {
    if (path="")
        return
    ToWide(path,wide)
    DllCall("DeleteFileW","UInt",&wide)
}
BasicRulesStart(i) {
    global
    local folder,stem,args,handle
    folder := NBRDir . "\name-rule-work"
    FileCreateDir, %folder%
    NBRSerial++, stem := folder . "\" . DllCall("GetCurrentProcessId") . "-" . A_TickCount . "-" . NBRSerial
    NBRInput := stem . ".in", NBROutput := stem . ".out", NBRStatus := stem . ".status"
    if (!BasicRulesWrite(NBRInput,NBRRaw%i%,NBRRawBytes%i%)) {
        BasicRulesClean()
        BasicRulesComplete(i,NBRRaw%i%,NBRRawBytes%i%,"worker_start_failed")
        return
    }
    args := Quote(NBRHelper) . " --format --rules " . Quote(NBRRules) . " --input " . Quote(NBRInput) . " --output " . Quote(NBROutput) . " --status " . Quote(NBRStatus)
    handle := BasicRulesLaunch(NBRHelper,args,1)
    if (!handle) {
        BasicRulesClean()
        BasicRulesComplete(i,NBRRaw%i%,NBRRawBytes%i%,"worker_start_failed")
        return
    }
    NBRWorker := handle, NBRWorkerIndex := i, NBRWorkerGeneration := NBRGeneration
    NBRStarted := A_TickCount, NBRAbandoned := 0
}
BasicRulesTick() {
    global
    local now,wait,elapsed,code,output,bytes,status,statusBytes,tag,i,reason
    if (!NBRReady || NBRBusy)
        return
    NBRBusy := 1, now := A_TickCount
    if (now>=NBRNextSignature) {
        NBRNextSignature := now+1000
        BasicRulesSignature()
    }
    if (now>=NBRNextSources) {
        NBRNextSources := now+1000
        BasicRulesSnapshot()
    }
    if (NBRWorker) {
        wait := DllCall("WaitForSingleObject","UInt",NBRWorker,"UInt",0,"UInt")
        elapsed := now-NBRStarted
        if (elapsed<0)
            elapsed += 4294967296
        if (wait=258 && elapsed>=1500 && !NBRAbandoned) {
            DllCall("TerminateProcess","UInt",NBRWorker,"UInt",124)
            NBRAbandoned := 1, i := NBRWorkerIndex
            if (NBRWorkerGeneration=NBRGeneration)
                BasicRulesComplete(i,NBRRaw%i%,NBRRawBytes%i%,"worker_timeout")
        } else if (wait!=258) {
            i := NBRWorkerIndex
            if (!NBRAbandoned && NBRWorkerGeneration=NBRGeneration) {
                code := 3, reason := "worker_io"
                DllCall("GetExitCodeProcess","UInt",NBRWorker,"UIntP",code)
                if (BasicRulesRead(NBROutput,output,bytes,1024) && BasicRulesRead(NBRStatus,status,statusBytes,256)) {
                    tag := BasicRulesASCII(status,statusBytes)
                    if (code=0 && tag="ok" && BasicRulesValidWide(output,bytes))
                        reason := ""
                    else if (code=2 && RegExMatch(tag,"^fallback:[a-z0-9_]+$") && BinaryEqual(output,bytes,NBRRaw%i%,NBRRawBytes%i%))
                        reason := SubStr(tag,10)
                }
                if (reason="")
                    BasicRulesComplete(i,output,bytes)
                else
                    BasicRulesComplete(i,NBRRaw%i%,NBRRawBytes%i%,reason)
            }
            BasicRulesClean()
        }
    }
    if (!NBRWorker && NBRPresent && NBRHelper!="") {
        Loop, %NBRCount%
        {
            i := A_Index
            if (!NBRComplete%i%) {
                BasicRulesStart(i)
                Break
            }
        }
    }
    if (NBRDirty) {
        NBRDirty := 0
        BasicRulesRefreshOwned()
    }
    NBRBusy := 0
}
BasicRulesLaunch(exe,args,hidden) {
    ToWide(exe,executable), ToWide(args,command)
    VarSetCapacity(si,68,0), VarSetCapacity(pi,16,0), NumPut(68,si,0,"UInt")
    flags := hidden ? 0x08000000 : 0
    if (!DllCall("CreateProcessW","UInt",&executable,"UInt",&command,"UInt",0,"UInt",0,"Int",0,"UInt",flags,"UInt",0,"UInt",0,"UInt",&si,"UInt",&pi))
        return 0
    DllCall("CloseHandle","UInt",NumGet(pi,4,"UInt"))
    return NumGet(pi,0,"UInt")
}
BasicRulesRefreshOwned() {
    global
    local hwnd,current,cb,wanted,wb
    if (ReadOnly || Paused)
        return
    Loop, Parse, Tracked, |
    {
        hwnd := A_LoopField
        if (!hwnd || !Rec%hwnd%_Owned || !Rec%hwnd%_CachedBytes || !MatchesRecord(hwnd))
            Continue
        if (!ReadCaption(hwnd,current,cb) || !BinaryEqual(current,cb,Rec%hwnd%_Last,Rec%hwnd%_LastBytes))
            Continue
        BuildWanted(Rec%hwnd%_Cached,Rec%hwnd%_CachedBytes,wanted,wb)
        if (!BinaryEqual(wanted,wb,current,cb) && MatchesRecord(hwnd) && SetCaptionChecked(hwnd,wanted,wb) && MatchesRecord(hwnd)) {
            CopyBinary(Rec%hwnd%_Last,wanted,wb), Rec%hwnd%_LastBytes := wb
            Log("name_rules_display_updated hwnd=" . hwnd)
        }
    }
}
BasicRulesRead(path,ByRef data,ByRef bytes,maximum) {
    bytes := 0
    ToWide(path,wide)
    h := DllCall("CreateFileW","UInt",&wide,"UInt",0x80000000,"UInt",7,"UInt",0,"UInt",3,"UInt",0x80,"UInt",0,"UInt")
    if (h=0xFFFFFFFF || !h)
        return 0
    good := DllCall("GetFileSizeEx","UInt",h,"Int64P",size) && size>=0 && size<=maximum
    if (good) {
        VarSetCapacity(data,size+2,0)
        good := DllCall("ReadFile","UInt",h,"UInt",&data,"UInt",size,"UIntP",bytes,"UInt",0) && bytes=size
    }
    DllCall("CloseHandle","UInt",h)
    return good
}
BasicRulesWrite(path,ByRef data,bytes) {
    ToWide(path,wide)
    h := DllCall("CreateFileW","UInt",&wide,"UInt",0x40000000,"UInt",0,"UInt",0,"UInt",2,"UInt",0x80,"UInt",0,"UInt")
    if (h=0xFFFFFFFF || !h)
        return 0
    good := DllCall("WriteFile","UInt",h,"UInt",&data,"UInt",bytes,"UIntP",written,"UInt",0) && written=bytes
    DllCall("CloseHandle","UInt",h)
    return good
}
BasicRulesASCII(ByRef data,bytes) {
    text := ""
    Loop, %bytes%
    {
        ch := NumGet(data,A_Index-1,"UChar")
        if (!ch || ch>127)
            return ""
        text .= Chr(ch)
    }
    return text
}
BasicRulesValidWide(ByRef data,bytes) {
    if (!bytes || Mod(bytes,2) || bytes>1024 || WideEqualsASCII(&data,"ChatGPT"))
        return 0
    units := bytes//2, nonwhite := 0, low := 0
    Loop, %units%
    {
        ch := NumGet(data,(A_Index-1)*2,"UShort")
        if (ch<32 || (ch>=127 && ch<=159) || (low && (ch<0xDC00 || ch>0xDFFF)))
            return 0
        if (!low && ch>=0xDC00 && ch<=0xDFFF)
            return 0
        low := !low && ch>=0xD800 && ch<=0xDBFF
        if (ch!=32 && ch!=0xA0 && ch!=0x1680 && !(ch>=0x2000 && ch<=0x200A) && ch!=0x2028 && ch!=0x2029 && ch!=0x202F && ch!=0x205F && ch!=0x3000)
            nonwhite := 1
    }
    return nonwhite && !low
}
BasicRulesHashFile(path) {
    if (!BasicRulesRead(path,data,bytes,131072))
        return "unreadable_or_oversized"
    return BasicRulesHash(data,bytes)
}
BasicRulesHash(ByRef data,bytes) {
    provider := 0, hash := 0, result := "hash_failed"
    if (DllCall("Advapi32\CryptAcquireContextW","UIntP",provider,"UInt",0,"UInt",0,"UInt",24,"UInt",0xF0000000)) {
        if (DllCall("Advapi32\CryptCreateHash","UInt",provider,"UInt",0x800C,"UInt",0,"UInt",0,"UIntP",hash)) {
            if (DllCall("Advapi32\CryptHashData","UInt",hash,"UInt",&data,"UInt",bytes,"UInt",0)) {
                VarSetCapacity(digest,32,0), n := 32
                if (DllCall("Advapi32\CryptGetHashParam","UInt",hash,"UInt",2,"UInt",&digest,"UIntP",n,"UInt",0)) {
                    result := "", hex := "0123456789abcdef"
                    Loop, 32
                    {
                        b := NumGet(digest,A_Index-1,"UChar")
                        result .= SubStr(hex,(b>>4)+1,1) . SubStr(hex,(b&15)+1,1)
                    }
                }
            }
            DllCall("Advapi32\CryptDestroyHash","UInt",hash)
        }
        DllCall("Advapi32\CryptReleaseContext","UInt",provider,"UInt",0)
    }
    return result
}
BasicRulesSnapshot() {
    global
    local packet,count,offset,hwnd,bytes,identities,signature,parent,temp,wideTemp,wideTarget
    VarSetCapacity(packet,131072,0), NumPut(0x31535443,packet,0,"UInt")
    count := 0, offset := 8, identities := ""
    Loop, Parse, Tracked, |
    {
        hwnd := A_LoopField
        bytes := Rec%hwnd%_CachedBytes
        if (!hwnd || !bytes || bytes>1024 || Mod(bytes,2) || !MatchesRecord(hwnd))
            Continue
        if (count>=128 || offset+4+bytes>131072)
            Break
        NumPut(bytes//2,packet,offset,"UInt"), offset += 4
        DllCall("RtlMoveMemory","UInt",&packet+offset,"UInt",&Rec%hwnd%_Cached,"UInt",bytes), offset += bytes
        identities .= hwnd . ":" . Rec%hwnd%_Pid . ":" . Rec%hwnd%_Lo . ":" . Rec%hwnd%_Hi . "|"
        count++
    }
    NumPut(count,packet,4,"UInt")
    signature := identities . BasicRulesHash(packet,offset)
    if (signature=NBRSourceSignature)
        return
    SplitPath, NBRSources,, parent
    FileCreateDir, %parent%
    temp := NBRSources . "." . DllCall("GetCurrentProcessId") . ".tmp"
    if (BasicRulesWrite(temp,packet,offset)) {
        ToWide(temp,wideTemp), ToWide(NBRSources,wideTarget)
        if (DllCall("MoveFileExW","UInt",&wideTemp,"UInt",&wideTarget,"UInt",9))
            NBRSourceSignature := signature
        else
            Log("name_rules_fallback code=snapshot_write_failed")
    }
    BasicRulesDelete(temp)
}
BasicRulesOpenEditor() {
    global NBRReady,NBRHelper,NBRRules,NBRSources
    if (!NBRReady)
        return
    BasicRulesSignature(), BasicRulesSnapshot()
    help := A_ScriptDir . "\..\..\docs\name-replacement.html"
    if (!FileExist(help))
        help := A_ScriptDir . "\docs\name-replacement.html"
    if (NBRHelper="" || !FileExist(help)) {
        MsgBox, 16, ChatGPT-TitleSync - Name replacement, The rules companion or local help page is unavailable.
        return
    }
    args := Quote(NBRHelper) . " --edit --rules " . Quote(NBRRules) . " --sources " . Quote(NBRSources) . " --help " . Quote(help)
    handle := BasicRulesLaunch(NBRHelper,args,0)
    if (handle)
        DllCall("CloseHandle","UInt",handle)
    else
        MsgBox, 16, ChatGPT-TitleSync - Name replacement, Could not open the rules editor.
}
BasicRulesClose() {
    global NBRWorker
    BasicRulesAbandon()
    if (NBRWorker)
        BasicRulesClean()
}
