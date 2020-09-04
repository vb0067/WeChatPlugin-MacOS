//
//  TKVersionManager.h
//  WeChatPlugin
//
//  Created by TK on 2018/2/24.
//  Copyright © 2018年 tk. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, TKVersionStatus) {
    TKVersionStatusOld,
    TKVersionStatusNew,
};

/**
 版本自动更新
 */
@interface TKVersionManager : NSObject

+ (instancetype _Nullable )shareManager;
- (void)checkVersionFinish:(void (^)(TKVersionStatus, NSString *))finish;
- (void)downloadPluginProgress:(void (^)(NSProgress *downloadProgress))downloadProgressBlock completionHandler:(void (^)(NSString *filePath, NSError * _Nullable error))completionHandler;
- (void)cancelDownload;

@end
