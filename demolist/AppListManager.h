//
//  AppListManager.h
//  demolist
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppListManager : NSObject

/// 通过 installedPlugins 反推已安装应用（主 App 枚举已被系统滤空）
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)installedApps;

+ (void)logApps:(NSArray<NSDictionary<NSString *, NSString *> *> *)apps;

@end

NS_ASSUME_NONNULL_END
