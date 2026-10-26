#import "RPSpeech.h"
#import "RPGEC.h"
#import "RPAudioCache.h"
#import "SRWebSocket.h"
#import <TargetConditionals.h>
static NSString *const token=@"6A5AA1D4EAFF4E9FB37E23D68491D6F4";
static NSUInteger requestCount=0;
NSUInteger RPNetworkSynthesisCount(void){return requestCount;}
BOOL RPHasSpeechContent(NSString *text){
 static NSCharacterSet *content;static dispatch_once_t once;
 dispatch_once(&once,^{
  NSMutableCharacterSet *ignored=[[NSCharacterSet punctuationCharacterSet]mutableCopy];
  [ignored formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  [ignored formUnionWithCharacterSet:[NSCharacterSet controlCharacterSet]];
  content=[ignored invertedSet];
 });
 return text.length&&[text rangeOfCharacterFromSet:content].location!=NSNotFound;
}
static NSString *const agent=@"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0";
NSString *RPXMLEscape(NSString *text){
 NSMutableString *s=[NSMutableString string];for(NSUInteger i=0;i<text.length;i++){unichar c=[text characterAtIndex:i];if(c>=32||c==9||c==10||c==13)[s appendFormat:@"%C",c];}
 for(NSArray *p in @[@[@"&",@"&amp;"],@[@"<",@"&lt;"],@[@">",@"&gt;"],@[@"\"",@"&quot;"],@[@"'",@"&apos;"]])[s replaceOccurrencesOfString:p[0] withString:p[1] options:0 range:NSMakeRange(0,s.length)];return s;
}
static NSError *RPSpeechError(NSString *s){return [NSError errorWithDomain:@"ReaderPlusSpeech" code:1 userInfo:@{NSLocalizedDescriptionKey:s}];}
@interface ReaderPlusSpeechConnection()<SRWebSocketDelegate>
@property(nonatomic,strong)SRWebSocket *socket;
@property(nonatomic,strong)NSTimer *timer;
@property(nonatomic,strong)NSMutableData *audio;
@property(nonatomic,copy)NSString *text,*voice,*locale;
@property(nonatomic)NSInteger rate;
@property(nonatomic,copy)void(^completion)(NSData*,NSError*);
@end
@implementation ReaderPlusSpeechConnection
-(void)synthesize:(NSString*)text voice:(NSString*)voice locale:(NSString*)locale rate:(NSInteger)rate completion:(void(^)(NSData*,NSError*))completion{
 requestCount++;
 [self cancel];self.completion=completion;self.text=text;self.voice=voice;self.locale=locale;self.rate=MAX(-50,MIN(100,rate));self.audio=[NSMutableData data];
 char gec[82];rp_gec_v2((int64_t)[NSDate date].timeIntervalSince1970,gec);
 NSString *url=[NSString stringWithFormat:@"wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=%@&Sec-MS-GEC=%s&Sec-MS-GEC-Version=2-143.0.3650.75&ConnectionId=%@",token,gec,[[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""]];
 NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];request.timeoutInterval=35;
 [request setValue:agent forHTTPHeaderField:@"User-Agent"];[request setValue:@"chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold" forHTTPHeaderField:@"Origin"];
 [request setValue:[NSString stringWithFormat:@"muid=%@;",[[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""]] forHTTPHeaderField:@"Cookie"];
 self.socket=[[SRWebSocket alloc]initWithURLRequest:request];self.socket.delegate=self;
 self.timer=[NSTimer scheduledTimerWithTimeInterval:40 target:self selector:@selector(timedOut) userInfo:nil repeats:NO];[self.socket open];
}
-(void)timedOut{[self finish:nil error:RPSpeechError(@"语音请求超时，请检查网络或选择系统语音。")];}
-(void)cancel{[self.timer invalidate];self.timer=nil;self.socket.delegate=nil;[self.socket close];self.socket=nil;self.completion=nil;self.audio=nil;}
-(void)finish:(NSData*)audio error:(NSError*)error{void(^done)(NSData*,NSError*)=self.completion;[self cancel];if(done)done(audio,error);}
-(void)webSocketDidOpen:(SRWebSocket*)socket{
 if(socket!=self.socket)return;
 NSDateFormatter *formatter=[NSDateFormatter new];formatter.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];formatter.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];formatter.dateFormat=@"EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'";
 NSString *stamp=[formatter stringFromDate:[NSDate date]];
 NSString *config=[NSString stringWithFormat:@"X-Timestamp:%@\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}",stamp];
 NSString *ssml=[NSString stringWithFormat:@"<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='%@'><voice name='%@'><prosody rate='%+ld%%' pitch='+0Hz' volume='+0%%'>%@</prosody></voice></speak>",RPXMLEscape(self.locale),RPXMLEscape(self.voice),(long)self.rate,RPXMLEscape(self.text)];
 NSString *message=[NSString stringWithFormat:@"X-RequestId:%@\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:%@\r\nPath:ssml\r\n\r\n%@",[[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""],stamp,ssml];
 NSError *error=nil;if(![socket sendString:config error:&error]||![socket sendString:message error:&error])[self finish:nil error:error?:RPSpeechError(@"语音发送失败。")];
}
-(void)webSocket:(SRWebSocket*)socket didReceiveMessageWithData:(NSData*)frame{
 if(socket!=self.socket)return;const uint8_t *p=frame.bytes;
 if(frame.length<2){[self finish:nil error:RPSpeechError(@"语音帧损坏。")];return;}NSUInteger header=((NSUInteger)p[0]<<8)|p[1];
 if(header>frame.length-2){[self finish:nil error:RPSpeechError(@"语音帧长度无效。")];return;}
 NSString *s=[[NSString alloc]initWithBytes:p+2 length:header encoding:NSUTF8StringEncoding];
 if([[s componentsSeparatedByString:@"\r\n"]containsObject:@"Path:audio"])[self.audio appendBytes:p+2+header length:frame.length-2-header];
 if(self.audio.length>8*1024*1024)[self finish:nil error:RPSpeechError(@"音频响应过大。")];
}
-(void)webSocket:(SRWebSocket*)socket didReceiveMessageWithString:(NSString*)message{
 if(socket!=self.socket)return;NSString *header=[[message componentsSeparatedByString:@"\r\n\r\n"]firstObject];
 if([[header componentsSeparatedByString:@"\r\n"]containsObject:@"Path:turn.end"]){NSData *audio=[self.audio copy];[self finish:audio error:audio.length?nil:RPSpeechError(@"微软未返回音频，可尝试系统语音。")];}
}
-(void)webSocket:(SRWebSocket*)socket didFailWithError:(NSError*)error{if(socket==self.socket)[self finish:nil error:error];}
-(void)webSocket:(SRWebSocket*)socket didCloseWithCode:(NSInteger)code reason:(NSString*)reason wasClean:(BOOL)clean{if(socket==self.socket)[self finish:nil error:RPSpeechError(reason?:@"微软语音连接提前关闭。")];}
@end
#if TARGET_OS_IPHONE
@interface RPSpeech()
@property(nonatomic,strong)ReaderPlusAudioPipeline *pipeline;
@property(nonatomic,strong)ReaderPlusAudioSegment *playingSegment,*announcedSegment,*preparedSegment;
@property(nonatomic,strong)AVAudioPlayer *player,*preparedPlayer;
@property(nonatomic,strong)AVSpeechSynthesizer *synth;
@property(nonatomic,strong)AVSpeechUtterance *utterance;
@property(nonatomic,strong)NSDictionary *document;
@property(nonatomic,copy)NSString *mode,*voice,*locale;
@property(nonatomic)NSInteger section,paragraph,rate;
@property(nonatomic,readwrite)BOOL active,paused,loading;
@property(nonatomic)BOOL hasStartedAudio;
@property(nonatomic)NSUInteger generation,bufferedTransitions,unbufferedTransitions,preparedAhead,requestsBeforeFirstPlayback;
@property(nonatomic)NSTimeInterval lastFinishTime,maximumTransitionGap;
@end
@implementation RPSpeech
-(instancetype)init{
 if((self=[super init])){
  self.synth=[AVSpeechSynthesizer new];self.synth.delegate=self;
  [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(interrupted:) name:AVAudioSessionInterruptionNotification object:nil];
  [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(route:) name:AVAudioSessionRouteChangeNotification object:nil];
 }
 return self;
}
-(void)dealloc{[[NSNotificationCenter defaultCenter]removeObserver:self];[self.pipeline cancel];}
-(void)interrupted:(NSNotification*)n{if([n.userInfo[AVAudioSessionInterruptionTypeKey]integerValue]==AVAudioSessionInterruptionTypeBegan){if(self.loading)[self stop];else if(self.active&&!self.paused)[self pauseOrResume];}}
-(void)route:(NSNotification*)n{if([n.userInfo[AVAudioSessionRouteChangeReasonKey]integerValue]==AVAudioSessionRouteChangeReasonOldDeviceUnavailable){if(self.loading)[self stop];else if(self.active&&!self.paused)[self pauseOrResume];}}
-(void)notify{if(self.changed)self.changed();}
-(void)stop{
 self.generation++;self.pipeline.changed=nil;[self.pipeline cancel];self.pipeline=nil;
 [self.player stop];self.player=nil;[self.preparedPlayer stop];self.preparedPlayer=nil;
 self.playingSegment=nil;self.announcedSegment=nil;self.preparedSegment=nil;self.utterance=nil;
 [self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];self.active=NO;self.paused=NO;self.loading=NO;
 [[AVAudioSession sharedInstance]setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];[self notify];
}
-(void)fail:(NSError*)error{[self stop];if(self.failed)self.failed(error.localizedDescription?:@"朗读失败。");}
-(void)start:(NSDictionary*)document section:(NSInteger)section paragraph:(NSInteger)paragraph{
 [self stop];self.document=document;self.section=MAX(0,section);self.paragraph=MAX(0,paragraph);self.active=YES;
 self.bufferedTransitions=0;self.unbufferedTransitions=0;self.preparedAhead=0;self.requestsBeforeFirstPlayback=0;self.hasStartedAudio=NO;self.lastFinishTime=0;self.maximumTransitionGap=0;
 NSUserDefaults *prefs=[NSUserDefaults standardUserDefaults];self.mode=RPCurrentMode();self.voice=RPCurrentVoice();self.rate=MAX(-50,MIN(100,[prefs integerForKey:@"speech.rate"]));
 NSArray *parts=[self.voice componentsSeparatedByString:@"-"];self.locale=parts.count>=2?[NSString stringWithFormat:@"%@-%@",parts[0],parts[1]]:@"zh-CN";
 NSError *error=nil;[[AVAudioSession sharedInstance]setCategory:AVAudioSessionCategoryPlayback withOptions:0 error:&error];
 if(!error)[[AVAudioSession sharedInstance]setMode:AVAudioSessionModeSpokenAudio error:&error];
 if(!error)[[AVAudioSession sharedInstance]setActive:YES error:&error];if(error){[self fail:error];return;}
 if([self.mode isEqual:@"系统语音（离线）"]){[self nextSystemParagraph];return;}
 BOOL online=[self.mode isEqual:@"微软在线与已下载音频"]&&[prefs boolForKey:@"speech.consent"];
 self.loading=YES;self.pipeline=[[ReaderPlusAudioPipeline alloc]initWithDocument:document section:self.section paragraph:self.paragraph voice:self.voice rate:self.rate allowNetwork:online requestFactory:nil];
 NSUInteger generation=self.generation;__weak typeof(self) weak=self;
 self.pipeline.changed=^{RPSpeech *s=weak;if(s&&s.active&&s.generation==generation)[s updateBufferedPlayback];};
 [self.pipeline start];[self notify];
}
-(void)nextSystemParagraph{
 if(!self.active)return;NSArray *sections=self.document[@"sections"];
 while(self.section<(NSInteger)sections.count){
  NSArray *paragraphs=sections[self.section][@"paragraphs"];
  if(self.paragraph>=(NSInteger)paragraphs.count){self.section++;self.paragraph=0;continue;}
  if(RPHasSpeechContent(paragraphs[self.paragraph]))break;
  self.paragraph++;
 }
 if(self.section>=(NSInteger)sections.count){[self stop];return;}
 NSString *text=sections[self.section][@"paragraphs"][self.paragraph];if(self.moved)self.moved(self.section,self.paragraph);
 NSString *identifier=[[NSUserDefaults standardUserDefaults]stringForKey:@"compat.systemVoice"];
 AVSpeechSynthesisVoice *local=identifier.length?[AVSpeechSynthesisVoice voiceWithIdentifier:identifier]:[AVSpeechSynthesisVoice voiceWithLanguage:self.locale];
 if(!local){[self fail:RPSpeechError(@"设备没有安装该语言的系统音色。请先在 iOS 设置中下载，或重新选择系统音色。")];return;}
 self.loading=NO;self.utterance=[[AVSpeechUtterance alloc]initWithString:text];self.utterance.voice=local;
 self.utterance.rate=MAX(AVSpeechUtteranceMinimumSpeechRate,MIN(AVSpeechUtteranceMaximumSpeechRate,0.5*(1+self.rate/200.0)));
 [self.synth speakUtterance:self.utterance];[self notify];
}
-(void)prepareLookaheadPlayer{
 ReaderPlusAudioSegment *next=self.pipeline.nextSegment;
 if(next==self.preparedSegment)return;
 [self.preparedPlayer stop];self.preparedPlayer=nil;self.preparedSegment=nil;
 if(!next.audio)return;
 AVAudioPlayer *player=[[AVAudioPlayer alloc]initWithData:next.audio error:nil];
 if(player&&[player prepareToPlay]){self.preparedPlayer=player;self.preparedSegment=next;if(self.player.isPlaying)self.preparedAhead++;}
}
-(void)updateBufferedPlayback{
 if(!self.active||!self.pipeline)return;
 ReaderPlusAudioSegment *current=self.pipeline.currentSegment;if(!current){[self stop];return;}
 if(self.announcedSegment!=current){
  self.announcedSegment=current;self.section=current.section;self.paragraph=current.paragraph;
  if(self.moved)self.moved(self.section,self.paragraph);
 }
 if(current.error){[self fail:current.error];return;}
 if(!current.audio){self.loading=YES;[self notify];return;}
 if(self.playingSegment!=current){
  NSError *error=nil;AVAudioPlayer *player=nil;
  if(self.preparedSegment==current){player=self.preparedPlayer;self.preparedPlayer=nil;self.preparedSegment=nil;}
  else{player=[[AVAudioPlayer alloc]initWithData:current.audio error:&error];if(player&&![player prepareToPlay])player=nil;}
  if(!player){[self fail:error?:RPSpeechError(@"音频无法播放。")];return;}
  self.player=player;self.playingSegment=current;self.player.delegate=self;self.loading=NO;
  if(!self.hasStartedAudio){self.hasStartedAudio=YES;self.requestsBeforeFirstPlayback=self.pipeline.networkRequestCount;}
  if(!self.paused){
   if(![self.player play]){[self fail:RPSpeechError(@"音频无法播放。")];return;}
   if(self.lastFinishTime>0){self.maximumTransitionGap=MAX(self.maximumTransitionGap,[NSDate timeIntervalSinceReferenceDate]-self.lastFinishTime);self.lastFinishTime=0;}
  }
 }
 [self prepareLookaheadPlayer];[self notify];
}
-(void)pauseOrResume{
 // The loading button remains Cancel. Pausing a playing paragraph does not let
 // lookahead completions start a new player or advance the reading position.
 if(self.loading){[self stop];return;}if(!self.active)return;
 if(self.paused){
  NSError *error=nil;[[AVAudioSession sharedInstance]setActive:YES error:&error];
  if(error){[self fail:error];return;}
  if(self.player&&![self.player play]){[self fail:RPSpeechError(@"音频无法继续播放。")];return;}
  if(self.utterance)[self.synth continueSpeaking];
 }else{[self.player pause];[self.synth pauseSpeakingAtBoundary:AVSpeechBoundaryImmediate];}
 self.paused=!self.paused;[self notify];
}
-(void)audioPlayerDidFinishPlaying:(AVAudioPlayer*)player successfully:(BOOL)flag{
 if(player!=self.player||!self.active)return;if(!flag){[self fail:RPSpeechError(@"音频播放失败。")];return;}
 self.player=nil;self.playingSegment=nil;self.lastFinishTime=[NSDate timeIntervalSinceReferenceDate];
 [self.pipeline advance];
 if(self.pipeline.currentSegment){if(self.pipeline.currentSegment.audio)self.bufferedTransitions++;else self.unbufferedTransitions++;}
 [self updateBufferedPlayback];
}
-(void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer*)player error:(NSError*)error{if(player==self.player)[self fail:error?:RPSpeechError(@"音频解码失败。")];}
-(void)speechSynthesizer:(AVSpeechSynthesizer*)s didFinishSpeechUtterance:(AVSpeechUtterance*)u{if(u!=self.utterance||!self.active)return;self.utterance=nil;self.paragraph++;[self nextSystemParagraph];}
-(NSDictionary*)playbackStatistics{
 return @{@"bufferedTransitions":@(self.bufferedTransitions),@"unbufferedTransitions":@(self.unbufferedTransitions),@"lookaheadPreparedWhilePlaying":@(self.preparedAhead),@"requestsBeforeFirstPlayback":@(self.requestsBeforeFirstPlayback),@"maximumTransitionGapSeconds":@(self.maximumTransitionGap)};
}
@end
#endif
