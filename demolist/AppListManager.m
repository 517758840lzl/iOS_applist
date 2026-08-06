//
//  AppListManager.m
//  demolist
//

#import "AppListManager.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>

@implementation AppListManager

/// 安全地从 proxy / plugin 读取字符串属性（避免对 LSPlugInKitProxy 误用 KVC 崩溃）
+ (nullable NSString *)stringValueFrom:(NSObject *)object selectors:(NSArray<NSString *> *)names {
    for (NSString *name in names) {
        SEL sel = NSSelectorFromString(name);
        if (![object respondsToSelector:sel]) continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id value = [object performSelector:sel];
#pragma clang diagnostic pop
        if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
            return (NSString *)value;
        }
    }
    return nil;
}

/// 从 Extension bundleId 推断主 App bundleId
+ (NSString *)mainBundleIDFrom:(NSString *)bundleID {
    if (bundleID.length == 0) return bundleID;

    static NSArray<NSString *> *suffixes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        suffixes = @[
            @".WidgetExtension", @".widgetextension", @".Widget", @".Widgets",
            @".NotificationServiceExtension", @".NotificationContentExtension",
            @".notificationserviceextension", @".notificationcontentextension",
            @".ShareExtension", @".shareextension", @".ActionExtension",
            @".action-extension", @".IntentExtension", @".IntentsExtension",
            @".ReplayKit", @".replaykit", @".BroadcastUploadExtension",
            @".FileProvider", @".TodayExtension", @".appex"
        ];
    });

    NSString *result = bundleID;
    for (NSString *suffix in suffixes) {
        if ([result.lowercaseString hasSuffix:suffix.lowercaseString]) {
            result = [result substringToIndex:result.length - suffix.length];
            break;
        }
    }

    // 常见：xxx.SomethingExtension → 去掉最后一段
    if ([result.lowercaseString containsString:@"extension"] ||
        [result.lowercaseString containsString:@"widget"]) {
        NSRange lastDot = [result rangeOfString:@"." options:NSBackwardsSearch];
        if (lastDot.location != NSNotFound && lastDot.location > 0) {
            result = [result substringToIndex:lastDot.location];
        }
    }
    return result;
}

+ (BOOL)isLikelySystemBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) return YES;
    NSArray<NSString *> *prefixes = @[
        @"com.apple.", @"com.apple", @"com.animoji.", @"com.bitstrips."
    ];
    for (NSString *p in prefixes) {
        if ([bundleID hasPrefix:p]) return YES;
    }
    return NO;
}

