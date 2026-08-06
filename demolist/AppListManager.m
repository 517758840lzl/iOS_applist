//
//  AppListManager.m
//  demolist
//

#import "AppListManager.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>

@implementation AppListManager

+ (void)logApps:(NSArray<NSDictionary<NSString *, NSString *> *> *)apps {
    NSData *json = [NSJSONSerialization dataWithJSONObject:apps
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:nil];
    if (json) {
        NSLog(@"AppListManager:\n%@", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
    }
}

#pragma mark - Helpers

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

/// 尝试从 PlugIn 拿到宿主 App 的 bundleId（比后缀猜测更准）
+ (nullable NSString *)containingAppBundleIDFrom:(NSObject *)proxy {
    // LSPlugInKitProxy 常见：containingBundle / containingApplication → LSBundleProxy / LSApplicationProxy
    for (NSString *selName in @[ @"containingBundle", @"containingApplication" ]) {
        SEL sel = NSSelectorFromString(selName);
        if (![proxy respondsToSelector:sel]) continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id host = [proxy performSelector:sel];
#pragma clang diagnostic pop
        if (![host isKindOfClass:[NSObject class]]) continue;
        NSString *bid = [self stringValueFrom:(NSObject *)host selectors:@[
            @"bundleIdentifier", @"applicationIdentifier"
        ]];
        if (bid.length > 0) return bid;
    }
    return nil;
}

/// 是否含中日韩字符
+ (BOOL)hasCJK:(NSString *)s {
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= 0x4E00 && c <= 0x9FFF) return YES;
    }
    return NO;
}

/// 判断显示名是否像 Extension / Widget 技术名（只用于名称择优，不参与 bundleId 合并）
+ (BOOL)isExtensionName:(NSString *)name {
    if (name.length == 0) return NO;
    if ([name containsString:@"扩展"] || [name containsString:@"小组件"]) return YES;

    NSString *lower = [[name lowercaseString]
                       stringByReplacingOccurrencesOfString:@" " withString:@""];
    static NSArray<NSString *> *keywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keywords = @[
            @"widget", @"extension", @"intent", @"notification",
            @"broadcast", @"liveactivity", @"replay", @"fileprovider",
            @"packettunnel", @"siripay", @"handler", @"shortcut"
        ];
    });
    for (NSString *kw in keywords) {
        if ([lower containsString:kw]) return YES;
    }
    // 无中文的纯技术短名：Push / Intents / Shortcuts / WidgetExtension
    if (![self hasCJK:name] && ![name containsString:@" "]) {
        if ([lower isEqualToString:@"push"] ||
            [lower isEqualToString:@"intents"] ||
            [lower isEqualToString:@"shortcuts"] ||
            [lower hasSuffix:@"widget"] ||
            [lower hasSuffix:@"extension"] ||
            [lower hasSuffix:@"ext"]) {
            return YES;
        }
    }
    return NO;
}

/// 末段是否像 Extension 组件名（用于剥 bundleId）
/// 注意：不能把 Aweme / IHexin / MPBBank / pushMessage 这类主 App 末段剥掉
+ (BOOL)isExtensionSegment:(NSString *)segment {
    if (segment.length == 0) return NO;
    NSString *lower = segment.lowercaseString;

    // 强特征：子串命中即可（很少出现在主 App 末段）
    static NSArray<NSString *> *strong;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        strong = @[
            @"widget", @"extension", @"intent", @"notification",
            @"broadcast", @"replay", @"liveactivity", @"fileprovider",
            @"packettunnel", @"appex", @"shortcut", @"handler",
            @"shareimage", @"sharetimeline", @"screencapture",
            @"flashtransfer", @"audiotransfer", @"tmallmarket",
            @"siripay", @"walletnotification", @"walletsiri",
            @"platform", @"matter"
        ];
    });
    for (NSString *t in strong) {
        if ([lower containsString:t]) return YES;
    }

    // 弱特征：整段等于这些词才剥（避免 pushMessage 被误剥）
    static NSArray<NSString *> *exact;
    static dispatch_once_t onceToken2;
    dispatch_once(&onceToken2, ^{
        exact = @[
            @"today", @"push", @"share", @"siri", @"tunnel",
            @"shortcuts", @"intents", @"widget", @"appex"
        ];
    });
    if ([exact containsObject:lower]) return YES;

    // KimiPushExt / NotificationService222 / push12
    if ([lower hasSuffix:@"ext"] && lower.length > 3) return YES;
    if ([lower hasSuffix:@"ui"] && [lower containsString:@"siri"]) return YES;
    if ([lower hasPrefix:@"push"] && lower.length > 4 &&
        [lower rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location != NSNotFound) {
        return YES;
    }
    // EQToday 等：以 today 结尾的复合段
    if ([lower hasSuffix:@"today"] && lower.length > 5) return YES;

    return NO;
}

