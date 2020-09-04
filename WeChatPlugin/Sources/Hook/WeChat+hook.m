//
//  WeChat+hook.m
//  WeChatPlugin
//
//  Created by TK on 2017/4/19.
//  Copyright © 2017年 tk. All rights reserved.
//

#import "WeChat+hook.h"
#import "WeChatPlugin.h"
#import "fishhook.h"
#import "TKIgnoreSessonModel.h"
#import "TKWebServerManager.h"
#import "TKMessageManager.h"
#import "TKAssistantMenuManager.h"
#import "TKAutoReplyModel.h"
#import "TKVersionManager.h"
#import "TKRemoteControlManager.h"
#import "TKDownloadWindowController.h"

@implementation NSObject (WeChatHook)

+ (void)hookWeChat {
    
    //      微信消息同步
    SEL syncBatchAddMsgsMethod = LargerOrEqualVersion(@"2.3.22") ? @selector(FFImgToOnFavInfoInfoVCZZ:isFirstSync:) : @selector(OnSyncBatchAddMsgs:isFirstSync:);
    tk_hookMethod(objc_getClass("MessageService"), syncBatchAddMsgsMethod, [self class], @selector(hook_OnSyncBatchAddMsgs:isFirstSync:));
    [self setup];
}

+ (void)setup {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        //        窗口置顶初始化
        [self setupWindowSticky];
    });
    [self checkPluginVersion];
    //    监听 NSWindow 最小化通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowsWillMiniaturize:) name:NSWindowWillMiniaturizeNotification object:nil];
}

+ (void)setupWindowSticky {
    BOOL onTop = [[TKWeChatPluginConfig sharedConfig] onTop];
    WeChat *wechat = [objc_getClass("WeChat") sharedInstance];
    wechat.mainWindowController.window.level = onTop == NSControlStateValueOn ? NSNormalWindowLevel+2 : NSNormalWindowLevel;
}

+ (void)checkPluginVersion {
    if ([[TKWeChatPluginConfig sharedConfig] forbidCheckVersion]) return;
    
    [[TKVersionManager shareManager] checkVersionFinish:^(TKVersionStatus status, NSString *message) {
        if (status == TKVersionStatusNew) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSAlert *alert = [[NSAlert alloc] init];
                [alert addButtonWithTitle:TKLocalizedString(@"assistant.update.alret.confirm")];
                [alert addButtonWithTitle:TKLocalizedString(@"assistant.update.alret.forbid")];
                [alert addButtonWithTitle:TKLocalizedString(@"assistant.update.alret.cancle")];
                [alert setMessageText:TKLocalizedString(@"assistant.update.alret.title")];
                [alert setInformativeText:message];
                NSModalResponse respose = [alert runModal];
                if (respose == NSAlertFirstButtonReturn) {
                    [[TKDownloadWindowController downloadWindowController] show];
                } else if (respose == NSAlertSecondButtonReturn) {
                    [[TKWeChatPluginConfig sharedConfig] setForbidCheckVersion:YES];
                }
            });
        }
    }];
}

/**
 hook 微信消息同步
 
 */
- (void)hook_OnSyncBatchAddMsgs:(NSArray *)msgs isFirstSync:(BOOL)arg2 {
    [self hook_OnSyncBatchAddMsgs:msgs isFirstSync:arg2];
    
    [msgs enumerateObjectsUsingBlock:^(AddMsg *addMsg, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDate *now = [NSDate date];
        NSTimeInterval nowSecond = now.timeIntervalSince1970;
        if (nowSecond - addMsg.createTime > 180) {      // 若是3分钟前的消息，则不进行自动回复与远程控制。
            return;
        }
        
        [self autoReplyWithMsg:addMsg];
        
        NSString *currentUserName = [objc_getClass("CUtility") GetCurrentUserName];
        if ([addMsg.fromUserName.string isEqualToString:currentUserName] &&
            [addMsg.toUserName.string isEqualToString:currentUserName]) {
            [self remoteControlWithMsg:addMsg];
            [self replySelfWithMsg:addMsg];
        }
    }];
}


