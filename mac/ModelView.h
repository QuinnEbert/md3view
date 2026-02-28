#import <Cocoa/Cocoa.h>
#import <OpenGL/gl3.h>

@class MD3PlayerModel;
@class ModelRenderer;
@class TextureCache;

@interface ModelView : NSOpenGLView

@property (nonatomic, strong) MD3PlayerModel *playerModel;
@property (nonatomic, strong) ModelRenderer *renderer;
@property (nonatomic, strong) TextureCache *textureCache;
@property (nonatomic) float gamma; // default 1.0

- (void)startDisplayLink;
- (void)stopDisplayLink;
- (NSImage *)captureScreenshotWithScale:(int)scale;
- (NSImage *)captureRenderWithWidth:(int)width height:(int)height;

@end
