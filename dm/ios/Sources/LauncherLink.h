#import <Foundation/Foundation.h>

// Only app-owned Boolean HUD and UUID restore requests are accepted. A URL
// cannot choose a filesystem path or supply arbitrary environment variables.
static inline NSDictionary *dm_launcher_options(NSURL *url, NSString *expectedScheme) {
    if (!url || !expectedScheme.length || url.absoluteString.length > 256) return nil;
    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (![c.scheme isEqualToString:expectedScheme] || ![c.host isEqualToString:@"launch"] ||
        c.path.length || c.user || c.password || c.port || c.fragment || !c.queryItems.count || c.queryItems.count > 2) return nil;
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in c.queryItems) {
        if (result[item.name]) return nil;
        if ([item.name isEqualToString:@"hud"] && ([item.value isEqualToString:@"0"] || [item.value isEqualToString:@"1"])) result[item.name] = @([item.value isEqualToString:@"1"]);
        else if ([item.name isEqualToString:@"restore"] && [[NSUUID alloc] initWithUUIDString:item.value]) result[item.name] = item.value;
        else return nil;
    }
    return result;
}
static inline NSNumber *dm_launcher_hud_value(NSURL *url, NSString *scheme) { return dm_launcher_options(url, scheme)[@"hud"]; }
static inline NSString *dm_launcher_restore_value(NSURL *url, NSString *scheme) { return dm_launcher_options(url, scheme)[@"restore"]; }
