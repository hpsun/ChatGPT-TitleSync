#import "RulesClient.h"
#import <signal.h>

NSString *CTSRulesDefaultPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/ChatGPT-TitleSync/title-rules.json"];
}
static NSString *FindPackaged(NSString *monitor, NSArray<NSString *> *relative, BOOL executable) {
    NSString *base=[monitor.stringByStandardizingPath.stringByResolvingSymlinksInPath stringByDeletingLastPathComponent];
    for(NSString *part in relative) {
        NSString *path=[[base stringByAppendingPathComponent:part] stringByStandardizingPath];
        BOOL exists=executable?[NSFileManager.defaultManager isExecutableFileAtPath:path]:[NSFileManager.defaultManager fileExistsAtPath:path];
        if(exists)return path;
    }
    return [[base stringByAppendingPathComponent:relative.firstObject] stringByStandardizingPath];
}
NSString *CTSRulesCompanionPath(NSString *monitor) {
    return FindPackaged(monitor,@[@"chatgpt-titlesync-rules",@"../shared/macos/chatgpt-titlesync-rules",@"../../shared/macos/chatgpt-titlesync-rules"],YES);
}
NSString *CTSRulesHelpPath(NSString *monitor) {
    return FindPackaged(monitor,@[@"docs/name-replacement.html",@"../docs/name-replacement.html",@"../../docs/name-replacement.html"],NO);
}
static BOOL RulesOutputValid(NSString *text) {
    return text && text.length<=512 && [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length &&
        [text rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location==NSNotFound &&
        [text caseInsensitiveCompare:@"ChatGPT"]!=NSOrderedSame;
}
static void AppendU32(NSMutableData *data,uint32_t value) {uint32_t little=CFSwapInt32HostToLittle(value);[data appendBytes:&little length:4];}
@interface CTSRulesClient () {
    NSLock *_lock;
    NSString *_executable,*_rulesPath,*_stateDirectory;
    NSData *_signature,*_sourceBytes;
    NSString *_helperSignature;
    NSTimeInterval _nextPollUptime;
    NSMutableDictionary<NSString *,NSString *> *_display;
    NSMutableSet<NSString *> *_pending;
    NSMutableDictionary<NSString *,NSTask *> *_children;
    BOOL _initialized,_hasRules,_closed;
    uint64_t _displayRevision,_rulesGeneration;
}
@property(nonatomic, readwrite, copy) NSString *sourcePath;
@end
@implementation CTSRulesClient
- (instancetype)initWithExecutablePath:(NSString *)executable rulesPath:(NSString *)rules stateDirectory:(NSString *)state {
    if((self=[super init])) {
        _executable=executable.copy;_rulesPath=rules.copy;_stateDirectory=state.copy;
        _sourcePath=[state stringByAppendingPathComponent:@"title-rule-sources.bin"];
        _lock=[NSLock new];_display=[NSMutableDictionary dictionary];_pending=[NSMutableSet set];_children=[NSMutableDictionary dictionary];
    }
    return self;
}
- (uint64_t)displayRevision {[_lock lock];uint64_t value=_displayRevision;[_lock unlock];return value;}
- (void)poll {
    // A monitor can resolve many windows per heartbeat. Read the independent
    // rule/helper signatures once per low-cost heartbeat, not once per window.
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    [_lock lock];
    if(_closed||(_initialized&&now<_nextPollUptime)){[_lock unlock];return;}
    _nextPollUptime=now+0.9;[_lock unlock];
    NSDictionary *helper=[NSFileManager.defaultManager attributesOfItemAtPath:_executable error:nil];
    NSTimeInterval helperModified=[helper[NSFileModificationDate] timeIntervalSince1970];
    NSString *helperStamp=[NSString stringWithFormat:@"%d|%@|%@|%.9f|%@|%@",[NSFileManager.defaultManager isExecutableFileAtPath:_executable],helper[NSFileType],helper[NSFileSize],helperModified,helper[NSFileSystemFileNumber],helper[NSFilePosixPermissions]];
    // Bound reads before allocation. An unreadable/malformed existing file is
    // sent to the validator and produces a raw-name fallback, never old rules.
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:_rulesPath error:nil];
    NSData *data=nil;
    if(attributes) {
        if([attributes[NSFileSize] unsignedLongLongValue]<=131072) {
            NSFileHandle *reader=[NSFileHandle fileHandleForReadingAtPath:_rulesPath];
            @try {data=[reader readDataOfLength:131073];if(data.length>131072)data=nil;}
            @catch(NSException *error) {data=nil;}
            @finally {[reader closeFile];}
        }
        if(!data)data=[@"invalid-rules-file" dataUsingEncoding:NSUTF8StringEncoding];
    }
    [_lock lock];
    if(_closed||(_initialized&&((_signature==data)||[_signature isEqualToData:data])&&[_helperSignature isEqualToString:helperStamp])){[_lock unlock];return;}
    // Restoring a missing/repaired packaged helper must invalidate a cached raw
    // fallback even when the user has not changed the rule file or source name.
    _initialized=YES;_signature=data.copy;_helperSignature=helperStamp.copy;_rulesGeneration++;_displayRevision++;[_display removeAllObjects];
    _hasRules=data!=nil;
    if(data) {
        id object=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if([object isKindOfClass:NSDictionary.class]&&[object[@"schema_version"] isKindOfClass:NSNumber.class]&&[object[@"schema_version"] integerValue]==1&&
           [object[@"enabled"] isKindOfClass:NSNumber.class]&&[object[@"rules"] isKindOfClass:NSArray.class]) {
            if(![object[@"enabled"] boolValue]||[object[@"rules"] count]==0)_hasRules=NO;
        }
    }
    [_lock unlock];
}
- (nullable NSString *)resolve:(NSString *)raw {
    [self poll];
    [_lock lock];
    if(_closed||!_hasRules){[_lock unlock];return raw;}
    NSString *saved=_display[raw];if(saved){[_lock unlock];return saved;}
    uint64_t generation=_rulesGeneration;
    NSString *token=[NSString stringWithFormat:@"%llu:%@",(unsigned long long)generation,raw];
    if([_pending containsObject:token]||_pending.count>=2){[_lock unlock];return nil;}
    [_pending addObject:token];NSData *rules=_signature.copy;[_lock unlock];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        @autoreleasepool {
            NSString *result=[self format:raw rules:rules token:token generation:generation];
            [self->_lock lock];[self->_pending removeObject:token];[self->_children removeObjectForKey:token];
            if(!self->_closed&&self->_rulesGeneration==generation) {
                // A result is keyed by its exact raw input and rule generation;
                // it cannot overwrite a later conversation or edited rule set.
                if(self->_display.count>=256)[self->_display removeAllObjects];
                self->_display[raw]=result?:raw;self->_displayRevision++;
            }
            [self->_lock unlock];
        }
    });
    return nil;
}
- (NSString *)format:(NSString *)raw rules:(NSData *)rules token:(NSString *)token generation:(uint64_t)generation {
    NSString *directory=[_stateDirectory stringByAppendingPathComponent:[@".rules-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSFileManager *manager=NSFileManager.defaultManager;NSError *error=nil;
    NSString *result=raw,*reason=@"worker_io";
    NSTask *task=[NSTask new];BOOL timedOut=NO;
    @try {
        if(![manager isExecutableFileAtPath:_executable]){reason=@"helper_missing";return raw;}
        if(![manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error])return raw;
        NSString *input=[directory stringByAppendingPathComponent:@"input.utf16"],*output=[directory stringByAppendingPathComponent:@"output.utf16"];
        NSString *snapshot=[directory stringByAppendingPathComponent:@"rules.json"],*status=[directory stringByAppendingPathComponent:@"status.txt"];
        NSData *bytes=[raw dataUsingEncoding:NSUTF16LittleEndianStringEncoding allowLossyConversion:NO];
        if(!bytes||![bytes writeToFile:input options:NSDataWritingAtomic error:&error]||![rules writeToFile:snapshot options:NSDataWritingAtomic error:&error])return raw;
        task.executableURL=[NSURL fileURLWithPath:_executable];task.arguments=@[@"--format",@"--rules",snapshot,@"--input",input,@"--output",output,@"--status",status];
        task.standardOutput=NSFileHandle.fileHandleWithNullDevice;task.standardError=NSFileHandle.fileHandleWithNullDevice;
        [_lock lock];
        if(_closed||_rulesGeneration!=generation){[_lock unlock];reason=@"stale";return raw;}
        _children[token]=task;
        BOOL launched=[task launchAndReturnError:&error];[_lock unlock];
        if(!launched){reason=@"worker_start";return raw;}
        NSTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+1.5;
        while(task.running&&NSProcessInfo.processInfo.systemUptime<deadline) {
            [_lock lock];BOOL cancelled=_closed||_rulesGeneration!=generation;[_lock unlock];
            if(cancelled){reason=@"stale";break;}
            [NSThread sleepForTimeInterval:0.005];
        }
        if(task.running) {
            timedOut=YES;[task terminate];
            NSTimeInterval grace=NSProcessInfo.processInfo.systemUptime+0.05;
            while(task.running&&NSProcessInfo.processInfo.systemUptime<grace)[NSThread sleepForTimeInterval:0.002];
            // This PID belongs only to the exact NSTask launched above. Never
            // signal the monitor, a source reader, ChatGPT, or another app.
            if(task.running)kill(task.processIdentifier,SIGKILL);
            reason=[reason isEqualToString:@"stale"]?reason:@"timeout";return raw;
        }
        if(task.terminationStatus!=0&&task.terminationStatus!=2){reason=@"worker_exit";return raw;}
        NSDictionary *outInfo=[manager attributesOfItemAtPath:output error:nil],*statusInfo=[manager attributesOfItemAtPath:status error:nil];
        if(!outInfo||[outInfo[NSFileSize] unsignedLongLongValue]>4096||!statusInfo||[statusInfo[NSFileSize] unsignedLongLongValue]>256)return raw;
        NSData *outData=[NSData dataWithContentsOfFile:output];
        NSString *text=[[NSString alloc] initWithData:outData encoding:NSUTF16LittleEndianStringEncoding];
        NSString *state=[NSString stringWithContentsOfFile:status encoding:NSASCIIStringEncoding error:nil];
        state=[state stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(task.terminationStatus==0&&[state isEqualToString:@"ok"]&&RulesOutputValid(text)){result=text;reason=nil;}
        else if(task.terminationStatus==2&&[state hasPrefix:@"fallback:"]&&[text isEqualToString:raw])reason=@"invalid_or_timeout";
        else reason=@"worker_protocol";
    } @catch(NSException *exception) {reason=@"worker_exception";}
    @finally {
        // No wait on an unbounded match: format workers are independently
        // killable. A leftover output is never read after the deadline.
        if(task.running&&!timedOut)[task terminate];
        [manager removeItemAtPath:directory error:nil];
        if(reason&&![reason isEqualToString:@"stale"])fprintf(stderr,"name_replacement_fallback:%s\n",reason.UTF8String);
    }
    return result;
}
- (void)publishSources:(NSArray<NSString *> *)rawNames {
    NSMutableData *packet=[NSMutableData dataWithBytes:"CTS1" length:4];
    NSMutableOrderedSet<NSString *> *names=[NSMutableOrderedSet orderedSet];
    for(NSString *name in rawNames)if(name.length&&name.length<=512&&names.count<128)[names addObject:name];
    AppendU32(packet,(uint32_t)names.count);
    for(NSString *name in names){NSData *bytes=[name dataUsingEncoding:NSUTF16LittleEndianStringEncoding allowLossyConversion:NO];if(!bytes)return;AppendU32(packet,(uint32_t)name.length);[packet appendData:bytes];}
    if(packet.length>131072)return;
    [_lock lock];BOOL changed=!_closed&&![_sourceBytes isEqualToData:packet];[_lock unlock];if(!changed)return;
    NSError *error=nil;
    if(![NSFileManager.defaultManager createDirectoryAtPath:_stateDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]||![packet writeToFile:self.sourcePath options:NSDataWritingAtomic error:&error])return;
    [_lock lock];if(!_closed)_sourceBytes=packet.copy;[_lock unlock];
}
- (BOOL)openEditorWithHelpPath:(NSString *)help error:(NSError **)error {
    if(![NSFileManager.defaultManager isExecutableFileAtPath:_executable]) {
        if(error)*error=[NSError errorWithDomain:@"TitleSyncRules" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Name replacement companion is missing. Build/package the companion first."}];return NO;
    }
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:_executable];
    task.arguments=@[@"--edit",@"--rules",_rulesPath,@"--sources",self.sourcePath,@"--help",help];
    return [task launchAndReturnError:error];
}
- (void)dispose {
    [_lock lock];_closed=YES;NSArray<NSTask *> *children=_children.allValues.copy;[_lock unlock];
    for(NSTask *task in children)if(task.running)[task terminate];
}
@end

NSString *CTSRulesOpenEditor(CTSRulesClient *client,NSString *help) {
    NSError *error=nil;
    return [client openEditorWithHelpPath:help error:&error]?nil:(error.localizedDescription?:@"The name replacement editor could not be opened.");
}
