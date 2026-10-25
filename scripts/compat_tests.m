#import <Foundation/Foundation.h>
#import "RPDocument.h"
#import "RPGEC.h"
#import "RPSpeech.h"
#import "RPAudioCache.h"
int main(int argc,char **argv){@autoreleasepool{
 char token[82];rp_gec_v2(1700000000,token);NSCAssert(!strcmp(token,"2CD23A2CA0B2595A-F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2"),@"GEC vector mismatch");
 const uint8_t gb[]={0xD6,0xD0,0xCE,0xC4};NSCAssert([RPDecode([NSData dataWithBytes:gb length:4])isEqual:@"中文"],@"GB18030 decode");
 NSString *s=[@"中文👨‍👩‍👧‍👦é。" stringByPaddingToLength:4000 withString:@"中文👨‍👩‍👧‍👦é。" startingAtIndex:0];NSArray *chunks=RPParagraphs(s);NSCAssert([[chunks componentsJoinedByString:@""]isEqual:s],@"Text lost at boundary");
 NSError *error=nil;NSDictionary *epub=RPImportDocument([NSURL fileURLWithPath:@"samples/体验电子书.epub"],@"sample",&error);NSCAssert(epub&&!error&&[epub[@"sections"]count]==2,@"EPUB sample import");NSCAssert([epub[@"sections"][0][@"title"]hasPrefix:@"第一章"],@"EPUB spine order");
 NSCAssert([RPXMLEscape(@"A & <B>")isEqual:@"A &amp; &lt;B&gt;"],@"XML escaping");
 NSString *unique=[NSUUID UUID].UUIDString;NSData *testAudio=[NSMutableData dataWithLength:256];NSError *cacheError=nil;NSCAssert(RPStoreAudio(testAudio,unique,@"test-voice",20,&cacheError),@"Offline write");NSCAssert([RPCachedAudio(unique,@"test-voice",20)isEqual:testAudio],@"Offline replay must load bytes without a connection");NSCAssert(!RPCachedAudio(unique,@"other-voice",20)&&!RPCachedAudio(unique,@"test-voice",50),@"Voice and speed must isolate cache entries");
 if(argc>1){__block BOOL done=NO;__block NSError *failure=nil;RPConnection *connection=[RPConnection new];[connection synthesize:@"你好，这是兼容版语音测试。" voice:@"zh-CN-XiaoxiaoNeural" locale:@"zh-CN" rate:0 completion:^(NSData *audio,NSError *e){failure=e;if(!e)NSCAssert(audio.length>1000,@"No audio");done=YES;}];NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:45];while(!done&&deadline.timeIntervalSinceNow>0)[[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];NSCAssert(done&&!failure,@"Live SocketRocket speech failed: %@",failure);}
 puts("PASS: compatibility GEC, Chinese decode, Unicode splitting, EPUB import, SSML and optional live synthesis");
}return 0;}
