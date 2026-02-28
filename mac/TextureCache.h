#import <Foundation/Foundation.h>
#import <OpenGL/gl3.h>

@class PK3Archive;

@interface TextureCache : NSObject

- (instancetype)initWithArchive:(PK3Archive *)archive;
- (GLuint)textureForPath:(NSString *)path;
- (GLuint)whiteTexture;
- (void)flush;

@end
