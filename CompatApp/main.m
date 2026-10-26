#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import "RPDocument.h"
#import "RPSpeech.h"
#import "RPAudioCache.h"
#import "RPAudioAudit.h"
#import "RPImportBrowser.h"

static UIColor *green(void){return [UIColor colorWithRed:.12 green:.42 blue:.36 alpha:1];}
static void alert(UIViewController *vc,NSString *title,NSString *message){UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];[vc presentViewController:a animated:YES completion:nil];}
static NSString *root(void){NSString *path=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES)[0]stringByAppendingPathComponent:@"Library"];[[NSFileManager defaultManager]createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];return path;}
static NSDictionary *jsonFile(NSString *path){NSData *d=[NSData dataWithContentsOfFile:path];return d?[NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:nil]:nil;}
static BOOL writeJSON(id value,NSString *path,NSError **error){NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:error];return data&&[data writeToFile:path options:NSDataWritingAtomic error:error];}

@interface RPLibrary:NSObject
@property(nonatomic,strong)NSMutableArray *books;
@property(nonatomic,copy)NSString *loadError;
-(void)savePosition:(NSDictionary*)book section:(NSInteger)section paragraph:(NSInteger)paragraph;
-(BOOL)remove:(NSDictionary*)book error:(NSError**)error;
-(void)importURL:(NSURL*)url completion:(void(^)(NSDictionary*,NSError*))completion;
@end
@implementation RPLibrary
-(instancetype)init{if((self=[super init])){NSString *path=[root()stringByAppendingPathComponent:@"library.json"];if([[NSFileManager defaultManager]fileExistsAtPath:path]){id value=jsonFile(path);if([value isKindOfClass:[NSArray class]])self.books=[value mutableCopy];else self.loadError=@"书架数据无法读取，为保护已有内容，已暂停写入。";}if(!self.books)self.books=[NSMutableArray array];}return self;}
-(void)savePosition:(NSDictionary*)book section:(NSInteger)section paragraph:(NSInteger)paragraph{if(self.loadError)return;NSMutableArray *next=[self.books mutableCopy];NSUInteger i=[next indexOfObjectPassingTest:^BOOL(id b,NSUInteger idx,BOOL *stop){return [b[@"id"]isEqual:book[@"id"]];}];if(i==NSNotFound)return;NSMutableDictionary *copy=[next[i]mutableCopy];copy[@"position"]=@{@"section":@(section),@"paragraph":@(paragraph)};next[i]=copy;NSError *e=nil;if(writeJSON(next,[root()stringByAppendingPathComponent:@"library.json"],&e))self.books=next;}
-(BOOL)remove:(NSDictionary*)book error:(NSError**)error{if(self.loadError)return NO;NSMutableArray *next=[self.books mutableCopy];NSIndexSet *items=[next indexesOfObjectsPassingTest:^BOOL(id b,NSUInteger i,BOOL *s){return [b[@"id"]isEqual:book[@"id"]];}];[next removeObjectsAtIndexes:items];if(!writeJSON(next,[root()stringByAppendingPathComponent:@"library.json"],error))return NO;self.books=next;for(NSString *ext in @[book[@"format"],@"json"])[[NSFileManager defaultManager]removeItemAtPath:[root()stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@",book[@"id"],ext]]error:nil];return YES;}
-(void)importURL:(NSURL*)url completion:(void(^)(NSDictionary*,NSError*))completion{
 if(self.loadError){completion(nil,[NSError errorWithDomain:@"ReaderPlus" code:1 userInfo:@{NSLocalizedDescriptionKey:self.loadError}]);return;}
 BOOL access=[url startAccessingSecurityScopedResource];NSString *idString=[NSUUID UUID].UUIDString,*ext=url.pathExtension.lowercaseString;
 NSString *source=[root()stringByAppendingPathComponent:[idString stringByAppendingPathExtension:ext]],*content=[root()stringByAppendingPathComponent:[idString stringByAppendingPathExtension:@"json"]];
 dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{
  NSError *error=nil;NSDictionary *attrs=[[NSFileManager defaultManager]attributesOfItemAtPath:url.path error:&error];NSDictionary *document=nil;
  if(!error&&[attrs fileSize]>50*1024*1024)error=[NSError errorWithDomain:@"ReaderPlus" code:1 userInfo:@{NSLocalizedDescriptionKey:@"文件超过 50 MB。"}];
  if(!error&&[[NSFileManager defaultManager]copyItemAtURL:url toURL:[NSURL fileURLWithPath:source] error:&error])document=RPImportDocument([NSURL fileURLWithPath:source],url.lastPathComponent.stringByDeletingPathExtension,&error);
  if(document&&[ext isEqual:@"pdf"]){CGPDFDocumentRef pdf=CGPDFDocumentCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:source]);NSUInteger pages=pdf?CGPDFDocumentGetNumberOfPages(pdf):0;
   if(!pages||pages>2000||(CGPDFDocumentIsEncrypted(pdf)&&!CGPDFDocumentIsUnlocked(pdf))){error=[NSError errorWithDomain:@"ReaderPlus" code:1 userInfo:@{NSLocalizedDescriptionKey:@"PDF 无法打开、需要密码或超过 2000 页。"}];document=nil;}
   else if(![document[@"sections"]count]){NSMutableArray *sections=[NSMutableArray array];for(NSUInteger i=0;i<pages;i++)[sections addObject:@{@"id":@(i),@"title":[NSString stringWithFormat:@"第 %lu 页",(unsigned long)i+1],@"paragraphs":@[]}];document=@{@"title":document[@"title"],@"sections":sections};}
   if(pdf)CGPDFDocumentRelease(pdf);
  }
  if(document&&!writeJSON(document,content,&error))document=nil;
  if(access)[url stopAccessingSecurityScopedResource];
  dispatch_async(dispatch_get_main_queue(),^{
   NSDictionary *book=nil;NSError *saveError=error;
   if(document){book=@{@"id":idString,@"title":document[@"title"],@"format":ext,@"addedAt":@([NSDate timeIntervalSinceReferenceDate]),@"position":@{@"section":@0,@"paragraph":@0}};NSMutableArray *next=[self.books mutableCopy];[next insertObject:book atIndex:0];if(writeJSON(next,[root()stringByAppendingPathComponent:@"library.json"],&saveError))self.books=next;else book=nil;}
   if(!book){[[NSFileManager defaultManager]removeItemAtPath:source error:nil];[[NSFileManager defaultManager]removeItemAtPath:content error:nil];}
   completion(book,saveError?:(!book?[NSError errorWithDomain:@"ReaderPlus" code:1 userInfo:@{NSLocalizedDescriptionKey:@"导入失败。"}]:nil));
  });
 });
}
@end

