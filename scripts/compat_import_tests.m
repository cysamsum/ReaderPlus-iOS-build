#import <Foundation/Foundation.h>
#import "RPImportBrowser.h"
#import "RPDocument.h"
#import "RPImportFile.h"

void ReaderPlusRunImportTests(void){
 NSFileManager *fm=[NSFileManager defaultManager];NSError *error=nil;
 NSURL *fixture=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]URLByAppendingPathComponent:[@"ReaderPlusImport-" stringByAppendingString:[NSUUID UUID].UUIDString] isDirectory:YES];
 NSURL *documents=[fixture URLByAppendingPathComponent:@"Documents" isDirectory:YES];
 NSURL *folder=[documents URLByAppendingPathComponent:@"Books" isDirectory:YES];
 NSCAssert([fm createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error],@"Create fixture");
 NSCAssert([fm createDirectoryAtURL:[documents URLByAppendingPathComponent:@"Library"] withIntermediateDirectories:YES attributes:nil error:&error],@"Create internal library");
 for(NSString *name in @[@"Book.TXT",@"Book.epub",@"Book.pdf",@"Notes.md",@"ignored.bin",@".hidden.txt"])[@"Import test text." writeToURL:[documents URLByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:&error];
 NSURL *child=[folder URLByAppendingPathComponent:@"Child.txt"];[@"本机导入测试，选择文件后应该显示这一段。" writeToURL:child atomically:YES encoding:NSUTF8StringEncoding error:&error];
 NSURL *outside=[fixture URLByAppendingPathComponent:@"Outside.txt"];[@"outside" writeToURL:outside atomically:YES encoding:NSUTF8StringEncoding error:&error];
 NSCAssert([fm createSymbolicLinkAtURL:[documents URLByAppendingPathComponent:@"Link.txt"] withDestinationURL:outside error:&error],@"Create symlink fixture");
 NSArray *files=RPLocalImportFiles(documents,documents,&error);
 NSSet *names=[NSSet setWithArray:[files valueForKey:@"lastPathComponent"]];
 NSCAssert(([names isEqual:[NSSet setWithArray:@[@"Books",@"Book.TXT",@"Book.epub",@"Book.pdf",@"Notes.md"]]]),@"List all supported books, omit internal/hidden/unsupported/symlink files");
 NSCAssert([files[0]lastPathComponent]&&[[files[0]lastPathComponent]isEqual:@"Books"],@"Folders precede files");
 NSArray *children=RPLocalImportFiles(documents,folder,&error);NSString *selected=children.count?[children[0]URLByResolvingSymlinksInPath].path:nil;NSCAssert(children.count==1&&[selected isEqual:child.URLByResolvingSymlinksInPath.path],@"Navigate within Documents: %@ expected %@ error %@",children,child,error);
 NSDictionary *book=RPImportDocument(children[0],@"Local book",&error);NSCAssert(book&&!error&&[book[@"sections"]count]>0,@"Selected local URL imports through the existing reader parser");
 error=nil;NSCAssert(!RPLocalImportFiles(documents,fixture,&error)&&error,@"Reject navigation outside Documents");
 // Selected temporary files must survive independently after the provider releases them.
 NSURL *selectedEPUB=[fixture URLByAppendingPathComponent:@"Selected.epub"];
 NSURL *savedEPUB=[documents URLByAppendingPathComponent:@"Permanent.epub"];
 NSURL *sample=[[NSURL fileURLWithPath:[fm currentDirectoryPath]]URLByAppendingPathComponent:@"samples/体验电子书.epub"];
 error=nil;NSCAssert([fm copyItemAtURL:sample toURL:selectedEPUB error:&error],@"Stage picker file");
 NSData *original=[NSData dataWithContentsOfURL:selectedEPUB];
 NSCAssert(RPCopyImportFile(selectedEPUB,savedEPUB,&error)&&!error,@"Coordinate provider file into permanent app storage: %@",error);
 NSCAssert([fm removeItemAtURL:selectedEPUB error:&error],@"Provider releases its temporary copy");
 NSCAssert([[NSData dataWithContentsOfURL:savedEPUB]isEqual:original],@"Permanent copy preserves selected bytes");
 NSDictionary *imported=RPImportDocument(savedEPUB,@"Selected EPUB",&error);NSCAssert(imported&&!error&&[imported[@"sections"]count]==2,@"Parse the coordinated EPUB after temporary source is gone");
 error=nil;NSCAssert(!RPCopyImportFile(selectedEPUB,[documents URLByAppendingPathComponent:@"Missing.epub"],&error)&&error,@"Surface unavailable provider files as an error");
 error=nil;NSCAssert(!RPCopyImportFile(folder,[documents URLByAppendingPathComponent:@"Folder.epub"],&error)&&error,@"Reject directories supplied by a host picker");
 NSString *tempRoot=[NSURL fileURLWithPath:NSTemporaryDirectory()].URLByResolvingSymlinksInPath.path;NSCAssert([fixture.URLByResolvingSymlinksInPath.path hasPrefix:[tempRoot stringByAppendingString:@"/"]],@"Cleanup stays within the generated temporary fixture");[fm removeItemAtURL:fixture error:nil];
 puts("PASS: local import catalog, coordinated provider copy, temporary file lifetime, errors, EPUB parsing and boundaries");
}