+ (nullable NSArray *)invokeArraySelector:(NSString *)selName on:(NSObject *)workspace {
    SEL sel = NSSelectorFromString(selName);
    if (![workspace respondsToSelector:sel]) {
        NSLog(@"AppListManager: selector %@ not found", selName);
        return nil;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id result = [workspace performSelector:sel];
#pragma clang diagnostic pop
    if (![result isKindOfClass:[NSArray class]]) {
        NSLog(@"AppListManager: %@ returned non-array: %@", selName, [result class]);
        return nil;
    }
    NSLog(@"AppListManager: %@ count=%lu", selName, (unsigned long)[(NSArray *)result count]);
    return (NSArray *)result;
}

+ (void)collectFromProxies:(NSArray *)proxies
                 intoNames:(NSMutableDictionary<NSString *, NSString *> *)nameByBundle
                     label:(NSString *)label {
    NSUInteger added = 0;
    for (NSObject *proxy in proxies) {
        @try {
            NSString *bundleID = [self stringValueFrom:proxy selectors:@[
                @"applicationIdentifier", @"bundleIdentifier", @"pluginIdentifier"
            ]];
            NSString *name = [self stringValueFrom:proxy selectors:@[
                @"localizedName", @"itemName", @"name"
            ]];

            if (!bundleID && !name) continue;

            NSString *mainID = bundleID ? [self mainBundleIDFrom:bundleID] : (name ?: @"");
            if ([self isLikelySystemBundleID:mainID]) continue;

            if (nameByBundle[mainID] == nil) {
                nameByBundle[mainID] = name.length ? name : mainID;
                added++;
            } else if (name.length && [nameByBundle[mainID] isEqualToString:mainID]) {
                nameByBundle[mainID] = name;
            }
        } @catch (NSException *exception) {
            NSLog(@"AppListManager: skipped one proxy (%@) — %@", label, exception.reason);
            continue;
        }
    }
    NSLog(@"AppListManager: %@ unique added=%lu, map total=%lu",
          label, (unsigned long)added, (unsigned long)nameByBundle.count);
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)installedApps {
    @try {
        NSMutableDictionary<NSString *, NSString *> *nameByBundle = [NSMutableDictionary dictionary];

        // ---- Primary: LSApplicationWorkspace（多种 selector）----
        // 注意：iOS 15+ 上 allApplications / allInstalledApplications 在普通签名 App 里经常直接返回 0；
        // 真机上往往只有 installedPlugins（App Extension）还能拿到数据，再反推主 App。
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        if (!workspaceClass) {
            // 部分环境需要先加载框架
            void *cs = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY);
            if (!cs) {
                dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
            }
            workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        }
        NSLog(@"AppListManager: LSApplicationWorkspace class=%@", workspaceClass ?: @"(nil)");

        if (workspaceClass) {
            SEL defaultWorkspaceSel = NSSelectorFromString(@"defaultWorkspace");
            if ([workspaceClass respondsToSelector:defaultWorkspaceSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                NSObject *workspace = [workspaceClass performSelector:defaultWorkspaceSel];
#pragma clang diagnostic pop
                if (workspace) {
                    NSArray<NSString *> *selectors = @[
                        @"allInstalledApplications",
                        @"allApplications",
                        @"installedApplications",
                        @"installedPlugins",
                    ];
                    for (NSString *selName in selectors) {
                        NSArray *list = [self invokeArraySelector:selName on:workspace];
                        if (list.count > 0) {
                            [self collectFromProxies:list intoNames:nameByBundle label:selName];
                        }
                    }
                } else {
                    NSLog(@"AppListManager: defaultWorkspace returned nil");
                }
            }
        }

        // ---- Fallback: MobileInstallationBrowse（现代系统基本已失效）----
        if (nameByBundle.count == 0) {
            void *lib = dlopen("/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation", RTLD_LAZY);
            NSLog(@"AppListManager: MobileInstallation dlopen=%p", lib);
            if (lib) {
                typedef int (*MIBrowseFunc)(CFDictionaryRef, CFDictionaryRef, CFArrayRef *);
                MIBrowseFunc Browse = (MIBrowseFunc)dlsym(lib, "MobileInstallationBrowse");
                NSLog(@"AppListManager: MobileInstallationBrowse=%p", Browse);
                if (Browse) {
                    CFArrayRef cfApps = NULL;
                    int ret = Browse((__bridge CFDictionaryRef)@{},
                                     (__bridge CFDictionaryRef)@{},
                                     &cfApps);
                    NSLog(@"AppListManager: MobileInstallationBrowse ret=%d cfApps=%p", ret, cfApps);
                    if (ret == 0 && cfApps) {
                        NSArray *miApps = (__bridge_transfer NSArray *)cfApps;
                        for (id item in miApps) {
                            if (![item isKindOfClass:[NSDictionary class]]) continue;
                            NSDictionary *info = (NSDictionary *)item;
                            NSString *bundleID = info[@"CFBundleIdentifier"];
                            NSString *name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
                            if (!bundleID && !name) continue;
                            NSString *key = bundleID ?: name;
                            if ([self isLikelySystemBundleID:key]) continue;
                            if (nameByBundle[key] == nil) {
                                nameByBundle[key] = name.length ? name : key;
                            }
                        }
                    }
                }
                dlclose(lib);
            }
        }

        NSMutableArray<NSDictionary<NSString *, NSString *> *> *apps = [NSMutableArray array];
        [nameByBundle enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, NSString *name, BOOL *stop) {
            [apps addObject:@{ @"name": name, @"bundleID": bundleID }];
        }];
        [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
        }];

        NSLog(@"AppListManager: final unique apps=%lu", (unsigned long)apps.count);
        return apps;
    } @catch (NSException *exception) {
        NSLog(@"AppListManager error: %@", exception);
        return @[];
    }
}

@end
