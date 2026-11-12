// Foundation-only integration checks. No AX, NSApplication, or editor launch.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#import "../../shared/macos/RulesClient.h"

static void Require(BOOL condition,NSString *message) {
    if(!condition){fprintf(stderr,"rules_client_check_failed:%s\n",message.UTF8String);exit(1);}
}
static NSString *Await(CTSRulesClient *client,NSString *raw,NSTimeInterval seconds) {
    NSTimeInterval until=NSProcessInfo.processInfo.systemUptime+seconds;
    do {
        NSString *value=[client resolve:raw];
        if(value)return value;
        [NSThread sleepForTimeInterval:0.01];
    }while(NSProcessInfo.processInfo.systemUptime<until);
    return nil;
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        Require(argc==2,@"pass the compiled companion path");
        NSFileManager *manager=NSFileManager.defaultManager;
        NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"CTSClientFixture-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSError *error=nil;
        Require([manager createDirectoryAtPath:root withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error],@"create private GUID directory");
        @try {
            NSString *worker=[root stringByAppendingPathComponent:@"owned-rules-worker"];
            NSString *rules=[root stringByAppendingPathComponent:@"rules.json"];
            NSString *state=[root stringByAppendingPathComponent:@"state"];
            CTSRulesClient *empty=[[CTSRulesClient alloc] initWithExecutablePath:worker rulesPath:rules stateDirectory:state];
            Require([[empty resolve:@"Example chat A"] isEqualToString:@"Example chat A"],@"absent rules are immediate identity");
            Require(![manager fileExistsAtPath:rules],@"read must not create rule preference");
            [empty dispose];
            NSDictionary *settings=@{@"schema_version":@1,@"enabled":@YES,@"revision":NSUUID.UUID.UUIDString,
                @"rules":@[@{@"enabled":@YES,@"mode":@"literal",@"pattern":@"Work / ",@"replacement":@""}]};
            NSData *bytes=[NSJSONSerialization dataWithJSONObject:settings options:0 error:&error];
            Require([bytes writeToFile:rules options:NSDataWritingAtomic error:&error],@"write owned rules");
            CTSRulesClient *client=[[CTSRulesClient alloc] initWithExecutablePath:worker rulesPath:rules stateDirectory:state];
            NSString *raw=@"Work / Example chat A";
            Require([[Await(client,raw,3) description] isEqualToString:raw],@"missing worker falls back to complete raw");
            uint64_t before=client.displayRevision;
            Require([manager copyItemAtPath:[NSString stringWithUTF8String:argv[1]] toPath:worker error:&error],@"restore owned worker");
            Require([manager setAttributes:@{NSFilePosixPermissions:@0700} ofItemAtPath:worker error:&error],@"make owned worker executable");
            // Wait for the documented sub-second file-signature poll; no source
            // acquisition occurs anywhere in this fixture or rules client.
            [NSThread sleepForTimeInterval:1.0];
            NSString *actual=Await(client,raw,4);
            Require([actual isEqualToString:@"Example chat A"],@"same rules and raw recover after helper restoration");
            Require(client.displayRevision>before,@"display generation advances without source generation");
            Require([[NSData dataWithContentsOfFile:rules] isEqualToData:bytes],@"formatting preserves preference bytes");
            [client publishSources:@[raw,@"示例 😀"]];
            NSData *packet=[NSData dataWithContentsOfFile:client.sourcePath];
            Require(packet.length>=8&&memcmp(packet.bytes,"CTS1",4)==0,@"Unicode source snapshot has CTS1 header");
            uint32_t count=0;memcpy(&count,(const uint8_t *)packet.bytes+4,4);
            Require(CFSwapInt32LittleToHost(count)==2,@"source snapshot keeps two fictional raw names");
            [client dispose];
            NSString *captionRules=[root stringByAppendingPathComponent:@"caption-rules.json"];
            CTSRulesClient *captions=[[CTSRulesClient alloc] initWithExecutablePath:worker rulesPath:captionRules stateDirectory:[root stringByAppendingPathComponent:@"caption-state"] captionMode:YES];
            Require([[captions resolve:raw] isEqualToString:[raw stringByAppendingString:@" — ChatGPT"]],@"missing preference keeps default suffix");
            Require(![manager fileExistsAtPath:captionRules],@"caption identity read must not create a preference");
            NSMutableDictionary *captionSettings=[@{@"schema_version":@1,@"enabled":@NO,@"append_chatgpt_suffix":@NO,@"revision":NSUUID.UUID.UUIDString,@"rules":@[]} mutableCopy];
            Require([[NSJSONSerialization dataWithJSONObject:captionSettings options:0 error:&error] writeToFile:captionRules options:NSDataWritingAtomic error:&error],@"write suffix-off configuration");
            [NSThread sleepForTimeInterval:1.0];
            Require([Await(captions,raw,4) isEqualToString:raw],@"empty disabled rules still honor suffix off");
            uint64_t captionRevision=captions.displayRevision;
            captionSettings[@"append_chatgpt_suffix"]=@YES;captionSettings[@"revision"]=NSUUID.UUID.UUIDString;
            Require([[NSJSONSerialization dataWithJSONObject:captionSettings options:0 error:&error] writeToFile:captionRules options:NSDataWritingAtomic error:&error],@"write suffix-on configuration");
            [NSThread sleepForTimeInterval:1.0];
            Require([Await(captions,raw,4) isEqualToString:[raw stringByAppendingString:@" — ChatGPT"]],@"same source hot-updates only display");
            Require(captions.displayRevision>captionRevision,@"caption preference changes display revision");
            captionSettings[@"append_chatgpt_suffix"]=@NO;captionSettings[@"enabled"]=@YES;
            captionSettings[@"rules"]=@[@{@"enabled":@YES,@"mode":@"regex",@"pattern":@"(",@"replacement":@""}];
            captionSettings[@"revision"]=NSUUID.UUID.UUIDString;
            Require([[NSJSONSerialization dataWithJSONObject:captionSettings options:0 error:&error] writeToFile:captionRules options:NSDataWritingAtomic error:&error],@"write owned invalid-regex configuration");
            [NSThread sleepForTimeInterval:1.0];
            Require([Await(captions,raw,4) isEqualToString:raw],@"regex failure preserves raw and valid suffix-off setting");
            [captions dispose];
            printf("{\"passed\":true,\"checks\":7,\"scope\":\"private_files_owned_worker_no_UI_no_AX\"}\n");
        } @finally {
            // root is generated above, never supplied by an argument or prefs.
            [manager removeItemAtPath:root error:nil];
        }
    }
    return 0;
}
