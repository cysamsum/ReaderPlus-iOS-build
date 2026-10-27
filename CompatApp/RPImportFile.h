#import <Foundation/Foundation.h>

// Copy a provider-owned file to a permanent app URL while access is held by caller.
BOOL RPCopyImportFile(NSURL *selected,NSURL *destination,NSError **error);
