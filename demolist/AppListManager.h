//
//  AppListManager.h
//  demolist
//
//  封装 LSApplicationWorkspace 私有 API，获取设备已安装应用列表
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppListManager : NSObject

/// 获取设备已安装应用列表
/// @return 包含 name / bundleID / version 的字典数组
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)installedApps;

@end

NS_ASSUME_NONNULL_END
