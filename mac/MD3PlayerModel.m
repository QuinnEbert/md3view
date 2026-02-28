#import "MD3PlayerModel.h"
#import "MD3Model.h"
#import "AnimationConfig.h"
#import "SkinParser.h"
#import "PK3Archive.h"
#import "ModelRenderer.h"
#import "TextureCache.h"
#import <math.h>
#import <mach/mach_time.h>

static double currentTimeMs(void) {
    static mach_timebase_info_data_t info;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ mach_timebase_info(&info); });
    uint64_t t = mach_absolute_time();
    return (double)(t * info.numer / info.denom) / 1000000.0;
}

static void vectorNormalize(float *v) {
    float len = sqrtf(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
    if (len > 0.0001f) { v[0] /= len; v[1] /= len; v[2] /= len; }
}

static void matrixMultiply3x3(float in1[3][3], float in2[3][3], float out[3][3]) {
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            out[i][j] = in1[i][0]*in2[0][j] + in1[i][1]*in2[1][j] + in1[i][2]*in2[2][j];
        }
    }
}

@implementation MD3PlayerModel {
    MD3Model *_lower;
    MD3Model *_upper;
    MD3Model *_head;
    AnimationConfig *_animConfig;
    NSDictionary<NSString *, NSString *> *_lowerSkin;
    NSDictionary<NSString *, NSString *> *_upperSkin;
    NSDictionary<NSString *, NSString *> *_headSkin;
    NSString *_modelName;
    NSString *_modelPath;
    PK3Archive *_archive;
    NSArray<NSString *> *_availableSkins;
    NSString *_currentSkin;
    float _centerHeight;
    float _boundingRadius;

    AnimState _torsoState;
    AnimState _legsState;
    BOOL _playing;
}

- (instancetype)initWithArchive:(PK3Archive *)archive modelPath:(NSString *)modelPath {
    self = [super init];
    if (!self) return nil;

    _modelName = [modelPath lastPathComponent];
    _modelPath = [modelPath copy];
    _archive = archive;

    // Enumerate available skins
    [self enumerateSkins];

    // Load MD3 files
    NSData *lowerData = [archive readFile:[modelPath stringByAppendingPathComponent:@"lower.md3"]];
    NSData *upperData = [archive readFile:[modelPath stringByAppendingPathComponent:@"upper.md3"]];
    NSData *headData = [archive readFile:[modelPath stringByAppendingPathComponent:@"head.md3"]];

    if (!lowerData || !upperData || !headData) {
        NSLog(@"MD3PlayerModel: missing .md3 files in %@", modelPath);
        return nil;
    }

    _lower = [[MD3Model alloc] initWithData:lowerData name:@"lower.md3"];
    _upper = [[MD3Model alloc] initWithData:upperData name:@"upper.md3"];
    _head = [[MD3Model alloc] initWithData:headData name:@"head.md3"];

    if (!_lower || !_upper || !_head) {
        NSLog(@"MD3PlayerModel: failed to parse .md3 files");
        return nil;
    }

    // Load default skin
    _currentSkin = @"default";
    [self loadSkin:_currentSkin];

    // Load animation config
    NSData *animData = [archive readFile:[modelPath stringByAppendingPathComponent:@"animation.cfg"]];
    if (animData) {
        _animConfig = [[AnimationConfig alloc] initWithData:animData];
    }

    // Compute center height from frame 0 bounding boxes
    [self computeCenterHeight];

    // Default animations
    _playing = YES;
    [self initAnimState:&_torsoState withAnim:TORSO_STAND];
    [self initAnimState:&_legsState withAnim:LEGS_IDLE];

    return self;
}

- (void)initAnimState:(AnimState *)state withAnim:(AnimNumber)anim {
    state->animIndex = anim;
    state->currentFrame = 0;
    state->nextFrame = 0;
    state->fraction = 0;
    state->frameTime = currentTimeMs();
    state->playing = YES;
}

