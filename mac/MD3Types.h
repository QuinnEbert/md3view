#ifndef MD3TYPES_H
#define MD3TYPES_H

#include <stdint.h>

// ============================================================
// On-disk MD3 binary format structures
// ============================================================

#define MD3_IDENT       (('3'<<24)+('P'<<16)+('D'<<8)+'I')
#define MD3_VERSION     15
#define MD3_XYZ_SCALE   (1.0f/64.0f)
#define MAX_QPATH       64

// MD3 limits
#define MD3_MAX_FRAMES      1024
#define MD3_MAX_TAGS        16
#define MD3_MAX_SURFACES    32
#define MD3_MAX_TRIANGLES   8192
#define MD3_MAX_VERTS       4096
#define MD3_MAX_SHADERS     256

#pragma pack(push, 1)

typedef struct {
    float   bounds[2][3];
    float   localOrigin[3];
    float   radius;
    char    name[16];
} MD3DiskFrame;

typedef struct {
    char    name[MAX_QPATH];
    float   origin[3];
    float   axis[3][3];
} MD3DiskTag;

typedef struct {
    int32_t ident;
    char    name[MAX_QPATH];
    int32_t flags;
    int32_t numFrames;
    int32_t numShaders;
    int32_t numVerts;
    int32_t numTriangles;
    int32_t ofsTriangles;
    int32_t ofsShaders;
    int32_t ofsSt;
    int32_t ofsXyzNormals;
    int32_t ofsEnd;
} MD3DiskSurface;

typedef struct {
    char    name[MAX_QPATH];
    int32_t shaderIndex;
} MD3DiskShader;

typedef struct {
    int32_t indexes[3];
} MD3DiskTriangle;

typedef struct {
    float   st[2];
} MD3DiskTexCoord;

typedef struct {
    int16_t xyz[3];
    int16_t normal;
} MD3DiskVertex;

typedef struct {
    int32_t ident;
    int32_t version;
    char    name[MAX_QPATH];
    int32_t flags;
    int32_t numFrames;
    int32_t numTags;
    int32_t numSurfaces;
    int32_t numSkins;
    int32_t ofsFrames;
    int32_t ofsTags;
    int32_t ofsSurfaces;
    int32_t ofsEnd;
} MD3DiskHeader;

#pragma pack(pop)

// ============================================================
// Runtime structures (decompressed, ready for rendering)
// ============================================================

typedef struct {
    float position[3];
    float normal[3];
} MD3Vertex;

typedef struct {
    char    name[MAX_QPATH];
    int     numFrames;
    int     numVerts;
    int     numTriangles;
    int32_t *triangles;         // numTriangles * 3
    float   *texCoords;         // numVerts * 2
    MD3Vertex *vertices;        // numVerts * numFrames
    char    shaderName[MAX_QPATH];
    uint32_t textureID;         // GL texture ID (set during rendering)
} MD3Surface;

typedef struct {
    char    name[MAX_QPATH];
    float   origin[3];
    float   axis[3][3];
} MD3Tag;

typedef struct {
    float   bounds[2][3];
    float   localOrigin[3];
    float   radius;
    char    name[16];
} MD3Frame;

// ============================================================
// Animation enum (matches Q3 bg_public.h)
// ============================================================

typedef enum {
    BOTH_DEATH1,
    BOTH_DEAD1,
    BOTH_DEATH2,
    BOTH_DEAD2,
    BOTH_DEATH3,
    BOTH_DEAD3,

    TORSO_GESTURE,

    TORSO_ATTACK,
    TORSO_ATTACK2,

    TORSO_DROP,
    TORSO_RAISE,

    TORSO_STAND,
    TORSO_STAND2,

    LEGS_WALKCR,
    LEGS_WALK,
    LEGS_RUN,
    LEGS_BACK,
    LEGS_SWIM,

    LEGS_JUMP,
    LEGS_LAND,

    LEGS_JUMPB,
    LEGS_LANDB,

    LEGS_IDLE,
    LEGS_IDLECR,

    LEGS_TURN,

    TORSO_GETFLAG,
    TORSO_GUARDBASE,
    TORSO_PATROL,
    TORSO_FOLLOWME,
    TORSO_AFFIRMATIVE,
    TORSO_NEGATIVE,

    MAX_ANIMATIONS,

    LEGS_BACKCR,
    LEGS_BACKWALK,
    FLAG_RUN,
    FLAG_STAND,
    FLAG_STAND2RUN,

    MAX_TOTALANIMATIONS
} AnimNumber;

static const char *AnimationNames[] = {
    "BOTH_DEATH1",
    "BOTH_DEAD1",
    "BOTH_DEATH2",
    "BOTH_DEAD2",
    "BOTH_DEATH3",
    "BOTH_DEAD3",
    "TORSO_GESTURE",
    "TORSO_ATTACK",
    "TORSO_ATTACK2",
    "TORSO_DROP",
    "TORSO_RAISE",
    "TORSO_STAND",
    "TORSO_STAND2",
    "LEGS_WALKCR",
    "LEGS_WALK",
    "LEGS_RUN",
    "LEGS_BACK",
    "LEGS_SWIM",
    "LEGS_JUMP",
    "LEGS_LAND",
    "LEGS_JUMPB",
    "LEGS_LANDB",
    "LEGS_IDLE",
    "LEGS_IDLECR",
    "LEGS_TURN",
    "TORSO_GETFLAG",
    "TORSO_GUARDBASE",
    "TORSO_PATROL",
    "TORSO_FOLLOWME",
    "TORSO_AFFIRMATIVE",
    "TORSO_NEGATIVE",
};

typedef struct {
    int     firstFrame;
    int     numFrames;
    int     loopFrames;
    int     frameLerp;      // msec between frames
    int     reversed;
    int     flipflop;
} Animation;

// ============================================================
// Animation state for a single body part
// ============================================================

typedef struct {
    AnimNumber  animIndex;
    int         currentFrame;
    int         nextFrame;
    float       fraction;       // lerp fraction between frames
    double      frameTime;      // time of last frame change
    BOOL        playing;
} AnimState;

#endif // MD3TYPES_H
