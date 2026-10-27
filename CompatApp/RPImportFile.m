#import "RPImportFile.h"

BOOL RPCopyImportFile(NSURL *selected,NSURL *destination,NSError **error){
 if(!selected.isFileURL||!destination.isFileURL){
  if(error)*error=[NSError errorWithDomain:@"ReaderPlusImport" code:2 userInfo:@{NSLocalizedDescriptionKey:@"未收到有效的本地文件，请重新选择或从文件管理器分享导入。"}];return NO;
 }
 __block NSError *copyError=nil;__block BOOL copied=NO;NSError *coordinationError=nil;
 NSFileCoordinator *coordinator=[[NSFileCoordinator alloc]initWithFilePresenter:nil];
 [coordinator coordinateReadingItemAtURL:selected options:NSFileCoordinatorReadingWithoutChanges error:&coordinationError byAccessor:^(NSURL *readable){
  NSFileManager *fm=[NSFileManager defaultManager];NSDictionary *attributes=[fm attributesOfItemAtPath:readable.path error:&copyError];
  if(!attributes)return;
  if(![attributes[NSFileType]isEqual:NSFileTypeRegular]){copyError=[NSError errorWithDomain:@"ReaderPlusImport" code:3 userInfo:@{NSLocalizedDescriptionKey:@"请选择书籍文件，不能导入文件夹。"}];return;}
  if([attributes fileSize]>50*1024*1024){copyError=[NSError errorWithDomain:@"ReaderPlusImport" code:4 userInfo:@{NSLocalizedDescriptionKey:@"文件超过 50 MB。"}];return;}
  copied=[fm copyItemAtURL:readable toURL:destination error:&copyError];
 }];
 if(!copied&&error)*error=copyError?:coordinationError?:[NSError errorWithDomain:@"ReaderPlusImport" code:5 userInfo:@{NSLocalizedDescriptionKey:@"文件提供方未提供可读取的副本，请重试或从文件管理器分享导入。"}];
 return copied;
}