static void transformPoint(const float *in, const float origin[3], const float axis[3][3], float *out) {
    // out = origin + in[0]*axis[0] + in[1]*axis[1] + in[2]*axis[2]
    for (int i = 0; i < 3; i++) {
        out[i] = origin[i] + in[0]*axis[0][i] + in[1]*axis[1][i] + in[2]*axis[2][i];
    }
}

- (void)computeCenterHeight {
    // Use the idle pose frames for accurate bounds of the standing model.
    int legsFrame = 0;
    int torsoFrame = 0;
    if (_animConfig) {
        const Animation *anims = [_animConfig animations];
        legsFrame = anims[LEGS_IDLE].firstFrame;
        torsoFrame = anims[TORSO_STAND].firstFrame;
    }
    // Clamp to valid ranges
    if (legsFrame >= [_lower numFrames]) legsFrame = 0;
    if (torsoFrame >= [_upper numFrames]) torsoFrame = 0;

    float minX = 1e9f, maxX = -1e9f;
    float minY = 1e9f, maxY = -1e9f;
    float minZ = 1e9f, maxZ = -1e9f;

    // Lower body verts at idle frame
    MD3Surface *surfaces = [_lower surfaces];
    for (int s = 0; s < [_lower numSurfaces]; s++) {
        MD3Vertex *verts = &surfaces[s].vertices[legsFrame * surfaces[s].numVerts];
        for (int v = 0; v < surfaces[s].numVerts; v++) {
            float x = verts[v].position[0], y = verts[v].position[1], z = verts[v].position[2];
            if (x < minX) minX = x; if (x > maxX) maxX = x;
            if (y < minY) minY = y; if (y > maxY) maxY = y;
            if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
        }
    }

    // Get tag_torso at legs idle frame — full transform, not just Z offset
    MD3Tag *torsoTag = [_lower tagForName:"tag_torso" atFrame:legsFrame];
    float tOrigin[3] = {0, 0, 0};
    float tAxis[3][3] = {{1,0,0},{0,1,0},{0,0,1}};
    if (torsoTag) {
        memcpy(tOrigin, torsoTag->origin, sizeof(float) * 3);
        memcpy(tAxis, torsoTag->axis, sizeof(float) * 9);
    }

    // Upper body verts at torso stand frame, transformed through tag_torso
    surfaces = [_upper surfaces];
    for (int s = 0; s < [_upper numSurfaces]; s++) {
        MD3Vertex *verts = &surfaces[s].vertices[torsoFrame * surfaces[s].numVerts];
        for (int v = 0; v < surfaces[s].numVerts; v++) {
            float world[3];
            transformPoint(verts[v].position, tOrigin, tAxis, world);
            if (world[0] < minX) minX = world[0]; if (world[0] > maxX) maxX = world[0];
            if (world[1] < minY) minY = world[1]; if (world[1] > maxY) maxY = world[1];
            if (world[2] < minZ) minZ = world[2]; if (world[2] > maxZ) maxZ = world[2];
        }
    }

    // Get tag_head at torso stand frame, transformed through tag_torso
    MD3Tag *headTag = [_upper tagForName:"tag_head" atFrame:torsoFrame];
    float hOrigin[3] = {0, 0, 0};
    float hAxis[3][3] = {{1,0,0},{0,1,0},{0,0,1}};
    if (headTag) {
        // Transform tag_head through tag_torso
        float localOrigin[3];
        transformPoint(headTag->origin, tOrigin, tAxis, localOrigin);
        memcpy(hOrigin, localOrigin, sizeof(float) * 3);
        matrixMultiply3x3(headTag->axis, tAxis, hAxis);
    }

    // Head verts at frame 0, transformed through both tags
    surfaces = [_head surfaces];
    for (int s = 0; s < [_head numSurfaces]; s++) {
        MD3Vertex *verts = &surfaces[s].vertices[0]; // head is typically 1 frame
        for (int v = 0; v < surfaces[s].numVerts; v++) {
            float world[3];
            transformPoint(verts[v].position, hOrigin, hAxis, world);
            if (world[0] < minX) minX = world[0]; if (world[0] > maxX) maxX = world[0];
            if (world[1] < minY) minY = world[1]; if (world[1] > maxY) maxY = world[1];
            if (world[2] < minZ) minZ = world[2]; if (world[2] > maxZ) maxZ = world[2];
        }
    }

    float cx = (minX + maxX) * 0.5f;
    float cy = (minY + maxY) * 0.5f;
    float cz = (minZ + maxZ) * 0.5f;
    _centerHeight = cz;

    // Bounding radius from center point
    float dx = fmaxf(maxX - cx, cx - minX);
    float dy = fmaxf(maxY - cy, cy - minY);
    float dz = fmaxf(maxZ - cz, cz - minZ);
    _boundingRadius = sqrtf(dx*dx + dy*dy + dz*dz);
}