#pragma mark - Other
/**
 自动回复
 
 @param addMsg 接收的消息
 */
- (void)autoReplyWithMsg:(AddMsg *)addMsg {
    //    addMsg.msgType != 49
    if (![[TKWeChatPluginConfig sharedConfig] autoReplyEnable]) return;
    if (addMsg.msgType != 1 && addMsg.msgType != 3) return;
    
    NSString *userName = addMsg.fromUserName.string;
    
    MMSessionMgr *sessionMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("MMSessionMgr")];
    unsigned int count; // 1
    Method *methods = class_copyMethodList([sessionMgr class], &count); // 2
    for (int i = 0; i < count; i++) { // 3
        const char *methodNameChar = sel_getName(method_getName(methods[i]));
        NSString *methodName = [[NSString alloc] initWithCString:methodNameChar encoding:NSUTF8StringEncoding];
        NSLog(@"%@", methodName); // 4
        Method result9 = class_getClassMethod([sessionMgr class], NSSelectorFromString(methodName));
          NSLog(@"%s", result9); // 4
        //
    } // 5
    WCContactData *msgContact = [sessionMgr getSessionContact:userName];
    if ([msgContact isBrandContact] || [msgContact isSelf]) {
        //        该消息为公众号或者本人发送的消息
        return;
    }
    NSArray *autoReplyModels = [[TKWeChatPluginConfig sharedConfig] autoReplyModels];
    [autoReplyModels enumerateObjectsUsingBlock:^(TKAutoReplyModel *model, NSUInteger idx, BOOL * _Nonnull stop) {
        if (!model.enable) return;
        if (!model.replyContent || model.replyContent.length == 0) return;
        
        if (model.enableSpecificReply) {
            if ([model.specificContacts containsObject:userName]) {
                [self replyWithMsg:addMsg model:model];
            }
            return;
        }
        if ([addMsg.fromUserName.string containsString:@"@chatroom"] && !model.enableGroupReply) return;
        if (![addMsg.fromUserName.string containsString:@"@chatroom"] && !model.enableSingleReply) return;
        
        [self replyWithMsg:addMsg model:model];
    }];
}

- (void)replyWithMsg:(AddMsg *)addMsg model:(TKAutoReplyModel *)model {
    NSString *msgContent = addMsg.content.string;
    if ([addMsg.fromUserName.string containsString:@"@chatroom"]) {
        NSRange range = [msgContent rangeOfString:@":\n"];
        if (range.length > 0) {
            msgContent = [msgContent substringFromIndex:range.location + range.length];
        }
    }
    
    NSArray *replyArray = [model.replyContent componentsSeparatedByString:@"|"];
    int index = arc4random() % replyArray.count;
    NSString *randomReplyContent = replyArray[index];
    NSInteger delayTime = model.enableDelay ? model.delayTime : 0;
    
    if (model.enableRegex) {
        NSString *regex = model.keyword;
        NSError *error;
        NSRegularExpression *regular = [NSRegularExpression regularExpressionWithPattern:regex options:NSRegularExpressionCaseInsensitive error:&error];
        if (error) return;
        NSInteger count = [regular numberOfMatchesInString:msgContent options:NSMatchingReportCompletion range:NSMakeRange(0, msgContent.length)];
        if (count > 0) {
            [[TKMessageManager shareManager] sendTextMessage:randomReplyContent toUsrName:addMsg.fromUserName.string delay:delayTime];
        }
    } else {
        NSArray * keyWordArray = [model.keyword componentsSeparatedByString:@"|"];
        [keyWordArray enumerateObjectsUsingBlock:^(NSString *keyword, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([keyword isEqualToString:@"*"] || [msgContent isEqualToString:keyword]) {
                [[TKMessageManager shareManager] sendTextMessage:randomReplyContent toUsrName:addMsg.fromUserName.string delay:delayTime];
                *stop = YES;
            }
        }];
    }
}


- (void)windowsWillMiniaturize:(NSNotification *)notification {
    NSObject *window = notification.object;
    ((NSWindow *)window).level =NSNormalWindowLevel;
}

@end
