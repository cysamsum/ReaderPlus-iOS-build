#import <Foundation/Foundation.h>

@protocol ReaderPlusAudioRequest <NSObject>
-(void)synthesize:(NSString*)text voice:(NSString*)voice locale:(NSString*)locale rate:(NSInteger)rate completion:(void(^)(NSData*,NSError*))completion;
-(void)cancel;
@end

@interface ReaderPlusAudioSegment : NSObject
@property(nonatomic,readonly)NSInteger section,paragraph;
@property(nonatomic,copy,readonly)NSString *text;
@property(nonatomic,strong,readonly)NSData *audio;
@property(nonatomic,strong,readonly)NSError *error;
@end

// Owns only the current paragraph and two lookahead paragraphs, in book order.
// Callers and notifications run on the main thread. A factory permits delayed,
// out-of-order responses in regression tests without contacting the service.
@interface ReaderPlusAudioPipeline : NSObject
@property(nonatomic,copy)void(^changed)(void);
@property(nonatomic,strong,readonly)ReaderPlusAudioSegment *currentSegment,*nextSegment;
@property(nonatomic,readonly)NSUInteger bufferedCount,inFlightCount,networkRequestCount;
-(instancetype)initWithDocument:(NSDictionary*)document section:(NSInteger)section paragraph:(NSInteger)paragraph voice:(NSString*)voice rate:(NSInteger)rate allowNetwork:(BOOL)allowNetwork requestFactory:(id<ReaderPlusAudioRequest>(^)(void))factory;
-(void)start;
-(void)advance;
-(void)cancel;
@end
