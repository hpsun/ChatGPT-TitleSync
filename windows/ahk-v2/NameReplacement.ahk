; Unicode companion client. No UIA reads, regex engine, or preference writes here.
RulesInit(rulesFile:="",runtimeDir:="",helper:="") {
    global NR,G
    if (runtimeDir="") {
        SplitPath(G.SettingsFile,, &runtimeDir)
    }
    if (rulesFile="") {
        localData:=EnvGet("LOCALAPPDATA")
        rulesFile:=localData "\ChatGPT-TitleSync\title-rules.json"
    }
    NR:={Rules:rulesFile,Dir:runtimeDir,Sources:runtimeDir "\title-rule-sources.bin",Override:helper
        ,Helper:"",Signature:"",Present:false,Generation:0,DisplayRevision:0,Cache:[],Queue:[]
        ,Worker:0,Dirty:false,Busy:false,NextSignature:0,NextSources:0,SourceSignature:"",Serial:0}
    RulesSignature()
}
RulesExact(a,b) {
    return DllCall("CompareStringOrdinal","WStr",a,"Int",StrLen(a),"WStr",b,"Int",StrLen(b),"Int",0,"Int")=2
}
RulesLocate() {
    global NR
    if (NR.Override!="")
        return FileExist(NR.Override)?NR.Override:""
    for _,p in [A_ScriptDir "\ChatGPT-TitleSync.Rules.exe",A_ScriptDir "\..\..\shared\windows\ChatGPT-TitleSync.Rules.exe"] {
        if FileExist(p) {
            return RulesFullPath(p)
        }
    }
    return ""
}
RulesSignature() {
    global NR
    helper:=RulesLocate(),present:=!!FileExist(NR.Rules)
    signature:=present?RulesHashFile(NR.Rules):"absent"
    if (helper!="") {
        changed:=FileGetTime(helper,"M"),length:=FileGetSize(helper)
        signature.="|" helper "|" changed "|" length
    } else
        signature.="|companion_missing"
    NR.Present:=present,NR.Helper:=helper
    if !RulesExact(signature,NR.Signature) {
        NR.Signature:=signature,NR.Generation++,NR.DisplayRevision++,NR.Cache:=[],NR.Queue:=[],NR.Dirty:=true
        RulesAbandon()
    }
}
RulesDisplay(raw) {
    global NR
    if (!IsObject(NR) || !NR.Present)
        return raw
    for i,item in NR.Cache
        if RulesExact(item.Raw,raw)
            return item.Display
    if (NR.Cache.Length>=128)
        return raw
    item:={Raw:raw,Display:raw,Complete:false,Generation:NR.Generation},NR.Cache.Push(item)
    if (NR.Helper="")
        RulesComplete(item,raw,"companion_missing")
    else
        NR.Queue.Push(item)
    return raw
}
RulesComplete(item,display,code:="") {
    global NR
    if (item.Generation!=NR.Generation)
        return
    item.Display:=display,item.Complete:=true,item.Code:=code,NR.DisplayRevision++,NR.Dirty:=true
    if (code!="")
        LogEvent("NameReplacementFallback",0,code)
}
RulesAbandon() {
    global NR
    if (IsObject(NR) && IsObject(NR.Worker)) {
        NR.Worker.Abandoned:=true
        if (DllCall("WaitForSingleObject","Ptr",NR.Worker.Handle,"UInt",0)=258)
            DllCall("TerminateProcess","Ptr",NR.Worker.Handle,"UInt",125)
    }
}
RulesClean(worker) {
    for _,p in [worker.Input,worker.Output,worker.Status] {
        try FileDelete(p)
    }
    DllCall("CloseHandle","Ptr",worker.Handle)
}
RulesStart(item) {
    global NR
    folder:=NR.Dir "\name-rule-work"
    DirCreate(folder)
    NR.Serial++,stem:=folder "\" DllCall("GetCurrentProcessId") "-" A_TickCount "-" NR.Serial
    input:=stem ".in",output:=stem ".out",status:=stem ".status"
    try {
        RulesWriteWide(input,item.Raw)
        args:=Q(NR.Helper) " --format --rules " Q(NR.Rules) " --input " Q(input) " --output " Q(output) " --status " Q(status)
        handle:=RulesLaunch(NR.Helper,args,true)
        NR.Worker:={Handle:handle,Item:item,Started:Tick(),Input:input,Output:output,Status:status,Abandoned:false}
    } catch {
        for _,p in [input,output,status] {
            try FileDelete(p)
        }
        RulesComplete(item,item.Raw,"worker_start_failed")
    }
}
RulesTick() {
    global NR,G
    if (!IsObject(NR) || G.Closing || NR.Busy)
        return
    NR.Busy:=true
    try {
        if (Tick()>=NR.NextSignature)
            NR.NextSignature:=Tick()+1000,RulesSignature()
        worker:=NR.Worker
        if IsObject(worker) {
            wait:=DllCall("WaitForSingleObject","Ptr",worker.Handle,"UInt",0)
            if (wait=258) {
                if (!worker.Abandoned && Tick()-worker.Started>=1500) {
                    RulesComplete(worker.Item,worker.Item.Raw,"worker_timeout")
                    RulesAbandon()
                }
            } else {
                if !worker.Abandoned {
                    display:=worker.Item.Raw,failure:="worker_io",exitCode:=3
                    DllCall("GetExitCodeProcess","Ptr",worker.Handle,"UIntP",&exitCode)
                    try {
                        result:=RulesReadWide(worker.Output),tag:=Trim(RulesReadStatus(worker.Status))
                        if (exitCode=0 && tag="ok" && Trim(result)!="" && NRLower(Trim(result))!="chatgpt" && !RegExMatch(result,"[\x00-\x1F\x7F-\x9F]"))
                            display:=result,failure:=""
                        else if (exitCode=2 && SubStr(tag,1,9)="fallback:" && RulesExact(result,worker.Item.Raw))
                            failure:=SubStr(tag,10)
                    }
                    RulesComplete(worker.Item,display,failure)
                }
                RulesClean(worker),NR.Worker:=0
            }
        }
        while (!IsObject(NR.Worker) && NR.Queue.Length) {
            item:=NR.Queue.RemoveAt(1)
            if (item.Generation=NR.Generation)
                RulesStart(item)
        }
        if NR.Dirty
            NR.Dirty:=false,RulesRefreshOwned()
        if (Tick()>=NR.NextSources)
            NR.NextSources:=Tick()+1000,RulesSnapshot()
    } catch {
        LogEvent("NameReplacementFallback",0,"adapter_failure")
    } finally {
        NR.Busy:=false
    }
}
RulesRefreshOwned() {
    global G
    if G.ReadOnly
        return
    for _,state in G.States {
        if (!state.Owned || !NRStateHas(state,"VerifiedTitle") || !Same(state.Id))
            continue
        current:=Caption(NRHwnd(state.Id))
        if !RulesExact(current,state.Last)
            continue
        raw:=state.VerifiedTitle
        if (Trim(raw)="" || NRLower(Trim(raw))="chatgpt")
            continue
        wanted:=RulesDisplay(raw) " — ChatGPT"
        if (!RulesExact(wanted,current) && RulesExact(Caption(NRHwnd(state.Id)),current) && WriteCaption(state.Id,wanted))
            state.Last:=wanted ; Never change Original or VerifiedTitle.
    }
}
RulesSnapshot() {
    global NR,G
    rows:=[],signature:=""
    for key,state in G.States {
        if NRStateHas(state,"VerifiedTitle") {
            raw:=state.VerifiedTitle
            signature.=key ":" StrLen(raw) ":" raw "`n"
            rows.Push(raw)
        }
    }
    if RulesExact(signature,NR.SourceSignature)
        return
    try {
        RulesWriteSources(NR.Sources,rows)
        NR.SourceSignature:=signature
    } catch {
        LogEvent("NameReplacementFallback",0,"source_snapshot_failed")
    }
}
RulesEditor() {
    global NR
    if !IsObject(NR)
        return
    helper:=RulesLocate()
    if (helper="") {
        MsgBox("ChatGPT-TitleSync.Rules.exe is required for Name replacement.","ChatGPT-TitleSync - Name replacement",16)
        return
    }
    help:=A_ScriptDir "\docs\name-replacement.html"
    if !FileExist(help)
        help:=A_ScriptDir "\..\..\docs\name-replacement.html"
    help:=RulesFullPath(help)
    args:=Q(helper) " --edit --rules " Q(NR.Rules) " --sources " Q(NR.Sources) " --help " Q(help)
    try {
        h:=RulesLaunch(helper,args,false)
        DllCall("CloseHandle","Ptr",h)
    } catch {
        MsgBox("Could not start the Unicode name-replacement editor.","ChatGPT-TitleSync - Name replacement",16)
    }
}
RulesClose() {
    global NR
    if !IsObject(NR)
        return
    RulesAbandon()
    if IsObject(NR.Worker) {
        if (DllCall("WaitForSingleObject","Ptr",NR.Worker.Handle,"UInt",0)=0)
            RulesClean(NR.Worker)
        else
            DllCall("CloseHandle","Ptr",NR.Worker.Handle)
        NR.Worker:=0
    }
}
NRStateHas(state,name) {
    return state.HasOwnProp(name)
}
NRHwnd(id) {
    return id["Hwnd"]
}
NRLower(value) {
    return StrLower(value)
}
RulesFullPath(path) {
    buf:=Buffer(65536,0)
    DllCall("GetFullPathNameW","WStr",path,"UInt",32768,"Ptr",buf,"Ptr",0)
    return StrGet(buf,"UTF-16")
}
RulesLaunch(helper,args,hidden) {
    siSize:=A_PtrSize=8?104:68,piSize:=A_PtrSize=8?24:16
    si:=Buffer(siSize,0),pi:=Buffer(piSize,0),NumPut("UInt",siSize,si,0)
    command:=Buffer((StrLen(args)+1)*2,0),StrPut(args,command,"UTF-16")
    flags:=hidden?0x08000000:0
    if !DllCall("CreateProcessW","WStr",helper,"Ptr",command,"Ptr",0,"Ptr",0,"Int",0,"UInt",flags,"Ptr",0,"Ptr",0,"Ptr",si,"Ptr",pi)
        throw Error("RulesWorkerCreateFailed")
    handle:=NumGet(pi,0,"Ptr"),thread:=NumGet(pi,A_PtrSize,"Ptr")
    DllCall("CloseHandle","Ptr",thread)
    return handle
}
RulesWriteWide(path,value) {
    file:=FileOpen(path,"w","CP0")
    if !IsObject(file)
        throw Error("RulesInputOpenFailed")
    units:=StrLen(value),data:=Buffer((units+1)*2,0),StrPut(value,data,"UTF-16")
    wrote:=file.RawWrite(data,units*2),file.Close()
    if (wrote!=units*2)
        throw Error("RulesInputWriteFailed")
}
RulesReadWide(path) {
    file:=FileOpen(path,"r","CP0")
    if !IsObject(file)
        throw Error("RulesOutputOpenFailed")
    bytes:=file.Length,file.Seek(0)
    if (bytes>1024 || Mod(bytes,2)) {
        file.Close()
        throw Error("RulesOutputLengthInvalid")
    }
    data:=Buffer(bytes+2,0),read:=file.RawRead(data,bytes),file.Close()
    value:=StrGet(data,bytes//2,"UTF-16")
    if (read!=bytes || StrLen(value)*2!=bytes)
        throw Error("RulesOutputEncodingInvalid")
    return value
}
RulesReadStatus(path) {
    f:=FileOpen(path,"r","UTF-8")
    if !IsObject(f)
        throw Error("RulesStatusOpenFailed")
    if (f.Length>256) {
        f.Close()
        throw Error("RulesStatusOversized")
    }
    result:=f.Read(),f.Close()
    if RegExMatch(result,"[^\x20-\x7E\r\n]")
        throw Error("RulesStatusNonAscii")
    return result
}
RulesHashFile(path) {
    f:=FileOpen(path,"r","CP0")
    if !IsObject(f)
        return "unreadable"
    bytes:=f.Length,f.Seek(0)
    if (bytes>131072) {
        f.Close()
        return "oversized:" bytes
    }
    data:=Buffer(bytes+1,0),read:=f.RawRead(data,bytes),f.Close()
    if (read!=bytes)
        return "unreadable"
    provider:=hash:=0
    if !DllCall("advapi32\CryptAcquireContextW","PtrP",&provider,"Ptr",0,"Ptr",0,"UInt",24,"UInt",0xF0000000)
        return "hash_unavailable"
    try {
        if !DllCall("advapi32\CryptCreateHash","Ptr",provider,"UInt",0x800c,"Ptr",0,"UInt",0,"PtrP",&hash)
            return "hash_unavailable"
        if !DllCall("advapi32\CryptHashData","Ptr",hash,"Ptr",data,"UInt",bytes,"UInt",0)
            return "hash_unavailable"
        digest:=Buffer(32,0),length:=32
        if !DllCall("advapi32\CryptGetHashParam","Ptr",hash,"UInt",2,"Ptr",digest,"UIntP",&length,"UInt",0)
            return "hash_unavailable"
        text:=""
        Loop 32
            text.=Format("{:02x}",NumGet(digest,A_Index-1,"UChar"))
        return text
    } finally {
        if hash
            DllCall("advapi32\CryptDestroyHash","Ptr",hash)
        DllCall("advapi32\CryptReleaseContext","Ptr",provider,"UInt",0)
    }
}
RulesWriteSources(path,rows) {
    packet:=Buffer(131074,0),NumPut("UInt",0x31535443,packet,0),offset:=8,count:=0
    for _,raw in rows {
        units:=StrLen(raw)
        if (count>=128 || units>512 || offset+4+units*2>131072)
            break
        NumPut("UInt",units,packet,offset),offset+=4
        StrPut(raw,packet.Ptr+offset,units+1,"UTF-16"),offset+=units*2,count++
    }
    NumPut("UInt",count,packet,4)
    SplitPath(path,, &directory)
    DirCreate(directory)
    temporary:=path "." DllCall("GetCurrentProcessId") ".tmp"
    f:=FileOpen(temporary,"w","CP0")
    if !IsObject(f)
        throw Error("RulesSnapshotOpenFailed")
    wrote:=f.RawWrite(packet,offset),f.Close()
    if (wrote!=offset)
        throw Error("RulesSnapshotWriteFailed")
    if !DllCall("MoveFileExW","WStr",temporary,"WStr",path,"UInt",9) {
        try FileDelete(temporary)
        throw Error("RulesSnapshotReplaceFailed")
    }
}
