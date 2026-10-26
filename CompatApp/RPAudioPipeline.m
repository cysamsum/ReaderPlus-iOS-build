#import "RPAudioPipeline.h"
#import "RPAudioCache.h"
#import "RPSpeech.h"

@interface ReaderPlusAudioSegment()
@property(nonatomic,readwrite)NSInteger section,paragraph;
@property(nonatomic,copy,readwrite)NSString *text;
@property(nonatomic,strong,readwrite)NSData *audio;
@property(nonatomic,strong,readwrite)NSError *error;
@property(nonatomic,strong)id<ReaderPlusAudioRequest> request;
@end
@implementation ReaderPlusAudioSegment
@end

@interface ReaderPlusAudioPipeline()
@property(nonatomic,strong)NSDictionary *document;
@property(nonatomic,strong)NSMutableArray *queue;
@property(nonatomic,copy)NSString *voice,*locale;
@property(nonatomic)NSInteger rate,startSection,startParagraph,cursorSection,cursorParagraph;
@property(nonatomic)BOOL allowNetwork,active,notificationPending,pumping;
@property(nonatomic)NSUInteger generation;
@property(nonatomic,readwrite)NSUInteger networkRequestCount;
@property(nonatomic,copy)id<ReaderPlusAudioRequest>(^requestFactory)(void);
@end

@implementation ReaderPlusAudioPipeline
-(instancetype)initWithDocument:(NSDictionary*)document section:(NSInteger)section paragraph:(NSInteger)paragraph voice:(NSString*)voice rate:(NSInteger)rate allowNetwork:(BOOL)allowNetwork requestFactory:(id<ReaderPlusAudioRequest>(^)(void))factory{
 if((self=[super init])){
  self.document=document;self.startSection=MAX(0,section);self.startParagraph=MAX(0,paragraph);
  self.voice=voice;self.rate=MAX(-50,MIN(100,rate));self.allowNetwork=allowNetwork;
  NSArray *parts=[voice componentsSeparatedByString:@"-"];
  self.locale=parts.count>=2?[NSString stringWithFormat:@"%@-%@",parts[0],parts[1]]:@"zh-CN";
  self.queue=[NSMutableArray array];self.requestFactory=factory?:^id<ReaderPlusAudioRequest>(void){return [ReaderPlusSpeechConnection new];};
 }
 return self;
}
-(void)dealloc{for(ReaderPlusAudioSegment *segment in self.queue)[segment.request cancel];}
-(ReaderPlusAudioSegment*)currentSegment{return self.queue.firstObject;}
-(ReaderPlusAudioSegment*)nextSegment{return self.queue.count>1?self.queue[1]:nil;}
-(NSUInteger)bufferedCount{return self.queue.count;}
-(NSUInteger)inFlightCount{NSUInteger count=0;for(ReaderPlusAudioSegment *segment in self.queue)if(segment.request)count++;return count;}
-(void)notify{
 if(!self.active||self.notificationPending)return;
 self.notificationPending=YES;NSUInteger generation=self.generation;__weak typeof(self) weak=self;
 dispatch_async(dispatch_get_main_queue(),^{ReaderPlusAudioPipeline *s=weak;if(!s||!s.active||s.generation!=generation)return;s.notificationPending=NO;if(s.changed)s.changed();});
}
-(void)fill{
 NSArray *sections=self.document[@"sections"];
 while(self.queue.count<3&&self.cursorSection<(NSInteger)sections.count){
  NSArray *paragraphs=sections[self.cursorSection][@"paragraphs"];
  if(self.cursorParagraph>=(NSInteger)paragraphs.count){self.cursorSection++;self.cursorParagraph=0;continue;}
  NSInteger paragraph=self.cursorParagraph++;NSString *text=paragraphs[paragraph];
  if(!RPHasSpeechContent(text))continue;
  ReaderPlusAudioSegment *segment=[ReaderPlusAudioSegment new];segment.section=self.cursorSection;segment.paragraph=paragraph;
  segment.text=text;[self.queue addObject:segment];
 }
}
-(void)pump{
 if(!self.active||self.pumping)return;
 self.pumping=YES;
 for(ReaderPlusAudioSegment *segment in [self.queue copy]){
  if(segment.audio||segment.error||segment.request)continue;
  segment.audio=RPCachedAudio(segment.text,self.voice,self.rate);if(segment.audio)continue;
  if(!self.allowNetwork){segment.error=[NSError errorWithDomain:@"ReaderPlusSpeech" code:1 userInfo:@{NSLocalizedDescriptionKey:@"此段尚未下载。请联网下载全书离线音频并保持相同音色、语速，或允许在线朗读。"}];continue;}
  if(self.inFlightCount>=2)continue;
  BOOL duplicate=NO;for(ReaderPlusAudioSegment *other in self.queue)if(other.request&&[other.text isEqual:segment.text]){duplicate=YES;break;}
  if(duplicate)continue;
  id<ReaderPlusAudioRequest> request=self.requestFactory();
  if(!request){segment.error=[NSError errorWithDomain:@"ReaderPlusSpeech" code:1 userInfo:@{NSLocalizedDescriptionKey:@"无法创建语音连接。"}];continue;}
  segment.request=request;self.networkRequestCount++;NSUInteger generation=self.generation;__weak typeof(self) weak=self;
  [request synthesize:segment.text voice:self.voice locale:self.locale rate:self.rate completion:^(NSData *audio,NSError *error){
   void(^deliver)(void)=^{
    ReaderPlusAudioPipeline *s=weak;
    if(!s||!s.active||s.generation!=generation||![s.queue containsObject:segment])return;
    segment.request=nil;NSError *result=error;
    if(!result&&!audio.length)result=[NSError errorWithDomain:@"ReaderPlusSpeech" code:1 userInfo:@{NSLocalizedDescriptionKey:@"语音服务未返回音频。"}];
    if(!result&&!RPStoreAudio(audio,segment.text,s.voice,s.rate,&result)&&!result)result=[NSError errorWithDomain:@"ReaderPlusSpeech" code:1 userInfo:@{NSLocalizedDescriptionKey:@"无法保存朗读音频。"}];
    segment.audio=result?nil:audio;segment.error=result;
    [s pump];[s notify];
   };
   if([NSThread isMainThread])deliver();else dispatch_async(dispatch_get_main_queue(),deliver);
  }];
 }
 self.pumping=NO;[self notify];
}
-(void)start{
 [self cancel];self.active=YES;self.networkRequestCount=0;self.cursorSection=self.startSection;self.cursorParagraph=self.startParagraph;
 [self fill];[self pump];
}
-(void)advance{
 if(!self.active)return;
 ReaderPlusAudioSegment *current=self.currentSegment;[current.request cancel];current.request=nil;
 if(current)[self.queue removeObjectAtIndex:0];[self fill];[self pump];
}
-(void)cancel{
 self.active=NO;self.generation++;self.notificationPending=NO;
 for(ReaderPlusAudioSegment *segment in self.queue){[segment.request cancel];segment.request=nil;}
 [self.queue removeAllObjects];
}
@end
