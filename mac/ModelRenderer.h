#import <Foundation/Foundation.h>
#import <OpenGL/gl3.h>
#import "MD3Types.h"

@class MD3Model;
@class TextureCache;

typedef struct {
    float origin[3];
    float axis[3][3];
} TagTransform;

@interface ModelRenderer : NSObject

- (instancetype)init;
- (BOOL)setupShaders;
- (void)renderModel:(MD3Model *)model
         atFrame:(int)frameA
       nextFrame:(int)frameB
        fraction:(float)frac
       transform:(TagTransform)transform
    textureCache:(TextureCache *)texCache
    skinMappings:(NSDictionary<NSString *, NSString *> *)skin
   viewMatrix:(const float *)viewMatrix
   projMatrix:(const float *)projMatrix
       gamma:(float)gamma;
- (void)cleanup;

@end
