#import "RPImportBrowser.h"

static BOOL RPImportInside(NSURL *root,NSURL *url){
 NSString *base=root.URLByResolvingSymlinksInPath.URLByStandardizingPath.path;
 NSString *path=url.URLByResolvingSymlinksInPath.URLByStandardizingPath.path;
 return [path isEqual:base]||[path hasPrefix:[base stringByAppendingString:@"/"]];
}
NSArray *RPLocalImportFiles(NSURL *root,NSURL *directory,NSError **error){
 if(!RPImportInside(root,directory)){
  if(error)*error=[NSError errorWithDomain:@"ReaderPlusImport" code:1 userInfo:@{NSLocalizedDescriptionKey:@"请选择本 App 文档目录内的文件。"}];return nil;
 }
 NSArray *keys=@[NSURLIsDirectoryKey,NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLFileSizeKey];
 NSArray *items=[[NSFileManager defaultManager]contentsOfDirectoryAtURL:directory includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles error:error];
 if(!items)return nil;NSMutableArray *visible=[NSMutableArray array];
 BOOL isRoot=[directory.URLByStandardizingPath.path isEqual:root.URLByStandardizingPath.path];
 for(NSURL *url in items){
  NSNumber *folder=nil,*regular=nil,*link=nil;[url getResourceValue:&folder forKey:NSURLIsDirectoryKey error:nil];[url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];[url getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];
  if(link.boolValue||!RPImportInside(root,url))continue;
  if(isRoot&&[url.lastPathComponent isEqual:@"Library"])continue;
  if(folder.boolValue||(regular.boolValue&&[@[@"txt",@"epub",@"pdf",@"md"]containsObject:url.pathExtension.lowercaseString]))[visible addObject:url];
 }
 return [visible sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){
  NSNumber *af=nil,*bf=nil;[a getResourceValue:&af forKey:NSURLIsDirectoryKey error:nil];[b getResourceValue:&bf forKey:NSURLIsDirectoryKey error:nil];
  if(af.boolValue!=bf.boolValue)return af.boolValue?NSOrderedAscending:NSOrderedDescending;
  return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
 }];
}

#if TARGET_OS_IPHONE
@interface ReaderPlusImportBrowser()
@property(nonatomic,strong)NSURL *rootURL,*directoryURL;
@property(nonatomic,strong)NSArray *files;
@property(nonatomic)BOOL choosing;
@end
@implementation ReaderPlusImportBrowser
-(instancetype)initWithRoot:(NSURL*)root directory:(NSURL*)directory{
 if((self=[super initWithStyle:UITableViewStylePlain])){self.rootURL=root;self.directoryURL=directory;}return self;
}
-(void)viewDidLoad{
 [super viewDidLoad];BOOL isRoot=[self.rootURL.path isEqual:self.directoryURL.path];self.title=isRoot?@"本机文档导入":self.directoryURL.lastPathComponent;
 if(isRoot)self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadFiles)];
 UILabel *hint=[[UILabel alloc]initWithFrame:CGRectMake(0,0,320,150)];hint.numberOfLines=0;hint.textAlignment=NSTextAlignmentCenter;hint.font=[UIFont systemFontOfSize:15];hint.textColor=[UIColor grayColor];hint.text=@"通过电脑的文件共享，把书传到“拾页 Reader+”，然后点右上角刷新。\n\n支持 TXT、EPUB、PDF 和 MD。也可从其他 App 选择“拷贝到拾页”。";self.tableView.tableFooterView=hint;
}
-(void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self reloadFiles];}
-(void)cancel{[self.navigationController dismissViewControllerAnimated:YES completion:nil];}
-(void)reloadFiles{
 NSError *error=nil;self.files=RPLocalImportFiles(self.rootURL,self.directoryURL,&error)?:@[];
 if(!self.files.count){UILabel *empty=[UILabel new];empty.numberOfLines=0;empty.textAlignment=NSTextAlignmentCenter;empty.textColor=[UIColor grayColor];empty.text=error.localizedDescription?:@"还没有待导入的文件";self.tableView.backgroundView=empty;}else self.tableView.backgroundView=nil;
 [self.tableView reloadData];
}
-(NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section{return self.files.count;}
-(UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)index{
 NSURL *url=self.files[index.row];NSNumber *folder=nil,*size=nil;[url getResourceValue:&folder forKey:NSURLIsDirectoryKey error:nil];[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
 UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.text=url.lastPathComponent;
 cell.detailTextLabel.text=folder.boolValue?@"文件夹":[NSString stringWithFormat:@"%@ · %@",url.pathExtension.uppercaseString,[NSByteCountFormatter stringFromByteCount:size.longLongValue countStyle:NSByteCountFormatterCountStyleFile]];
 cell.accessoryType=folder.boolValue?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;return cell;
}
-(void)tableView:(UITableView*)table didSelectRowAtIndexPath:(NSIndexPath*)index{
 [table deselectRowAtIndexPath:index animated:YES];if(self.choosing)return;
 NSURL *url=self.files[index.row];NSNumber *folder=nil;[url getResourceValue:&folder forKey:NSURLIsDirectoryKey error:nil];
 if(folder.boolValue){ReaderPlusImportBrowser *next=[[ReaderPlusImportBrowser alloc]initWithRoot:self.rootURL directory:url];next.picked=self.picked;[self.navigationController pushViewController:next animated:YES];}
 else{self.choosing=YES;self.tableView.userInteractionEnabled=NO;if(self.picked)self.picked(url);}
}
@end
#endif
