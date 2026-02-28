#import "ModelRenderer.h"
#import "MD3Model.h"
#import "TextureCache.h"
#import <OpenGL/gl3.h>
#import <math.h>

static const char *vertexShaderSource =
    "#version 150\n"
    "in vec3 posA;\n"
    "in vec3 normalA;\n"
    "in vec3 posB;\n"
    "in vec3 normalB;\n"
    "in vec2 texCoord;\n"
    "uniform float lerp;\n"
    "uniform mat4 modelMatrix;\n"
    "uniform mat4 viewMatrix;\n"
    "uniform mat4 projMatrix;\n"
    "uniform mat3 normalMatrix;\n"
    "out vec2 vTexCoord;\n"
    "out vec3 vNormal;\n"
    "out vec3 vWorldPos;\n"
    "void main() {\n"
    "    vec3 pos = mix(posA, posB, lerp);\n"
    "    vec3 norm = normalize(mix(normalA, normalB, lerp));\n"
    "    vec4 worldPos = modelMatrix * vec4(pos, 1.0);\n"
    "    vWorldPos = worldPos.xyz;\n"
    "    vNormal = normalMatrix * norm;\n"
    "    vTexCoord = texCoord;\n"
    "    gl_Position = projMatrix * viewMatrix * worldPos;\n"
    "}\n";

static const char *fragmentShaderSource =
    "#version 150\n"
    "in vec2 vTexCoord;\n"
    "in vec3 vNormal;\n"
    "in vec3 vWorldPos;\n"
    "uniform sampler2D tex;\n"
    "uniform float gamma;\n"
    "out vec4 fragColor;\n"
    "void main() {\n"
    "    vec3 norm = normalize(vNormal);\n"
    "    vec3 lightDir = normalize(vec3(0.5, 0.3, 1.0));\n"
    "    float ambient = 0.35;\n"
    "    float diffuse = max(dot(norm, lightDir), 0.0) * 0.65;\n"
    "    vec4 texColor = texture(tex, vTexCoord);\n"
    "    if (texColor.a < 0.5) discard;\n"
    "    vec3 color = texColor.rgb * (ambient + diffuse);\n"
    "    fragColor = vec4(pow(color, vec3(1.0 / gamma)), texColor.a);\n"
    "}\n";

@implementation ModelRenderer {
    GLuint _program;
    GLint _locPosA, _locNormalA, _locPosB, _locNormalB, _locTexCoord;
    GLint _locLerp, _locModelMatrix, _locViewMatrix, _locProjMatrix, _locNormalMatrix;
    GLint _locTex, _locGamma;
    GLuint _vao;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _program = 0;
    _vao = 0;
    return self;
}

