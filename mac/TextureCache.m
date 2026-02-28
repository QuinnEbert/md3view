#import "TextureCache.h"
#import "PK3Archive.h"
#import <OpenGL/gl3.h>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_TGA
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#include "stb_image.h"

@implementation TextureCache {
    PK3Archive *_archive;
    NSMutableDictionary<NSString *, NSNumber *> *_cache;
    GLuint _whiteTexture;
}

- (instancetype)initWithArchive:(PK3Archive *)archive {
    self = [super init];
    if (!self) return nil;
    _archive = archive;
    _cache = [NSMutableDictionary new];
    _whiteTexture = 0;
    return self;
}

- (GLuint)whiteTexture {
    if (_whiteTexture == 0) {
        glGenTextures(1, &_whiteTexture);
        glBindTexture(GL_TEXTURE_2D, _whiteTexture);
        uint32_t white = 0xFFFFFFFF;
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, &white);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    }
    return _whiteTexture;
}

- (GLuint)textureForPath:(NSString *)path {
    if (!path || path.length == 0) return [self whiteTexture];

    NSString *key = [path lowercaseString];
    NSNumber *cached = _cache[key];
    if (cached) return [cached unsignedIntValue];

    // Try loading the file directly
    NSData *data = [_archive readFile:path];

    // Try alternate extensions if not found
    if (!data) {
        NSString *basePath = [path stringByDeletingPathExtension];
        NSArray *exts = @[@"tga", @"jpg", @"jpeg", @"png", @"TGA", @"JPG", @"PNG"];
        for (NSString *ext in exts) {
            data = [_archive readFile:[basePath stringByAppendingPathExtension:ext]];
            if (data) break;
        }
    }

    if (!data) {
        _cache[key] = @([self whiteTexture]);
        return [self whiteTexture];
    }

    int w, h, channels;
    // Q3 UVs: v=0 is top of image, matching TGA/JPEG native layout.
    // Do NOT flip — OpenGL's row-0-at-bottom naturally maps v=0 to image top.
    stbi_set_flip_vertically_on_load(0);
    unsigned char *pixels = stbi_load_from_memory(
        (const unsigned char *)[data bytes], (int)[data length],
        &w, &h, &channels, 4);

    if (!pixels) {
        NSLog(@"TextureCache: failed to decode %@", path);
        _cache[key] = @([self whiteTexture]);
        return [self whiteTexture];
    }

    GLuint tex;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    glGenerateMipmap(GL_TEXTURE_2D);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);

    stbi_image_free(pixels);

    _cache[key] = @(tex);
    return tex;
}

- (void)flush {
    for (NSNumber *texID in _cache.allValues) {
        GLuint tex = [texID unsignedIntValue];
        if (tex != _whiteTexture) {
            glDeleteTextures(1, &tex);
        }
    }
    [_cache removeAllObjects];
    if (_whiteTexture) {
        glDeleteTextures(1, &_whiteTexture);
        _whiteTexture = 0;
    }
}

@end
