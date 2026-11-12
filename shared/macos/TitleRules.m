// Shared macOS Unicode rule companion. Formatting never initializes AppKit UI.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

static const NSUInteger MaxBytes=131072, MaxUnits=512, MaxRules=32;
static NSString *Local(NSString *en,NSString *zh){return [[[NSLocale preferredLanguages] firstObject] hasPrefix:@"zh"]?zh:en;}
static BOOL Absolute(NSString *s){return s.length&&s.isAbsolutePath;}
static BOOL BoolValue(id x){return x&&CFGetTypeID((__bridge CFTypeRef)x)==CFBooleanGetTypeID();}
static BOOL ValidName(NSString *s){
    if(!s||s.length>MaxUnits||![[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length])return NO;
    if([[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] caseInsensitiveCompare:@"ChatGPT"]==NSOrderedSame)return NO;
    for(NSUInteger i=0;i<s.length;i++){
        unichar c=[s characterAtIndex:i];if(c<32||(c>=127&&c<=159))return NO;
        if(c>=0xD800&&c<=0xDBFF){if(i+1>=s.length)return NO;unichar low=[s characterAtIndex:i+1];if(low<0xDC00||low>0xDFFF)return NO;i++;}
        else if(c>=0xDC00&&c<=0xDFFF)return NO;
    }
    return YES;
}
static NSString *Decode(NSData *data,BOOL optionalBOM){
    if(!data)return nil;
    if(data.length%2)return nil;
    if(optionalBOM&&data.length>=2){const unsigned char *p=data.bytes;if(p[0]==255&&p[1]==254)data=[data subdataWithRange:NSMakeRange(2,data.length-2)];}
    return [[NSString alloc]initWithData:data encoding:NSUTF16LittleEndianStringEncoding];
}
static NSData *Packet(NSString *s){return [s dataUsingEncoding:NSUTF16LittleEndianStringEncoding allowLossyConversion:NO];}
static NSData *ReadBounded(NSString *path,NSUInteger limit,NSError **error){
    NSFileHandle *f=[NSFileHandle fileHandleForReadingAtPath:path];
    if(!f){if(error)*error=[NSError errorWithDomain:@"TitleRules" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Cannot open file"}];return nil;}
    NSData *d=nil;
    @try {d=[f readDataOfLength:limit+1];[f closeFile];}
    @catch(NSException *exception){
        @try {[f closeFile];} @catch(NSException *ignored){(void)ignored;}
        if(error)*error=[NSError errorWithDomain:@"TitleRules" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Cannot read file"}];
        (void)exception;return nil;
    }
    if(d.length>limit){if(error)*error=[NSError errorWithDomain:@"TitleRules" code:4 userInfo:@{NSLocalizedDescriptionKey:@"File limit exceeded"}];return nil;}return d;
}
static BOOL Template(NSString *s,NSUInteger groups,NSArray **tokens,NSString **error){
    NSMutableArray *out=[NSMutableArray array];NSMutableString *literal=[NSMutableString string];
    for(NSUInteger i=0;i<s.length;){
        unichar c=[s characterAtIndex:i++];if(c!='$'){[literal appendFormat:@"%C",c];continue;}
        if(i>=s.length){if(error)*error=@"InvalidReplacement";return NO;}
        unichar next=[s characterAtIndex:i];
        if(next=='$'){[literal appendString:@"$"];i++;continue;}
        if(literal.length){[out addObject:[literal copy]];[literal setString:@""];}
        BOOL braces=next=='{';if(braces)i++;NSUInteger start=i;
        while(i<s.length&&[s characterAtIndex:i]>='0'&&[s characterAtIndex:i]<='9')i++;
        NSUInteger count=i-start;if(count<1||count>2||(braces&&(i>=s.length||[s characterAtIndex:i]!='}'))){if(error)*error=@"InvalidReplacement";return NO;}
        NSUInteger number=[[s substringWithRange:NSMakeRange(start,count)] integerValue];
        if(braces)i++;if(number>groups){if(error)*error=@"InvalidGroupReference";return NO;}[out addObject:@(number)];
    }
    if(literal.length)[out addObject:[literal copy]];if(tokens)*tokens=out;return YES;
}
static NSDictionary *DefaultRules(void){return @{@"schema_version":@1,@"enabled":@YES,@"revision":@"",@"rules":@[]};}
static NSArray *Compile(NSDictionary *config,NSString **failure){
    if(![config isKindOfClass:NSDictionary.class]||![config[@"schema_version"] isKindOfClass:NSNumber.class]||
       BoolValue(config[@"schema_version"])||[config[@"schema_version"] doubleValue]!=1.0||![config[@"enabled"] isKindOfClass:NSNumber.class]||!BoolValue(config[@"enabled"])||
       ![config[@"revision"] isKindOfClass:NSString.class]||![config[@"rules"] isKindOfClass:NSArray.class]||[config[@"rules"] count]>MaxRules){if(failure)*failure=@"InvalidConfiguration";return nil;}
    NSMutableArray *compiled=[NSMutableArray array];
    for(id raw in config[@"rules"]){
        if(![raw isKindOfClass:NSDictionary.class]||!BoolValue(raw[@"enabled"])||![raw[@"mode"] isKindOfClass:NSString.class]||
           ![raw[@"pattern"] isKindOfClass:NSString.class]||![raw[@"replacement"] isKindOfClass:NSString.class]||
           [raw[@"pattern"] length]>MaxUnits||[raw[@"replacement"] length]>MaxUnits||
           (![[raw objectForKey:@"mode"] isEqual:@"literal"]&&![[raw objectForKey:@"mode"] isEqual:@"regex"])){if(failure)*failure=@"InvalidRule";return nil;}
        if(![raw[@"enabled"] boolValue])continue;
        if(![raw[@"pattern"] length]){if(failure)*failure=@"EmptyPattern";return nil;}
        NSMutableDictionary *r=[raw mutableCopy];
        if([r[@"mode"] isEqual:@"regex"]){
            NSError *error=nil;NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:r[@"pattern"] options:0 error:&error];
            if(!regex){if(failure)*failure=@"CompileError";return nil;}
            NSArray *tokens=nil;if(!Template(r[@"replacement"],regex.numberOfCaptureGroups,&tokens,failure))return nil;
            r[@"regex"]=regex;r[@"tokens"]=tokens;
        }
        [compiled addObject:r];
    }
    return compiled;
}
static BOOL Append(NSMutableString *out,NSString *part){if(out.length+part.length>MaxUnits)return NO;[out appendString:part];return YES;}
static NSString *ApplyRule(NSDictionary *rule,NSString *input,NSTimeInterval deadline,NSString **failure){
    NSMutableString *out=[NSMutableString string];NSUInteger cursor=0;
    if([rule[@"mode"] isEqual:@"literal"]){
        NSString *find=rule[@"pattern"],*replacement=rule[@"replacement"];
        while(cursor<=input.length){
            if(NSProcessInfo.processInfo.systemUptime>deadline){if(failure)*failure=@"AggregateTimeout";return nil;}
            NSRange r=[input rangeOfString:find options:NSLiteralSearch range:NSMakeRange(cursor,input.length-cursor)];
            if(r.location==NSNotFound){if(!Append(out,[input substringFromIndex:cursor])){if(failure)*failure=@"InvalidOutput";return nil;}break;}
            if(!Append(out,[input substringWithRange:NSMakeRange(cursor,r.location-cursor)])||!Append(out,replacement)){if(failure)*failure=@"InvalidOutput";return nil;}
            cursor=NSMaxRange(r);
        }
    }else{
        NSRegularExpression *re=rule[@"regex"];NSArray *matches=[re matchesInString:input options:0 range:NSMakeRange(0,input.length)];
        for(NSTextCheckingResult *m in matches){
            if(NSProcessInfo.processInfo.systemUptime>deadline){if(failure)*failure=@"AggregateTimeout";return nil;}
            if(!Append(out,[input substringWithRange:NSMakeRange(cursor,m.range.location-cursor)])){if(failure)*failure=@"InvalidOutput";return nil;}
            for(id token in rule[@"tokens"]){
                NSString *value=token;
                if([token isKindOfClass:NSNumber.class]){NSRange r=[m rangeAtIndex:[token unsignedIntegerValue]];value=r.location==NSNotFound?@"":[input substringWithRange:r];}
                if(!Append(out,value)){if(failure)*failure=@"InvalidOutput";return nil;}
            }
            cursor=NSMaxRange(m.range);
        }
        if(!Append(out,[input substringFromIndex:cursor])){if(failure)*failure=@"InvalidOutput";return nil;}
    }
    return out;
}
static NSString *Format(NSDictionary *config,NSString *raw,NSString **failure){
    NSTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+0.5;
    NSString *error=nil;NSArray *rules=Compile(config,&error);if(!rules){if(failure)*failure=error;return raw;}
    if(!ValidName(raw)){if(failure)*failure=@"InvalidRaw";return raw;}
    if(![config[@"enabled"] boolValue])return raw;
    if(NSProcessInfo.processInfo.systemUptime>deadline){if(failure)*failure=@"AggregateTimeout";return raw;}
    NSString *value=raw;
    for(NSDictionary *r in rules){
        value=ApplyRule(r,value,deadline,&error);
        if(!value||!ValidName(value)){if(failure)*failure=error?:@"InvalidOutput";return raw;}
    }
    return value;
}
static NSDictionary *Load(NSString *path,NSData **bytes,NSString **failure){
    NSError *attributeError=nil;NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:&attributeError];
    if(!attributes){
        if([attributeError.domain isEqual:NSCocoaErrorDomain]&&(attributeError.code==NSFileNoSuchFileError||attributeError.code==NSFileReadNoSuchFileError)){if(bytes)*bytes=nil;return DefaultRules();}
        if([attributeError.domain isEqual:NSPOSIXErrorDomain]&&attributeError.code==ENOENT){if(bytes)*bytes=nil;return DefaultRules();}
        if(failure)*failure=@"RulesReadFailed";return nil;
    }
    NSError *error=nil;NSData *data=ReadBounded(path,MaxBytes,&error);if(bytes)*bytes=data;
    if(!data){if(failure)*failure=([error.domain isEqual:@"TitleRules"]&&error.code==4)?@"RulesTooLarge":@"RulesReadFailed";return nil;}
    id result=[NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if(![result isKindOfClass:NSDictionary.class]){if(failure)*failure=@"ParseError";return nil;}return result;
}
static BOOL AtomicData(NSData *data,NSString *path,NSError **error){
    NSString *temp=[path.stringByDeletingLastPathComponent stringByAppendingPathComponent:[@".rules-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    int fd=open(temp.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL,0600);if(fd<0)return NO;
    const unsigned char *p=data.bytes;NSUInteger left=data.length;BOOL ok=YES;
    while(left){ssize_t n=write(fd,p,left);if(n<=0){ok=NO;break;}left-=(NSUInteger)n;p+=n;}
    if(ok&&fsync(fd)!=0)ok=NO;if(close(fd)!=0)ok=NO;
    if(ok&&rename(temp.fileSystemRepresentation,path.fileSystemRepresentation)!=0)ok=NO;
    if(!ok){unlink(temp.fileSystemRepresentation);if(error)*error=[NSError errorWithDomain:@"TitleRules" code:5 userInfo:@{NSLocalizedDescriptionKey:@"Atomic save failed"}];}
    return ok;
}
static int FormatCLI(NSDictionary *args){
    NSString *rules=args[@"--rules"],*input=args[@"--input"],*output=args[@"--output"],*status=args[@"--status"];
    if(!Absolute(rules)||!Absolute(input)||!Absolute(output)||!Absolute(status))return 3;
    NSSet *paths=[NSSet setWithArray:@[rules.stringByStandardizingPath,input.stringByStandardizingPath,output.stringByStandardizingPath,status.stringByStandardizingPath]];
    if(paths.count!=4)return 3;
    NSError *io=nil;NSData *rawData=ReadBounded(input,MaxUnits*2+2,&io);if(!rawData)return 3;
    const unsigned char *p=rawData.bytes;if(rawData.length>=2&&p[0]==255&&p[1]==254)rawData=[rawData subdataWithRange:NSMakeRange(2,rawData.length-2)];
    NSString *raw=Decode(rawData,NO),*failure=nil;NSDictionary *config=Load(rules,NULL,&failure);NSString *value=raw;
    if(!raw)failure=@"InvalidUtf16";else if(config)value=Format(config,raw,&failure);
    NSData *result=failure?rawData:Packet(value);if(!result)return 3;
    if(![result writeToFile:output options:0 error:&io])return 3;
    NSString *code=failure?[@"fallback:" stringByAppendingString:failure]:@"ok";
    if(![[code dataUsingEncoding:NSASCIIStringEncoding] writeToFile:status options:0 error:&io])return 3;
    return [failure isEqual:@"RulesReadFailed"]?3:(failure?2:0);
}
static NSArray *Sources(NSString *path,NSDate **modified){
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];if(modified)*modified=attrs[NSFileModificationDate];
    NSData *d=ReadBounded(path,MaxBytes,NULL);if(d.length<8)return @[];const unsigned char *p=d.bytes;
    if(memcmp(p,"CTS1",4))return @[];uint32_t count=(uint32_t)p[4]|((uint32_t)p[5]<<8)|((uint32_t)p[6]<<16)|((uint32_t)p[7]<<24);if(count>128)return @[];
    NSUInteger offset=8;NSMutableArray *out=[NSMutableArray array];
    for(uint32_t i=0;i<count;i++){
        if(offset+4>d.length)return @[];uint32_t n=(uint32_t)p[offset]|((uint32_t)p[offset+1]<<8)|((uint32_t)p[offset+2]<<16)|((uint32_t)p[offset+3]<<24);offset+=4;
        if(n>MaxUnits||offset+(NSUInteger)n*2>d.length)return @[];
        NSString *s=Decode([d subdataWithRange:NSMakeRange(offset,(NSUInteger)n*2)],NO);offset+=(NSUInteger)n*2;
        if(!s)return @[];if(![out containsObject:s])[out addObject:s];
    }
    return offset==d.length?out:@[];
}
static NSMutableSet<NSTask*> *OwnedWorkers;
static BOOL EditorClosing=NO;
static void StopOwnedWorkers(void){
    @synchronized(OwnedWorkers){EditorClosing=YES;for(NSTask *task in OwnedWorkers)if(task.running)kill(task.processIdentifier,SIGKILL);}
}
static NSDictionary *RunChild(NSString *exe,NSData *rules,NSString *sample){
    static dispatch_once_t once;dispatch_once(&once,^{OwnedWorkers=[NSMutableSet set];});
    NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"ChatGPT-TitleSync-rules-preview-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSError *error=nil;if(![NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error])return @{@"status":@"fallback:PreviewIO",@"value":sample};
    NSString *rp=[dir stringByAppendingPathComponent:@"rules.json"],*ip=[dir stringByAppendingPathComponent:@"input.bin"],*op=[dir stringByAppendingPathComponent:@"output.bin"],*sp=[dir stringByAppendingPathComponent:@"status.txt"];
    if(rules)[rules writeToFile:rp atomically:NO];[Packet(sample) writeToFile:ip atomically:NO];
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:exe];task.arguments=@[@"--format",@"--rules",rp,@"--input",ip,@"--output",op,@"--status",sp];
    task.standardOutput=NSFileHandle.fileHandleWithNullDevice;task.standardError=NSFileHandle.fileHandleWithNullDevice;
    BOOL launched=NO,timeout=NO;
    @synchronized(OwnedWorkers){if(!EditorClosing){[OwnedWorkers addObject:task];launched=[task launchAndReturnError:&error];}}
    if(launched){NSTimeInterval until=NSProcessInfo.processInfo.systemUptime+1.5;while(task.running&&NSProcessInfo.processInfo.systemUptime<until)[NSThread sleepForTimeInterval:0.01];if(task.running){timeout=YES;kill(task.processIdentifier,SIGKILL);}[task waitUntilExit];}
    NSString *status=timeout?@"fallback:WorkerTimeout":[NSString stringWithContentsOfFile:sp encoding:NSASCIIStringEncoding error:nil];
    NSString *value=Decode(ReadBounded(op,MaxUnits*2,NULL),NO);
    if(timeout){status=@"fallback:WorkerTimeout";value=sample;}
    else if(!launched||!status||!value){status=@"fallback:PreviewIO";value=sample;}
    @synchronized(OwnedWorkers){[OwnedWorkers removeObject:task];}
    NSDictionary *result=@{@"status":status,@"value":value};
    [NSFileManager.defaultManager removeItemAtPath:dir error:nil];return result;
}

@interface RulesEditor:NSObject<NSApplicationDelegate,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate,NSTextFieldDelegate>
@property NSString *rulesPath,*sourcesPath,*helpPath,*exe;
@property NSData *baseBytes;
@property NSMutableArray<NSMutableDictionary*> *rows;
@property NSWindow *window;
@property NSTableView *table;
@property NSButton *enabled,*save,*useRule,*cancelButton;
@property BOOL saving;
@property NSRange sampleSelection;
@property NSString *selectionSample;
@property NSPopUpButton *current,*candidate;
@property NSTextField *timestamp,*sample,*output,*explanation,*suggestPattern,*suggestReplacement,*suggestResult;
@property NSArray *suggestions;
@property NSUInteger previewGeneration;
@property NSTimer *sourceTimer;
@end
@implementation RulesEditor
- (NSTextField*)field:(NSString*)text frame:(NSRect)frame editable:(BOOL)editable{
    NSTextField *f=[[NSTextField alloc]initWithFrame:frame];f.stringValue=text?:@"";f.editable=editable;f.selectable=YES;f.bezeled=editable;f.drawsBackground=editable;f.font=[NSFont systemFontOfSize:12];
    [self.window.contentView addSubview:f];return f;
}
- (NSButton*)button:(NSString*)title frame:(NSRect)frame action:(SEL)action{
    NSButton *b=[[NSButton alloc]initWithFrame:frame];b.title=title;b.bezelStyle=NSBezelStyleRounded;b.target=self;b.action=action;[self.window.contentView addSubview:b];return b;
}
- (void)applicationDidFinishLaunching:(NSNotification*)note{
    (void)note;NSString *failure=nil;NSData *baseData=nil;NSDictionary *config=Load(self.rulesPath,&baseData,&failure);self.baseBytes=baseData;if(!config)config=DefaultRules();
    if(![config[@"rules"] isKindOfClass:NSArray.class]||[config[@"rules"] count]>MaxRules){failure=@"InvalidConfiguration";config=DefaultRules();}
    self.rows=[NSMutableArray array];for(NSDictionary *r in config[@"rules"]?:@[])if([r isKindOfClass:NSDictionary.class])[self.rows addObject:[r mutableCopy]];
    self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1100,800) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=Local(@"ChatGPT-TitleSync — Name replacement",@"ChatGPT-TitleSync — 名称替换");self.window.releasedWhenClosed=NO;self.window.delegate=self;[self.window center];
    self.enabled=[self button:Local(@"Enable name replacement",@"启用名称替换") frame:NSMakeRect(20,752,220,28) action:@selector(changed:)];
    [self.enabled setButtonType:NSButtonTypeSwitch];self.enabled.state=[config[@"enabled"] boolValue]?NSControlStateValueOn:NSControlStateValueOff;
    self.current=[[NSPopUpButton alloc]initWithFrame:NSMakeRect(260,752,660,28) pullsDown:NO];self.current.target=self;self.current.action=@selector(chooseSource:);[self.window.contentView addSubview:self.current];
    [self button:Local(@"Refresh names",@"刷新名称") frame:NSMakeRect(940,752,135,28) action:@selector(refreshSources:)];
    self.timestamp=[self field:@"" frame:NSMakeRect(260,725,810,22) editable:NO];
    NSScrollView *scroll=[[NSScrollView alloc]initWithFrame:NSMakeRect(20,408,1055,305)];scroll.hasVerticalScroller=YES;scroll.borderType=NSBezelBorder;
    self.table=[[NSTableView alloc]initWithFrame:scroll.bounds];self.table.dataSource=self;self.table.delegate=self;self.table.rowHeight=27;self.table.allowsMultipleSelection=NO;
    NSArray *keys=@[@"enabled",@"mode",@"pattern",@"replacement"],*labels=@[Local(@"Enabled",@"启用"),Local(@"Mode",@"模式"),Local(@"Find / pattern",@"查找／正则"),Local(@"Replacement",@"替换")];
    CGFloat widths[]={75,100,430,430};
    for(NSUInteger i=0;i<keys.count;i++){NSTableColumn *c=[[NSTableColumn alloc]initWithIdentifier:keys[i]];c.title=labels[i];c.width=widths[i];c.minWidth=widths[i];c.editable=YES;c.headerCell.font=[NSFont boldSystemFontOfSize:12];
        if(i==0){NSButtonCell *cell=[NSButtonCell new];[cell setButtonType:NSButtonTypeSwitch];cell.title=@"";c.dataCell=cell;}
        if(i==1){NSPopUpButtonCell *cell=[[NSPopUpButtonCell alloc]initTextCell:@"" pullsDown:NO];[cell addItemsWithTitles:@[@"literal",@"regex"]];c.dataCell=cell;}
        [self.table addTableColumn:c];}
    self.table.headerView.frame=NSMakeRect(0,0,1055,32);scroll.documentView=self.table;[self.window.contentView addSubview:scroll];
    [self button:Local(@"Add",@"新增") frame:NSMakeRect(20,366,100,30) action:@selector(add:)];
    [self button:Local(@"Remove",@"删除") frame:NSMakeRect(130,366,100,30) action:@selector(remove:)];
    [self button:Local(@"Move up",@"上移") frame:NSMakeRect(240,366,110,30) action:@selector(up:)];
    [self button:Local(@"Move down",@"下移") frame:NSMakeRect(360,366,120,30) action:@selector(down:)];
    [self field:Local(@"Manual sample",@"手工示例") frame:NSMakeRect(20,326,130,24) editable:NO];self.sample=[self field:@"" frame:NSMakeRect(155,325,920,26) editable:YES];self.sample.delegate=self;
    [self field:Local(@"Preview",@"预览") frame:NSMakeRect(20,290,130,24) editable:NO];self.output=[self field:@"" frame:NSMakeRect(155,289,920,26) editable:NO];
    [self button:Local(@"Suggest regex",@"建议正则") frame:NSMakeRect(20,249,135,30) action:@selector(suggest:)];
    self.candidate=[[NSPopUpButton alloc]initWithFrame:NSMakeRect(165,249,700,30) pullsDown:NO];self.candidate.target=self;self.candidate.action=@selector(chooseSuggestion:);[self.window.contentView addSubview:self.candidate];
    self.useRule=[self button:Local(@"Use rule",@"使用规则") frame:NSMakeRect(880,249,195,30) action:@selector(useSuggestion:)];self.useRule.enabled=NO;
    self.explanation=[self field:Local(@"Choose a verified current name or type a sample. Suggestions never apply automatically.",@"请选择当前名称或输入示例；建议不会自动应用。") frame:NSMakeRect(20,212,1055,30) editable:NO];
    [self field:Local(@"Pattern",@"正则") frame:NSMakeRect(20,180,130,24) editable:NO];self.suggestPattern=[self field:@"" frame:NSMakeRect(155,179,920,26) editable:NO];
    [self field:Local(@"Replacement",@"替换") frame:NSMakeRect(20,145,130,24) editable:NO];self.suggestReplacement=[self field:@"" frame:NSMakeRect(155,144,920,26) editable:NO];
    [self field:Local(@"Candidate result",@"建议结果") frame:NSMakeRect(20,110,130,24) editable:NO];self.suggestResult=[self field:@"" frame:NSMakeRect(155,109,920,26) editable:NO];
    [self button:Local(@"Help",@"帮助") frame:NSMakeRect(20,25,110,32) action:@selector(help:)];
    self.cancelButton=[self button:Local(@"Cancel",@"取消") frame:NSMakeRect(825,25,115,32) action:@selector(cancel:)];
    self.save=[self button:Local(@"Save",@"保存") frame:NSMakeRect(955,25,120,32) action:@selector(saveRules:)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sampleSelectionChanged:) name:NSTextViewDidChangeSelectionNotification object:nil];
    [self refreshSources:nil];self.sourceTimer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refreshSources:) userInfo:nil repeats:YES];
    [self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    if(failure)[self alert:Local(@"The rules file is invalid. Nothing has been changed; edit and explicitly save to replace it.",@"规则文件无效；尚未改动。请编辑后明确保存。")];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table{(void)table;return self.rows.count;}
- (id)tableView:(NSTableView*)table objectValueForTableColumn:(NSTableColumn*)column row:(NSInteger)row{(void)table;id v=self.rows[row][column.identifier];if([column.identifier isEqual:@"mode"])return @([v isEqual:@"regex"]?1:0);return v?:@"";}
- (void)tableView:(NSTableView*)table setObjectValue:(id)value forTableColumn:(NSTableColumn*)column row:(NSInteger)row{
    (void)table;if(row<0||(NSUInteger)row>=self.rows.count)return;
    if([column.identifier isEqual:@"mode"])value=[value integerValue]==1?@"regex":@"literal";
    if([column.identifier isEqual:@"enabled"])value=@([value boolValue]);self.rows[row][column.identifier]=value?:@"";[self changed:nil];
}
- (void)sampleSelectionChanged:(NSNotification*)note{NSText *editor=self.sample.currentEditor;if(editor&&note.object==editor){self.sampleSelection=editor.selectedRange;self.selectionSample=self.sample.stringValue;}}
- (BOOL)windowShouldClose:(NSWindow*)window{(void)window;return !self.saving;}
- (void)controlTextDidChange:(NSNotification*)note{(void)note;[self changed:nil];}
- (NSDictionary*)draft{
    return @{@"schema_version":@1,@"enabled":@(self.enabled.state==NSControlStateValueOn),@"revision":NSUUID.UUID.UUIDString,@"rules":[self.rows copy]};
}
- (void)changed:(id)sender{(void)sender;[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(preview) object:nil];[self performSelector:@selector(preview) withObject:nil afterDelay:0.12];}
- (void)preview{
    NSUInteger generation=++self.previewGeneration;NSData *data=[NSJSONSerialization dataWithJSONObject:self.draft options:0 error:nil];NSString *sample=self.sample.stringValue?:@"",*exe=self.exe;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSDictionary *r=RunChild(exe,data,sample);dispatch_async(dispatch_get_main_queue(),^{if(generation!=self.previewGeneration)return;self.output.stringValue=r[@"value"];self.output.toolTip=r[@"status"];});});
}
- (void)add:(id)sender{(void)sender;if(self.rows.count>=MaxRules){[self alert:@"At most 32 rules."];return;}[self.rows addObject:[@{@"enabled":@YES,@"mode":@"literal",@"pattern":@"",@"replacement":@""} mutableCopy]];[self.table reloadData];[self changed:nil];}
- (void)remove:(id)sender{(void)sender;NSInteger i=self.table.selectedRow;if(i>=0){[self.rows removeObjectAtIndex:i];[self.table reloadData];[self changed:nil];}}
- (void)move:(NSInteger)delta{NSInteger i=self.table.selectedRow,j=i+delta;if(i<0||j<0||(NSUInteger)j>=self.rows.count)return;[self.rows exchangeObjectAtIndex:i withObjectAtIndex:j];[self.table reloadData];[self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:j] byExtendingSelection:NO];[self changed:nil];}
- (void)up:(id)sender{(void)sender;[self move:-1];}
- (void)down:(id)sender{(void)sender;[self move:1];}
- (void)refreshSources:(id)sender{
    (void)sender;NSDate *modified=nil;NSArray *names=Sources(self.sourcesPath,&modified);NSString *selected=self.current.titleOfSelectedItem;
    NSArray *old=self.current.itemTitles;if(![old isEqual:names]){[self.current removeAllItems];[self.current addItemsWithTitles:names];if([names containsObject:selected])[self.current selectItemWithTitle:selected];}
    self.timestamp.stringValue=modified?[NSString stringWithFormat:Local(@"Verified snapshot: %@ · %lu names",@"已验证名称快照：%@ · %lu个名称"),modified,(unsigned long)names.count]:Local(@"No valid snapshot. Manual samples remain available.",@"没有有效快照，仍可使用手工示例。");
}
- (void)chooseSource:(id)sender{(void)sender;if(self.current.selectedItem){self.sample.stringValue=self.current.titleOfSelectedItem;[self changed:nil];}}
- (void)addSuggestion:(NSMutableArray*)items title:(NSString*)title explanation:(NSString*)explanation pattern:(NSString*)pattern replacement:(NSString*)replacement{
    [items addObject:@{@"title":title,@"explanation":explanation,@"pattern":pattern,@"replacement":replacement}];
}
- (void)suggest:(id)sender{
    (void)sender;NSString *sample=self.sample.stringValue;if(!sample.length){[self alert:Local(@"Select a current name or type a sample first.",@"请先选择当前名称或输入示例。")];return;}
    NSMutableArray *items=[NSMutableArray array];NSRange selected=NSMakeRange(NSNotFound,0);NSText *editor=self.sample.currentEditor;if(editor)selected=editor.selectedRange;else if([self.selectionSample isEqual:sample])selected=self.sampleSelection;
    if(selected.location!=NSNotFound&&selected.length&&NSMaxRange(selected)<=sample.length){
        NSString *keep=[sample substringWithRange:selected];NSString *pattern=[NSString stringWithFormat:@"^.*?(%@).*$",[NSRegularExpression escapedPatternForString:keep]];
        [self addSuggestion:items title:Local(@"Keep selected text",@"保留选中文字") explanation:Local(@"Derived from the selected sample text; review and generalize before use.",@"根据示例选中文字生成，请审阅后使用或概括。") pattern:pattern replacement:@"$1"];
    }
    NSRange best=NSMakeRange(NSNotFound,0);
    for(NSString *separator in @[@" | ",@"｜",@": ",@"：",@" — ",@" - ",@"/"]){NSRange r=[sample rangeOfString:separator];if(r.location!=NSNotFound&&r.location>0&&NSMaxRange(r)<sample.length&&(best.location==NSNotFound||r.location<best.location))best=r;}
    if(best.location!=NSNotFound){
        NSString *prefix=[sample substringToIndex:NSMaxRange(best)],*escaped=[NSRegularExpression escapedPatternForString:prefix];
        [self addSuggestion:items title:Local(@"Remove the observed prefix",@"去掉示例中观察到的前缀") explanation:Local(@"Escapes the prefix from this example; no built-in personal prefix is used.",@"转义当前示例的前缀，没有内置个人前缀。") pattern:[@"^" stringByAppendingString:escaped] replacement:@""];
        [self addSuggestion:items title:Local(@"Keep text after the observed separator",@"保留示例分隔符之后的文字") explanation:Local(@"Anchors the escaped observed prefix and captures the remainder.",@"锚定并转义示例前缀，捕获其余文字。") pattern:[NSString stringWithFormat:@"^%@(.*)$",escaped] replacement:@"$1"];
    }
    NSDictionary *pairs=@{@"[":@"]",@"(":@")",@"{":@"}",@"<":@">",@"【":@"】",@"「":@"」",@"《":@"》",@"“":@"”",@"\"":@"\""};
    for(NSString *open in pairs){NSString *close=pairs[open];if([sample hasPrefix:open]&&[sample hasSuffix:close]&&sample.length>open.length+close.length){[self addSuggestion:items title:Local(@"Keep text inside the observed delimiters",@"保留示例外层分隔符中的文字") explanation:Local(@"Matches the entire example shape. Review nested delimiters before use.",@"匹配整名的外层形状；嵌套分隔符需审阅。") pattern:[NSString stringWithFormat:@"^%@(.*)%@$",[NSRegularExpression escapedPatternForString:open],[NSRegularExpression escapedPatternForString:close]] replacement:@"$1"];break;}}
    if(!items.count)[self addSuggestion:items title:Local(@"Match the exact example",@"匹配完整示例") explanation:Local(@"Escaped exact-match starting point. Edit it before Save if a broader rule is needed.",@"完整转义示例，仅为编辑起点；需要通用规则时请修改后保存。") pattern:[NSString stringWithFormat:@"^%@$",[NSRegularExpression escapedPatternForString:sample]] replacement:@"$0"];
    self.suggestions=items;[self.candidate removeAllItems];for(NSDictionary *s in items)[self.candidate addItemWithTitle:s[@"title"]];[self chooseSuggestion:nil];
}
- (void)chooseSuggestion:(id)sender{
    (void)sender;NSInteger i=self.candidate.indexOfSelectedItem;if(i<0||(NSUInteger)i>=self.suggestions.count)return;NSDictionary *s=self.suggestions[i];self.explanation.stringValue=s[@"explanation"];self.suggestPattern.stringValue=s[@"pattern"];self.suggestReplacement.stringValue=s[@"replacement"];self.useRule.enabled=YES;
    NSDictionary *config=@{@"schema_version":@1,@"enabled":@YES,@"revision":NSUUID.UUID.UUIDString,@"rules":@[@{@"enabled":@YES,@"mode":@"regex",@"pattern":s[@"pattern"],@"replacement":s[@"replacement"]}]};
    NSData *data=[NSJSONSerialization dataWithJSONObject:config options:0 error:nil];NSString *sample=self.sample.stringValue,*exe=self.exe;NSDictionary *selected=s;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSDictionary *r=RunChild(exe,data,sample);dispatch_async(dispatch_get_main_queue(),^{if(self.candidate.indexOfSelectedItem==i&&self.suggestions[i]==selected)self.suggestResult.stringValue=r[@"value"];});});
}
- (void)useSuggestion:(id)sender{
    (void)sender;NSInteger i=self.candidate.indexOfSelectedItem;if(i<0||(NSUInteger)i>=self.suggestions.count||self.rows.count>=MaxRules)return;NSDictionary *s=self.suggestions[i];[self.rows addObject:[@{@"enabled":@YES,@"mode":@"regex",@"pattern":s[@"pattern"],@"replacement":s[@"replacement"]} mutableCopy]];[self.table reloadData];[self changed:nil];
}
- (void)alert:(NSString*)message{NSAlert *alert=[NSAlert new];alert.messageText=Local(@"Name replacement",@"名称替换");alert.informativeText=message?:@"Error";[alert runModal];}
- (void)saveRules:(id)sender{
    (void)sender;[self.window makeFirstResponder:nil];NSDictionary *draft=self.draft;NSData *data=[NSJSONSerialization dataWithJSONObject:draft options:NSJSONWritingSortedKeys error:nil];
    if(!data||data.length>MaxBytes){[self alert:@"The rules file is too large."];return;}
    self.saving=YES;self.cancelButton.enabled=NO;self.save.enabled=NO;self.table.enabled=NO;self.enabled.enabled=NO;NSString *exe=self.exe,*path=self.rulesPath;NSData *base=self.baseBytes;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSDictionary *check=RunChild(exe,data,@"Example name");NSString *status=check[@"status"],*failure=nil;
        if(![status isEqual:@"ok"]&&![status isEqual:@"fallback:InvalidOutput"]&&![status isEqual:@"fallback:AggregateTimeout"])failure=[@"Validation failed: " stringByAppendingString:status?:@"Unknown"];
        if(!failure){
            NSError *error=nil;NSString *parent=path.stringByDeletingLastPathComponent;
            [NSFileManager.defaultManager createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error];
            int lockfd=error?-1:open([[path stringByAppendingString:@".lock"] fileSystemRepresentation],O_RDWR|O_CREAT,0600);
            if(lockfd<0||flock(lockfd,LOCK_EX|LOCK_NB)!=0)failure=@"Another save is in progress.";
            else{
                NSData *current=[NSData dataWithContentsOfFile:path];BOOL equal=(!current&&!base)||[current isEqualToData:base];
                if(!equal)failure=@"The rules changed in another editor. Reopen before saving.";
                else if(!AtomicData(data,path,&error))failure=error.localizedDescription?:@"Atomic save failed.";
                else if(![[NSData dataWithContentsOfFile:path] isEqualToData:data]){
                    BOOL restored=base?AtomicData(base,path,NULL):(unlink(path.fileSystemRepresentation)==0||errno==ENOENT);failure=restored?@"Readback failed; the prior rules were restored.":@"Readback failed; rollback also failed. Reopen and inspect the rules file.";
                }
                flock(lockfd,LOCK_UN);
            }
            if(lockfd>=0)close(lockfd);
        }
        dispatch_async(dispatch_get_main_queue(),^{self.saving=NO;self.cancelButton.enabled=YES;self.save.enabled=YES;self.table.enabled=YES;self.enabled.enabled=YES;if(failure)[self alert:failure];else{self.baseBytes=data;[self cancel:nil];}});
    });
}
- (void)help:(id)sender{(void)sender;NSString *path=self.helpPath;if([[[NSLocale preferredLanguages] firstObject] hasPrefix:@"zh"]){NSString *zh=[path.stringByDeletingPathExtension stringByAppendingString:@".zh-CN.html"];if([NSFileManager.defaultManager fileExistsAtPath:zh])path=zh;}if(Absolute(path)&&[NSFileManager.defaultManager fileExistsAtPath:path])[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path]];else[self alert:@"The packaged local help page is unavailable."];}
- (void)cancel:(id)sender{(void)sender;[self.sourceTimer invalidate];self.previewGeneration++;StopOwnedWorkers();[NSNotificationCenter.defaultCenter removeObserver:self];[self.window close];[NSApp terminate:nil];}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app{(void)app;return YES;}
@end
int main(int argc,const char *argv[]){@autoreleasepool{
    NSMutableDictionary *args=[NSMutableDictionary dictionary];BOOL format=NO,edit=NO;
    for(int i=1;i<argc;i++){NSString *key=[NSString stringWithUTF8String:argv[i]];if([key isEqual:@"--format"]){format=YES;continue;}if([key isEqual:@"--edit"]){edit=YES;continue;}if(i+1>=argc)return 3;args[key]=[NSString stringWithUTF8String:argv[++i]];}
    if(format&&!edit&&argc==10&&args.count==4)return FormatCLI(args);
    if(!edit||format||argc!=8||args.count!=3||!Absolute(args[@"--rules"])||!Absolute(args[@"--sources"])||!Absolute(args[@"--help"]))return 3;
    RulesEditor *editor=[RulesEditor new];editor.rulesPath=args[@"--rules"];editor.sourcesPath=args[@"--sources"];editor.helpPath=args[@"--help"];editor.exe=[NSString stringWithUTF8String:argv[0]];
    if(!editor.exe.isAbsolutePath)editor.exe=[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:editor.exe];
    NSApplication *app=[NSApplication sharedApplication];app.delegate=editor;[app setActivationPolicy:NSApplicationActivationPolicyRegular];[app run];return 0;
}}
