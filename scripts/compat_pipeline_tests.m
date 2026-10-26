#import <Foundation/Foundation.h>
#import "RPAudioPipeline.h"
#import "RPAudioCache.h"
#import "RPSpeech.h"

@interface ReaderPlusFakeAudioRequest:NSObject<ReaderPlusAudioRequest>
@property(nonatomic,copy)NSString *text,*voice;
@property(nonatomic)NSInteger rate;
@property(nonatomic)BOOL cancelled;
@property(nonatomic,copy)void(^completion)(NSData*,NSError*);
@end
@implementation ReaderPlusFakeAudioRequest
-(void)synthesize:(NSString*)text voice:(NSString*)voice locale:(NSString*)locale rate:(NSInteger)rate completion:(void(^)(NSData*,NSError*))completion{self.text=text;self.voice=voice;self.rate=rate;self.completion=completion;}
-(void)cancel{self.cancelled=YES;self.completion=nil;}
-(void)finish:(NSData*)audio error:(NSError*)error{void(^done)(NSData*,NSError*)=self.completion;self.completion=nil;if(done)done(audio,error);}
@end

static NSDictionary *testDocument(NSArray *first,NSArray *second){return @{@"sections":@[@{@"paragraphs":first},@{@"paragraphs":@[]},@{@"paragraphs":second}]};}
static ReaderPlusAudioPipeline *pipeline(NSDictionary *document,NSString *voice,BOOL online,NSMutableArray *requests){
 return [[ReaderPlusAudioPipeline alloc]initWithDocument:document section:0 paragraph:0 voice:voice rate:20 allowNetwork:online requestFactory:^id<ReaderPlusAudioRequest>(void){ReaderPlusFakeAudioRequest *r=[ReaderPlusFakeAudioRequest new];[requests addObject:r];return r;}];
}
static void drain(void){[[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];}
void ReaderPlusRunPipelineTests(void){
 NSString *unique=[NSUUID UUID].UUIDString;
 NSArray *texts=@[[unique stringByAppendingString:@"-0"],[unique stringByAppendingString:@"-1"],[unique stringByAppendingString:@"-2"],[unique stringByAppendingString:@"-3"]];
 NSData *audio=[NSMutableData dataWithLength:256];NSMutableArray *requests=[NSMutableArray array];
 ReaderPlusAudioPipeline *p=pipeline(testDocument(@[texts[0],texts[1]],@[texts[2],texts[3]]),@"pipeline-test-voice",YES,requests);
 [p start];NSCAssert(p.bufferedCount==3&&p.inFlightCount==2&&requests.count==2,@"Prepare current and next concurrently, bounded to two requests and three segments");
 ReaderPlusFakeAudioRequest *first=requests[0],*second=requests[1];
 [second finish:audio error:nil];
 NSCAssert(!p.currentSegment.audio&&p.currentSegment.paragraph==0&&p.nextSegment.audio,@"Out-of-order next response must not advance or play before current");
 NSCAssert(requests.count==3&&p.inFlightCount==2,@"Refill the free request slot while current is still pending");
 [first finish:audio error:nil];NSCAssert(p.currentSegment.audio,@"Current response is now ready");
 [p advance];NSCAssert(p.currentSegment.section==0&&p.currentSegment.paragraph==1&&p.currentSegment.audio,@"Advance directly to buffered audio");
 NSCAssert(requests.count==4&&p.bufferedCount==3&&p.inFlightCount==2,@"Lookahead stays bounded after advancing");
 for(ReaderPlusFakeAudioRequest *r in [requests copy])if(r.completion)[r finish:audio error:nil];
 [p advance];NSCAssert(p.currentSegment.section==2&&p.currentSegment.paragraph==0,@"Cross chapter boundaries and skip empty chapters in order");
 [p advance];[p advance];NSCAssert(!p.currentSegment&&p.inFlightCount==0&&requests.count==4,@"No request beyond the end of the book");[p cancel];

 // A late reply from a cancelled session must neither cache nor signal playback.
 NSString *cancelText=[unique stringByAppendingString:@"-cancel"];
 [requests removeAllObjects];p=pipeline(testDocument(@[cancelText],@[]),@"cancel-test-voice",YES,requests);__block NSUInteger notifications=0;p.changed=^{notifications++;};
 [p start];ReaderPlusFakeAudioRequest *cancelled=requests[0];void(^late)(NSData*,NSError*)=[cancelled.completion copy];[p cancel];late(audio,nil);drain();
 NSCAssert(cancelled.cancelled&&!p.currentSegment&&notifications==0&&!RPCachedAudio(cancelText,@"cancel-test-voice",20),@"Stop/seek cancels requests and rejects stale callbacks before cache writes");
 [p start];NSCAssert(p.inFlightCount==1&&requests.count==2,@"A new generation starts independently");late(audio,nil);NSCAssert(!p.currentSegment.audio,@"Previous-generation reply cannot satisfy restarted playback");[p cancel];

 // Errors in lookahead are deferred until that position becomes current.
 [requests removeAllObjects];p=pipeline(testDocument(@[[unique stringByAppendingString:@"-ok"],[unique stringByAppendingString:@"-fail"]],@[]),@"error-test-voice",YES,requests);[p start];
 [(ReaderPlusFakeAudioRequest*)requests[0]finish:audio error:nil];NSError *error=[NSError errorWithDomain:@"test" code:7 userInfo:nil];[(ReaderPlusFakeAudioRequest*)requests[1]finish:nil error:error];
 NSCAssert(p.currentSegment.audio&&!p.currentSegment.error,@"A lookahead failure must not interrupt the current paragraph");[p advance];NSCAssert(p.currentSegment.error==error,@"Report the failure at its actual book position");[p cancel];

 // Offline mode never opens a connection, including for lookahead cache misses.
 [requests removeAllObjects];p=pipeline(testDocument(@[[unique stringByAppendingString:@"-offline-miss"]],@[]),@"offline-test",NO,requests);[p start];NSCAssert(p.currentSegment.error&&requests.count==0,@"Offline miss must not synthesize");[p cancel];
 p=pipeline(testDocument(@[texts[0]],@[texts[1],texts[2]]),@"pipeline-test-voice",NO,requests);[p start];NSCAssert(p.currentSegment.audio&&p.nextSegment.audio&&requests.count==0,@"Prefetch existing offline files without opening a connection");[p cancel];

 // Repeated paragraphs share an in-flight request and then reuse the saved audio.
 [requests removeAllObjects];NSString *repeat=[unique stringByAppendingString:@"-repeat"];p=pipeline(testDocument(@[repeat,repeat],@[]),@"repeat-test",YES,requests);[p start];NSCAssert(requests.count==1,@"Coalesce duplicate text requests");[(ReaderPlusFakeAudioRequest*)requests[0]finish:audio error:nil];NSCAssert(p.currentSegment.audio&&p.nextSegment.audio&&requests.count==1,@"Repeated text reuses the completed request");[p cancel];
 // Skip non-speech paragraphs without changing source positions or hiding real errors.
 NSArray *silent=@[@"",@"。",@"！",@"…",@"——",@"，；：？！",@"\"'()[]{}",@" \t\r\n　",@"\u200B\uFEFF",@"𐄀"];
 for(NSString *text in silent)NSCAssert(!RPHasSpeechContent(text),@"Ignore punctuation and invisible text: %@",text);
 NSCAssert(!RPHasSpeechContent(nil),@"Ignore missing text");
 for(NSString *text in @[@"中",@"A",@"1",@"你好。",@"£",@"😀",@"𠀀"])NSCAssert(RPHasSpeechContent(text),@"Retain letters, numbers and symbols: %@",text);
 NSDictionary *punctuated=testDocument(@[@"。",texts[0],@"…",@"——",texts[1]],@[@"！",texts[2],@"。"]);
 [requests removeAllObjects];p=pipeline(punctuated,@"pipeline-test-voice",NO,requests);[p start];
 NSCAssert(p.currentSegment.paragraph==1&&p.nextSegment.paragraph==4&&p.bufferedCount==3&&requests.count==0,@"Skip leading and consecutive punctuation, preserve original positions and fill lookahead");
 [p advance];[p advance];NSCAssert(p.currentSegment.section==2&&p.currentSegment.paragraph==1&&p.currentSegment.audio,@"Skip punctuation across chapters in offline mode");[p advance];NSCAssert(!p.currentSegment,@"Trailing punctuation ends playback normally");[p cancel];
 [requests removeAllObjects];NSString *after=[unique stringByAppendingString:@"-after-punctuation"];
 p=pipeline(testDocument(@[@"。",after,@"！"],@[]),@"punctuation-online",YES,requests);[p start];
 NSCAssert(requests.count==1&&[[(ReaderPlusFakeAudioRequest*)requests[0]text]isEqual:after]&&p.currentSegment.paragraph==1,@"Only actual text reaches Microsoft");
 [(ReaderPlusFakeAudioRequest*)requests[0]finish:nil error:error];NSCAssert(p.currentSegment.error==error,@"Normal text failures remain visible");[p cancel];
 [requests removeAllObjects];p=pipeline(testDocument(silent,silent),@"punctuation-only",YES,requests);[p start];NSCAssert(!p.currentSegment&&requests.count==0&&p.networkRequestCount==0,@"All-punctuation books need no synthesis");[p cancel];
 p=[[ReaderPlusAudioPipeline alloc]initWithDocument:punctuated section:0 paragraph:2 voice:@"pipeline-test-voice" rate:20 allowNetwork:NO requestFactory:nil];[p start];NSCAssert(p.currentSegment.paragraph==4&&p.currentSegment.audio,@"Starting on punctuation resumes at the next original text position");[p cancel];
 // Whole-book download shares the filter, including cached books and empty totals.
 NSUInteger before=RPNetworkSynthesisCount();RPDownload *download=[RPDownload new];__block BOOL completed=NO;__block NSUInteger total=99,done=99;
 [download start:testDocument(silent,silent) progress:^(NSUInteger n,NSUInteger t){done=n;total=t;}completion:^(NSError *e){NSCAssert(!e,@"Punctuation-only download succeeds");completed=YES;}];
 NSCAssert(completed&&done==0&&total==0&&!download.active&&RPNetworkSynthesisCount()==before,@"Punctuation-only download completes without network");
 NSUserDefaults *prefs=[NSUserDefaults standardUserDefaults];NSString *voice=RPCurrentVoice();NSInteger rate=MAX(-50,MIN(100,[prefs integerForKey:@"speech.rate"]));
 NSCAssert(RPStoreAudio(audio,texts[0],voice,rate,nil)&&RPStoreAudio(audio,texts[1],voice,rate,nil),@"Cache download fixture");completed=NO;
 [download start:testDocument(@[@"。",texts[0],@"！",texts[1]],silent) progress:^(NSUInteger n,NSUInteger t){done=n;total=t;}completion:^(NSError *e){NSCAssert(!e,@"Cached text download succeeds");completed=YES;}];
 NSCAssert(completed&&done==2&&total==2&&RPNetworkSynthesisCount()==before,@"Download progress counts only spoken paragraphs");
 drain();puts("PASS: ordered lookahead, punctuation skipping, original positions, download filtering, concurrency, cancellation and error propagation");
}
