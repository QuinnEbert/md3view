#import "AnimationConfig.h"

@implementation AnimationConfig {
    Animation _animations[MAX_TOTALANIMATIONS];
    BOOL _fixedLegs;
    BOOL _fixedTorso;
}

- (const Animation *)animations {
    return _animations;
}

- (instancetype)initWithData:(NSData *)data {
    self = [super init];
    if (!self) return nil;

    memset(_animations, 0, sizeof(_animations));
    _fixedLegs = NO;
    _fixedTorso = NO;

    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) {
        text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }
    if (!text) return nil;

    const char *cstr = [text UTF8String];
    const char *p = cstr;
    int skip = 0;

    // Skip optional header keywords
    while (*p) {
        // Skip whitespace and newlines
        while (*p && (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n')) p++;
        if (!*p) break;

        // Skip comment lines (// comments)
        if (p[0] == '/' && p[1] == '/') {
            while (*p && *p != '\n') p++;
            continue;
        }

        // If it starts with a digit or minus, we've reached the animation data
        if ((*p >= '0' && *p <= '9') || *p == '-') break;

        // Parse known keywords
        char token[256];
        int ti = 0;
        while (*p && *p != ' ' && *p != '\t' && *p != '\r' && *p != '\n' && ti < 255) {
            token[ti++] = *p++;
        }
        token[ti] = '\0';

        if (strcasecmp(token, "footsteps") == 0) {
            // Skip the footstep type
            while (*p && (*p == ' ' || *p == '\t')) p++;
            while (*p && *p != ' ' && *p != '\t' && *p != '\r' && *p != '\n') p++;
        } else if (strcasecmp(token, "headoffset") == 0) {
            // Skip 3 floats
            for (int i = 0; i < 3; i++) {
                while (*p && (*p == ' ' || *p == '\t')) p++;
                while (*p && *p != ' ' && *p != '\t' && *p != '\r' && *p != '\n') p++;
            }
        } else if (strcasecmp(token, "sex") == 0) {
            while (*p && (*p == ' ' || *p == '\t')) p++;
            while (*p && *p != ' ' && *p != '\t' && *p != '\r' && *p != '\n') p++;
        } else if (strcasecmp(token, "fixedlegs") == 0) {
            _fixedLegs = YES;
        } else if (strcasecmp(token, "fixedtorso") == 0) {
            _fixedTorso = YES;
        }
    }

    // Parse animation entries
    for (int i = 0; i < MAX_ANIMATIONS; i++) {
        // Skip whitespace, newlines, comments
        while (*p) {
            while (*p && (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n')) p++;
            if (p[0] == '/' && p[1] == '/') {
                while (*p && *p != '\n') p++;
                continue;
            }
            break;
        }

        if (!*p) {
            // Handle missing team animations (TORSO_GETFLAG through TORSO_NEGATIVE)
            if (i >= TORSO_GETFLAG && i <= TORSO_NEGATIVE) {
                _animations[i] = _animations[TORSO_GESTURE];
                continue;
            }
            break;
        }

        // firstFrame
        _animations[i].firstFrame = atoi(p);
        while (*p && *p != ' ' && *p != '\t') p++;

        // Compute leg frame offset at LEGS_WALKCR
        if (i == LEGS_WALKCR) {
            skip = _animations[LEGS_WALKCR].firstFrame - _animations[TORSO_GESTURE].firstFrame;
        }
        if (i >= LEGS_WALKCR && i < TORSO_GETFLAG) {
            _animations[i].firstFrame -= skip;
        }

        // numFrames
        while (*p && (*p == ' ' || *p == '\t')) p++;
        int numFrames = atoi(p);
        while (*p && *p != ' ' && *p != '\t') p++;
        _animations[i].reversed = 0;
        _animations[i].flipflop = 0;
        if (numFrames < 0) {
            numFrames = -numFrames;
            _animations[i].reversed = 1;
        }
        _animations[i].numFrames = numFrames;

        // loopFrames
        while (*p && (*p == ' ' || *p == '\t')) p++;
        _animations[i].loopFrames = atoi(p);
        while (*p && *p != ' ' && *p != '\t') p++;

        // fps
        while (*p && (*p == ' ' || *p == '\t')) p++;
        float fps = atof(p);
        while (*p && *p != ' ' && *p != '\t' && *p != '\r' && *p != '\n') p++;
        if (fps == 0) fps = 1;
        _animations[i].frameLerp = (int)(1000.0f / fps);

        // Skip rest of line (comments etc)
        while (*p && *p != '\n') p++;
    }

    // Extra animations
    _animations[LEGS_BACKCR] = _animations[LEGS_WALKCR];
    _animations[LEGS_BACKCR].reversed = 1;
    _animations[LEGS_BACKWALK] = _animations[LEGS_WALK];
    _animations[LEGS_BACKWALK].reversed = 1;

    _animations[FLAG_RUN].firstFrame = 0;
    _animations[FLAG_RUN].numFrames = 16;
    _animations[FLAG_RUN].loopFrames = 16;
    _animations[FLAG_RUN].frameLerp = (int)(1000.0f / 15.0f);
    _animations[FLAG_RUN].reversed = 0;

    _animations[FLAG_STAND].firstFrame = 16;
    _animations[FLAG_STAND].numFrames = 5;
    _animations[FLAG_STAND].loopFrames = 0;
    _animations[FLAG_STAND].frameLerp = (int)(1000.0f / 20.0f);
    _animations[FLAG_STAND].reversed = 0;

    _animations[FLAG_STAND2RUN].firstFrame = 16;
    _animations[FLAG_STAND2RUN].numFrames = 5;
    _animations[FLAG_STAND2RUN].loopFrames = 1;
    _animations[FLAG_STAND2RUN].frameLerp = (int)(1000.0f / 15.0f);
    _animations[FLAG_STAND2RUN].reversed = 1;

    return self;
}

@end
