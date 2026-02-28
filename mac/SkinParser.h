#import <Foundation/Foundation.h>

@interface SkinParser : NSObject

// Parse a .skin file: returns dictionary of surface_name -> texture_path
+ (NSDictionary<NSString *, NSString *> *)parseSkinData:(NSData *)data;

@end
