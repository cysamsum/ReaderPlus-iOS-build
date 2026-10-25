#import "RPDocument.h"
#import <CoreFoundation/CoreFoundation.h>
#import <zlib.h>
#import <dlfcn.h>

static NSError *RPError(NSString *message){return [NSError errorWithDomain:@"ReaderPlus" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];}
NSString *RPDecode(NSData *data){
 const uint8_t *p=data.bytes;NSString *s=nil;
 if(data.length>=2&&((p[0]==255&&p[1]==254)||(p[0]==254&&p[1]==255)))s=[[NSString alloc]initWithData:data encoding:NSUTF16StringEncoding];
 if(!s)s=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
 if(!s)s=[[NSString alloc]initWithData:data encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)];
 return [s stringByReplacingOccurrencesOfString:@"\uFEFF" withString:@""];
}
NSArray *RPParagraphs(NSString *text){
 NSMutableArray *out=[NSMutableArray array];NSMutableString *chunk=[NSMutableString string];
 NSCharacterSet *breaks=[NSCharacterSet newlineCharacterSet];
 for(NSString *line in [text componentsSeparatedByCharactersInSet:breaks]){
  NSString *trim=[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  [trim enumerateSubstringsInRange:NSMakeRange(0,trim.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *s,NSRange r,NSRange e,BOOL *stop){
   if(chunk.length+s.length>350&&chunk.length){[out addObject:[chunk copy]];[chunk setString:@""];}
   [chunk appendString:s];
   if(chunk.length>=80&&[@"。！？!?；;" rangeOfString:s].location!=NSNotFound){[out addObject:[chunk copy]];[chunk setString:@""];}
  }];
  if(chunk.length){[out addObject:[chunk copy]];[chunk setString:@""];}
 }
 return out;
}
static uint16_t u16(const uint8_t *p){return (uint16_t)(p[0]|p[1]<<8);}
static uint32_t u32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
// Bounded, read-only ZIP extraction. Never write archive paths to the filesystem.
static NSDictionary *RPUnzip(NSData *zip,NSError **error){
 const uint8_t *p=zip.bytes;NSUInteger n=zip.length,end=NSNotFound;
 if(n<22){*error=RPError(@"EPUB ZIP 结构无效。");return nil;}
 NSUInteger first=n>65557?n-65557:0;
 for(NSUInteger i=n-22;;i--){if(u32(p+i)==0x06054b50&&i+22+u16(p+i+20)==n){end=i;break;}if(i==first)break;}
 if(end==NSNotFound||u16(p+end+4)||u16(p+end+6)){*error=RPError(@"不支持此 EPUB ZIP 格式。");return nil;}
 NSUInteger count=u16(p+end+10),offset=u32(p+end+16),total=0;
 if(count>4000){*error=RPError(@"EPUB 项目过多。");return nil;}
 NSMutableDictionary *out=[NSMutableDictionary dictionary];
 for(NSUInteger i=0;i<count;i++){
  if(offset>n||n-offset<46||u32(p+offset)!=0x02014b50)goto invalid;
  uint16_t flags=u16(p+offset+8),method=u16(p+offset+10),nameLen=u16(p+offset+28),extra=u16(p+offset+30),comment=u16(p+offset+32);
  uint32_t crc=u32(p+offset+16),compressed=u32(p+offset+20),size=u32(p+offset+24),local=u32(p+offset+42);
  if((NSUInteger)46+nameLen+extra+comment>n-offset)goto invalid;
  NSString *name=[[NSString alloc]initWithBytes:p+offset+46 length:nameLen encoding:NSUTF8StringEncoding];
  offset+=46+nameLen+extra+comment;
  if(!name||[name hasSuffix:@"/"])continue;
  NSString *ext=name.pathExtension.lowercaseString;
  if(![@[@"xml",@"opf",@"xhtml",@"html",@"htm"]containsObject:ext])continue;
  if(flags&1||size>8*1024*1024||size>32*1024*1024-total)goto invalid;
  if(local>n||n-local<30||u32(p+local)!=0x04034b50)goto invalid;
  NSUInteger start=(NSUInteger)local+30+u16(p+local+26)+u16(p+local+28);
  if(start>n||compressed>n-start)goto invalid;
  NSMutableData *data=[NSMutableData dataWithLength:MAX((NSUInteger)size,1)];
  if(method==0){if(compressed!=size)goto invalid;if(size)memcpy(data.mutableBytes,p+start,size);}
  else if(method==8){z_stream stream={0};stream.next_in=(Bytef*)p+start;stream.avail_in=compressed;stream.next_out=data.mutableBytes;stream.avail_out=MAX(size,1);
   if(inflateInit2(&stream,-MAX_WBITS)!=Z_OK)goto invalid;int result=inflate(&stream,Z_FINISH);inflateEnd(&stream);if(result!=Z_STREAM_END||stream.total_out!=size)goto invalid;
  }else goto invalid;
  data.length=size;if(crc32(0,data.bytes,(uInt)data.length)!=crc)goto invalid;
  total+=size;out[name]=data;
 }
 return out;
 invalid:*error=RPError(@"EPUB 损坏、加密或超出正文大小限制。");return nil;
}
@interface RPXML:NSObject<NSXMLParserDelegate>
@property(nonatomic,copy)void(^start)(NSString*,NSDictionary*);
@property(nonatomic,copy)void(^chars)(NSString*);
@property(nonatomic,copy)void(^end)(NSString*);
@end
@implementation RPXML
-(void)parser:(NSXMLParser*)p didStartElement:(NSString*)e namespaceURI:(NSString*)u qualifiedName:(NSString*)q attributes:(NSDictionary*)a{if(self.start)self.start(e,a);}
-(void)parser:(NSXMLParser*)p foundCharacters:(NSString*)s{if(self.chars)self.chars(s);}
-(void)parser:(NSXMLParser*)p didEndElement:(NSString*)e namespaceURI:(NSString*)u qualifiedName:(NSString*)q{if(self.end)self.end(e);}
@end
static BOOL RPParse(NSData *data,RPXML *delegate){if(!data)return NO;NSXMLParser *p=[[NSXMLParser alloc]initWithData:data];p.shouldProcessNamespaces=YES;p.shouldResolveExternalEntities=NO;p.delegate=delegate;return [p parse];}
static NSString *RPPath(NSString *href,NSString *base){
 NSString *path=[[[href componentsSeparatedByString:@"#"]firstObject]componentsSeparatedByString:@"?"][0];path=path.stringByRemovingPercentEncoding;
 if(!path.length||[path hasPrefix:@"/"]||[path containsString:@":"]||[path containsString:@"\\"])return nil;
 NSMutableArray *parts=[NSMutableArray array];if(base.length)[parts addObjectsFromArray:[base.stringByDeletingLastPathComponent componentsSeparatedByString:@"/"]];
 [parts removeObject:@"."];[parts removeObject:@""];
 for(NSString *part in [path componentsSeparatedByString:@"/"]){if([part isEqual:@".."]) {if(!parts.count)return nil;[parts removeLastObject];}else if(part.length&&![part isEqual:@"."])[parts addObject:part];}
 return [parts componentsJoinedByString:@"/"];
}
static NSString *RPHTML(NSString *html){
 NSString *s=html?:@"";
 for(NSString *pattern in @[@"(?is)<head\\b[^>]*>.*?</head\\s*>",@"(?is)<script\\b[^>]*>.*?</script\\s*>",@"(?is)<style\\b[^>]*>.*?</style\\s*>",@"(?s)<!--.*?-->"])
  s=[s stringByReplacingOccurrencesOfString:pattern withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0,s.length)];
 s=[s stringByReplacingOccurrencesOfString:@"(?i)<(?:br|/?p|/?div|/?h[1-6]|/?li|/?section)\\b[^>]*>" withString:@"\n" options:NSRegularExpressionSearch range:NSMakeRange(0,s.length)];
 s=[s stringByReplacingOccurrencesOfString:@"<[^>]+>" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0,s.length)];
 NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:@"&#(x[0-9a-fA-F]+|[0-9]+);" options:0 error:nil];
 for(NSTextCheckingResult *m in [[regex matchesInString:s options:0 range:NSMakeRange(0,s.length)]reverseObjectEnumerator]){
  NSString *digits=[s substringWithRange:[m rangeAtIndex:1]];unsigned long v=strtoul(digits.UTF8String+([digits hasPrefix:@"x"]?1:0),NULL,[digits hasPrefix:@"x"]?16:10);
  if(v&&v<=0x10FFFF&&!(v>=0xD800&&v<=0xDFFF)){UTF32Char ch=(UTF32Char)v;NSString *value=[[NSString alloc]initWithBytes:&ch length:4 encoding:NSUTF32LittleEndianStringEncoding];s=[s stringByReplacingCharactersInRange:m.range withString:value];}
 }
 NSArray *pairs=@[@[@"&nbsp;",@" "],@[@"&lt;",@"<"],@[@"&gt;",@">"],@[@"&quot;",@"\""],@[@"&apos;",@"'"],@[@"&amp;",@"&"]];
 for(NSArray *pair in pairs)s=[s stringByReplacingOccurrencesOfString:pair[0] withString:pair[1]];return s;
}
@protocol RPPDFText <NSObject>
-(id)initWithURL:(NSURL*)url;
-(NSUInteger)pageCount;
-(id)pageAtIndex:(NSUInteger)index;
-(NSString*)string;
@end
NSDictionary *RPImportDocument(NSURL *url,NSString *title,NSError **error){
 NSString *ext=url.pathExtension.lowercaseString;NSMutableArray *sections=[NSMutableArray array];
 if([ext isEqual:@"pdf"]){
  // PDFKit is loaded only when present (iOS 11+). No hard link on iOS 9/10.
  dlopen("/System/Library/Frameworks/PDFKit.framework/PDFKit",RTLD_LAZY);
  id<RPPDFText> pdf=[(id<RPPDFText>)[NSClassFromString(@"PDFDocument") alloc]initWithURL:url];
  NSUInteger count=pdf?[pdf pageCount]:0;
  if(count>2000){*error=RPError(@"PDF 超过 2000 页。");return nil;}
  for(NSUInteger i=0;i<count;i++)[sections addObject:@{@"id":@(i),@"title":[NSString stringWithFormat:@"第 %lu 页",(unsigned long)i+1],@"paragraphs":RPParagraphs([(id<RPPDFText>)[pdf pageAtIndex:i]string]?:@"")}];
  return @{@"title":title,@"sections":sections};
 }
 NSData *data=[NSData dataWithContentsOfURL:url options:0 error:error];if(!data)return nil;
 if(data.length>50*1024*1024){*error=RPError(@"文件超过 50 MB。");return nil;}
 if([ext isEqual:@"epub"]){
  NSDictionary *zip=RPUnzip(data,error);if(!zip)return nil;
  __block NSString *opf=nil;RPXML *container=[RPXML new];container.start=^(NSString *e,NSDictionary *a){if([e isEqual:@"rootfile"]&&!opf)opf=a[@"full-path"];};
  if(!RPParse(zip[@"META-INF/container.xml"],container)||!(opf=RPPath(opf,@""))){*error=RPError(@"EPUB 缺少包描述。");return nil;}
  NSMutableDictionary *items=[NSMutableDictionary dictionary];NSMutableArray *spine=[NSMutableArray array];NSMutableString *bookTitle=[NSMutableString string];__block BOOL inTitle=NO;
  RPXML *package=[RPXML new];package.start=^(NSString *e,NSDictionary *a){if([e isEqual:@"item"]&&a[@"id"]&&a[@"href"])items[a[@"id"]]=a;if([e isEqual:@"itemref"]&&a[@"idref"]&&![a[@"linear"]isEqual:@"no"])[spine addObject:a[@"idref"]];if([e isEqual:@"title"])inTitle=YES;};package.chars=^(NSString *s){if(inTitle)[bookTitle appendString:s];};package.end=^(NSString *e){if([e isEqual:@"title"])inTitle=NO;};
  if(!RPParse(zip[opf],package)||spine.count>2000){*error=RPError(@"EPUB 章节结构无效。");return nil;}
  for(NSString *key in spine){NSDictionary *item=items[key];if(![@[@"application/xhtml+xml",@"text/html"]containsObject:item[@"media-type"]])continue;
   NSString *path=RPPath(item[@"href"],opf);NSData *chapter=path?zip[path]:nil;if(!chapter){*error=RPError(@"EPUB 章节路径无效。");return nil;}
   NSArray *paras=RPParagraphs(RPHTML(RPDecode(chapter)));if(paras.count)[sections addObject:@{@"id":@(sections.count),@"title":[paras[0] substringToIndex:MIN([paras[0] length],48)],@"paragraphs":paras}];
  }
  if(bookTitle.length)title=bookTitle;
 }else if([@[@"txt",@"md"]containsObject:ext]){
  NSString *text=RPDecode(data);if(!text){*error=RPError(@"无法识别文字编码。");return nil;}
  NSArray *paras=RPParagraphs(text);for(NSUInteger i=0;i<paras.count;i+=120)[sections addObject:@{@"id":@(sections.count),@"title":[NSString stringWithFormat:@"第 %lu 节",(unsigned long)sections.count+1],@"paragraphs":[paras subarrayWithRange:NSMakeRange(i,MIN((NSUInteger)120,paras.count-i))]}];
 }else{*error=RPError(@"支持 TXT、EPUB、PDF 和 Markdown。");return nil;}
 if(!sections.count){*error=RPError(@"没有可读取的正文，或文档受 DRM 保护。");return nil;}
 return @{@"title":title,@"sections":sections};
}
