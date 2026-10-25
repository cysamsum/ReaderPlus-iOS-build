#import <Foundation/Foundation.h>
NSString *RPCurrentVoice(void);
NSString *RPCurrentMode(void);
NSData *RPCachedAudio(NSString *text,NSString *voice,NSInteger rate);
BOOL RPStoreAudio(NSData *audio,NSString *text,NSString *voice,NSInteger rate,NSError **error);
@interface RPDownload:NSObject
@property(nonatomic,readonly)BOOL active;
-(void)start:(NSDictionary*)document progress:(void(^)(NSUInteger,NSUInteger))progress completion:(void(^)(NSError*))completion;
-(void)cancel;
@end
