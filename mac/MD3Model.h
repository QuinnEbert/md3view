#import <Foundation/Foundation.h>
#import "MD3Types.h"

@interface MD3Model : NSObject

- (nullable instancetype)initWithData:(NSData *)data name:(NSString *)name;

@property (nonatomic, readonly) int numFrames;
@property (nonatomic, readonly) int numTags;
@property (nonatomic, readonly) int numSurfaces;

@property (nonatomic, readonly) MD3Surface *surfaces;
@property (nonatomic, readonly) MD3Tag *tags;       // numTags * numFrames
@property (nonatomic, readonly) MD3Frame *frames;

- (nullable MD3Tag *)tagForName:(const char *)name atFrame:(int)frame;

@end
