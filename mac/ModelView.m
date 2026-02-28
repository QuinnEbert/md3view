#import "ModelView.h"
#import "ModelRenderer.h"
#import "MD3PlayerModel.h"
#import "TextureCache.h"
#import <OpenGL/gl3.h>
#import <QuartzCore/CVDisplayLink.h>
#import <math.h>

@implementation ModelView {
    CVDisplayLinkRef _displayLink;
    float _rotationX;
    float _rotationY;
    float _zoom;
    NSPoint _lastMouse;
    BOOL _dragging;
    BOOL _shadersReady;
}

- (instancetype)initWithFrame:(NSRect)frame {
    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFAAlphaSize, 8,
        NSOpenGLPFADepthSize, 24,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAAccelerated,
        NSOpenGLPFASampleBuffers, 1,
        NSOpenGLPFASamples, 4,
        0
    };
    NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    self = [super initWithFrame:frame pixelFormat:pf];
    if (self) {
        _rotationX = 0;
        _rotationY = -90;  // Start facing camera
        _zoom = 100.0f;
        _dragging = NO;
        _shadersReady = NO;
        _gamma = 1.0f;
        [self setWantsBestResolutionOpenGLSurface:YES];
    }
    return self;
}

- (void)prepareOpenGL {
    [super prepareOpenGL];

    [[self openGLContext] makeCurrentContext];

    GLint swapInterval = 1;
    [[self openGLContext] setValues:&swapInterval forParameter:NSOpenGLContextParameterSwapInterval];

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    glFrontFace(GL_CW);  // Q3 winding order
    glCullFace(GL_BACK);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glClearColor(0.2f, 0.2f, 0.25f, 1.0f);

    if (!_renderer) {
        _renderer = [[ModelRenderer alloc] init];
    }
    _shadersReady = [_renderer setupShaders];
    if (!_shadersReady) {
        NSLog(@"ModelView: shader setup failed");
    }
}

static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *now,
                                     const CVTimeStamp *outputTime, CVOptionFlags flagsIn,
                                     CVOptionFlags *flagsOut, void *ctx) {
    @autoreleasepool {
        ModelView *view = (__bridge ModelView *)ctx;
        dispatch_async(dispatch_get_main_queue(), ^{
            [view setNeedsDisplay:YES];
        });
    }
    return kCVReturnSuccess;
}

- (void)startDisplayLink {
    if (_displayLink) return;
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, displayLinkCallback, (__bridge void *)self);
    CGLContextObj cglCtx = [[self openGLContext] CGLContextObj];
    CGLPixelFormatObj cglPF = [[self pixelFormat] CGLPixelFormatObj];
    CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, cglCtx, cglPF);
    CVDisplayLinkStart(_displayLink);
}

- (void)stopDisplayLink {
    if (_displayLink) {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
        _displayLink = NULL;
    }
}

- (void)dealloc {
    [self stopDisplayLink];
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)reshape {
    [super reshape];
    [[self openGLContext] makeCurrentContext];
    NSSize size = [self convertSizeToBacking:self.bounds.size];
    glViewport(0, 0, (GLsizei)size.width, (GLsizei)size.height);
}

static void buildPerspective(float *m, float fovY, float aspect, float nearZ, float farZ) {
    float f = 1.0f / tanf(fovY * 0.5f * M_PI / 180.0f);
    memset(m, 0, 16 * sizeof(float));
    m[0] = f / aspect;
    m[5] = f;
    m[10] = (farZ + nearZ) / (nearZ - farZ);
    m[11] = -1.0f;
    m[14] = (2.0f * farZ * nearZ) / (nearZ - farZ);
}

static void buildLookAt(float *m, float eyeX, float eyeY, float eyeZ,
                         float cx, float cy, float cz,
                         float upX, float upY, float upZ) {
    float fx = cx - eyeX, fy = cy - eyeY, fz = cz - eyeZ;
    float flen = sqrtf(fx*fx + fy*fy + fz*fz);
    fx /= flen; fy /= flen; fz /= flen;

    float sx = fy*upZ - fz*upY, sy = fz*upX - fx*upZ, sz = fx*upY - fy*upX;
    float slen = sqrtf(sx*sx + sy*sy + sz*sz);
    sx /= slen; sy /= slen; sz /= slen;

    float ux = sy*fz - sz*fy, uy = sz*fx - sx*fz, uz = sx*fy - sy*fx;

    memset(m, 0, 16 * sizeof(float));
    m[0] = sx;  m[4] = sy;  m[8]  = sz;  m[12] = -(sx*eyeX + sy*eyeY + sz*eyeZ);
    m[1] = ux;  m[5] = uy;  m[9]  = uz;  m[13] = -(ux*eyeX + uy*eyeY + uz*eyeZ);
    m[2] = -fx; m[6] = -fy; m[10] = -fz; m[14] =  (fx*eyeX + fy*eyeY + fz*eyeZ);
    m[3] = 0;   m[7] = 0;   m[11] = 0;   m[15] = 1;
}

