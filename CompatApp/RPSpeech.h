#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "RPAudioPipeline.h"
NSString *RPXMLEscape(NSString *text);
// Punctuation, whitespace and control characters alone need no audio.
BOOL RPHasSpeechContent(NSString *text);
NSUInteger RPNetworkSynthesisCount(void);
@interface ReaderPlusSpeechConnection:NSObject<ReaderPlusAudioRequest>
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
-(NSDictionary*)playbackStatistics;
@end
