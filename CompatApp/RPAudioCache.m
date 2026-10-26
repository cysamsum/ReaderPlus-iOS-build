#import "RPAudioCache.h"
#import "RPSpeech.h"
#import <CommonCrypto/CommonDigest.h>
NSString *RPCurrentVoice(void){return [[NSUserDefaults standardUserDefaults]stringForKey:@"speech.voice"]?:@"zh-CN-XiaoxiaoNeural";}
NSString *RPCurrentMode(void){NSUserDefaults *d=[NSUserDefaults standardUserDefaults];NSString *s=[d stringForKey:@"compat.mode"];BOOL system=[d boolForKey:@"compat.system"]||[[d stringForKey:@"speech.engine"]isEqual:@"系统语音（离线）"];return s?:(system?@"系统语音（离线）":@"微软在线与已下载音频");}
static NSString *audioPath(NSString *text,NSString *voice,NSInteger rate){
 NSString *base=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES)[0]stringByAppendingPathComponent:@"ReaderPlusOfflineAudio"];
 [[NSFileManager defaultManager]createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:nil];
 [[NSURL fileURLWithPath:base]setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
 NSData *input=[[NSString stringWithFormat:@"edge-mp3-v1\n%@\n%ld\n%@",voice,(long)rate,text]dataUsingEncoding:NSUTF8StringEncoding];unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(input.bytes,(CC_LONG)input.length,hash);NSMutableString *name=[NSMutableString string];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[name appendFormat:@"%02x",hash[i]];
 return [base stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"mp3"]];
}
NSData *RPCachedAudio(NSString *text,NSString *voice,NSInteger rate){NSData *data=[NSData dataWithContentsOfFile:audioPath(text,voice,rate)];return data.length>100?data:nil;}
BOOL RPStoreAudio(NSData *audio,NSString *text,NSString *voice,NSInteger rate,NSError **error){return [audio writeToFile:audioPath(text,voice,rate) options:NSDataWritingAtomic error:error];}
@interface RPDownload()
@property(nonatomic,readwrite)BOOL active;
@property(nonatomic,strong)NSArray *texts;
@property(nonatomic,copy)NSString *voice,*locale;
@property(nonatomic)NSInteger rate;
@property(nonatomic)NSUInteger index,generation;
@property(nonatomic,strong)ReaderPlusSpeechConnection *connection;
@property(nonatomic,copy)void(^progress)(NSUInteger,NSUInteger);
@property(nonatomic,copy)void(^completion)(NSError*);
@end
@implementation RPDownload
-(void)cancel{self.generation++;self.active=NO;[self.connection cancel];self.connection=nil;self.progress=nil;self.completion=nil;}
-(void)start:(NSDictionary*)document progress:(void(^)(NSUInteger,NSUInteger))progress completion:(void(^)(NSError*))completion{
 [self cancel];NSMutableArray *texts=[NSMutableArray array];for(NSDictionary *section in document[@"sections"])for(NSString *text in section[@"paragraphs"])if(RPHasSpeechContent(text))[texts addObject:text];self.texts=texts;self.voice=RPCurrentVoice();NSArray *parts=[self.voice componentsSeparatedByString:@"-"];self.locale=parts.count>=2?[NSString stringWithFormat:@"%@-%@",parts[0],parts[1]]:@"zh-CN";self.rate=MAX(-50,MIN(100,[[NSUserDefaults standardUserDefaults]integerForKey:@"speech.rate"]));self.index=0;self.progress=progress;self.completion=completion;self.active=YES;[self next];
}
-(void)finish:(NSError*)error{void(^done)(NSError*)=self.completion;[self cancel];if(done)done(error);}
-(void)next{
 if(!self.active)return;
 while(self.index<self.texts.count&&RPCachedAudio(self.texts[self.index],self.voice,self.rate))self.index++;
 if(self.progress)self.progress(self.index,self.texts.count);
 if(self.index>=self.texts.count){[self finish:nil];return;}
 NSUInteger generation=self.generation;NSString *text=self.texts[self.index];self.connection=[ReaderPlusSpeechConnection new];__weak typeof(self) weak=self;
 [self.connection synthesize:text voice:self.voice locale:self.locale rate:self.rate completion:^(NSData *audio,NSError *error){RPDownload *s=weak;if(!s||!s.active||s.generation!=generation)return;NSError *saveError=error;if(!saveError&&!RPStoreAudio(audio,text,s.voice,s.rate,&saveError)){}if(saveError){[s finish:saveError];return;}s.index++;dispatch_async(dispatch_get_main_queue(),^{[s next];});}];
}
@end
