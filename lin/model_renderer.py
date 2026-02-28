"""OpenGL 3.2 Core model renderer with GLSL 150 shaders."""

import ctypes
import numpy as np

from OpenGL.GL import *
from OpenGL.GL import shaders

from md3_types import TagTransform

VERTEX_SHADER_SOURCE = """#version 150
in vec3 posA;
in vec3 normalA;
in vec3 posB;
in vec3 normalB;
in vec2 texCoord;
uniform float lerp;
uniform mat4 modelMatrix;
uniform mat4 viewMatrix;
uniform mat4 projMatrix;
uniform mat3 normalMatrix;
out vec2 vTexCoord;
out vec3 vNormal;
out vec3 vWorldPos;
void main() {
    vec3 pos = mix(posA, posB, lerp);
    vec3 norm = normalize(mix(normalA, normalB, lerp));
    vec4 worldPos = modelMatrix * vec4(pos, 1.0);
    vWorldPos = worldPos.xyz;
    vNormal = normalMatrix * norm;
    vTexCoord = texCoord;
    gl_Position = projMatrix * viewMatrix * worldPos;
}
"""

FRAGMENT_SHADER_SOURCE = """#version 150
in vec2 vTexCoord;
in vec3 vNormal;
in vec3 vWorldPos;
uniform sampler2D tex;
uniform float gamma;
out vec4 fragColor;
void main() {
    vec3 norm = normalize(vNormal);
    vec3 lightDir = normalize(vec3(0.5, 0.3, 1.0));
    float ambient = 0.35;
    float diffuse = max(dot(norm, lightDir), 0.0) * 0.65;
    vec4 texColor = texture(tex, vTexCoord);
    if (texColor.a < 0.5) discard;
    vec3 color = texColor.rgb * (ambient + diffuse);
    fragColor = vec4(pow(color, vec3(1.0 / gamma)), texColor.a);
}
"""


class ModelRenderer:
    def __init__(self):
        self._program = 0
        self._vao = 0
        self._loc_posA = -1
        self._loc_normalA = -1
        self._loc_posB = -1
        self._loc_normalB = -1
        self._loc_texCoord = -1
        self._loc_lerp = -1
        self._loc_model_matrix = -1
        self._loc_view_matrix = -1
        self._loc_proj_matrix = -1
        self._loc_normal_matrix = -1
        self._loc_tex = -1
        self._loc_gamma = -1

    def setup_shaders(self):
        try:
            vs = shaders.compileShader(VERTEX_SHADER_SOURCE, GL_VERTEX_SHADER)
            fs = shaders.compileShader(FRAGMENT_SHADER_SOURCE, GL_FRAGMENT_SHADER)
            self._program = shaders.compileProgram(vs, fs)
        except Exception as e:
            print(f"Shader compile error: {e}")
            return False

        self._loc_posA = glGetAttribLocation(self._program, "posA")
        self._loc_normalA = glGetAttribLocation(self._program, "normalA")
        self._loc_posB = glGetAttribLocation(self._program, "posB")
        self._loc_normalB = glGetAttribLocation(self._program, "normalB")
        self._loc_texCoord = glGetAttribLocation(self._program, "texCoord")

        self._loc_lerp = glGetUniformLocation(self._program, "lerp")
        self._loc_model_matrix = glGetUniformLocation(self._program, "modelMatrix")
        self._loc_view_matrix = glGetUniformLocation(self._program, "viewMatrix")
        self._loc_proj_matrix = glGetUniformLocation(self._program, "projMatrix")
        self._loc_normal_matrix = glGetUniformLocation(self._program, "normalMatrix")
        self._loc_tex = glGetUniformLocation(self._program, "tex")
        self._loc_gamma = glGetUniformLocation(self._program, "gamma")

        self._vao = glGenVertexArrays(1)

        return True

    def render_model(self, model, frame_a, frame_b, frac, transform,
                     tex_cache, skin, view_matrix, proj_matrix, gamma):
        if model is None or self._program == 0:
            return

        num_frames = model.num_frames
        if num_frames == 0:
            return
        frame_a = frame_a % num_frames
        frame_b = frame_b % num_frames

        glUseProgram(self._program)
        glBindVertexArray(self._vao)

        # Set view/proj uniforms
        glUniformMatrix4fv(self._loc_view_matrix, 1, GL_FALSE, view_matrix)
        glUniformMatrix4fv(self._loc_proj_matrix, 1, GL_FALSE, proj_matrix)

        # Build model matrix from transform
        model_mat = _build_model_matrix(transform)
        glUniformMatrix4fv(self._loc_model_matrix, 1, GL_FALSE, model_mat)

        normal_mat = _extract_normal_matrix(model_mat)
        glUniformMatrix3fv(self._loc_normal_matrix, 1, GL_FALSE, normal_mat)

        glUniform1f(self._loc_lerp, frac)
        glUniform1f(self._loc_gamma, gamma)
        glUniform1i(self._loc_tex, 0)

        for surf in model.surfaces:
            # Look up texture
            tex_path = None
            if skin:
                tex_path = skin.get(surf.name)
            if tex_path is None and surf.shaderName:
                tex_path = surf.shaderName
            tex_id = tex_cache.texture_for_path(tex_path) if tex_path else tex_cache.white_texture()

            glActiveTexture(GL_TEXTURE0)
            glBindTexture(GL_TEXTURE_2D, tex_id)

            # Build frame A vertex data (positions + normals interleaved)
            verts_a = _pack_vertices(surf, frame_a)
            verts_b = _pack_vertices(surf, frame_b)
            tex_data = np.array(surf.texCoords, dtype=np.float32)
            idx_data = np.array(surf.triangles, dtype=np.int32)

            vbo_a = glGenBuffers(1)
            vbo_b = glGenBuffers(1)
            vbo_tex = glGenBuffers(1)
            ebo = glGenBuffers(1)

            # Frame A positions + normals
            glBindBuffer(GL_ARRAY_BUFFER, vbo_a)
            glBufferData(GL_ARRAY_BUFFER, verts_a.nbytes, verts_a, GL_STREAM_DRAW)
            glEnableVertexAttribArray(self._loc_posA)
            glVertexAttribPointer(self._loc_posA, 3, GL_FLOAT, GL_FALSE, 24, ctypes.c_void_p(0))
            glEnableVertexAttribArray(self._loc_normalA)
            glVertexAttribPointer(self._loc_normalA, 3, GL_FLOAT, GL_FALSE, 24, ctypes.c_void_p(12))

            # Frame B positions + normals
            glBindBuffer(GL_ARRAY_BUFFER, vbo_b)
            glBufferData(GL_ARRAY_BUFFER, verts_b.nbytes, verts_b, GL_STREAM_DRAW)
            glEnableVertexAttribArray(self._loc_posB)
            glVertexAttribPointer(self._loc_posB, 3, GL_FLOAT, GL_FALSE, 24, ctypes.c_void_p(0))
            glEnableVertexAttribArray(self._loc_normalB)
            glVertexAttribPointer(self._loc_normalB, 3, GL_FLOAT, GL_FALSE, 24, ctypes.c_void_p(12))

            # Texture coordinates
            glBindBuffer(GL_ARRAY_BUFFER, vbo_tex)
            glBufferData(GL_ARRAY_BUFFER, tex_data.nbytes, tex_data, GL_STREAM_DRAW)
            glEnableVertexAttribArray(self._loc_texCoord)
            glVertexAttribPointer(self._loc_texCoord, 2, GL_FLOAT, GL_FALSE, 0, ctypes.c_void_p(0))

            # Index buffer
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
            glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx_data.nbytes, idx_data, GL_STREAM_DRAW)

            glDrawElements(GL_TRIANGLES, surf.numTriangles * 3, GL_UNSIGNED_INT, None)

            glDeleteBuffers(1, [vbo_a])
            glDeleteBuffers(1, [vbo_b])
            glDeleteBuffers(1, [vbo_tex])
            glDeleteBuffers(1, [ebo])

        glBindVertexArray(0)
        glUseProgram(0)

    def cleanup(self):
        if self._program:
            glDeleteProgram(self._program)
            self._program = 0
        if self._vao:
            glDeleteVertexArrays(1, [self._vao])
            self._vao = 0