- (float)centerHeight { return _centerHeight; }
- (float)boundingRadius { return _boundingRadius; }

- (void)enumerateSkins {
    NSMutableSet<NSString *> *skinNames = [NSMutableSet new];
    NSString *prefix = [_modelPath stringByAppendingPathComponent:@"lower_"];

    for (NSString *file in [_archive allFiles]) {
        NSString *lower = [file lowercaseString];
        NSString *prefixLower = [prefix lowercaseString];
        if ([lower hasPrefix:prefixLower] && [lower hasSuffix:@".skin"]) {
            // Extract skin name: "lower_red.skin" -> "red"
            NSString *filename = [[file lastPathComponent] lowercaseString];
            NSString *skinName = [filename substringFromIndex:6]; // skip "lower_"
            skinName = [skinName stringByDeletingPathExtension];   // strip ".skin"
            if (skinName.length > 0) {
                [skinNames addObject:skinName];
            }
        }
    }

    // Sort with "default" first
    NSMutableArray *sorted = [[skinNames allObjects] mutableCopy];
    [sorted sortUsingSelector:@selector(caseInsensitiveCompare:)];
    if ([sorted containsObject:@"default"]) {
        [sorted removeObject:@"default"];
        [sorted insertObject:@"default" atIndex:0];
    }
    _availableSkins = [sorted copy];
}

- (void)loadSkin:(NSString *)skinName {
    NSString *lowerSkinPath = [_modelPath stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"lower_%@.skin", skinName]];
    NSString *upperSkinPath = [_modelPath stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"upper_%@.skin", skinName]];
    NSString *headSkinPath = [_modelPath stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"head_%@.skin", skinName]];

    NSData *lowerSkinData = [_archive readFile:lowerSkinPath];
    NSData *upperSkinData = [_archive readFile:upperSkinPath];
    NSData *headSkinData = [_archive readFile:headSkinPath];

    _lowerSkin = [SkinParser parseSkinData:lowerSkinData];
    _upperSkin = [SkinParser parseSkinData:upperSkinData];
    _headSkin = [SkinParser parseSkinData:headSkinData];
    _currentSkin = [skinName copy];
}

- (void)selectSkin:(NSString *)skinName {
    [self loadSkin:skinName];
}

- (NSArray<NSString *> *)availableSkins { return _availableSkins; }
- (NSString *)currentSkin { return _currentSkin; }

- (AnimNumber)torsoAnim { return _torsoState.animIndex; }
- (AnimNumber)legsAnim { return _legsState.animIndex; }

- (void)setTorsoAnim:(AnimNumber)torsoAnim {
    [self setTorsoAnimation:torsoAnim];
}

- (void)setLegsAnim:(AnimNumber)legsAnim {
    [self setLegsAnimation:legsAnim];
}

- (BOOL)playing { return _playing; }
- (void)setPlaying:(BOOL)playing { _playing = playing; }
- (NSString *)modelName { return _modelName; }
- (AnimationConfig *)animConfig { return _animConfig; }

- (void)setTorsoAnimation:(AnimNumber)anim {
    [self initAnimState:&_torsoState withAnim:anim];
}

- (void)setLegsAnimation:(AnimNumber)anim {
    [self initAnimState:&_legsState withAnim:anim];
}

- (void)stepFrame:(int)direction {
    if (_playing) return;
    [self stepAnimState:&_torsoState direction:direction];
    [self stepAnimState:&_legsState direction:direction];
}

