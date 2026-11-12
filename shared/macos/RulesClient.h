#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Foundation-only bridge shared by the Swift and Objective-C monitors.
// Methods never read AX or modify a window; all formatting is delegated to an
// owned disposable companion, and raw source/restore leases stay with the owner.
FOUNDATION_EXPORT NSString *CTSRulesDefaultPath(void);
FOUNDATION_EXPORT NSString *CTSRulesCompanionPath(NSString *monitorExecutable);
FOUNDATION_EXPORT NSString *CTSRulesHelpPath(NSString *monitorExecutable);
@interface CTSRulesClient : NSObject
- (instancetype)initWithExecutablePath:(NSString *)executable rulesPath:(NSString *)rules stateDirectory:(NSString *)state NS_SWIFT_NAME(init(executablePath:rulesPath:stateDirectory:));
- (instancetype)initWithExecutablePath:(NSString *)executable rulesPath:(NSString *)rules stateDirectory:(NSString *)state captionMode:(BOOL)captionMode NS_SWIFT_NAME(init(executablePath:rulesPath:stateDirectory:captionMode:));
@property(nonatomic, readonly) BOOL captionMode;
@property(nonatomic, readonly) uint64_t displayRevision;
@property(nonatomic, readonly, copy) NSString *sourcePath;
- (void)poll;
// nil means a bounded asynchronous formatting request is pending.
- (nullable NSString *)resolve:(NSString *)raw NS_SWIFT_NAME(resolve(_:));
- (void)publishSources:(NSArray<NSString *> *)rawNames NS_SWIFT_NAME(publishSources(_:));
- (BOOL)openEditorWithHelpPath:(NSString *)help error:(NSError **)error;
- (void)dispose;
@end
FOUNDATION_EXPORT NSString * _Nullable CTSRulesOpenEditor(CTSRulesClient *client, NSString *help);
NS_ASSUME_NONNULL_END