@interface RPChoices:UITableViewController
@property(nonatomic,strong)NSArray *items;
@property(nonatomic,copy)NSString *key,*selected;
@property(nonatomic,copy)void(^choose)(NSDictionary*);
@end
@implementation RPChoices
-(NSInteger)tableView:(UITableView*)v numberOfRowsInSection:(NSInteger)s{return self.items.count;}
-(UITableViewCell*)tableView:(UITableView*)v cellForRowAtIndexPath:(NSIndexPath*)p{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];NSDictionary *item=self.items[p.row];c.textLabel.text=item[@"title"]?:item[@"FriendlyName"];c.detailTextLabel.text=item[@"ShortName"];if([item[self.key]isEqual:self.selected])c.accessoryType=UITableViewCellAccessoryCheckmark;return c;}
-(void)tableView:(UITableView*)v didSelectRowAtIndexPath:(NSIndexPath*)p{if(self.choose)self.choose(self.items[p.row]);[self.navigationController popViewControllerAnimated:YES];}
@end
static NSArray *defaultVoices(void){return @[
@{@"ShortName":@"zh-CN-XiaoxiaoNeural",@"FriendlyName":@"晓晓 · 普通话女声"},@{@"ShortName":@"zh-CN-YunxiNeural",@"FriendlyName":@"云希 · 普通话男声"},@{@"ShortName":@"zh-CN-XiaoyiNeural",@"FriendlyName":@"晓伊 · 普通话女声"},@{@"ShortName":@"zh-TW-HsiaoChenNeural",@"FriendlyName":@"曉臻 · 台湾华语"},@{@"ShortName":@"zh-HK-HiuMaanNeural",@"FriendlyName":@"曉曼 · 粤语"},@{@"ShortName":@"en-US-JennyNeural",@"FriendlyName":@"Jenny · English"}];}
@interface RPSettings:UITableViewController
@property(nonatomic,copy)void(^changed)(void);
@end
@implementation RPSettings
-(void)viewDidLoad{[super viewDidLoad];self.title=@"阅读与声音";}
-(NSInteger)numberOfSectionsInTableView:(UITableView*)t{return 4;}
-(NSInteger)tableView:(UITableView*)t numberOfRowsInSection:(NSInteger)s{return s==0?2:s==1?4:s==2?1:3;}
-(NSString*)tableView:(UITableView*)t titleForHeaderInSection:(NSInteger)s{return @[@"阅读",@"朗读",@"隐私",@"关于"][s];}
-(NSString*)tableView:(UITableView*)t titleForFooterInSection:(NSInteger)s{if(s==1)return @"微软在线与缓存：优先播放已有音频，并提前准备后续段落。仅离线音频：不发起网络请求，需先下载全书且保持相同音色、语速。系统语音：使用 iOS 安装的音色，音色与微软不同。Windows 模型包尚无可用的 iOS 引擎。";if(s==2)return @"授权后将当前及后续预读段落通过 TLS 发送至微软。老系统若不支持服务的证书或 TLS，可改用已下载音频。";return nil;}
-(UITableViewCell*)tableView:(UITableView*)t cellForRowAtIndexPath:(NSIndexPath*)p{
 NSUserDefaults *d=[NSUserDefaults standardUserDefaults];UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
 if(p.section==0){c.textLabel.text=p.row?@"主题":@"字号";c.detailTextLabel.text=p.row?([d stringForKey:@"reading.theme"]?:@"护眼纸色"):[NSString stringWithFormat:@"%ld",(long)([d integerForKey:@"reading.fontSize"]?:21)];}
 if(p.section==1){c.textLabel.text=@[@"朗读方式",@"语言与音色",@"语速",@"更新微软音色列表"][p.row];c.detailTextLabel.text=p.row==0?RPCurrentMode():p.row==1?([d stringForKey:@"speech.voice"]?:@"晓晓"):p.row==2?[NSString stringWithFormat:@"%+ld%%",(long)[d integerForKey:@"speech.rate"]]:@"";}
 if(p.section==1&&p.row==1&&[RPCurrentMode()isEqual:@"系统语音（离线）"]){NSString *identifier=[d stringForKey:@"compat.systemVoice"];AVSpeechSynthesisVoice *voice=identifier.length?[AVSpeechSynthesisVoice voiceWithIdentifier:identifier]:nil;c.detailTextLabel.text=voice?[NSString stringWithFormat:@"%@ · %@",voice.name,voice.language]:@"按语言自动选择";}
 if(p.section==2){c.textLabel.text=@"允许发送朗读段落";UISwitch *s=[UISwitch new];s.on=[d boolForKey:@"speech.consent"];[s addTarget:self action:@selector(consent:) forControlEvents:UIControlEventValueChanged];c.accessoryView=s;}
 if(p.section==3){c.textLabel.text=@[@"拾页 Reader+ 1.2.1",@"目标系统 iOS 9–26.1",@"开源许可"][p.row];if(p.row<2)c.accessoryType=UITableViewCellAccessoryNone;}
 return c;
}
-(void)consent:(UISwitch*)s{[[NSUserDefaults standardUserDefaults]setBool:s.on forKey:@"speech.consent"];if(self.changed)self.changed();}
-(void)options:(NSArray*)items key:(NSString*)key title:(NSString*)title{
 UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
 for(id item in items){NSString *label=[item description];[a addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[[NSUserDefaults standardUserDefaults]setObject:item forKey:key];if(self.changed)self.changed();[self.tableView reloadData];}]];}
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=self.view;a.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,80,1,1);[self presentViewController:a animated:YES completion:nil];
}
-(void)tableView:(UITableView*)t didSelectRowAtIndexPath:(NSIndexPath*)p{
 [t deselectRowAtIndexPath:p animated:YES];NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
 if(p.section==0){[self options:p.row?@[@"护眼纸色",@"白色",@"夜间"]:@[@16,@18,@21,@24,@28,@32] key:p.row?@"reading.theme":@"reading.fontSize" title:p.row?@"选择主题":@"选择字号"];return;}
 if(p.section==1&&p.row==0)[self options:@[@"微软在线与已下载音频",@"仅播放离线音频",@"系统语音（离线）"]key:@"compat.mode" title:@"选择朗读方式"];
 if(p.section==1&&p.row==1){BOOL system=[RPCurrentMode()isEqual:@"系统语音（离线）"];NSArray *voices=[d arrayForKey:@"compat.voices"]?:defaultVoices();if(system){NSMutableArray *local=[NSMutableArray array];for(AVSpeechSynthesisVoice *voice in [AVSpeechSynthesisVoice speechVoices])[local addObject:@{@"ShortName":voice.identifier,@"FriendlyName":[NSString stringWithFormat:@"%@ · %@",voice.name,voice.language]}];voices=local;}RPChoices *vc=[RPChoices new];vc.title=system?@"设备系统音色":@"微软语言与音色";vc.items=voices;vc.key=@"ShortName";NSString *pref=system?@"compat.systemVoice":@"speech.voice";vc.selected=[d stringForKey:pref];__weak typeof(self) weak=self;vc.choose=^(NSDictionary *item){[d setObject:item[@"ShortName"]forKey:pref];if(weak.changed)weak.changed();[weak.tableView reloadData];};[self.navigationController pushViewController:vc animated:YES];}
 if(p.section==1&&p.row==2)[self options:@[@(-50),@(-30),@0,@20,@50,@80,@100] key:@"speech.rate" title:@"语速百分比"];
 if(p.section==1&&p.row==3){NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/voices/list?trustedclienttoken=6A5AA1D4EAFF4E9FB37E23D68491D6F4"]];r.timeoutInterval=20;
  [[[NSURLSession sharedSession]dataTaskWithRequest:r completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){NSArray *voices=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;dispatch_async(dispatch_get_main_queue(),^{if(error||!voices.count||![(id)voices isKindOfClass:[NSArray class]]){alert(self,@"更新失败",error.localizedDescription?:@"服务没有返回音色列表。");return;}NSArray *sorted=[voices sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){NSString *x=[NSString stringWithFormat:@"%d%@",[a[@"Locale"]hasPrefix:@"zh"]?0:1,a[@"ShortName"]],*y=[NSString stringWithFormat:@"%d%@",[b[@"Locale"]hasPrefix:@"zh"]?0:1,b[@"ShortName"]];return [x compare:y];}];[d setObject:sorted forKey:@"compat.voices"];alert(self,@"音色已更新",[NSString stringWithFormat:@"已获取 %lu 个音色。",(unsigned long)sorted.count]);});}]resume];
 }
 if(p.section==3&&p.row==2){NSMutableString *text=[NSMutableString stringWithString:@"界面与旧系统兼容层使用 UIKit。GEC v2 派生模块按 LGPLv3 提供，© rany 及项目贡献者。WebSocket 使用 SocketRocket 0.6.1。\n\n"];
  for(NSString *name in @[@"Edge-TTS-LICENSE",@"edge-tts-LGPLv3",@"GPL-3.0",@"SocketRocket-LICENSE",@"SocketRocket-PATENTS"]){NSString *s=[NSString stringWithContentsOfFile:[[NSBundle mainBundle]pathForResource:name ofType:@"txt"]encoding:NSUTF8StringEncoding error:nil];if(s)[text appendFormat:@"%@\n%@\n\n",name,s];}
  UIViewController *vc=[UIViewController new];vc.title=@"开源许可";UITextView *v=[[UITextView alloc]initWithFrame:vc.view.bounds];v.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;v.editable=NO;v.text=text;v.font=[UIFont systemFontOfSize:14];[vc.view addSubview:v];[self.navigationController pushViewController:vc animated:YES];
 }
}
@end

