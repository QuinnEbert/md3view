#import <Foundation/Foundation.h>
#import "MD3Types.h"

@class MD3Model;
@class AnimationConfig;
@class ModelRenderer;
@class TextureCache;
@class PK3Archive;

@interface MD3PlayerModel : NSObject

- (nullable instancetype)initWithArchive:(PK3Archive *)archive
                               modelPath:(NSString *)modelPath;

@property (nonatomic, readonly) NSString *modelName;
@property (nonatomic, readonly) AnimationConfig *animConfig;

// Skin selection
@property (nonatomic, readonly) NSArray<NSString *> *availableSkins;
@property (nonatomic, readonly) NSString *currentSkin;
- (void)selectSkin:(NSString *)skinName;

// Animation control
@property (nonatomic) AnimNumber torsoAnim;
@property (nonatomic) AnimNumber legsAnim;
@property (nonatomic) BOOL playing;

- (void)setTorsoAnimation:(AnimNumber)anim;
- (void)setLegsAnimation:(AnimNumber)anim;
- (void)stepFrame:(int)direction; // +1 or -1 for frame stepping when paused

// Frame info for UI
- (int)torsoCurrentFrame;
- (int)torsoNumFrames;
- (int)legsCurrentFrame;
- (int)legsNumFrames;

// Scrub to specific frame (0..numFrames-1)
- (void)scrubTorsoToFrame:(int)frame;
- (void)scrubLegsToFrame:(int)frame;

// Model center height (Z) for camera targeting — midpoint of assembled model
@property (nonatomic, readonly) float centerHeight;
// Bounding radius from center point (for camera framing)
@property (nonatomic, readonly) float boundingRadius;

- (void)renderWithRenderer:(ModelRenderer *)renderer
              textureCache:(TextureCache *)texCache
                viewMatrix:(const float *)viewMatrix
                projMatrix:(const float *)projMatrix
                     gamma:(float)gamma;

@end
