#import <Foundation/Foundation.h>

@interface PK3Archive : NSObject

- (nullable instancetype)initWithPath:(NSString *)path;
- (NSArray<NSString *> *)allFiles;
- (NSArray<NSString *> *)playerModelPaths;
- (nullable NSData *)readFile:(NSString *)filePath;

@property (nonatomic, readonly) NSString *archivePath;

@end