- (void)stepAnimState:(AnimState *)state direction:(int)dir {
    if (!_animConfig) return;
    const Animation *anim = &_animConfig.animations[state->animIndex];
    if (anim->numFrames <= 0) return;

    state->currentFrame += dir;
    if (state->currentFrame < 0) state->currentFrame = anim->numFrames - 1;
    if (state->currentFrame >= anim->numFrames) state->currentFrame = 0;
    state->nextFrame = state->currentFrame;
    state->fraction = 0;
}

- (int)torsoCurrentFrame { return _torsoState.currentFrame; }
- (int)torsoNumFrames {
    if (!_animConfig) return 0;
    return _animConfig.animations[_torsoState.animIndex].numFrames;
}
- (int)legsCurrentFrame { return _legsState.currentFrame; }
- (int)legsNumFrames {
    if (!_animConfig) return 0;
    return _animConfig.animations[_legsState.animIndex].numFrames;
}

- (void)scrubTorsoToFrame:(int)frame {
    if (!_animConfig) return;
    const Animation *anim = &_animConfig.animations[_torsoState.animIndex];
    if (anim->numFrames <= 0) return;
    _torsoState.currentFrame = frame % anim->numFrames;
    _torsoState.nextFrame = _torsoState.currentFrame;
    _torsoState.fraction = 0;
}

- (void)scrubLegsToFrame:(int)frame {
    if (!_animConfig) return;
    const Animation *anim = &_animConfig.animations[_legsState.animIndex];
    if (anim->numFrames <= 0) return;
    _legsState.currentFrame = frame % anim->numFrames;
    _legsState.nextFrame = _legsState.currentFrame;
    _legsState.fraction = 0;
}

- (void)updateAnimState:(AnimState *)state {
    if (!_playing || !_animConfig) return;
    const Animation *anim = &_animConfig.animations[state->animIndex];
    if (anim->numFrames <= 1) return;

    double now = currentTimeMs();
    double elapsed = now - state->frameTime;

    if (anim->frameLerp <= 0) return;

    state->fraction = (float)(elapsed / (double)anim->frameLerp);
    while (state->fraction >= 1.0f) {
        state->fraction -= 1.0f;
        state->frameTime += anim->frameLerp;
        state->currentFrame++;

        if (anim->loopFrames > 0) {
            // Looping animation
            if (state->currentFrame >= anim->numFrames) {
                state->currentFrame = anim->numFrames - anim->loopFrames;
            }
        } else {
            // Non-looping: clamp to last frame
            if (state->currentFrame >= anim->numFrames - 1) {
                state->currentFrame = anim->numFrames - 1;
                state->fraction = 0;
            }
        }
    }

    state->nextFrame = state->currentFrame + 1;
    if (anim->loopFrames > 0) {
        if (state->nextFrame >= anim->numFrames) {
            state->nextFrame = anim->numFrames - anim->loopFrames;
        }
    } else {
        if (state->nextFrame >= anim->numFrames) {
            state->nextFrame = anim->numFrames - 1;
        }
    }
}

- (void)getFrameA:(int *)frameA frameB:(int *)frameB fraction:(float *)frac
     forAnimState:(AnimState *)state {
    if (!_animConfig) {
        *frameA = 0; *frameB = 0; *frac = 0;
        return;
    }
    const Animation *anim = &_animConfig.animations[state->animIndex];

    int fa = anim->firstFrame + state->currentFrame;
    int fb = anim->firstFrame + state->nextFrame;

    if (anim->reversed) {
        fa = anim->firstFrame + anim->numFrames - 1 - state->currentFrame;
        fb = anim->firstFrame + anim->numFrames - 1 - state->nextFrame;
    }

    *frameA = fa;
    *frameB = fb;
    *frac = state->fraction;
}