static GLuint compileShader(GLenum type, const char *source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    GLint status;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (!status) {
        char log[1024];
        glGetShaderInfoLog(shader, sizeof(log), NULL, log);
        NSLog(@"Shader compile error: %s", log);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

- (BOOL)setupShaders {
    GLuint vs = compileShader(GL_VERTEX_SHADER, vertexShaderSource);
    GLuint fs = compileShader(GL_FRAGMENT_SHADER, fragmentShaderSource);
    if (!vs || !fs) return NO;

    _program = glCreateProgram();
    glAttachShader(_program, vs);
    glAttachShader(_program, fs);
    glLinkProgram(_program);

    GLint status;
    glGetProgramiv(_program, GL_LINK_STATUS, &status);
    if (!status) {
        char log[1024];
        glGetProgramInfoLog(_program, sizeof(log), NULL, log);
        NSLog(@"Program link error: %s", log);
        return NO;
    }

    glDeleteShader(vs);
    glDeleteShader(fs);

    _locPosA = glGetAttribLocation(_program, "posA");
    _locNormalA = glGetAttribLocation(_program, "normalA");
    _locPosB = glGetAttribLocation(_program, "posB");
    _locNormalB = glGetAttribLocation(_program, "normalB");
    _locTexCoord = glGetAttribLocation(_program, "texCoord");

    _locLerp = glGetUniformLocation(_program, "lerp");
    _locModelMatrix = glGetUniformLocation(_program, "modelMatrix");
    _locViewMatrix = glGetUniformLocation(_program, "viewMatrix");
    _locProjMatrix = glGetUniformLocation(_program, "projMatrix");
    _locNormalMatrix = glGetUniformLocation(_program, "normalMatrix");
    _locTex = glGetUniformLocation(_program, "tex");
    _locGamma = glGetUniformLocation(_program, "gamma");

    glGenVertexArrays(1, &_vao);

    return YES;
}

static void buildModelMatrix(TagTransform t, float *out) {
    // Column-major 4x4 from origin + axis[3][3]
    // Q3 axis: axis[0] = forward, axis[1] = left, axis[2] = up
    out[0]  = t.axis[0][0]; out[1]  = t.axis[0][1]; out[2]  = t.axis[0][2]; out[3]  = 0;
    out[4]  = t.axis[1][0]; out[5]  = t.axis[1][1]; out[6]  = t.axis[1][2]; out[7]  = 0;
    out[8]  = t.axis[2][0]; out[9]  = t.axis[2][1]; out[10] = t.axis[2][2]; out[11] = 0;
    out[12] = t.origin[0];  out[13] = t.origin[1];  out[14] = t.origin[2];  out[15] = 1;
}

static void extractNormalMatrix(const float *m4, float *m3) {
    // Upper-left 3x3 of the model matrix
    m3[0] = m4[0]; m3[1] = m4[1]; m3[2] = m4[2];
    m3[3] = m4[4]; m3[4] = m4[5]; m3[5] = m4[6];
    m3[6] = m4[8]; m3[7] = m4[9]; m3[8] = m4[10];
}

- (void)renderModel:(MD3Model *)model
         atFrame:(int)frameA
       nextFrame:(int)frameB
        fraction:(float)frac
       transform:(TagTransform)transform
    textureCache:(TextureCache *)texCache
    skinMappings:(NSDictionary<NSString *, NSString *> *)skin
   viewMatrix:(const float *)viewMatrix
   projMatrix:(const float *)projMatrix
       gamma:(float)gamma {

    if (!model || !_program) return;

    int numFrames = [model numFrames];
    if (numFrames == 0) return;
    frameA = frameA % numFrames;
    frameB = frameB % numFrames;

    glUseProgram(_program);
    glBindVertexArray(_vao);

    // Set view/proj uniforms
    glUniformMatrix4fv(_locViewMatrix, 1, GL_FALSE, viewMatrix);
    glUniformMatrix4fv(_locProjMatrix, 1, GL_FALSE, projMatrix);

    // Build model matrix from transform
    float modelMat[16];
    buildModelMatrix(transform, modelMat);
    glUniformMatrix4fv(_locModelMatrix, 1, GL_FALSE, modelMat);

    float normalMat[9];
    extractNormalMatrix(modelMat, normalMat);
    glUniformMatrix3fv(_locNormalMatrix, 1, GL_FALSE, normalMat);

    glUniform1f(_locLerp, frac);
    glUniform1f(_locGamma, gamma);
    glUniform1i(_locTex, 0);

    MD3Surface *surfaces = [model surfaces];
    for (int s = 0; s < [model numSurfaces]; s++) {
        MD3Surface *surf = &surfaces[s];

        // Look up texture
        NSString *surfName = [NSString stringWithUTF8String:surf->name];
        NSString *texPath = skin[surfName];
        if (!texPath && strlen(surf->shaderName) > 0) {
            texPath = [NSString stringWithUTF8String:surf->shaderName];
        }
        GLuint texID = texPath ? [texCache textureForPath:texPath] : [texCache whiteTexture];

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, texID);

        // Upload vertex data for frame A and B
        MD3Vertex *vertsA = &surf->vertices[frameA * surf->numVerts];
        MD3Vertex *vertsB = &surf->vertices[frameB * surf->numVerts];

        GLuint vboA, vboB, vboTex, ebo;
        glGenBuffers(1, &vboA);
        glGenBuffers(1, &vboB);
        glGenBuffers(1, &vboTex);
        glGenBuffers(1, &ebo);

        // Frame A positions + normals
        glBindBuffer(GL_ARRAY_BUFFER, vboA);
        glBufferData(GL_ARRAY_BUFFER, surf->numVerts * sizeof(MD3Vertex), vertsA, GL_STREAM_DRAW);
        glEnableVertexAttribArray(_locPosA);
        glVertexAttribPointer(_locPosA, 3, GL_FLOAT, GL_FALSE, sizeof(MD3Vertex), (void *)0);
        glEnableVertexAttribArray(_locNormalA);
        glVertexAttribPointer(_locNormalA, 3, GL_FLOAT, GL_FALSE, sizeof(MD3Vertex), (void *)(3 * sizeof(float)));

        // Frame B positions + normals
        glBindBuffer(GL_ARRAY_BUFFER, vboB);
        glBufferData(GL_ARRAY_BUFFER, surf->numVerts * sizeof(MD3Vertex), vertsB, GL_STREAM_DRAW);
        glEnableVertexAttribArray(_locPosB);
        glVertexAttribPointer(_locPosB, 3, GL_FLOAT, GL_FALSE, sizeof(MD3Vertex), (void *)0);
        glEnableVertexAttribArray(_locNormalB);
        glVertexAttribPointer(_locNormalB, 3, GL_FLOAT, GL_FALSE, sizeof(MD3Vertex), (void *)(3 * sizeof(float)));

        // Texture coordinates
        glBindBuffer(GL_ARRAY_BUFFER, vboTex);
        glBufferData(GL_ARRAY_BUFFER, surf->numVerts * 2 * sizeof(float), surf->texCoords, GL_STREAM_DRAW);
        glEnableVertexAttribArray(_locTexCoord);
        glVertexAttribPointer(_locTexCoord, 2, GL_FLOAT, GL_FALSE, 0, (void *)0);

        // Index buffer
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, surf->numTriangles * 3 * sizeof(int32_t), surf->triangles, GL_STREAM_DRAW);

        glDrawElements(GL_TRIANGLES, surf->numTriangles * 3, GL_UNSIGNED_INT, 0);

        glDeleteBuffers(1, &vboA);
        glDeleteBuffers(1, &vboB);
        glDeleteBuffers(1, &vboTex);
        glDeleteBuffers(1, &ebo);
    }

    glBindVertexArray(0);
    glUseProgram(0);
}

- (void)cleanup {
    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
    if (_vao) {
        glDeleteVertexArrays(1, &_vao);
        _vao = 0;
    }
}

@end