def _build_model_matrix(t):
    """Build column-major 4x4 matrix from TagTransform."""
    m = np.zeros(16, dtype=np.float32)
    # Q3 axis: axis[0] = forward, axis[1] = left, axis[2] = up
    m[0]  = t.axis[0][0]; m[1]  = t.axis[0][1]; m[2]  = t.axis[0][2]; m[3]  = 0
    m[4]  = t.axis[1][0]; m[5]  = t.axis[1][1]; m[6]  = t.axis[1][2]; m[7]  = 0
    m[8]  = t.axis[2][0]; m[9]  = t.axis[2][1]; m[10] = t.axis[2][2]; m[11] = 0
    m[12] = t.origin[0];  m[13] = t.origin[1];  m[14] = t.origin[2];  m[15] = 1
    return m


def _extract_normal_matrix(m4):
    """Extract upper-left 3x3 from 4x4 column-major matrix."""
    m3 = np.zeros(9, dtype=np.float32)
    m3[0] = m4[0]; m3[1] = m4[1]; m3[2] = m4[2]
    m3[3] = m4[4]; m3[4] = m4[5]; m3[5] = m4[6]
    m3[6] = m4[8]; m3[7] = m4[9]; m3[8] = m4[10]
    return m3


def _pack_vertices(surf, frame):
    """Pack vertex positions + normals for a single frame into a float32 array.

    Layout: [px, py, pz, nx, ny, nz] per vertex (6 floats = 24 bytes stride).
    """
    base = frame * surf.numVerts
    data = np.zeros(surf.numVerts * 6, dtype=np.float32)
    for i in range(surf.numVerts):
        v = surf.vertices[base + i]
        off = i * 6
        data[off]     = v.position[0]
        data[off + 1] = v.position[1]
        data[off + 2] = v.position[2]
        data[off + 3] = v.normal[0]
        data[off + 4] = v.normal[1]
        data[off + 5] = v.normal[2]
    return data
