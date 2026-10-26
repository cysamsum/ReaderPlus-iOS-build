#import "RPAudioAudit.h"
#import "RPSpeech.h"
#import "RPAudioCache.h"
#import <UIKit/UIKit.h>
#import <stdlib.h>
@interface RPAudioAudit()
@property(nonatomic,strong)RPSpeech *speech;
@property(nonatomic,strong)ReaderPlusSpeechConnection *connection;
@property(nonatomic,strong)NSTimer *timer;
@property(nonatomic,strong)NSDate *deadline;
@property(nonatomic,strong)NSMutableDictionary *report;
@property(nonatomic,copy)NSString *phase,*failure;
@property(nonatomic)NSUInteger requestsBeforeOffline,pausedPositionCount;
@property(nonatomic,strong)NSMutableArray *onlinePositions;
@property(nonatomic,strong)NSDate *pauseStarted;
@property(nonatomic)BOOL onlinePausedOnce;
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
-(void)beginOnlinePrefetch{
 self.phase=@"online-prefetch";self.deadline=[NSDate dateWithTimeIntervalSinceNow:90];
 NSUserDefaults *d=[NSUserDefaults standardUserDefaults];[d setObject:@"微软在线与已下载音频" forKey:@"compat.mode"];[d setBool:YES forKey:@"speech.consent"];
 NSString *run=[NSString stringWithFormat:@"%u",arc4random_uniform(1000000)];
 NSArray *texts=@[[NSString stringWithFormat:@"这是提前缓冲的第一段。朗读这一段时，后面的内容已经发送到语音服务。下一段不需要等本段读完才开始准备。测试编号，%@。",run],[NSString stringWithFormat:@"这是提前准备的第二段，测试编号，%@。",run],[NSString stringWithFormat:@"跨过空章节，继续播放第三段，测试编号，%@。",run]];
 NSDictionary *document=@{@"title":@"Prefetch regression",@"sections":@[@{@"paragraphs":@[texts[0],texts[1]]},@{@"paragraphs":@[]},@{@"paragraphs":@[texts[2]]}]};
 self.onlinePositions=[NSMutableArray array];__weak typeof(self) weak=self;
 self.speech.moved=^(NSInteger section,NSInteger paragraph){[weak.onlinePositions addObject:@{@"section":@(section),@"paragraph":@(paragraph)}];};
 [self.speech start:document section:0 paragraph:0];
}
-(void)check{
 if(self.failure){[self save:NO message:self.failure];return;}
 if(self.deadline.timeIntervalSinceNow<=0){[self save:NO message:[@"Timed out in phase " stringByAppendingString:self.phase]];return;}
 if([self.phase isEqual:@"online-prefetch"]&&self.speech.active){
  if(!self.onlinePausedOnce&&!self.speech.loading){[self.speech pauseOrResume];self.onlinePausedOnce=YES;self.pauseStarted=[NSDate date];self.pausedPositionCount=self.onlinePositions.count;}
  else if(self.pauseStarted&&-[self.pauseStarted timeIntervalSinceNow]>=1){
   if(!self.speech.paused||self.onlinePositions.count!=self.pausedPositionCount){[self save:NO message:@"Lookahead changed playback while paused."];return;}
   self.report[@"pauseDidNotAdvance"]=@YES;self.pauseStarted=nil;[self.speech pauseOrResume];
  }
 }
 if(self.speech.active)return;
 if([self.phase isEqual:@"system"]){self.report[@"systemSpeechCompleted"]=@YES;self.phase=@"synthesizing";self.deadline=[NSDate dateWithTimeIntervalSinceNow:45];self.connection=[ReaderPlusSpeechConnection new];__weak typeof(self) weak=self;
  [self.connection synthesize:@"你好，这是离线播放验证。" voice:@"zh-CN-XiaoxiaoNeural" locale:@"zh-CN" rate:0 completion:^(NSData *audio,NSError *error){RPAudioAudit *s=weak;if(!s)return;if(error){[s save:NO message:error.localizedDescription];return;}NSError *writeError=nil;if(!RPStoreAudio(audio,@"你好，这是离线播放验证。",@"zh-CN-XiaoxiaoNeural",0,&writeError)){[s save:NO message:writeError.localizedDescription];return;}NSUserDefaults *d=[NSUserDefaults standardUserDefaults];[d setObject:@"仅播放离线音频" forKey:@"compat.mode"];[d setObject:@"zh-CN-XiaoxiaoNeural" forKey:@"speech.voice"];[d setBool:NO forKey:@"speech.consent"];s.requestsBeforeOffline=RPNetworkSynthesisCount();s.phase=@"cached";s.report[@"downloadedAudioBytes"]=@(audio.length);s.deadline=[NSDate dateWithTimeIntervalSinceNow:20];[s.speech start:[s document:@"你好，这是离线播放验证。"]section:0 paragraph:0];}];return;
 }
 if([self.phase isEqual:@"cached"]){
  self.report[@"cachedSpeechCompleted"]=@YES;NSUInteger requests=RPNetworkSynthesisCount()-self.requestsBeforeOffline;self.report[@"networkRequestsDuringOfflinePlayback"]=@(requests);
  if(requests){[self save:NO message:@"Offline playback unexpectedly opened a synthesis connection."];return;}[self beginOnlinePrefetch];return;
 }
 if([self.phase isEqual:@"online-prefetch"]){
  NSDictionary *stats=[self.speech playbackStatistics];self.report[@"onlinePrefetch"]=stats;self.report[@"onlinePositions"]=self.onlinePositions;
  NSArray *expected=@[@{@"section":@0,@"paragraph":@0},@{@"section":@0,@"paragraph":@1},@{@"section":@2,@"paragraph":@0}];
  BOOL passed=[self.onlinePositions isEqual:expected]&&[stats[@"bufferedTransitions"]unsignedIntegerValue]==2&&[stats[@"unbufferedTransitions"]unsignedIntegerValue]==0&&[stats[@"requestsBeforeFirstPlayback"]unsignedIntegerValue]>=2&&[stats[@"lookaheadPreparedWhilePlaying"]unsignedIntegerValue]>=1&&[stats[@"maximumTransitionGapSeconds"]doubleValue]<1.0&&[self.report[@"pauseDidNotAdvance"]boolValue];
  self.report[@"onlinePrefetchCompleted"]=@(passed);[self save:passed message:passed?@"System and offline playback completed; online lookahead prepared consecutive paragraphs with no network-wait transitions, correct chapter order and pause/resume.":@"Online lookahead regression failed; inspect playback counters and paragraph order."];
 }
}
@end