/// 从 Extension / Plugin bundleId 推断主 App bundleId
+ (NSString *)mainBundleIDFrom:(NSString *)bundleID {
    if (bundleID.length == 0) return bundleID;

    // 1) 已知后缀（精确）
    static NSArray<NSString *> *suffixes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        suffixes = @[
            @".widgetextension", @".widgets", @".widget",
            @".notificationserviceextension", @".notificationcontentextension",
            @".notificationservice", @".notificationcontent",
            @".notificationservices", @".notification",
            @".shareextension", @".share",
            @".broadcastuploadextension", @".broadcast",
            @".actionextension", @".action-extension",
            @".intentextension", @".intentsextension",
            @".intentsui", @".intents",
            @".liveactivity",
            @".pushextension", @".pushnotificationattachment",
            @".videopushnotification", @".push",
            @".replaykit", @".fileprovider", @".todayextension",
            @".appex", @".today", @".packettunnel", @".shortcuts",
            @".siripay", @".siripayui",
        ];
    });

    NSString *result = bundleID;
    NSString *lower = result.lowercaseString;
    for (NSString *suffix in suffixes) {
        if ([lower hasSuffix:suffix]) {
            result = [result substringToIndex:result.length - suffix.length];
            lower = result.lowercaseString;
            break;
        }
    }

    // 2) 循环剥「像 Extension」的末段，直到不能再剥
    //    覆盖：.ShareImage / .EQToday / .WeChatScreenCapture / .imeituanNotificationContentPlatform
    while (YES) {
        NSArray<NSString *> *parts = [result componentsSeparatedByString:@"."];
        if (parts.count < 3) break; // 至少保留 com.vendor.app
        NSString *last = parts.lastObject;
        if (![self isExtensionSegment:last]) break;
        result = [[parts subarrayWithRange:NSMakeRange(0, parts.count - 1)]
                  componentsJoinedByString:@"."];
    }
    return result;
}

+ (BOOL)isLikelySystemBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) return YES;
    return [bundleID hasPrefix:@"com.apple."] ||
           [bundleID isEqualToString:@"com.apple"] ||
           [bundleID hasPrefix:@"com.animoji."] ||
           [bundleID hasPrefix:@"com.bitstrips."];
}

/// 两个显示名择优：真实 App 名 > Extension 技术名；中文优先于纯英文技术名
+ (NSString *)preferredName:(NSString *)existing candidate:(NSString *)candidate mainID:(NSString *)mainID {
    if (candidate.length == 0) return existing;
    if (existing.length == 0 || [existing isEqualToString:mainID]) return candidate;

    BOOL oldExt = [self isExtensionName:existing];
    BOOL newExt = [self isExtensionName:candidate];
    if (oldExt && !newExt) return candidate;
    if (!oldExt && newExt) return existing;

    BOOL oldCJK = [self hasCJK:existing];
    BOOL newCJK = [self hasCJK:candidate];
    if (!oldCJK && newCJK) return candidate;
    if (oldCJK && !newCJK) return existing;

    // 都正常或都是 extension：保留已有
    return existing;
}

