#import <Foundation/Foundation.h>
#import "MD3Types.h"

@interface AnimationConfig : NSObject

- (nullable instancetype)initWithData:(NSData *)data;

- (const Animation *)animations;

@property (nonatomic, readonly) BOOL fixedLegs;
@property (nonatomic, readonly) BOOL fixedTorso;

@end
