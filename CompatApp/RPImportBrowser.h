#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

// Lists supported books and folders within the app's Documents directory.
NSArray *RPLocalImportFiles(NSURL *root,NSURL *directory,NSError **error);

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
@interface ReaderPlusImportBrowser:UITableViewController
@property(nonatomic,copy)void(^picked)(NSURL*);
-(instancetype)initWithRoot:(NSURL*)root directory:(NSURL*)directory;
@end
#endif
