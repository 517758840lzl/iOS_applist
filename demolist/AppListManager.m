//
//  AppListManager.m
//  demolist
//

#import "AppListManager.h"

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

+ (nullable NSString *)containingAppBundleIDFrom:(NSObject *)proxy {
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

+ (BOOL)hasCJK:(NSString *)s {
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= 0x4E00 && c <= 0x9FFF) return YES;
    }
    return NO;
}

+ (BOOL)isExtensionName:(NSString *)name {
    if (name.length == 0) return NO;

    NSString *lower = [[[name lowercaseString]
                        stringByReplacingOccurrencesOfString:@" " withString:@""]
                       stringByReplacingOccurrencesOfString:@"-" withString:@""];
    static NSArray<NSString *> *keywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keywords = @[
            // Latin / API-style
            @"widget", @"extension", @"extensión", @"extensão", @"extensie",
            @"erweiterung", @"estensione", @"eklenti", @"plugin",
            @"intent", @"notification", @"broadcast", @"liveactivity",
            @"replay", @"fileprovider", @"packettunnel", @"siripay",
            @"handler", @"shortcut",
            // zh Hans / Hant
            @"扩展", @"擴展", @"小组件", @"小組件", @"插件", @"外掛",
            // ja
            @"拡張", @"ウィジェット", @"プラグイン",
            // ko
            @"확장", @"위젯", @"플러그인",
            // ru / pl
            @"расширение", @"виджет", @"rozszerzenie", @"widżet",
        ];
    });
    for (NSString *kw in keywords) {
        if ([lower containsString:kw]) return YES;
    }
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

+ (BOOL)isExtensionSegment:(NSString *)segment {
    if (segment.length == 0) return NO;
    NSString *lower = segment.lowercaseString;

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

    static NSArray<NSString *> *exact;
    static dispatch_once_t onceToken2;
    dispatch_once(&onceToken2, ^{
        exact = @[ @"today", @"push", @"share", @"siri", @"tunnel", @"shortcuts", @"intents", @"appex" ];
    });
    if ([exact containsObject:lower]) return YES;

    if ([lower hasSuffix:@"ext"] && lower.length > 3) return YES;
    if ([lower hasSuffix:@"ui"] && [lower containsString:@"siri"]) return YES;
    if ([lower hasPrefix:@"push"] && lower.length > 4 &&
        [lower rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location != NSNotFound) {
        return YES;
    }
    if ([lower hasSuffix:@"today"] && lower.length > 5) return YES;
    return NO;
}

+ (NSString *)mainBundleIDFrom:(NSString *)bundleID {
    if (bundleID.length == 0) return bundleID;

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
            break;
        }
    }

    while (YES) {
        NSArray<NSString *> *parts = [result componentsSeparatedByString:@"."];
        if (parts.count < 3) break;
        if (![self isExtensionSegment:parts.lastObject]) break;
        result = [[parts subarrayWithRange:NSMakeRange(0, parts.count - 1)] componentsJoinedByString:@"."];
    }
    return result;
}

+ (BOOL)isLikelySystemBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) return YES;
    return [bundleID hasPrefix:@"com.apple."] || [bundleID isEqualToString:@"com.apple"];
}

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
    return existing;
}

#pragma mark - Collect / Merge

+ (void)collectPlugins:(NSArray *)proxies into:(NSMutableDictionary<NSString *, NSString *> *)nameByBundle {
    for (NSObject *proxy in proxies) {
        @try {
            NSString *rawBundleID = [self stringValueFrom:proxy selectors:@[
                @"applicationIdentifier", @"bundleIdentifier", @"pluginIdentifier"
            ]];
            NSString *name = [self stringValueFrom:proxy selectors:@[
                @"localizedName", @"itemName", @"name"
            ]];
            if (!rawBundleID && !name) continue;

            NSString *hostID = [self containingAppBundleIDFrom:proxy];
            NSString *mainID = hostID.length
                ? hostID
                : (rawBundleID ? [self mainBundleIDFrom:rawBundleID] : name);
            if ([self isLikelySystemBundleID:mainID]) continue;

            if (nameByBundle[mainID] == nil) {
                nameByBundle[mainID] = name.length ? name : mainID;
            } else {
                nameByBundle[mainID] = [self preferredName:nameByBundle[mainID] candidate:name mainID:mainID];
            }
        } @catch (NSException *exception) {
            NSLog(@"AppListManager: skipped plugin — %@", exception.reason);
        }
    }
}

+ (void)mergePrefixChildren:(NSMutableDictionary<NSString *, NSString *> *)nameByBundle {
    NSArray<NSString *> *keys = [nameByBundle.allKeys
                                 sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
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
            if ([child hasPrefix:[parent stringByAppendingString:@"."]]) {
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
}

#pragma mark - Public

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)installedApps {
    @try {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        if (!workspaceClass) return @[];

        SEL defaultWorkspaceSel = NSSelectorFromString(@"defaultWorkspace");
        if (![workspaceClass respondsToSelector:defaultWorkspaceSel]) return @[];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSObject *workspace = [workspaceClass performSelector:defaultWorkspaceSel];
#pragma clang diagnostic pop
        if (!workspace) return @[];

        SEL pluginsSel = NSSelectorFromString(@"installedPlugins");
        if (![workspace respondsToSelector:pluginsSel]) return @[];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id plugins = [workspace performSelector:pluginsSel];
#pragma clang diagnostic pop
        if (![plugins isKindOfClass:[NSArray class]]) return @[];

        NSMutableDictionary<NSString *, NSString *> *nameByBundle = [NSMutableDictionary dictionary];
        [self collectPlugins:plugins into:nameByBundle];
        [self mergePrefixChildren:nameByBundle];

        NSMutableArray<NSDictionary<NSString *, NSString *> *> *apps = [NSMutableArray array];
        [nameByBundle enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, NSString *name, BOOL *stop) {
            [apps addObject:@{ @"name": name, @"bundleID": bundleID }];
        }];
        [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
        }];
        return apps;
    } @catch (NSException *exception) {
        NSLog(@"AppListManager error: %@", exception);
        return @[];
    }
}

@end