- (void)drawRect:(NSRect)dirtyRect {
    [[self openGLContext] makeCurrentContext];

    if (!_shadersReady) return;

    NSSize size = [self convertSizeToBacking:self.bounds.size];
    glViewport(0, 0, (GLsizei)size.width, (GLsizei)size.height);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    if (_playerModel && _textureCache) {
        float aspect = size.width / size.height;
        float projMatrix[16];
        buildPerspective(projMatrix, 45.0f, aspect, 1.0f, 2000.0f);

        // Camera orbiting around model center, Z-up
        float centerZ = [_playerModel centerHeight];
        float radX = _rotationX * M_PI / 180.0f;
        float radY = _rotationY * M_PI / 180.0f;
        float camX = _zoom * cosf(radX) * cosf(radY);
        float camY = _zoom * cosf(radX) * sinf(radY);
        float camZ = centerZ + _zoom * sinf(radX);

        float viewMatrix[16];
        buildLookAt(viewMatrix, camX, camY, camZ, 0, 0, centerZ, 0, 0, 1);

        [_playerModel renderWithRenderer:_renderer
                            textureCache:_textureCache
                              viewMatrix:viewMatrix
                              projMatrix:projMatrix
                                   gamma:_gamma];
    }

    [[self openGLContext] flushBuffer];
}

// Mouse interaction
- (void)mouseDown:(NSEvent *)event {
    _dragging = YES;
    _lastMouse = [self convertPoint:[event locationInWindow] fromView:nil];
}

- (void)mouseUp:(NSEvent *)event {
    _dragging = NO;
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint pos = [self convertPoint:[event locationInWindow] fromView:nil];
    float dx = pos.x - _lastMouse.x;
    float dy = pos.y - _lastMouse.y;
    _rotationY += dx * 0.5f;
    _rotationX += dy * 0.5f;
    // Clamp pitch
    if (_rotationX > 89) _rotationX = 89;
    if (_rotationX < -89) _rotationX = -89;
    _lastMouse = pos;
    [self setNeedsDisplay:YES];
}

- (void)scrollWheel:(NSEvent *)event {
    _zoom -= [event deltaY] * 2.0f;
    if (_zoom < 10) _zoom = 10;
    if (_zoom > 500) _zoom = 500;
    [self setNeedsDisplay:YES];
}

- (void)keyDown:(NSEvent *)event {
    // Arrow keys for frame stepping when paused
    if ([event keyCode] == 123) { // Left arrow
        [_playerModel stepFrame:-1];
        [self setNeedsDisplay:YES];
    } else if ([event keyCode] == 124) { // Right arrow
        [_playerModel stepFrame:1];
        [self setNeedsDisplay:YES];
    } else {
        [super keyDown:event];
    }
}

// Screenshot
- (NSImage *)captureScreenshotWithScale:(int)scale {
    [[self openGLContext] makeCurrentContext];

    NSSize viewSize = [self convertSizeToBacking:self.bounds.size];
    int w = (int)viewSize.width * scale;
    int h = (int)viewSize.height * scale;

    // Create FBO
    GLuint fbo, colorTex, depthRB;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);

    glGenTextures(1, &colorTex);
    glBindTexture(GL_TEXTURE_2D, colorTex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, colorTex, 0);

    glGenRenderbuffers(1, &depthRB);
    glBindRenderbuffer(GL_RENDERBUFFER, depthRB);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, w, h);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRB);

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Screenshot FBO not complete");
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glDeleteFramebuffers(1, &fbo);
        glDeleteTextures(1, &colorTex);
        glDeleteRenderbuffers(1, &depthRB);
        return nil;
    }

    glViewport(0, 0, w, h);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    if (_playerModel && _textureCache) {
        float aspect = (float)w / (float)h;
        float projMatrix[16];
        buildPerspective(projMatrix, 45.0f, aspect, 1.0f, 2000.0f);

        float centerZ = [_playerModel centerHeight];
        float radX = _rotationX * M_PI / 180.0f;
        float radY = _rotationY * M_PI / 180.0f;
        float camX = _zoom * cosf(radX) * cosf(radY);
        float camY = _zoom * cosf(radX) * sinf(radY);
        float camZ = centerZ + _zoom * sinf(radX);

        float viewMatrix[16];
        buildLookAt(viewMatrix, camX, camY, camZ, 0, 0, centerZ, 0, 0, 1);

        [_playerModel renderWithRenderer:_renderer
                            textureCache:_textureCache
                              viewMatrix:viewMatrix
                              projMatrix:projMatrix
                                   gamma:_gamma];
    }

    // Read pixels as RGB (no alpha)
    unsigned char *pixels = malloc(w * h * 4);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, pixels);

    // Flip vertically and strip alpha to RGB
    unsigned char *flipped = malloc(w * h * 3);
    for (int row = 0; row < h; row++) {
        unsigned char *src = pixels + (h - 1 - row) * w * 4;
        unsigned char *dst = flipped + row * w * 3;
        for (int x = 0; x < w; x++) {
            dst[x * 3 + 0] = src[x * 4 + 0];
            dst[x * 3 + 1] = src[x * 4 + 1];
            dst[x * 3 + 2] = src[x * 4 + 2];
        }
    }
    free(pixels);

    // Create NSImage (opaque RGB, no alpha)
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:&flipped
                      pixelsWide:w
                      pixelsHigh:h
                   bitsPerSample:8
                 samplesPerPixel:3
                        hasAlpha:NO
                        isPlanar:NO
                  colorSpaceName:NSDeviceRGBColorSpace
                     bytesPerRow:w * 3
                    bitsPerPixel:24];

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(w, h)];
    [image addRepresentation:rep];
    free(flipped);

    // Cleanup
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glDeleteFramebuffers(1, &fbo);
    glDeleteTextures(1, &colorTex);
    glDeleteRenderbuffers(1, &depthRB);

    // Restore viewport
    NSSize size = [self convertSizeToBacking:self.bounds.size];
    glViewport(0, 0, (GLsizei)size.width, (GLsizei)size.height);

    return image;
}

