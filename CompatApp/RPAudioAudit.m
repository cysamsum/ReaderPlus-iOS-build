#import "RPAudioAudit.h"
#import "RPSpeech.h"
#import "RPAudioCache.h"
#import <UIKit/UIKit.h>
@interface RPAudioAudit()
@property(nonatomic,strong)RPSpeech *speech;
@property(nonatomic,strong)RPConnection *connection;
@property(nonatomic,strong)NSTimer *timer;
@property(nonatomic,strong)NSDate *deadline;
@property(nonatomic,strong)NSMutableDictionary *report;
@property(nonatomic,copy)NSString *phase,*failure;
@property(nonatomic)NSUInteger requestsBeforeOffline;
@end
@implementation RPAudioAudit
-(NSDictionary*)document:(NSString*)text{return @{@"title":@"Audio regression test",@"sections":@[@{@"id":@0,@"title":@"test",@"paragraphs":@[text]}]};}
-(void)save:(BOOL)passed message:(NSString*)message{
 [self.timer invalidate];self.timer=nil;[self.speech stop];[self.connection cancel];self.report[@"passed"]=@(passed);self.report[@"message"]=message?:@"";
 NSString *path=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES)[0]stringByAppendingPathComponent:@"audio-regression.json"];
 [[NSJSONSerialization dataWithJSONObject:self.report options:NSJSONWritingPrettyPrinted error:nil]writeToFile:path atomically:YES];NSLog(@"AUDIO_REGRESSION %@",self.report);
}
-(void)run{
 self.report=[@{@"systemVersion":[UIDevice currentDevice].systemVersion}mutableCopy];
 NSArray *voices=[AVSpeechSynthesisVoice speechVoices];AVSpeechSynthesisVoice *voice=nil;for(AVSpeechSynthesisVoice *v in voices)if([v.language hasPrefix:@"en"]){voice=v;break;}if(!voice)voice=voices.firstObject;
 if(!voice){[self save:NO message:@"Simulator has no installed system voices; actual system synthesis remains unverified."];return;}
 NSUserDefaults *d=[NSUserDefaults standardUserDefaults];[d setObject:@"系统语音（离线）" forKey:@"compat.mode"];[d setObject:[voice.language stringByAppendingString:@"-TestNeural"]forKey:@"speech.voice"];[d setInteger:0 forKey:@"speech.rate"];
 self.phase=@"system";self.speech=[RPSpeech new];__weak typeof(self) weak=self;self.speech.failed=^(NSString *message){weak.failure=message;};
 [self.speech start:[self document:@"Hello. This is the offline system speech test."]section:0 paragraph:0];self.deadline=[NSDate dateWithTimeIntervalSinceNow:30];self.timer=[NSTimer scheduledTimerWithTimeInterval:.2 target:self selector:@selector(check) userInfo:nil repeats:YES];
}
-(void)check{
 if(self.failure){[self save:NO message:self.failure];return;}
 if(self.deadline.timeIntervalSinceNow<=0){[self save:NO message:[@"Timed out in phase " stringByAppendingString:self.phase]];return;}
 if(self.speech.active)return;
 if([self.phase isEqual:@"system"]){self.report[@"systemSpeechCompleted"]=@YES;self.phase=@"synthesizing";self.deadline=[NSDate dateWithTimeIntervalSinceNow:45];self.connection=[RPConnection new];__weak typeof(self) weak=self;
  [self.connection synthesize:@"你好，这是离线播放验证。" voice:@"zh-CN-XiaoxiaoNeural" locale:@"zh-CN" rate:0 completion:^(NSData *audio,NSError *error){RPAudioAudit *s=weak;if(!s)return;if(error){[s save:NO message:error.localizedDescription];return;}NSError *writeError=nil;if(!RPStoreAudio(audio,@"你好，这是离线播放验证。",@"zh-CN-XiaoxiaoNeural",0,&writeError)){[s save:NO message:writeError.localizedDescription];return;}NSUserDefaults *d=[NSUserDefaults standardUserDefaults];[d setObject:@"仅播放离线音频" forKey:@"compat.mode"];[d setObject:@"zh-CN-XiaoxiaoNeural" forKey:@"speech.voice"];[d setBool:NO forKey:@"speech.consent"];s.requestsBeforeOffline=RPNetworkSynthesisCount();s.phase=@"cached";s.report[@"downloadedAudioBytes"]=@(audio.length);s.deadline=[NSDate dateWithTimeIntervalSinceNow:20];[s.speech start:[s document:@"你好，这是离线播放验证。"]section:0 paragraph:0];}];return;
 }
 if([self.phase isEqual:@"cached"]){self.report[@"cachedSpeechCompleted"]=@YES;NSUInteger requests=RPNetworkSynthesisCount()-self.requestsBeforeOffline;self.report[@"networkRequestsDuringOfflinePlayback"]=@(requests);[self save:requests==0 message:@"System synthesis and downloaded MP3 playback both completed; offline playback made no synthesis requests."];}
}
@end
