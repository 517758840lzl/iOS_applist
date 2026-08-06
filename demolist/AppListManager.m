//
//  AppListManager.m
//  demolist
//

#import "AppListManager.h"
#import <dlfcn.h>

@implementation AppListManager

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)installedApps {
    @try {
        NSMutableArray<NSDictionary<NSString *, NSString *> *> *apps = [NSMutableArray array];

        // ---- Primary: LSApplicationWorkspace with "allApplications" ----
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        if (workspaceClass) {
            SEL defaultWorkspaceSel = NSSelectorFromString(@"defaultWorkspace");
            if ([workspaceClass respondsToSelector:defaultWorkspaceSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                NSObject *workspace = [workspaceClass performSelector:defaultWorkspaceSel];
#pragma clang diagnostic pop
                if (workspace) {
                    SEL allAppsSel = NSSelectorFromString(@"allApplications");
                    if ([workspace respondsToSelector:allAppsSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        NSArray *appProxies = [workspace performSelector:allAppsSel];
#pragma clang diagnostic pop
                        if (appProxies && [appProxies isKindOfClass:[NSArray class]]) {
                            for (NSObject *proxy in appProxies) {
                                @try {
                                    NSString *name = [proxy valueForKey:@"localizedName"];
                                    if (name) {
                                        [apps addObject:@{ @"name": name }];
                                    }
                                } @catch (NSException *exception) {
                                    NSLog(@"AppListManager: skipped one proxy — %@", exception.reason);
                                    continue;
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Fallback: MobileInstallationBrowse ----
        if (apps.count == 0) {
            void *lib = dlopen("/System/Library/PrivateFrameworks/MobileInstallation.framework/MobileInstallation", RTLD_LAZY);
            if (lib) {
                typedef int (*MIBrowseFunc)(CFDictionaryRef, CFDictionaryRef, CFArrayRef *);
                MIBrowseFunc Browse = (MIBrowseFunc)dlsym(lib, "MobileInstallationBrowse");
                if (Browse) {
                    CFArrayRef cfApps = NULL;
                    int ret = Browse((__bridge CFDictionaryRef)@{},
                                     (__bridge CFDictionaryRef)@{},
                                     &cfApps);
                    if (ret == 0 && cfApps) {
                        NSArray *miApps = (__bridge_transfer NSArray *)cfApps;
                        for (id item in miApps) {
                            @try {
                                if (![item isKindOfClass:[NSDictionary class]]) continue;
                                NSDictionary *info = (NSDictionary *)item;
                                NSString *name = info[@"CFBundleDisplayName"]
                                              ?: info[@"CFBundleName"];
                                if (name) {
                                    [apps addObject:@{ @"name": name }];
                                }
                            } @catch (NSException *exception) {
                                NSLog(@"AppListManager MI: skipped — %@", exception.reason);
                                continue;
                            }
                        }
                    }
                }
                dlclose(lib);
            }
        }

        return apps;
    } @catch (NSException *exception) {
        NSLog(@"AppListManager error: %@", exception);
        return @[];
    }
}

@end
