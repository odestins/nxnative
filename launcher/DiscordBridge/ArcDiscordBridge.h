#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^ASDiscordCompletion)(NSDictionary<NSString *, id> * _Nullable result, NSString * _Nullable error);
@interface ASDiscordBridge : NSObject
@property(nonatomic, copy, nullable) void (^eventHandler)(NSString *event, NSString *value);
+ (BOOL)compiledAvailable;
+ (NSNumber * _Nullable)parseSnowflake:(NSString *)value;
- (instancetype)initWithApplicationID:(uint64_t)applicationID;
- (void)tick;
- (BOOL)cancelAuthorization;
- (NSDictionary<NSString *, id> *)snapshot;
- (void)perform:(NSString *)action parameters:(NSDictionary<NSString *, id> *)parameters completion:(ASDiscordCompletion)completion NS_SWIFT_DISABLE_ASYNC;
@end
NS_ASSUME_NONNULL_END
