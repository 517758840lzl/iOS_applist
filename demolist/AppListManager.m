//
//  AppListManager.m
//  demolist
//

#import "AppListManager.h"

@implementation AppListManager

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)installedApps {
    @try {
        NSMutableArray<NSDictionary<NSString *, NSString *> *> *apps = [NSMutableArray array];

        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        if (!workspaceClass) return @[];

        SEL defaultWorkspaceSel = NSSelectorFromString(@"defaultWorkspace");
        if (![workspaceClass respondsToSelector:defaultWorkspaceSel]) return @[];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSObject *workspace = [workspaceClass performSelector:defaultWorkspaceSel];
#pragma clang diagnostic pop
        if (!workspace) return @[];

        SEL allAppsSel = NSSelectorFromString(@"allInstalledApplications");
        if (![workspace respondsToSelector:allAppsSel]) return @[];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *appProxies = [workspace performSelector:allAppsSel];
#pragma clang diagnostic pop
        if (!appProxies) return @[];

        for (NSObject *proxy in appProxies) {
            NSString *bundleID = [proxy valueForKey:@"applicationIdentifier"] ?: @"";
            NSString *name      = [proxy valueForKey:@"localizedName"] ?: @"";
            NSString *version   = [proxy valueForKey:@"shortVersionString"] ?: @"";

            [apps addObject:@{
                @"name": name,
                @"bundleID": bundleID,
                @"version": version
            }];
        }

        return apps;
    } @catch (NSException *exception) {
        NSLog(@"AppListManager error: %@", exception);
        return @[];
    }
}

@end
