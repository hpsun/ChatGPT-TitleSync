// macOS draft — NOT compiled or tested on a Mac.
// clang -fobjc-arc -fblocks -framework Cocoa -framework ApplicationServices ChatGPTWindowTitles.m -o chatgpt-titlesync-objc
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>

// One per-user login item and preference are shared by all Mac implementations.
// Native macOS compilation and login behavior are unverified on this host.
static NSUserDefaults *TitleSyncStartupPreferences(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:@"io.github.hpsun.ChatGPTTitleSync"];
}
static BOOL TitleSyncStartupEnabled(void) {
    NSUserDefaults *prefs=TitleSyncStartupPreferences();
    return [prefs objectForKey:@"AutoStartEnabled"]==nil ? YES : [prefs boolForKey:@"AutoStartEnabled"];
}
static BOOL TitleSyncApplyStartup(BOOL wanted, NSError **error) {
    NSFileManager *manager=NSFileManager.defaultManager;
    NSURL *directory=[manager.homeDirectoryForCurrentUser URLByAppendingPathComponent:@"Library/LaunchAgents" isDirectory:YES];
    NSURL *target=[directory URLByAppendingPathComponent:@"io.github.hpsun.ChatGPTTitleSync.plist"];
    if(wanted) {
        NSString *executable=NSBundle.mainBundle.executablePath;
        if(!executable)executable=NSProcessInfo.processInfo.arguments.firstObject;
        if(!executable.isAbsolutePath)executable=[manager.currentDirectoryPath stringByAppendingPathComponent:executable];
        executable=executable.stringByStandardizingPath.stringByResolvingSymlinksInPath;
        if(![manager isExecutableFileAtPath:executable]) {
            if(error)*error=[NSError errorWithDomain:@"TitleSyncStartup" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Executable path is unavailable."}];
            return NO;
        }
        NSDictionary *values=@{@"Label":@"io.github.hpsun.ChatGPTTitleSync",@"ProgramArguments":@[executable],@"RunAtLoad":@YES,@"KeepAlive":@NO};
        NSData *data=[NSPropertyListSerialization dataWithPropertyList:values format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
        if(!data || ![manager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:error] || ![data writeToURL:target options:NSDataWritingAtomic error:error])return NO;
    } else if([manager fileExistsAtPath:target.path] && ![manager removeItemAtURL:target error:error])return NO;
    [TitleSyncStartupPreferences() setBool:wanted forKey:@"AutoStartEnabled"];
    return YES;
}


static NSURL *TitleSyncStartupTarget(void) {
    return [NSFileManager.defaultManager.homeDirectoryForCurrentUser URLByAppendingPathComponent:@"Library/LaunchAgents/io.github.hpsun.ChatGPTTitleSync.plist"];
}
static NSDictionary *TitleSyncStartupCheckpoint(NSError **error) {
    NSURL *target=TitleSyncStartupTarget();NSData *file=nil;
    if([NSFileManager.defaultManager fileExistsAtPath:target.path]){file=[NSData dataWithContentsOfURL:target options:0 error:error];if(!file)return nil;}
    return @{@"File":file?:NSNull.null,@"Preference":[TitleSyncStartupPreferences() objectForKey:@"AutoStartEnabled"]?:NSNull.null};
}
static BOOL TitleSyncStartupRestore(NSDictionary *before,NSError **error) {
    NSFileManager *manager=NSFileManager.defaultManager;NSURL *target=TitleSyncStartupTarget();id file=before[@"File"];
    if(file==NSNull.null){if([manager fileExistsAtPath:target.path]&&![manager removeItemAtURL:target error:error])return NO;}
    else if(![manager createDirectoryAtURL:target.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]||![(NSData *)file writeToURL:target options:NSDataWritingAtomic error:error])return NO;
    NSUserDefaults *preferences=TitleSyncStartupPreferences();id value=before[@"Preference"];
    if(value==NSNull.null)[preferences removeObjectForKey:@"AutoStartEnabled"];else[preferences setObject:value forKey:@"AutoStartEnabled"];
    if(![preferences synchronize]){if(error)*error=[NSError errorWithDomain:@"TitleSyncStartup" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Could not restore login preference."}];return NO;}return YES;
}

// Main-thread icon policy; native macOS compilation/runtime remain unverified.
// Injectable suite, asset root, clock and picker keep future tests outside real preferences.
@interface TitleSyncIcons : NSObject
@property(nonatomic,strong) NSUserDefaults *preferences;
@property(nonatomic,strong) NSURL *assets;
@property(nonatomic,copy) NSDate *(^clock)(void);
@property(nonatomic,copy) NSNumber *(^picker)(NSArray<NSNumber *> *);
@property(nonatomic,copy) NSDictionary<NSString *,id> *state;
@property(nonatomic,copy) NSString *failedSlot;
- (instancetype)initWithPreferences:(NSUserDefaults *)preferences assets:(NSURL *)assets clock:(NSDate *(^)(void))clock picker:(NSNumber *(^)(NSArray<NSNumber *> *))picker;
- (BOOL)initializeFromPreferences:(NSError **)error;
- (NSDictionary *)prepareMode:(NSString *)mode fixed:(NSInteger)fixed period:(NSString *)period error:(NSError **)error;
- (BOOL)commit:(NSDictionary *)plan error:(NSError **)error;
- (NSDictionary *)checkpoint;
- (BOOL)restoreCheckpoint:(NSDictionary *)before error:(NSError **)error;
- (NSImage *)imageForId:(NSInteger)number error:(NSError **)error;
- (NSInteger)currentId;
- (BOOL)tickReport:(void (^)(NSString *))report;
@end
@implementation TitleSyncIcons
+ (NSArray<NSString *> *)names {return @[@"IconMode",@"FixedIcon",@"IconPeriod",@"RandomIcon",@"IconSlot"];}
+ (NSDictionary *)defaults {return @{@"IconMode":@"fixed",@"FixedIcon":@45,@"IconPeriod":@"day",@"RandomIcon":@45,@"IconSlot":@""};}
+ (NSError *)failure:(NSString *)message {return [NSError errorWithDomain:@"TitleSyncIcons" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];}
+ (NSURL *)findAssets {
    NSURL *executable=[NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments.firstObject].URLByStandardizingPath.URLByResolvingSymlinksInPath;
    NSMutableArray<NSURL *> *candidates=[NSMutableArray array];NSURL *resource=NSBundle.mainBundle.resourceURL;
    if(resource){[candidates addObject:[resource URLByAppendingPathComponent:@"themes"]];[candidates addObject:[resource URLByAppendingPathComponent:@"assets/themes"]];}
    [candidates addObject:[executable.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"assets/themes"]];
    [candidates addObject:[[executable.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"../assets/themes"] URLByStandardizingPath]];
    for(NSURL *path in candidates)if([NSFileManager.defaultManager fileExistsAtPath:path.path])return path;
    return candidates.firstObject;
}
- (instancetype)init {return [self initWithPreferences:TitleSyncStartupPreferences() assets:nil clock:nil picker:nil];}
- (instancetype)initWithPreferences:(NSUserDefaults *)preferences assets:(NSURL *)assets clock:(NSDate *(^)(void))clock picker:(NSNumber *(^)(NSArray<NSNumber *> *))picker {
    if((self=[super init])){_preferences=preferences;_assets=assets?:[TitleSyncIcons findAssets];_state=[TitleSyncIcons defaults];_clock=clock?:^NSDate *{return NSDate.date;};_picker=picker?:^NSNumber *(NSArray<NSNumber *> *choices){return choices[arc4random_uniform((uint32_t)choices.count)];};}return self;
}
+ (NSString *)slot:(NSString *)period date:(NSDate *)date zone:(NSTimeZone *)zone {
    NSDateFormatter *formatter=[NSDateFormatter new];formatter.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];formatter.calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];formatter.timeZone=zone;
    formatter.dateFormat=[period isEqualToString:@"day"]?@"yyyyMMdd":@"yyyyMMddHHZ";
    if(![period isEqualToString:@"5min"])return [formatter stringFromDate:date];
    NSCalendar *calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];calendar.timeZone=zone;
    NSInteger bin=[calendar component:NSCalendarUnitMinute fromDate:date]/5;formatter.dateFormat=@"yyyyMMddHH";NSString *head=[formatter stringFromDate:date];formatter.dateFormat=@"Z";
    return [NSString stringWithFormat:@"%@%02ld%@",head,(long)bin,[formatter stringFromDate:date]];
}
- (NSInteger)currentId {return [self.state[[self.state[@"IconMode"] isEqualToString:@"fixed"]?@"FixedIcon":@"RandomIcon"] integerValue];}
- (NSImage *)imageForId:(NSInteger)number error:(NSError **)error {
    NSImage *image=number>=45&&number<=52?[[NSImage alloc] initWithContentsOfURL:[self.assets URLByAppendingPathComponent:[NSString stringWithFormat:@"%ld.png",(long)number]]]:nil;
    if(!image||!image.isValid){if(error)*error=[TitleSyncIcons failure:[NSString stringWithFormat:@"Icon asset %ld is unavailable.",(long)number]];return nil;}
    image.size=NSMakeSize(18,18);image.template=NO;return image;
}
- (BOOL)validate:(NSDictionary *)value error:(NSError **)error {
    id mode=value[@"IconMode"],fixed=value[@"FixedIcon"],period=value[@"IconPeriod"],random=value[@"RandomIcon"],slot=value[@"IconSlot"];
    BOOL valid=[mode isKindOfClass:NSString.class]&&[@[@"fixed",@"random"] containsObject:mode]&&[period isKindOfClass:NSString.class]&&[@[@"day",@"hour",@"5min"] containsObject:period]&&[fixed isKindOfClass:NSNumber.class]&&[random isKindOfClass:NSNumber.class]&&[fixed doubleValue]==(double)[fixed integerValue]&&[random doubleValue]==(double)[random integerValue]&&[fixed integerValue]>=45&&[fixed integerValue]<=52&&[random integerValue]>=45&&[random integerValue]<=52&&[slot isKindOfClass:NSString.class];
    if(!valid){if(error)*error=[TitleSyncIcons failure:@"Invalid icon mode, palette or period."];return NO;}
    NSInteger first=[mode isEqualToString:@"random"]?45:[fixed integerValue],last=[mode isEqualToString:@"random"]?52:first;
    for(NSInteger number=first;number<=last;number++)if(![self imageForId:number error:error])return NO;
    return YES;
}
- (NSDictionary *)checkpoint {
    NSMutableDictionary *values=[NSMutableDictionary dictionary];for(NSString *key in [TitleSyncIcons names])values[key]=[self.preferences objectForKey:key]?:NSNull.null;
    return @{@"Values":values,@"State":self.state};
}
- (BOOL)restoreCheckpoint:(NSDictionary *)before error:(NSError **)error {
    NSDictionary *values=before[@"Values"];for(NSString *key in [TitleSyncIcons names]){id old=values[key];if(old==NSNull.null)[self.preferences removeObjectForKey:key];else[self.preferences setObject:old forKey:key];}
    if(![self.preferences synchronize]){if(error)*error=[TitleSyncIcons failure:@"Could not restore icon preferences."];return NO;}
    self.state=before[@"State"];return YES;
}
- (NSDictionary *)prepareMode:(NSString *)mode fixed:(NSInteger)fixed period:(NSString *)period error:(NSError **)error {
    NSMutableDictionary *plan=[self.state mutableCopy];plan[@"IconMode"]=mode;plan[@"FixedIcon"]=@(fixed);plan[@"IconPeriod"]=period;
    if(![self validate:plan error:error])return nil;
    if([mode isEqualToString:@"random"]){NSString *slot=[TitleSyncIcons slot:period date:self.clock() zone:NSTimeZone.localTimeZone];
        if(![self.state[@"IconMode"] isEqual:mode]||![self.state[@"IconPeriod"] isEqual:period]||![self.state[@"IconSlot"] isEqual:slot]){
            NSMutableArray<NSNumber *> *choices=[NSMutableArray array];for(NSInteger i=45;i<=52;i++)if(i!=[self.state[@"RandomIcon"] integerValue])[choices addObject:@(i)];NSNumber *selected=self.picker(choices);
            if(![choices containsObject:selected]){if(error)*error=[TitleSyncIcons failure:@"Icon picker repeated or left the palette."];return nil;}plan[@"RandomIcon"]=selected;plan[@"IconSlot"]=slot;
        }}return [plan copy];
}
- (BOOL)commit:(NSDictionary *)plan error:(NSError **)error {
    if(![self validate:plan error:error])return NO;NSDictionary *before=[self checkpoint];
    for(NSString *key in [TitleSyncIcons names])if(![[self.preferences objectForKey:key] isEqual:plan[key]])[self.preferences setObject:plan[key] forKey:key];
    BOOL saved=[self.preferences synchronize];for(NSString *key in [TitleSyncIcons names])saved=saved&&[[self.preferences objectForKey:key] isEqual:plan[key]];
    if(!saved){NSError *rollback=nil;BOOL restored=[self restoreCheckpoint:before error:&rollback];if(error)*error=[TitleSyncIcons failure:restored?@"Could not verify icon preferences.":@"Icon save and rollback failed."];return NO;}
    self.state=[plan copy];self.failedSlot=nil;return YES;
}
- (BOOL)initializeFromPreferences:(NSError **)error {
    NSMutableDictionary *loaded=[[TitleSyncIcons defaults] mutableCopy];for(NSString *key in [TitleSyncIcons names]){id value=[self.preferences objectForKey:key];if(value)loaded[key]=value;}
    if(![self validate:loaded error:error])return NO;self.state=[loaded copy];
    if([loaded[@"IconMode"] isEqualToString:@"random"]){NSDictionary *plan=[self prepareMode:loaded[@"IconMode"] fixed:[loaded[@"FixedIcon"] integerValue] period:loaded[@"IconPeriod"] error:error];if(!plan)return NO;if(![plan isEqualToDictionary:loaded])return [self commit:plan error:error];}return YES;
}
- (BOOL)tickReport:(void (^)(NSString *))report {
    if(![self.state[@"IconMode"] isEqualToString:@"random"])return NO;NSString *slot=[TitleSyncIcons slot:self.state[@"IconPeriod"] date:self.clock() zone:NSTimeZone.localTimeZone];
    if([slot isEqual:self.state[@"IconSlot"]]||[slot isEqual:self.failedSlot])return NO;
    NSError *error=nil;NSDictionary *plan=[self prepareMode:@"random" fixed:[self.state[@"FixedIcon"] integerValue] period:self.state[@"IconPeriod"] error:&error];
    if(plan&&[self commit:plan error:&error])return YES;self.failedSlot=slot;if(report)report(slot);return NO;
}
@end

static id AXRead(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}
static NSString *AXString(AXUIElementRef element, CFStringRef attribute) {
    id value = AXRead(element, attribute);
    return [value isKindOfClass:NSString.class] ? value : nil;
}
// Candidate Mac locator, unverified on real ChatGPT Mac.
// Only native envelope roles; AXWebArea is a leaf: its children are NEVER read.
static NSString *ConversationTitle(AXUIElementRef window, NSString **error, BOOL (^stillActive)(void)) {
    NSSet *containers = [NSSet setWithArray:@[@"AXWindow",@"AXGroup",@"AXSplitGroup",@"AXScrollArea",@"AXLayoutArea"]];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:@[(__bridge id)window, @0]];
    NSMutableArray *documents = [NSMutableArray array];
    NSUInteger head = 0;
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 2.0;
    while (head < queue.count) {
        if (!stillActive() || head >= 64 || CFAbsoluteTimeGetCurrent() >= deadline) { *error = @"native envelope exceeds 64 nodes"; return nil; }
        NSArray *entry = queue[head++];
        AXUIElementRef node = (__bridge AXUIElementRef)entry[0];
        NSInteger depth = [entry[1] integerValue];
        AXUIElementSetMessagingTimeout(node,0.5);
        NSString *role = AXString(node, kAXRoleAttribute);
        if (!role) { *error = @"AXRole unreadable"; return nil; }
        if ([role isEqualToString:@"AXWebArea"]) { [documents addObject:(__bridge id)node]; continue; }
        if ([containers containsObject:role]) {
            if (depth >= 8) { *error = @"native envelope depth exceeded"; return nil; }
            id children = AXRead(node, kAXChildrenAttribute);
            if (![children isKindOfClass:NSArray.class]) { *error = @"AXChildren unreadable"; return nil; }
            if(queue.count+[(NSArray *)children count]>64){*error=@"native envelope node limit";return nil;}
            for (id child in children) [queue addObject:@[child, @(depth + 1)]];
        }
    }
    if (documents.count != 1) { *error = @"current conversation title unavailable or ambiguous"; return nil; }
    NSString *name = AXString((__bridge AXUIElementRef)documents[0], kAXTitleAttribute);
    if (!name.length || name.length > 512 || !stillActive() ||
        ![name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
        *error = @"empty, generic or oversized document title"; return nil;
    }
    return name;
}
@interface WindowRecord : NSObject
@property(nonatomic) AXUIElementRef window;
@property(nonatomic) pid_t pid;
@property(nonatomic, strong) NSDate *launched;
@property(nonatomic) NSInteger token;
@property(nonatomic, copy) NSString *original;
@property(nonatomic, copy) NSString *lastWritten;
@property(nonatomic, strong) NSDate *retry;
@property(nonatomic, copy) NSString *cachedTitle;
@property(nonatomic, strong) NSDate *nextForegroundRead;
@property(nonatomic, strong) NSDate *nextBackgroundRead;
@property(nonatomic) BOOL manualOverride;
@property(nonatomic) NSUInteger sourceRevision; // state-queue-only submission generation
@property(nonatomic) BOOL hasObservedRole;
@property(nonatomic) BOOL observedForeground;
@end
@implementation WindowRecord
- (void)dealloc { if (_window) CFRelease(_window); }
@end

@interface Monitor : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSStatusItem *status;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSMutableArray<WindowRecord *> *records;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) dispatch_queue_t foregroundQueue;
@property(nonatomic, strong) dispatch_queue_t backgroundQueue;
@property(nonatomic) BOOL foregroundBusy;
@property(nonatomic) BOOL backgroundBusy;
@property(nonatomic) NSTimeInterval backgroundInterval;
@property(nonatomic, strong) NSLock *timingLock;
@property(nonatomic, strong) NSUserDefaults *scanPreferences;
@property(nonatomic, strong) NSPanel *settingsPanel;
@property(nonatomic, strong) NSTextField *foregroundInput;
@property(nonatomic, strong) NSTextField *backgroundInput;
@property(nonatomic, strong) NSTextField *settingsMessage;
@property(nonatomic, strong) NSButton *autoStartInput;
@property(nonatomic) BOOL autoStartEnabled;
@property(nonatomic,strong) TitleSyncIcons *icons;
@property(nonatomic,strong) NSPopUpButton *iconModeInput;
@property(nonatomic,strong) NSPopUpButton *fixedIconInput;
@property(nonatomic,strong) NSPopUpButton *iconPeriodInput;
@property(nonatomic, strong) NSArray<NSString *> *lines;
@property(nonatomic, copy) NSString *bundleID;
@property(nonatomic) NSTimeInterval interval;
@property(nonatomic) NSInteger nextToken;
@property(nonatomic) BOOL paused;
@property(nonatomic) BOOL queued;
@property(nonatomic) BOOL quitting;
@property(nonatomic) NSUInteger generation;
- (void)applyIcon:(NSImage *)image;
- (void)metadataTick;
- (void)iconModeChanged:(id)sender;
@end
@implementation Monitor
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("ChatGPTTitleDraft.ObjC.AX", DISPATCH_QUEUE_SERIAL);
        _foregroundQueue = dispatch_queue_create("ChatGPTTitleDraft.ObjC.Foreground", DISPATCH_QUEUE_SERIAL);
        _backgroundQueue = dispatch_queue_create("ChatGPTTitleDraft.ObjC.Background", DISPATCH_QUEUE_SERIAL);
        _autoStartEnabled=TitleSyncStartupEnabled();_icons=[TitleSyncIcons new];
        _records = [NSMutableArray array]; _nextToken = 1; _interval = 2; _backgroundInterval = 5;
        // Legacy preferences domain retained so existing settings survive the product rename.
        _timingLock=[NSLock new];_scanPreferences=[[NSUserDefaults alloc] initWithSuiteName:@"org.chatgpt-title.objc"];
        NSDictionary *saved=[_scanPreferences dictionaryForKey:@"ScanIntervals"];
        NSInteger savedFg=[saved[@"ForegroundSeconds"] integerValue],savedBg=[saved[@"BackgroundSeconds"] integerValue];
        if(savedFg>=1&&savedFg<=3600)_interval=savedFg;
        if(savedBg>=5&&savedBg<=3600)_backgroundInterval=savedBg;
        _bundleID = @"com.openai.chat"; // expected identifier; verify on target Mac or use --bundle-id
        _lines = @[@"尚未检查；Mac AX 行为未实机验证"];
        NSArray *args = NSProcessInfo.processInfo.arguments;
        for (NSUInteger i=1; i+1<args.count; i++) {
            if ([args[i] isEqualToString:@"--bundle-id"]) _bundleID = args[i+1];
            if ([args[i] isEqualToString:@"--background-interval"] && [args[i+1] doubleValue] >= 5 && [args[i+1] doubleValue] <= 3600) _backgroundInterval = [args[i+1] doubleValue];
            if ([args[i] isEqualToString:@"--interval"] && [args[i+1] doubleValue] >= 1 && [args[i+1] doubleValue] <= 3600) _interval = [args[i+1] doubleValue];
        }
    }
    return self;
}
- (void)log:(NSString *)event record:(WindowRecord *)record error:(NSString *)error {
    NSMutableDictionary *row = [@{@"time":[[NSISO8601DateFormatter new] stringFromDate:NSDate.date], @"event":event} mutableCopy];
    if (record) { row[@"pid"]=@(record.pid); row[@"windowToken"]=@(record.token); }
    if (error) row[@"error"]=error;
    NSData *data = [NSJSONSerialization dataWithJSONObject:row options:0 error:nil];
    if (data) fprintf(stdout, "%s\n", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.status = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.status.button.title = @"GPT";self.status.button.toolTip=@"ChatGPT-TitleSync / ChatGPT 标题同步助手";
    NSError *iconError=nil;if(![self.icons initializeFromPreferences:&iconError])[self log:@"icon_preferences_failed" record:nil error:iconError.localizedDescription];
    NSImage *initialImage=[self.icons imageForId:self.icons.currentId error:&iconError];if(initialImage)[self applyIcon:initialImage];else[self log:@"icon_load_failed" record:nil error:@"baseline_or_saved_asset"];
    NSError *startupError=nil;
    if(!TitleSyncApplyStartup(self.autoStartEnabled,&startupError)){self.autoStartEnabled=NO;self.lines=[self.lines arrayByAddingObject:@"登录自启动注册失败"];[self log:@"startup_registration_failed" record:nil error:startupError.localizedDescription];}
    [self rebuildMenu];
    // Repeating NSTimer uses scheduled deadlines, not an AX-pass completion delay.
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(metadataTick) userInfo:nil repeats:YES];
    [self enqueueScan];
}
- (void)applyIcon:(NSImage *)image {self.status.button.image=image;self.status.button.title=@"";NSApp.applicationIconImage=image;}
- (void)metadataTick {
    if(self.quitting)return;
    if([self.icons tickReport:^(NSString *slot){[self log:@"icon_rotation_failed" record:nil error:slot];}]){
        NSError *error=nil;NSImage *image=[self.icons imageForId:self.icons.currentId error:&error];
        if(image)[self applyIcon:image];else[self log:@"icon_load_failed" record:nil error:self.icons.state[@"IconSlot"]];
    }
    [self enqueueScan];
}
- (void)iconModeChanged:(id)sender {self.fixedIconInput.enabled=self.iconModeInput.indexOfSelectedItem==0;self.iconPeriodInput.enabled=self.iconModeInput.indexOfSelectedItem==1;}
- (void)rebuildMenu {
    NSMenu *menu = [NSMenu new];
    NSMenuItem *state = [[NSMenuItem alloc] initWithTitle:self.paused ? @"已暂停；关闭功能后尝试还原" : [NSString stringWithFormat:@"监听中（每 %.1f 秒）",self.interval] action:NULL keyEquivalent:@""];
    state.enabled = NO; [menu addItem:state];
    for (NSString *line in self.lines) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:line action:NULL keyEquivalent:@""];
        item.enabled = NO; [menu addItem:item];
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *startup=[[NSMenuItem alloc] initWithTitle:@"开机自启动 / Start at sign-in" action:@selector(toggleAutoStart) keyEquivalent:@""];
    startup.target=self;startup.state=self.autoStartEnabled?NSControlStateValueOn:NSControlStateValueOff;[menu addItem:startup];
    NSArray *titles = @[@"扫描间隔设置…",self.paused ? @"恢复监听" : @"暂停并还原", @"检查／请求辅助功能权限", @"退出并还原"];
    SEL actions[] = {@selector(showScanSettings),@selector(togglePause),@selector(requestPermission),@selector(quit)};
    for (NSUInteger i=0;i<titles.count;i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[i] action:actions[i] keyEquivalent:i==3?@"q":@""];
        item.target=self; [menu addItem:item];
    }
    self.status.menu=menu;
}
// A modeless panel leaves normal monitoring responsive while editing.
- (NSArray<NSNumber *> *)timingSnapshot {
    [self.timingLock lock];NSArray *value=@[@(self.interval),@(self.backgroundInterval)];[self.timingLock unlock];return value;
}
- (void)toggleAutoStart {
    BOOL wanted=!self.autoStartEnabled;NSError *error=nil;
    if(TitleSyncApplyStartup(wanted,&error)){self.autoStartEnabled=wanted;self.autoStartInput.state=wanted?NSControlStateValueOn:NSControlStateValueOff;[self rebuildMenu];}
    else{NSAlert *alert=[NSAlert new];alert.messageText=@"开机自启动";alert.informativeText=error.localizedDescription?:@"Could not update startup.";[alert runModal];}
}
- (void)showScanSettings {
    if(!self.settingsPanel){
        NSPanel *panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,440,380) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        panel.title=@"ChatGPT-TitleSync — 扫描间隔设置";panel.releasedWhenClosed=NO;NSView *view=panel.contentView;
        NSArray *labels=@[@"前台来源读取（秒）：",@"后台来源刷新（秒）："];
        for(NSUInteger index=0;index<2;index++){NSTextField *label=[NSTextField labelWithString:labels[index]];label.frame=NSMakeRect(14,298-36*index,190,24);[view addSubview:label];}
        self.foregroundInput=[[NSTextField alloc] initWithFrame:NSMakeRect(222,298,110,24)];
        self.backgroundInput=[[NSTextField alloc] initWithFrame:NSMakeRect(222,262,110,24)];
        [view addSubview:self.foregroundInput];[view addSubview:self.backgroundInput];
        self.autoStartInput=[NSButton checkboxWithTitle:@"开机自启动 / Start at sign-in" target:nil action:NULL];
        self.autoStartInput.frame=NSMakeRect(14,337,360,24);[view addSubview:self.autoStartInput];
        NSTextField *hint=[NSTextField labelWithString:@"前台1–3600秒；后台5–3600秒。原生标题维护固定1秒。"];
        hint.font=[NSFont systemFontOfSize:11];hint.frame=NSMakeRect(14,230,365,22);[view addSubview:hint];
        self.settingsMessage=[NSTextField labelWithString:@""];self.settingsMessage.textColor=NSColor.systemRedColor;
        self.settingsMessage.font=[NSFont systemFontOfSize:11];self.settingsMessage.frame=NSMakeRect(14,43,365,22);[view addSubview:self.settingsMessage];
        NSButton *save=[[NSButton alloc] initWithFrame:NSMakeRect(216,8,76,28)];save.title=@"保存";save.target=self;save.action=@selector(saveScanSettings);save.keyEquivalent=@"\r";[view addSubview:save];
        NSButton *cancel=[[NSButton alloc] initWithFrame:NSMakeRect(300,8,76,28)];cancel.title=@"取消";cancel.target=self;cancel.action=@selector(cancelScanSettings);cancel.keyEquivalent=@"\033";[view addSubview:cancel];
        NSArray *iconLabels=@[@"图标模式 / Icon mode",@"固定配色 / Palette",@"随机周期 / Period"];
        NSArray *iconValues=@[@[@"固定 / Fixed",@"随机 / Random"],@[@"45",@"46",@"47",@"48",@"49",@"50",@"51",@"52"],@[@"每日 / Daily",@"每小时 / Hourly",@"每5分钟 / Every 5 minutes"]];
        NSMutableArray<NSPopUpButton *> *choices=[NSMutableArray array];
        for(NSUInteger i=0;i<3;i++){CGFloat y=186-36*i;NSTextField *label=[NSTextField labelWithString:iconLabels[i]];label.frame=NSMakeRect(14,y,200,24);[view addSubview:label];NSPopUpButton *popup=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(222,y,190,26) pullsDown:NO];[popup addItemsWithTitles:iconValues[i]];[view addSubview:popup];[choices addObject:popup];}
        self.iconModeInput=choices[0];self.fixedIconInput=choices[1];self.iconPeriodInput=choices[2];self.iconModeInput.target=self;self.iconModeInput.action=@selector(iconModeChanged:);
        self.settingsPanel=panel;
    }
    self.foregroundInput.stringValue=[NSString stringWithFormat:@"%.0f",self.interval];
    self.backgroundInput.stringValue=[NSString stringWithFormat:@"%.0f",self.backgroundInterval];
    self.autoStartInput.state=self.autoStartEnabled?NSControlStateValueOn:NSControlStateValueOff;
    [self.iconModeInput selectItemAtIndex:[self.icons.state[@"IconMode"] isEqualToString:@"fixed"]?0:1];
    [self.fixedIconInput selectItemAtIndex:[self.icons.state[@"FixedIcon"] integerValue]-45];
    NSUInteger periodIndex=[@[@"day",@"hour",@"5min"] indexOfObject:self.icons.state[@"IconPeriod"]];[self.iconPeriodInput selectItemAtIndex:periodIndex==NSNotFound?0:(NSInteger)periodIndex];[self iconModeChanged:nil];
    self.settingsMessage.stringValue=@"";[self.settingsPanel center];[self.settingsPanel makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
}
- (void)cancelScanSettings {[self.settingsPanel orderOut:nil];}
- (void)saveScanSettings {
    NSScanner *fgScan=[NSScanner scannerWithString:[self.foregroundInput.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    NSScanner *bgScan=[NSScanner scannerWithString:[self.backgroundInput.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    NSInteger fg=0,bg=0;
    if(![fgScan scanInteger:&fg]||!fgScan.isAtEnd||![bgScan scanInteger:&bg]||!bgScan.isAtEnd||fg<1||fg>3600||bg<5||bg>3600){self.settingsMessage.stringValue=@"请输入整数：前台1–3600秒，后台5–3600秒。";return;}
    NSInteger modeIndex=self.iconModeInput.indexOfSelectedItem,fixedIndex=self.fixedIconInput.indexOfSelectedItem,periodIndex=self.iconPeriodInput.indexOfSelectedItem;
    if(modeIndex<0||modeIndex>1||fixedIndex<0||fixedIndex>7||periodIndex<0||periodIndex>2){self.settingsMessage.stringValue=@"Choose all icon settings.";return;}
    BOOL wantedStartup=self.autoStartInput.state==NSControlStateValueOn;NSError *saveError=nil;
    NSDictionary *plan=[self.icons prepareMode:modeIndex==0?@"fixed":@"random" fixed:45+fixedIndex period:@[@"day",@"hour",@"5min"][periodIndex] error:&saveError];
    NSInteger selected=[plan[[plan[@"IconMode"] isEqualToString:@"fixed"]?@"FixedIcon":@"RandomIcon"] integerValue];
    NSImage *image=plan?[self.icons imageForId:selected error:&saveError]:nil;
    if(!image){self.settingsMessage.stringValue=saveError.localizedDescription?:@"Icon validation failed.";return;}
    NSDictionary *beforeIcons=[self.icons checkpoint],*beforeStartup=TitleSyncStartupCheckpoint(&saveError);id beforeScan=[self.scanPreferences objectForKey:@"ScanIntervals"];
    if(!beforeStartup){self.settingsMessage.stringValue=saveError.localizedDescription?:@"Could not snapshot login registration.";return;}
    BOOL saved=TitleSyncApplyStartup(wantedStartup,&saveError)&&[self.icons commit:plan error:&saveError];
    if(saved){[self.scanPreferences setObject:@{@"ForegroundSeconds":@(fg),@"BackgroundSeconds":@(bg)} forKey:@"ScanIntervals"];saved=[self.scanPreferences synchronize];NSDictionary *back=[self.scanPreferences dictionaryForKey:@"ScanIntervals"];saved=saved&&[back[@"ForegroundSeconds"] integerValue]==fg&&[back[@"BackgroundSeconds"] integerValue]==bg;}
    if(!saved){NSError *rollback=nil;BOOL a=[self.icons restoreCheckpoint:beforeIcons error:&rollback],b=TitleSyncStartupRestore(beforeStartup,&rollback);if(beforeScan)[self.scanPreferences setObject:beforeScan forKey:@"ScanIntervals"];else[self.scanPreferences removeObjectForKey:@"ScanIntervals"];BOOL c=[self.scanPreferences synchronize];self.settingsMessage.stringValue=[NSString stringWithFormat:@"%@%@",saveError.localizedDescription?:@"Could not verify saved settings.",(a&&b&&c)?@"":@"; rollback failed"];return;}
    self.autoStartEnabled=wantedStartup;[self applyIcon:image];
    self.generation++;
    [self.timingLock lock];self.interval=fg;self.backgroundInterval=bg;[self.timingLock unlock];
    dispatch_async(self.queue,^{for(WindowRecord *record in self.records){record.sourceRevision++;record.nextForegroundRead=NSDate.distantPast;record.nextBackgroundRead=NSDate.distantPast;}});
    [self.settingsPanel orderOut:nil];[self rebuildMenu];[self enqueueScan];[self log:@"scan_intervals_changed" record:nil error:nil];
}
- (void)requestPermission {
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
    [self enqueueScan]; // user decides; no privacy-setting changes
}
- (BOOL)identityAlive:(WindowRecord *)record {
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:record.pid];
    if (!app || app.terminated || ![app.launchDate isEqualToDate:record.launched]) return NO;
    pid_t actual=0;
    return AXUIElementGetPid(record.window,&actual)==kAXErrorSuccess && actual==record.pid;
}
- (void)releaseChangedLease:(WindowRecord *)record current:(NSString *)current {
    if (!record.lastWritten || [current isEqualToString:record.lastWritten]) return;
    record.original=nil; record.lastWritten=nil;
    [self log:@"lease_released_external_caption" record:record error:nil];
}
- (void)restoreAll {
    for (WindowRecord *record in self.records) {
        if (!record.lastWritten || !record.original) continue;
        if (![self identityAlive:record]) {
            [self log:@"restore_skipped_identity_or_external_change" record:record error:nil]; continue;
        }
        NSString *current=AXString(record.window,kAXTitleAttribute);
        if (!current || ![current isEqualToString:record.lastWritten]) {
            if (current) [self releaseChangedLease:record current:current];
            [self log:@"restore_skipped_identity_or_external_change" record:record error:nil]; continue;
        }
        AXError result=AXUIElementSetAttributeValue(record.window,kAXTitleAttribute,(__bridge CFStringRef)record.original);
        if (result==kAXErrorSuccess && [self identityAlive:record] && [AXString(record.window,kAXTitleAttribute) isEqualToString:record.original]) {
            [self log:@"restored" record:record error:nil]; record.lastWritten=nil; record.original=nil;
        } else [self log:@"restore_failed" record:record error:[NSString stringWithFormat:@"AXError %d",result]];
    }
}
- (void)togglePause {
    self.generation++;self.paused=!self.paused;
    if (self.paused) {
        dispatch_async(self.queue, ^{[self restoreAll];});
        self.lines=@[@"已暂停；还原请求已排队，结果见日志"];
    } else [self enqueueScan];
    [self rebuildMenu];
}
- (void)quit {
    if (self.quitting) return;
    self.generation++;self.quitting=YES; [self.timer invalidate];
    dispatch_async(self.queue, ^{[self restoreAll]; dispatch_async(dispatch_get_main_queue(), ^{[NSApp terminate:nil];});});
}
- (void)enqueueScan {
    if (self.paused || self.queued || self.quitting) return;
    self.queued=YES;
    dispatch_async(self.queue, ^{
        NSArray *rows=[self scan];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.queued=NO;
            if (!self.paused) {self.lines=rows; [self rebuildMenu];}
        });
    });
}
// NSWorkspace is checked before AX. Other foreground apps cause zero AX tree reads.
- (NSDictionary *)focusedEntry {
    NSRunningApplication *front=NSWorkspace.sharedWorkspace.frontmostApplication;
    if(!front||front.terminated||![front.bundleIdentifier isEqualToString:self.bundleID]||!front.launchDate)return nil;
    if(!AXIsProcessTrusted())return nil;
    AXUIElementRef system=AXUIElementCreateSystemWide();AXUIElementSetMessagingTimeout(system,0.5);
    id app=AXRead(system,kAXFocusedApplicationAttribute);CFRelease(system);
    if(!app||CFGetTypeID((__bridge CFTypeRef)app)!=AXUIElementGetTypeID())return nil;
    pid_t pid=0;if(AXUIElementGetPid((__bridge AXUIElementRef)app,&pid)!=kAXErrorSuccess||pid!=front.processIdentifier)return nil;
    AXUIElementSetMessagingTimeout((__bridge AXUIElementRef)app,0.5);
    id window=AXRead((__bridge AXUIElementRef)app,kAXFocusedWindowAttribute);
    if(!window||CFGetTypeID((__bridge CFTypeRef)window)!=AXUIElementGetTypeID()||NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=pid)return nil;
    AXUIElementSetMessagingTimeout((__bridge AXUIElementRef)window,0.5);
    return @{@"window":window,@"pid":@(pid),@"launched":front.launchDate};
}
- (BOOL)active:(WindowRecord *)record {
    NSDictionary *entry=[self focusedEntry];
    return entry&&[entry[@"pid"] intValue]==record.pid&&[entry[@"launched"] isEqualToDate:record.launched]&&CFEqual(record.window,(__bridge AXUIElementRef)entry[@"window"]);
}
// Lease mutation is serialized here; source reads have independent FG/BG queues.
- (BOOL)allowed {
    __block BOOL value=NO;
    if(NSThread.isMainThread)return !self.paused&&!self.quitting;
    dispatch_sync(dispatch_get_main_queue(),^{value=!self.paused&&!self.quitting;});
    return value;
}
- (BOOL)generic:(NSString *)title {
    NSString *value=[title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return value.length==0||[value caseInsensitiveCompare:@"ChatGPT"]==NSOrderedSame;
}
- (BOOL)eligible:(WindowRecord *)record foreground:(BOOL)foreground {
    return [self allowed]&&[self identityAlive:record]&&[self active:record]==foreground;
}
// Target-app AXWindows is metadata only. AXWebArea children remain excluded.
- (NSArray<WindowRecord *> *)discover {
    if(!AXIsProcessTrusted())return @[];
    NSMutableArray *found=[NSMutableArray array];NSUInteger apps=0;
    NSMutableDictionary<NSNumber *,NSDictionary *> *completeSnapshots=[NSMutableDictionary dictionary];
    for(NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:self.bundleID]) {
        if(apps++>=16)break;if(app.terminated||!app.launchDate)continue;
        AXUIElementRef axApp=AXUIElementCreateApplication(app.processIdentifier);
        AXUIElementSetMessagingTimeout(axApp,0.5);id windows=AXRead(axApp,kAXWindowsAttribute);CFRelease(axApp);
        if(![windows isKindOfClass:NSArray.class])continue;
        // Failed or capped enumeration cannot establish that an old window closed.
        if([(NSArray *)windows count]<=64)completeSnapshots[@(app.processIdentifier)]=@{@"launched":app.launchDate,@"windows":windows};
        NSUInteger count=0;for(id window in windows) {
            if(count++>=64)break;
            AXUIElementRef axWindow=(__bridge AXUIElementRef)window;
            AXUIElementSetMessagingTimeout(axWindow,0.5);
            WindowRecord *record=nil;
            for(WindowRecord *old in self.records)if(old.pid==app.processIdentifier&&[old.launched isEqualToDate:app.launchDate]&&CFEqual(old.window,axWindow)){record=old;break;}
            if(!record){record=[WindowRecord new];record.window=(AXUIElementRef)CFRetain(axWindow);record.pid=app.processIdentifier;record.launched=app.launchDate;record.token=self.nextToken++;[self.records addObject:record];}
            [found addObject:record];
        }
    }
    for(WindowRecord *old in self.records.copy) {
        BOOL retire=![self identityAlive:old];
        NSDictionary *snapshot=completeSnapshots[@(old.pid)];
        if(!retire && snapshot && [snapshot[@"launched"] isEqualToDate:old.launched]) {
            BOOL present=NO;
            for(id window in snapshot[@"windows"])if(CFEqual(old.window,(__bridge AXUIElementRef)window)){present=YES;break;}
            retire=!present;
        }
        if(retire)[self.records removeObjectIdenticalTo:old];
    }
    NSMutableArray *retained=[NSMutableArray array];
    for(WindowRecord *record in found)if([self.records indexOfObjectIdenticalTo:record]!=NSNotFound)[retained addObject:record];
    return retained;
}
- (BOOL)write:(WindowRecord *)record wanted:(NSString *)wanted expected:(NSString *)expected foreground:(BOOL)foreground {
    if(![self eligible:record foreground:foreground]||![AXString(record.window,kAXTitleAttribute) isEqualToString:expected])return NO;
    Boolean writable=0;if(AXUIElementIsAttributeSettable(record.window,kAXTitleAttribute,&writable)!=kAXErrorSuccess||!writable)return NO;
    [self releaseChangedLease:record current:expected];
    NSString *original=record.original?:expected;
    AXError result=AXUIElementSetAttributeValue(record.window,kAXTitleAttribute,(__bridge CFStringRef)wanted);
    if(result!=kAXErrorSuccess){[self log:@"caption_write_failed" record:record error:nil];return NO;}
    record.original=original;record.lastWritten=wanted;
    BOOL verified=[self identityAlive:record]&&[AXString(record.window,kAXTitleAttribute) isEqualToString:wanted];
    [self log:verified?@"caption_written":@"caption_readback_unconfirmed" record:record error:nil];
    return verified;
}
- (void)applySource:(NSString *)name record:(WindowRecord *)record foreground:(BOOL)foreground {
    if([self.records indexOfObjectIdenticalTo:record]==NSNotFound||![self eligible:record foreground:foreground])return;
    NSString *current=AXString(record.window,kAXTitleAttribute);if(!current)return;
    [self releaseChangedLease:record current:current];
    if([self generic:name]) {
        record.cachedTitle=nil;
        if(record.lastWritten&&[current isEqualToString:record.lastWritten]&&record.original&&[self write:record wanted:record.original expected:current foreground:foreground]){record.lastWritten=nil;record.original=nil;}
        return;
    }
    NSString *wanted=[name stringByAppendingString:@" — ChatGPT"];record.cachedTitle=wanted;
    if([self generic:current])record.manualOverride=NO;
    if([current isEqualToString:wanted])return;
    if(![self generic:current]&&![current isEqualToString:record.lastWritten]){record.manualOverride=YES;[self log:@"custom_caption_preserved" record:record error:nil];return;}
    if(!record.manualOverride)[self write:record wanted:wanted expected:current foreground:foreground];
}
- (void)startSource:(WindowRecord *)record foreground:(BOOL)foreground {
    NSUInteger sourceRevision=++record.sourceRevision;
    NSArray *timing=[self timingSnapshot];
    if(foreground){self.foregroundBusy=YES;record.nextForegroundRead=[NSDate dateWithTimeIntervalSinceNow:[timing[0] doubleValue]];}
    else{self.backgroundBusy=YES;record.nextBackgroundRead=[NSDate dateWithTimeIntervalSinceNow:[timing[1] doubleValue]];}
    __block NSUInteger revision=0;dispatch_sync(dispatch_get_main_queue(),^{revision=self.generation;});
    dispatch_queue_t worker=foreground?self.foregroundQueue:self.backgroundQueue;
    dispatch_async(worker, ^{
        NSString *error=nil;NSString *name=ConversationTitle(record.window,&error,^BOOL{__block BOOL current=NO;dispatch_sync(dispatch_get_main_queue(),^{current=self.generation==revision;});return current&&[self eligible:record foreground:foreground];});
        dispatch_async(self.queue, ^{
            if(foreground)self.foregroundBusy=NO;else self.backgroundBusy=NO;
            __block BOOL current=NO;dispatch_sync(dispatch_get_main_queue(),^{current=self.generation==revision;});
            if(!current||![self allowed]||record.sourceRevision!=sourceRevision)return;
            if(name)[self applySource:name record:record foreground:foreground];
            else[self log:@"source_read_failed_or_role_changed" record:record error:nil];
        });
    });
}
- (NSArray<NSString *> *)scan {
    if(![self allowed]||!AXIsProcessTrusted())return @[@"Accessibility permission required"];
    NSArray *timing=[self timingSnapshot];
    NSArray<WindowRecord *> *candidates=[self discover];WindowRecord *foreground=nil,*due=nil;
    NSDate *now=NSDate.date;
    for(WindowRecord *record in candidates) {
        BOOL isForeground=[self active:record];
        if(record.hasObservedRole && record.observedForeground!=isForeground)record.sourceRevision++;
        record.hasObservedRole=YES;record.observedForeground=isForeground;
        if(isForeground){foreground=record;continue;}
        NSString *current=AXString(record.window,kAXTitleAttribute);if(!current)continue;
        [self releaseChangedLease:record current:current];
        // Generic reset repair uses cached source data, never a new source read.
        if([self generic:current]&&record.cachedTitle){record.manualOverride=NO;if([self write:record wanted:record.cachedTitle expected:current foreground:NO])[self log:@"background_reset_repaired_from_cache" record:record error:nil];}
        else if(![current isEqualToString:record.lastWritten]&&![self generic:current])record.manualOverride=YES;
        NSDate *recordDue=record.nextBackgroundRead?:NSDate.distantPast;
        NSDate *bestDue=due.nextBackgroundRead?:NSDate.distantPast;
        if([recordDue compare:now]!=NSOrderedDescending&&(!due||[recordDue compare:bestDue]==NSOrderedAscending))due=record;
    }
    if(foreground&&!self.foregroundBusy&&([timing[0] doubleValue]<=1||!foreground.nextForegroundRead||[foreground.nextForegroundRead compare:now]!=NSOrderedDescending))[self startSource:foreground foreground:YES];
    if(due&&!self.backgroundBusy)[self startSource:due foreground:NO];
    return @[[NSString stringWithFormat:@"Foreground source: %.1fs; background source: %.1fs",[timing[0] doubleValue],[timing[1] doubleValue]],@"Background reset repair: 1s, cached titles only"];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application=[NSApplication sharedApplication];
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        __attribute__((objc_precise_lifetime)) Monitor *monitor=[Monitor new];
        application.delegate=monitor;
        [application run];
    }
    return 0;
}