- (NSImage *)captureRenderWithWidth:(int)w height:(int)h {
    [[self openGLContext] makeCurrentContext];

    // Create FBO
    GLuint fbo, colorTex, depthRB;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);

    glGenTextures(1, &colorTex);
    glBindTexture(GL_TEXTURE_2D, colorTex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, colorTex, 0);

    glGenRenderbuffers(1, &depthRB);
    glBindRenderbuffer(GL_RENDERBUFFER, depthRB);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, w, h);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRB);

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"Render FBO not complete");
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glDeleteFramebuffers(1, &fbo);
        glDeleteTextures(1, &colorTex);
        glDeleteRenderbuffers(1, &depthRB);
        return nil;
    }

    glViewport(0, 0, w, h);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    if (_playerModel && _textureCache) {
        float renderAspect = (float)w / (float)h;
        float fovY = 45.0f;
        float projMatrix[16];
        buildPerspective(projMatrix, fovY, renderAspect, 1.0f, 2000.0f);

        // Smart framing: compute zoom distance to fit the model's bounding sphere
        // into the render frame, preserving the user's rotation angles.
        float radius = [_playerModel boundingRadius];
        float centerZ = [_playerModel centerHeight];
        float padding = 1.4f; // 40% breathing room

        // Distance needed to fit sphere vertically: r / sin(fov/2)
        float halfFovRad = fovY * 0.5f * M_PI / 180.0f;
        float distV = (radius * padding) / sinf(halfFovRad);
        // Distance needed to fit sphere horizontally: r / sin(hfov/2)
        // where hfov = 2*atan(tan(fov/2)*aspect)
        float halfHFov = atanf(tanf(halfFovRad) * renderAspect);
        float distH = (radius * padding) / sinf(halfHFov);
        // Use the larger (farther) distance so model fits both axes
        float smartZoom = fmaxf(distV, distH);

        float radX = _rotationX * M_PI / 180.0f;
        float radY = _rotationY * M_PI / 180.0f;
        float camX = smartZoom * cosf(radX) * cosf(radY);
        float camY = smartZoom * cosf(radX) * sinf(radY);
        float camZ = centerZ + smartZoom * sinf(radX);

        float viewMatrix[16];
        buildLookAt(viewMatrix, camX, camY, camZ, 0, 0, centerZ, 0, 0, 1);

        [_playerModel renderWithRenderer:_renderer
                            textureCache:_textureCache
                              viewMatrix:viewMatrix
                              projMatrix:projMatrix
                                   gamma:_gamma];
    }

    // Read pixels as RGB (no alpha)
    unsigned char *pixels = malloc(w * h * 4);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, pixels);

    // Flip vertically and strip alpha to RGB
    unsigned char *flipped = malloc(w * h * 3);
    for (int row = 0; row < h; row++) {
        unsigned char *src = pixels + (h - 1 - row) * w * 4;
        unsigned char *dst = flipped + row * w * 3;
        for (int x = 0; x < w; x++) {
            dst[x * 3 + 0] = src[x * 4 + 0];
            dst[x * 3 + 1] = src[x * 4 + 1];
            dst[x * 3 + 2] = src[x * 4 + 2];
        }
    }
    free(pixels);

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:&flipped
                      pixelsWide:w
                      pixelsHigh:h
                   bitsPerSample:8
                 samplesPerPixel:3
                        hasAlpha:NO
                        isPlanar:NO
                  colorSpaceName:NSDeviceRGBColorSpace
                     bytesPerRow:w * 3
                    bitsPerPixel:24];

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(w, h)];
    [image addRepresentation:rep];
    free(flipped);

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glDeleteFramebuffers(1, &fbo);
    glDeleteTextures(1, &colorTex);
    glDeleteRenderbuffers(1, &depthRB);

    NSSize size = [self convertSizeToBacking:self.bounds.size];
    glViewport(0, 0, (GLsizei)size.width, (GLsizei)size.height);

    return image;
}

@end