@interface RPPDFCanvas:UIView
@property(nonatomic)CGPDFDocumentRef pdf;
@property(nonatomic)NSInteger page;
@end
@implementation RPPDFCanvas
-(void)drawRect:(CGRect)rect{if(!self.pdf)return;CGPDFPageRef page=CGPDFDocumentGetPage(self.pdf,self.page+1);if(!page)return;CGContextRef c=UIGraphicsGetCurrentContext();[[UIColor whiteColor]setFill];UIRectFill(self.bounds);CGContextSaveGState(c);CGContextTranslateCTM(c,0,self.bounds.size.height);CGContextScaleCTM(c,1,-1);CGContextConcatCTM(c,CGPDFPageGetDrawingTransform(page,kCGPDFCropBox,self.bounds,0,YES));CGContextDrawPDFPage(c,page);CGContextRestoreGState(c);}
@end
@interface RPReader:UIViewController<UITableViewDataSource,UITableViewDelegate,UIScrollViewDelegate>
@property(nonatomic,strong)NSDictionary *book,*document;
@property(nonatomic,strong)RPLibrary *library;
@property(nonatomic,strong)RPSpeech *speech;
@property(nonatomic,strong)RPDownload *download;
@property(nonatomic,strong)UIButton *downloadButton;
@property(nonatomic,strong)UITableView *table;
@property(nonatomic,strong)UILabel *chapter;
@property(nonatomic,strong)UIView *bar;
@property(nonatomic,strong)UIButton *play,*previous,*next,*stopButton;
@property(nonatomic,strong)UISegmentedControl *mode;
@property(nonatomic,strong)UIScrollView *pdfScroll;
@property(nonatomic,strong)RPPDFCanvas *canvas;
@property(nonatomic)CGPDFDocumentRef pdf;
@property(nonatomic)NSInteger section,paragraph;
@property(nonatomic)BOOL restoring;
@end
@implementation RPReader
-(void)dealloc{if(_pdf)CGPDFDocumentRelease(_pdf);}
-(NSArray*)sections{return self.document[@"sections"]?:@[];}
-(NSArray*)paragraphs{return self.section<(NSInteger)self.sections.count?self.sections[self.section][@"paragraphs"]:@[];}
-(void)viewDidLoad{
 [super viewDidLoad];self.title=self.book[@"title"];self.section=[self.book[@"position"][@"section"]integerValue];self.paragraph=[self.book[@"position"][@"paragraph"]integerValue];self.speech=[RPSpeech new];__weak typeof(self) weak=self;
 self.speech.changed=^{[weak updatePlay];};self.speech.failed=^(NSString *message){if(weak)alert(weak,@"朗读提示",message);};self.speech.moved=^(NSInteger s,NSInteger p){RPReader *v=weak;if(!v)return;v.section=s;v.paragraph=p;[v showSection:YES];[v save];};
 self.chapter=[UILabel new];self.chapter.font=[UIFont systemFontOfSize:14];self.chapter.textAlignment=NSTextAlignmentCenter;[self.view addSubview:self.chapter];
 self.mode=[[UISegmentedControl alloc]initWithItems:@[@"文字",@"原页"]];self.mode.selectedSegmentIndex=1;[self.mode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];[self.view addSubview:self.mode];self.mode.hidden=![self.book[@"format"]isEqual:@"pdf"];
 self.table=[[UITableView alloc]initWithFrame:CGRectZero style:UITableViewStylePlain];self.table.dataSource=self;self.table.delegate=self;self.table.separatorStyle=UITableViewCellSeparatorStyleNone;self.table.estimatedRowHeight=170;self.table.rowHeight=UITableViewAutomaticDimension;[self.view addSubview:self.table];
 self.pdfScroll=[UIScrollView new];self.pdfScroll.minimumZoomScale=1;self.pdfScroll.maximumZoomScale=4;self.pdfScroll.delegate=self;self.canvas=[RPPDFCanvas new];[self.pdfScroll addSubview:self.canvas];[self.view addSubview:self.pdfScroll];
 self.bar=[UIView new];[self.view addSubview:self.bar];NSMutableArray *buttons=[NSMutableArray array];
 self.downloadButton=[UIButton buttonWithType:UIButtonTypeSystem];[self.downloadButton setTitle:@"下载全书离线音频" forState:UIControlStateNormal];self.downloadButton.titleLabel.font=[UIFont systemFontOfSize:13];[self.downloadButton addTarget:self action:@selector(downloadTapped) forControlEvents:UIControlEventTouchUpInside];[self.bar addSubview:self.downloadButton];
 for(NSString *title in @[@"上一节",@"朗读",@"停止",@"下一节"]){UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:title forState:UIControlStateNormal];b.titleLabel.font=[UIFont boldSystemFontOfSize:17];[self.bar addSubview:b];[buttons addObject:b];}
 self.previous=buttons[0];self.play=buttons[1];self.stopButton=buttons[2];self.next=buttons[3];[self.previous addTarget:self action:@selector(back) forControlEvents:UIControlEventTouchUpInside];[self.next addTarget:self action:@selector(forward) forControlEvents:UIControlEventTouchUpInside];[self.play addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];[self.stopButton addTarget:self.speech action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
 self.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc]initWithTitle:@"设置" style:UIBarButtonItemStylePlain target:self action:@selector(settings)],[[UIBarButtonItem alloc]initWithTitle:@"章节" style:UIBarButtonItemStylePlain target:self action:@selector(contents)]];
 self.document=jsonFile([root()stringByAppendingPathComponent:[self.book[@"id"]stringByAppendingPathExtension:@"json"]]);
 if(!self.document){alert(self,@"无法打开",@"书籍内容文件缺失或损坏。");self.document=@{@"sections":@[]};}
 if([self.book[@"format"]isEqual:@"pdf"]){self.pdf=CGPDFDocumentCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:[root()stringByAppendingPathComponent:[self.book[@"id"]stringByAppendingPathExtension:@"pdf"]]]);self.canvas.pdf=self.pdf;}
 self.section=MAX(0,MIN(self.section,(NSInteger)self.sections.count-1));self.paragraph=MAX(0,MIN(self.paragraph,(NSInteger)self.paragraphs.count-1));[self applyTheme];[self showSection:YES];
}
-(void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];CGRect b=self.view.bounds;CGFloat top=self.topLayoutGuide.length,bottom=self.bottomLayoutGuide.length,w=b.size.width;self.chapter.frame=CGRectMake(12,top,w-24,30);self.mode.frame=CGRectMake(20,top+32,w-40,30);CGFloat y=top+(self.mode.hidden?32:70);CGRect content=CGRectMake(0,y,w,MAX(0,b.size.height-y-bottom-96));self.table.frame=content;self.pdfScroll.frame=content;self.canvas.frame=CGRectMake(0,0,content.size.width,content.size.height);self.pdfScroll.contentSize=content.size;self.bar.frame=CGRectMake(0,b.size.height-bottom-96,w,96);NSArray *buttons=@[self.previous,self.play,self.stopButton,self.next];for(NSInteger i=0;i<4;i++)[buttons[i]setFrame:CGRectMake(i*w/4,5,w/4,52)];self.downloadButton.frame=CGRectMake(12,57,w-24,32);}
-(UIView*)viewForZoomingInScrollView:(UIScrollView*)s{return s==self.pdfScroll?self.canvas:nil;}
-(void)viewWillDisappear:(BOOL)a{[super viewWillDisappear:a];[self.speech stop];[self.download cancel];[self.downloadButton setTitle:@"下载全书离线音频" forState:UIControlStateNormal];[self save];}
-(void)save{[self.library savePosition:self.book section:self.section paragraph:self.paragraph];}
-(void)applyTheme{NSUserDefaults *d=[NSUserDefaults standardUserDefaults];NSString *theme=[d stringForKey:@"reading.theme"]?:@"护眼纸色";BOOL dark=[theme isEqual:@"夜间"];UIColor *paper=dark?[UIColor colorWithWhite:.09 alpha:1]:[theme isEqual:@"白色"]?[UIColor whiteColor]:[UIColor colorWithRed:.96 green:.93 blue:.85 alpha:1];self.view.backgroundColor=paper;self.table.backgroundColor=paper;self.chapter.textColor=dark?[UIColor lightTextColor]:[UIColor darkGrayColor];self.bar.backgroundColor=paper;[self.table reloadData];}
-(void)showSection:(BOOL)scroll{
 self.chapter.text=self.sections.count?[NSString stringWithFormat:@"%@  ·  %ld / %lu",self.sections[self.section][@"title"],(long)self.section+1,(unsigned long)self.sections.count]:@"没有章节";self.canvas.page=self.section;[self.canvas setNeedsDisplay];self.pdfScroll.zoomScale=1;[self modeChanged];[self.table reloadData];
 if(scroll&&self.paragraphs.count){self.restoring=YES;dispatch_async(dispatch_get_main_queue(),^{if(self.paragraph<(NSInteger)self.paragraphs.count)[self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.paragraph inSection:0]atScrollPosition:UITableViewScrollPositionTop animated:NO];self.restoring=NO;});}
 [self updatePlay];
}
-(void)modeChanged{BOOL original=!self.mode.hidden&&self.mode.selectedSegmentIndex==1;self.pdfScroll.hidden=!original;self.table.hidden=original;}
-(void)updatePlay{NSString *title=self.speech.loading?@"取消":self.speech.active?(self.speech.paused?@"继续":@"暂停"):@"朗读";[self.play setTitle:title forState:UIControlStateNormal];self.previous.enabled=self.section>0;self.next.enabled=self.section+1<(NSInteger)self.sections.count;self.stopButton.enabled=self.speech.active;BOOL hasText=NO;for(NSInteger i=self.section;i<(NSInteger)self.sections.count;i++)if([self.sections[i][@"paragraphs"]count]){hasText=YES;break;}self.play.enabled=hasText;}
-(void)rpMoveBy:(NSInteger)delta{[self.speech stop];self.section=MAX(0,MIN(self.section+delta,(NSInteger)self.sections.count-1));self.paragraph=0;[self showSection:YES];[self save];}
-(void)back{[self rpMoveBy:-1];}-(void)forward{[self rpMoveBy:1];}
-(void)playTapped{if(self.speech.active){[self.speech pauseOrResume];return;}NSUserDefaults *d=[NSUserDefaults standardUserDefaults];if([RPCurrentMode()isEqual:@"微软在线与已下载音频"]&&![d boolForKey:@"speech.consent"]){UIAlertController *a=[UIAlertController alertControllerWithTitle:@"使用微软自然语音" message:@"未下载的朗读段落将通过加密连接发送到微软语音服务，生成的音频会保存到本机。也可选择仅播放离线音频。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"允许并朗读" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[d setBool:YES forKey:@"speech.consent"];[self.speech start:self.document section:self.section paragraph:self.paragraph];}]];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];return;}[self.speech start:self.document section:self.section paragraph:self.paragraph];}
-(void)downloadTapped{
 if(self.download.active){[self.download cancel];[self.downloadButton setTitle:@"下载全书离线音频" forState:UIControlStateNormal];return;}
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"下载全书离线音频" message:@"将整本书的文字按段发送至微软，以当前音色和语速合成为 MP3 存在手机上。下载后断网可播放；未下载的新文字无法在断网时即时合成。请保持本页开启，可随时取消并继续。" preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:@"开始下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){[[NSUserDefaults standardUserDefaults]setBool:YES forKey:@"speech.consent"];[self.speech stop];self.download=[RPDownload new];__weak typeof(self) weak=self;[self.download start:self.document progress:^(NSUInteger done,NSUInteger total){[weak.downloadButton setTitle:[NSString stringWithFormat:@"下载 %lu / %lu · 点击取消",(unsigned long)done,(unsigned long)total]forState:UIControlStateNormal];}completion:^(NSError *error){RPReader *v=weak;if(!v)return;[v.downloadButton setTitle:@"下载全书离线音频" forState:UIControlStateNormal];alert(v,error?@"下载中断":@"离线音频已保存",error?error.localizedDescription:@"可在设置中选择“仅播放离线音频”，使用相同音色与语速断网播放。已保存的音频无需重新下载。");}];}]];
 [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
-(NSInteger)tableView:(UITableView*)t numberOfRowsInSection:(NSInteger)s{return MAX((NSUInteger)1,self.paragraphs.count);}
-(UITableViewCell*)tableView:(UITableView*)t cellForRowAtIndexPath:(NSIndexPath*)p{UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];c.textLabel.numberOfLines=0;NSInteger size=[[NSUserDefaults standardUserDefaults]integerForKey:@"reading.fontSize"]?:21;c.textLabel.font=[UIFont systemFontOfSize:MAX(15,MIN(34,size))];BOOL dark=[[[NSUserDefaults standardUserDefaults]stringForKey:@"reading.theme"]isEqual:@"夜间"];c.textLabel.textColor=dark?[UIColor colorWithWhite:.9 alpha:1]:[UIColor colorWithWhite:.13 alpha:1];c.textLabel.text=self.paragraphs.count?self.paragraphs[p.row]:@"此页没有可朗读文字。iOS 9/10 支持 PDF 原页查看；PDF 文字提取需要 iOS 11 及以上，扫描件仍需 OCR。";c.backgroundColor=self.paragraphs.count&&p.row==self.paragraph?[green()colorWithAlphaComponent:.12]:self.table.backgroundColor;c.selectionStyle=UITableViewCellSelectionStyleNone;return c;}
-(void)tableView:(UITableView*)t didSelectRowAtIndexPath:(NSIndexPath*)p{if(!self.paragraphs.count)return;[self.speech stop];self.paragraph=p.row;[self save];[t reloadData];[self playTapped];}
-(void)scrollViewDidEndDragging:(UIScrollView*)s willDecelerate:(BOOL)d{if(!d)[self recordScroll:s];}
-(void)scrollViewDidEndDecelerating:(UIScrollView*)s{[self recordScroll:s];}
-(void)recordScroll:(UIScrollView*)s{if(s!=self.table||self.restoring||self.speech.active||!self.paragraphs.count)return;NSArray *visible=[self.table.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)];if(visible.count){self.paragraph=[visible[0]row];[self save];}}
-(void)settings{[self.speech stop];RPSettings *vc=[[RPSettings alloc]initWithStyle:UITableViewStyleGrouped];__weak typeof(self) weak=self;vc.changed=^{[weak.speech stop];[weak applyTheme];};[self.navigationController pushViewController:vc animated:YES];}
-(void)contents{RPChoices *vc=[RPChoices new];vc.title=[self.book[@"format"]isEqual:@"pdf"]?@"页码":@"章节";vc.items=self.sections;vc.key=@"id";__weak typeof(self) weak=self;vc.choose=^(NSDictionary *item){[weak.speech stop];weak.section=[item[@"id"]integerValue];weak.paragraph=0;[weak showSection:YES];[weak save];};[self.navigationController pushViewController:vc animated:YES];}
@end

@interface RPBooks:UITableViewController<UIDocumentPickerDelegate>
@property(nonatomic,strong)RPLibrary *library;
@property(nonatomic)BOOL importing;
@property(nonatomic)BOOL importSmokeRan;
-(void)importURL:(NSURL*)url;
@end
@implementation RPBooks
-(void)viewDidLoad{[super viewDidLoad];self.title=@"拾页 Reader+";self.library=[RPLibrary new];self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importTapped)];self.navigationItem.leftBarButtonItem=self.editButtonItem;
 UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,320,130)];UILabel *title=[[UILabel alloc]initWithFrame:CGRectMake(20,12,280,50)];title.autoresizingMask=UIViewAutoresizingFlexibleWidth;title.text=@"让文字，也有声音。";title.font=[UIFont boldSystemFontOfSize:25];[header addSubview:title];UILabel *hint=[[UILabel alloc]initWithFrame:CGRectMake(20,60,280,54)];hint.autoresizingMask=UIViewAutoresizingFlexibleWidth;hint.text=@"TXT · EPUB · PDF · Markdown\n点击 + 导入，或从其他 App 分享打开。";hint.numberOfLines=2;hint.font=[UIFont systemFontOfSize:14];hint.textColor=[UIColor grayColor];[header addSubview:hint];self.tableView.tableHeaderView=header;
 UIButton *sample=[UIButton buttonWithType:UIButtonTypeSystem];sample.frame=CGRectMake(0,0,320,60);[sample setTitle:@"导入体验电子书" forState:UIControlStateNormal];[sample addTarget:self action:@selector(sample) forControlEvents:UIControlEventTouchUpInside];self.tableView.tableFooterView=sample;
 if(self.library.loadError)dispatch_async(dispatch_get_main_queue(),^{alert(self,@"书架提示",self.library.loadError);});
 if([[NSProcessInfo processInfo].arguments containsObject:@"--smoke-reader"])dispatch_async(dispatch_get_main_queue(),^{[self sample];});
}
-(void)viewWillAppear:(BOOL)a{[super viewWillAppear:a];[self.tableView reloadData];}
-(void)viewDidAppear:(BOOL)animated{
 [super viewDidAppear:animated];
 if(!self.importSmokeRan&&[[NSProcessInfo processInfo].arguments containsObject:@"--smoke-import"]){
  self.importSmokeRan=YES;dispatch_async(dispatch_get_main_queue(),^{[self importTapped];});
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
   UIViewController *presented=self.navigationController.presentedViewController;BOOL expectedLocal=[NSProcessInfo processInfo].operatingSystemVersion.majorVersion<11||[[NSProcessInfo processInfo].arguments containsObject:@"--smoke-local-picker"];
   BOOL local=[presented isKindOfClass:[UINavigationController class]]&&[[(UINavigationController*)presented topViewController]isKindOfClass:[ReaderPlusImportBrowser class]];
   BOOL system=[presented isKindOfClass:[UIDocumentPickerViewController class]];
   NSDictionary *report=@{@"systemVersion":[UIDevice currentDevice].systemVersion,@"presentedClass":presented?NSStringFromClass(presented.class):@"none",@"expectedLocal":@(expectedLocal),@"localPickerVisible":@(local),@"systemPickerVisible":@(system),@"passed":@(presented.view.window&&(expectedLocal?local:system))};
   NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES)[0];writeJSON(report,[documents stringByAppendingPathComponent:@"import-regression.json"],nil);
  });
 }
}
-(void)sample{NSURL *url=[[NSBundle mainBundle]URLForResource:@"体验电子书" withExtension:@"epub"];if(url)[self importURL:url];}
-(NSInteger)tableView:(UITableView*)t numberOfRowsInSection:(NSInteger)s{return self.library.books.count;}
-(UITableViewCell*)tableView:(UITableView*)t cellForRowAtIndexPath:(NSIndexPath*)p{NSDictionary *b=self.library.books[p.row];UITableViewCell *c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];c.textLabel.text=b[@"title"];c.textLabel.font=[UIFont boldSystemFontOfSize:19];c.detailTextLabel.text=[NSString stringWithFormat:@"%@  ·  第 %ld 节/页",[b[@"format"]uppercaseString],(long)[b[@"position"][@"section"]integerValue]+1];c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return c;}
-(CGFloat)tableView:(UITableView*)t heightForRowAtIndexPath:(NSIndexPath*)p{return 78;}
-(void)open:(NSDictionary*)book{RPReader *vc=[RPReader new];vc.book=book;vc.library=self.library;[self.navigationController pushViewController:vc animated:YES];}
-(void)tableView:(UITableView*)t didSelectRowAtIndexPath:(NSIndexPath*)p{[self open:self.library.books[p.row]];}
-(void)tableView:(UITableView*)t commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath*)p{if(style!=UITableViewCellEditingStyleDelete)return;NSDictionary *book=self.library.books[p.row];UIAlertController *a=[UIAlertController alertControllerWithTitle:@"删除书籍？" message:@"将删除本地副本和阅读进度。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){NSError *error=nil;if(![self.library remove:book error:&error])alert(self,@"删除失败",error.localizedDescription?:self.library.loadError);[self.tableView reloadData];}]];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];}
-(void)presentLocalImport{
 NSURL *documents=[[NSFileManager defaultManager]URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
 ReaderPlusImportBrowser *browser=[[ReaderPlusImportBrowser alloc]initWithRoot:documents directory:documents];__weak typeof(self) weak=self;
 browser.picked=^(NSURL *url){RPBooks *books=weak;[books.navigationController dismissViewControllerAnimated:YES completion:^{[books importURL:url];}];};
 UINavigationController *nav=[[UINavigationController alloc]initWithRootViewController:browser];nav.modalPresentationStyle=UIModalPresentationFormSheet;[self.navigationController presentViewController:nav animated:YES completion:nil];
}
-(void)importTapped{
 if(self.importing||self.navigationController.presentedViewController)return;
 // Real iOS 9 asserts in the native picker's initializer without provisioned
 // iCloud container entitlements. The local browser works with USB sharing and
 // never depends on cloud signing capabilities or installed document providers.
 if([NSProcessInfo processInfo].operatingSystemVersion.majorVersion<11||[[NSProcessInfo processInfo].arguments containsObject:@"--smoke-local-picker"]){[self presentLocalImport];return;}
 UIDocumentPickerViewController *picker=nil;
 @try{picker=[[UIDocumentPickerViewController alloc]initWithDocumentTypes:@[@"public.data",@"public.content"]inMode:UIDocumentPickerModeImport];}
 @catch(NSException *exception){NSLog(@"System document picker unavailable: %@",exception.reason);[self presentLocalImport];return;}
 picker.delegate=self;picker.modalPresentationStyle=UIModalPresentationFormSheet;picker.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self.navigationController presentViewController:picker animated:YES completion:nil];
}
-(void)documentPicker:(UIDocumentPickerViewController*)p didPickDocumentAtURL:(NSURL*)url{[p dismissViewControllerAnimated:YES completion:^{[self importURL:url];}];}
-(void)documentPicker:(UIDocumentPickerViewController*)p didPickDocumentsAtURLs:(NSArray*)urls{if(urls.count)[p dismissViewControllerAnimated:YES completion:^{[self importURL:urls[0]];}];}
-(void)importURL:(NSURL*)url{if(self.importing)return;self.importing=YES;self.navigationItem.rightBarButtonItem.enabled=NO;self.title=@"正在导入…";[self.library importURL:url completion:^(NSDictionary *book,NSError *error){self.importing=NO;self.navigationItem.rightBarButtonItem.enabled=YES;self.title=@"拾页 Reader+";[self.tableView reloadData];if(error)alert(self,@"导入失败",error.localizedDescription);else [self open:book];}];}
@end
@interface RPAppDelegate:UIResponder<UIApplicationDelegate>
@property(nonatomic,strong)UIWindow *window;
@property(nonatomic,strong)RPBooks *books;
@property(nonatomic,strong)RPAudioAudit *audioAudit;
@end
@implementation RPAppDelegate
-(BOOL)application:(UIApplication*)app didFinishLaunchingWithOptions:(NSDictionary*)options{self.window=[[UIWindow alloc]initWithFrame:[UIScreen mainScreen].bounds];self.window.tintColor=green();self.books=[[RPBooks alloc]initWithStyle:UITableViewStylePlain];self.window.rootViewController=[[UINavigationController alloc]initWithRootViewController:self.books];[self.window makeKeyAndVisible];if([[NSProcessInfo processInfo].arguments containsObject:@"--smoke-audio"]){self.audioAudit=[RPAudioAudit new];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self.audioAudit run];});}return YES;}
-(BOOL)application:(UIApplication*)app openURL:(NSURL*)url options:(NSDictionary*)options{UINavigationController *nav=(id)self.window.rootViewController;[nav popToRootViewControllerAnimated:NO];[self.books importURL:url];return YES;}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass([RPAppDelegate class]));}}
