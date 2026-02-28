#import "MD3Model.h"
#import <math.h>

@implementation MD3Model {
    MD3Surface *_surfaces;
    MD3Tag *_tags;
    MD3Frame *_frames;
    int _numFrames;
    int _numTags;
    int _numSurfaces;
}

- (void)dealloc {
    for (int i = 0; i < _numSurfaces; i++) {
        free(_surfaces[i].triangles);
        free(_surfaces[i].texCoords);
        free(_surfaces[i].vertices);
    }
    free(_surfaces);
    free(_tags);
    free(_frames);
}

static void decompressNormal(int16_t encodedNormal, float *nx, float *ny, float *nz) {
    float lat = ((encodedNormal >> 8) & 0xFF) * (2.0f * M_PI / 255.0f);
    float lng = (encodedNormal & 0xFF) * (2.0f * M_PI / 255.0f);
    *nx = cosf(lat) * sinf(lng);
    *ny = sinf(lat) * sinf(lng);
    *nz = cosf(lng);
}

- (instancetype)initWithData:(NSData *)data name:(NSString *)name {
    self = [super init];
    if (!self) return nil;

    const uint8_t *buf = (const uint8_t *)[data bytes];
    NSUInteger len = [data length];

    if (len < sizeof(MD3DiskHeader)) return nil;

    const MD3DiskHeader *header = (const MD3DiskHeader *)buf;
    if (header->ident != MD3_IDENT || header->version != MD3_VERSION) {
        NSLog(@"MD3Model: invalid ident/version for %@", name);
        return nil;
    }

    _numFrames = header->numFrames;
    _numTags = header->numTags;
    _numSurfaces = header->numSurfaces;

    // Parse frames
    _frames = calloc(_numFrames, sizeof(MD3Frame));
    const MD3DiskFrame *diskFrame = (const MD3DiskFrame *)(buf + header->ofsFrames);
    for (int i = 0; i < _numFrames; i++) {
        memcpy(_frames[i].bounds, diskFrame[i].bounds, sizeof(float) * 6);
        memcpy(_frames[i].localOrigin, diskFrame[i].localOrigin, sizeof(float) * 3);
        _frames[i].radius = diskFrame[i].radius;
        memcpy(_frames[i].name, diskFrame[i].name, 16);
    }

    // Parse tags (numTags * numFrames)
    int totalTags = _numTags * _numFrames;
    _tags = calloc(totalTags, sizeof(MD3Tag));
    const MD3DiskTag *diskTag = (const MD3DiskTag *)(buf + header->ofsTags);
    for (int i = 0; i < totalTags; i++) {
        memcpy(_tags[i].name, diskTag[i].name, MAX_QPATH);
        memcpy(_tags[i].origin, diskTag[i].origin, sizeof(float) * 3);
        memcpy(_tags[i].axis, diskTag[i].axis, sizeof(float) * 9);
    }

    // Parse surfaces
    _surfaces = calloc(_numSurfaces, sizeof(MD3Surface));
    const uint8_t *surfPtr = buf + header->ofsSurfaces;

    for (int i = 0; i < _numSurfaces; i++) {
        if (surfPtr < buf || surfPtr >= buf + len) break;

        const MD3DiskSurface *diskSurf = (const MD3DiskSurface *)surfPtr;
        MD3Surface *surf = &_surfaces[i];

        // Copy name and lowercase it
        memcpy(surf->name, diskSurf->name, MAX_QPATH);
        for (char *c = surf->name; *c; c++) {
            if (*c >= 'A' && *c <= 'Z') *c += 32;
        }
        // Strip trailing _1 or _2
        size_t nameLen = strlen(surf->name);
        if (nameLen > 2 && surf->name[nameLen - 2] == '_') {
            surf->name[nameLen - 2] = '\0';
        }

        surf->numFrames = diskSurf->numFrames;
        surf->numVerts = diskSurf->numVerts;
        surf->numTriangles = diskSurf->numTriangles;

        // Read shader name
        if (diskSurf->numShaders > 0) {
            const MD3DiskShader *diskShader = (const MD3DiskShader *)(surfPtr + diskSurf->ofsShaders);
            memcpy(surf->shaderName, diskShader->name, MAX_QPATH);
        }

        // Read triangles
        surf->triangles = calloc(surf->numTriangles * 3, sizeof(int32_t));
        const MD3DiskTriangle *diskTri = (const MD3DiskTriangle *)(surfPtr + diskSurf->ofsTriangles);
        for (int j = 0; j < surf->numTriangles; j++) {
            surf->triangles[j * 3 + 0] = diskTri[j].indexes[0];
            surf->triangles[j * 3 + 1] = diskTri[j].indexes[1];
            surf->triangles[j * 3 + 2] = diskTri[j].indexes[2];
        }

        // Read texture coordinates
        surf->texCoords = calloc(surf->numVerts * 2, sizeof(float));
        const MD3DiskTexCoord *diskSt = (const MD3DiskTexCoord *)(surfPtr + diskSurf->ofsSt);
        for (int j = 0; j < surf->numVerts; j++) {
            surf->texCoords[j * 2 + 0] = diskSt[j].st[0];
            surf->texCoords[j * 2 + 1] = diskSt[j].st[1];
        }

        // Read and decompress vertices (all frames)
        int totalVerts = surf->numVerts * surf->numFrames;
        surf->vertices = calloc(totalVerts, sizeof(MD3Vertex));
        const MD3DiskVertex *diskVert = (const MD3DiskVertex *)(surfPtr + diskSurf->ofsXyzNormals);
        for (int j = 0; j < totalVerts; j++) {
            surf->vertices[j].position[0] = diskVert[j].xyz[0] * MD3_XYZ_SCALE;
            surf->vertices[j].position[1] = diskVert[j].xyz[1] * MD3_XYZ_SCALE;
            surf->vertices[j].position[2] = diskVert[j].xyz[2] * MD3_XYZ_SCALE;
            decompressNormal(diskVert[j].normal,
                             &surf->vertices[j].normal[0],
                             &surf->vertices[j].normal[1],
                             &surf->vertices[j].normal[2]);
        }

        surfPtr += diskSurf->ofsEnd;
    }

    return self;
}

- (MD3Tag *)tagForName:(const char *)name atFrame:(int)frame {
    if (frame < 0 || frame >= _numFrames) return NULL;
    MD3Tag *frameTags = &_tags[frame * _numTags];
    for (int i = 0; i < _numTags; i++) {
        if (strcasecmp(frameTags[i].name, name) == 0) {
            return &frameTags[i];
        }
    }
    return NULL;
}

- (MD3Surface *)surfaces { return _surfaces; }
- (MD3Tag *)tags { return _tags; }
- (MD3Frame *)frames { return _frames; }
- (int)numFrames { return _numFrames; }
- (int)numTags { return _numTags; }
- (int)numSurfaces { return _numSurfaces; }

@end
