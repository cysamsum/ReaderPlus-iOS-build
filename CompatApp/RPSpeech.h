#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
NSString *RPXMLEscape(NSString *text);
NSUInteger RPNetworkSynthesisCount(void);
@interface RPConnection:NSObject
-(void)synthesize:(NSString*)text voice:(NSString*)voice locale:(NSString*)locale rate:(NSInteger)rate completion:(void(^)(NSData*,NSError*))completion;
-(void)cancel;
@end
@interface RPSpeech:NSObject<AVAudioPlayerDelegate,AVSpeechSynthesizerDelegate>
@property(nonatomic,copy)void(^changed)(void);
@property(nonatomic,copy)void(^failed)(NSString*);
@property(nonatomic,copy)void(^moved)(NSInteger,NSInteger);
@property(nonatomic,readonly)BOOL active;
@property(nonatomic,readonly)BOOL paused;
@property(nonatomic,readonly)BOOL loading;
-(void)start:(NSDictionary*)document section:(NSInteger)section paragraph:(NSInteger)paragraph;
-(void)pauseOrResume;
-(void)stop;
@end