- (void)lerpTag:(MD3Tag *)outTag model:(MD3Model *)model tagName:(const char *)tagName
         frameA:(int)frameA frameB:(int)frameB fraction:(float)frac {
    MD3Tag *tagA = [model tagForName:tagName atFrame:frameA];
    MD3Tag *tagB = [model tagForName:tagName atFrame:frameB];

    if (!tagA || !tagB) {
        memset(outTag, 0, sizeof(MD3Tag));
        outTag->axis[0][0] = 1; outTag->axis[1][1] = 1; outTag->axis[2][2] = 1;
        return;
    }

    float backLerp = 1.0f - frac;
    for (int i = 0; i < 3; i++) {
        outTag->origin[i] = tagA->origin[i] * backLerp + tagB->origin[i] * frac;
        outTag->axis[0][i] = tagA->axis[0][i] * backLerp + tagB->axis[0][i] * frac;
        outTag->axis[1][i] = tagA->axis[1][i] * backLerp + tagB->axis[1][i] * frac;
        outTag->axis[2][i] = tagA->axis[2][i] * backLerp + tagB->axis[2][i] * frac;
    }
    vectorNormalize(outTag->axis[0]);
    vectorNormalize(outTag->axis[1]);
    vectorNormalize(outTag->axis[2]);
}

- (TagTransform)positionChildOnTag:(TagTransform)parentTransform tag:(MD3Tag)tag {
    TagTransform child;

    // child.origin = parent.origin + tag.origin[0]*parent.axis[0] + tag.origin[1]*parent.axis[1] + tag.origin[2]*parent.axis[2]
    for (int i = 0; i < 3; i++) {
        child.origin[i] = parentTransform.origin[i];
        for (int j = 0; j < 3; j++) {
            child.origin[i] += tag.origin[j] * parentTransform.axis[j][i];
        }
    }

    // child.axis = tag.axis * parent.axis
    matrixMultiply3x3(tag.axis, parentTransform.axis, child.axis);

    return child;
}

- (void)renderWithRenderer:(ModelRenderer *)renderer
              textureCache:(TextureCache *)texCache
                viewMatrix:(const float *)viewMatrix
                projMatrix:(const float *)projMatrix
                     gamma:(float)gamma {

    [self updateAnimState:&_torsoState];
    [self updateAnimState:&_legsState];

    // --- Lower body (legs) ---
    int legsFrameA, legsFrameB;
    float legsFrac;
    [self getFrameA:&legsFrameA frameB:&legsFrameB fraction:&legsFrac forAnimState:&_legsState];

    TagTransform legsTransform;
    memset(&legsTransform, 0, sizeof(legsTransform));
    legsTransform.axis[0][0] = 1; legsTransform.axis[1][1] = 1; legsTransform.axis[2][2] = 1;

    [renderer renderModel:_lower atFrame:legsFrameA nextFrame:legsFrameB fraction:legsFrac
                transform:legsTransform textureCache:texCache skinMappings:_lowerSkin
               viewMatrix:viewMatrix projMatrix:projMatrix gamma:gamma];

    // --- Upper body (torso) ---
    // Get tag_torso from lower model
    MD3Tag torsoTag;
    [self lerpTag:&torsoTag model:_lower tagName:"tag_torso" frameA:legsFrameA frameB:legsFrameB fraction:legsFrac];
    TagTransform torsoTransform = [self positionChildOnTag:legsTransform tag:torsoTag];

    int torsoFrameA, torsoFrameB;
    float torsoFrac;
    [self getFrameA:&torsoFrameA frameB:&torsoFrameB fraction:&torsoFrac forAnimState:&_torsoState];

    [renderer renderModel:_upper atFrame:torsoFrameA nextFrame:torsoFrameB fraction:torsoFrac
                transform:torsoTransform textureCache:texCache skinMappings:_upperSkin
               viewMatrix:viewMatrix projMatrix:projMatrix gamma:gamma];

    // --- Head ---
    MD3Tag headTag;
    [self lerpTag:&headTag model:_upper tagName:"tag_head" frameA:torsoFrameA frameB:torsoFrameB fraction:torsoFrac];
    TagTransform headTransform = [self positionChildOnTag:torsoTransform tag:headTag];

    // Head is static (frame 0)
    [renderer renderModel:_head atFrame:0 nextFrame:0 fraction:0
                transform:headTransform textureCache:texCache skinMappings:_headSkin
               viewMatrix:viewMatrix projMatrix:projMatrix gamma:gamma];
}

@end