#pragma mark - Collect / Merge

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
            NSString *rawBundleID = [self stringValueFrom:proxy selectors:@[
                @"applicationIdentifier", @"bundleIdentifier", @"pluginIdentifier"
            ]];
            NSString *name = [self stringValueFrom:proxy selectors:@[
                @"localizedName", @"itemName", @"name"
            ]];

            if (!rawBundleID && !name) continue;

            // 优先用 PlugIn 宿主 App；否则用后缀/末段推断
            NSString *hostID = [self containingAppBundleIDFrom:proxy];
            NSString *mainID = hostID.length
                ? hostID
                : (rawBundleID ? [self mainBundleIDFrom:rawBundleID] : (name ?: @""));
            if ([self isLikelySystemBundleID:mainID]) continue;

            if (nameByBundle[mainID] == nil) {
                nameByBundle[mainID] = name.length ? name : mainID;
                added++;
            } else {
                nameByBundle[mainID] = [self preferredName:nameByBundle[mainID]
                                                 candidate:name
                                                    mainID:mainID];
            }
        } @catch (NSException *exception) {
            NSLog(@"AppListManager: skipped one proxy (%@) — %@", label, exception.reason);
            continue;
        }
    }
    NSLog(@"AppListManager: %@ unique added=%lu, map total=%lu",
          label, (unsigned long)added, (unsigned long)nameByBundle.count);
}

/// 二次合并：若 A 是 B 的前缀（B = A.xxx），则把 B 并入 A
/// 解决剥段后仍残留的父子重复，例如 com.taobao.taobao4iphone vs ...TmallMarket
+ (void)mergePrefixChildren:(NSMutableDictionary<NSString *, NSString *> *)nameByBundle {
    NSArray<NSString *> *keys = [nameByBundle.allKeys
                                 sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        // 短的在前，优先作为父 key
        if (a.length != b.length) return a.length < b.length ? NSOrderedAscending : NSOrderedDescending;
        return [a compare:b];
    }];

    NSMutableArray<NSString *> *toRemove = [NSMutableArray array];
    for (NSUInteger i = 0; i < keys.count; i++) {
        NSString *child = keys[i];
        if ([toRemove containsObject:child]) continue;

        NSString *bestParent = nil;
        for (NSUInteger j = 0; j < i; j++) {
            NSString *parent = keys[j];
            if ([toRemove containsObject:parent]) continue;
            // child 必须以 parent. 开头
            NSString *prefix = [parent stringByAppendingString:@"."];
            if ([child hasPrefix:prefix]) {
                // 取最长父前缀（keys 已按长度升序，后面的更长）
                bestParent = parent;
            }
        }
        if (!bestParent) continue;

        nameByBundle[bestParent] = [self preferredName:nameByBundle[bestParent]
                                             candidate:nameByBundle[child]
                                                mainID:bestParent];
        [toRemove addObject:child];
    }
    [nameByBundle removeObjectsForKeys:toRemove];
    if (toRemove.count > 0) {
        NSLog(@"AppListManager: prefix-merge removed %lu children, remaining=%lu",
              (unsigned long)toRemove.count, (unsigned long)nameByBundle.count);
    }
}

#pragma mark - Public

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)installedApps {
    @try {
        NSMutableDictionary<NSString *, NSString *> *nameByBundle = [NSMutableDictionary dictionary];

        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        if (!workspaceClass) {
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
                    // 主 App 列表优先（名称更准），再 plugins
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
                            NSString *key = bundleID ? [self mainBundleIDFrom:bundleID] : name;
                            if ([self isLikelySystemBundleID:key]) continue;
                            if (nameByBundle[key] == nil) {
                                nameByBundle[key] = name.length ? name : key;
                            } else {
                                nameByBundle[key] = [self preferredName:nameByBundle[key]
                                                              candidate:name
                                                                 mainID:key];
                            }
                        }
                    }
                }
                dlclose(lib);
            }
        }

        // 关键：父子 bundleId 前缀合并（修你列表里剩的重复）
        [self mergePrefixChildren:nameByBundle];

        NSMutableArray<NSDictionary<NSString *, NSString *> *> *apps = [NSMutableArray array];
        [nameByBundle enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, NSString *name, BOOL *stop) {
            // 最终再滤一遍仍像 extension 名且无更好名称的项：保留，但可标出来
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
