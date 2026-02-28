using OpenTK.Graphics.OpenGL4;

namespace MD3View;

public class ModelRenderer
{
    private const string VertexShaderSource = @"#version 150
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
";

    private const string FragmentShaderSource = @"#version 150
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
";

    private int _program;
    private int _locPosA, _locNormalA, _locPosB, _locNormalB, _locTexCoord;
    private int _locLerp, _locModelMatrix, _locViewMatrix, _locProjMatrix, _locNormalMatrix;
    private int _locTex, _locGamma;
    private int _vao;

    public bool SetupShaders()
    {
        int vs = CompileShader(ShaderType.VertexShader, VertexShaderSource);
        int fs = CompileShader(ShaderType.FragmentShader, FragmentShaderSource);
        if (vs == 0 || fs == 0) return false;

        _program = GL.CreateProgram();
        GL.AttachShader(_program, vs);
        GL.AttachShader(_program, fs);
        GL.LinkProgram(_program);

        GL.GetProgram(_program, GetProgramParameterName.LinkStatus, out int status);
        if (status == 0)
        {
            var log = GL.GetProgramInfoLog(_program);
            System.Diagnostics.Debug.WriteLine($"Program link error: {log}");
            return false;
        }

        GL.DeleteShader(vs);
        GL.DeleteShader(fs);

        _locPosA = GL.GetAttribLocation(_program, "posA");
        _locNormalA = GL.GetAttribLocation(_program, "normalA");
        _locPosB = GL.GetAttribLocation(_program, "posB");
        _locNormalB = GL.GetAttribLocation(_program, "normalB");
        _locTexCoord = GL.GetAttribLocation(_program, "texCoord");

        _locLerp = GL.GetUniformLocation(_program, "lerp");
        _locModelMatrix = GL.GetUniformLocation(_program, "modelMatrix");
        _locViewMatrix = GL.GetUniformLocation(_program, "viewMatrix");
        _locProjMatrix = GL.GetUniformLocation(_program, "projMatrix");
        _locNormalMatrix = GL.GetUniformLocation(_program, "normalMatrix");
        _locTex = GL.GetUniformLocation(_program, "tex");
        _locGamma = GL.GetUniformLocation(_program, "gamma");

        GL.GenVertexArrays(1, out _vao);

        return true;
    }

    public void RenderModel(MD3Model? model, int frameA, int frameB, float frac,
        TagTransform transform, TextureCache texCache,
        Dictionary<string, string>? skin, float[] viewMatrix, float[] projMatrix, float gamma)
    {
        if (model == null || _program == 0) return;

        int numFrames = model.NumFrames;
        if (numFrames == 0) return;
        frameA = frameA % numFrames;
        frameB = frameB % numFrames;

        GL.UseProgram(_program);
        GL.BindVertexArray(_vao);

        // Set view/proj uniforms
        GL.UniformMatrix4(_locViewMatrix, 1, false, viewMatrix);
        GL.UniformMatrix4(_locProjMatrix, 1, false, projMatrix);

        // Build model matrix from transform
        float[] modelMat = new float[16];
        BuildModelMatrix(transform, modelMat);
        GL.UniformMatrix4(_locModelMatrix, 1, false, modelMat);

        float[] normalMat = new float[9];
        ExtractNormalMatrix(modelMat, normalMat);
        GL.UniformMatrix3(_locNormalMatrix, 1, false, normalMat);

        GL.Uniform1(_locLerp, frac);
        GL.Uniform1(_locGamma, gamma);
        GL.Uniform1(_locTex, 0);

        for (int s = 0; s < model.NumSurfaces; s++)
        {
            var surf = model.Surfaces[s];

            // Look up texture
            string? texPath = null;
            skin?.TryGetValue(surf.Name, out texPath);
            if (texPath == null && surf.ShaderName.Length > 0)
                texPath = surf.ShaderName;
            int texID = texPath != null ? texCache.TextureForPath(texPath) : texCache.WhiteTexture;

            GL.ActiveTexture(TextureUnit.Texture0);
            GL.BindTexture(TextureTarget.Texture2D, texID);

            // Upload vertex data for frame A and B
            int vertOffset_A = frameA * surf.NumVerts;
            int vertOffset_B = frameB * surf.NumVerts;

            // Build interleaved data for frame A (pos + normal = 6 floats per vertex)
            float[] dataA = new float[surf.NumVerts * 6];
            float[] dataB = new float[surf.NumVerts * 6];
            for (int v = 0; v < surf.NumVerts; v++)
            {
                var va = surf.Vertices[vertOffset_A + v];
                dataA[v * 6 + 0] = va.PosX;
                dataA[v * 6 + 1] = va.PosY;
                dataA[v * 6 + 2] = va.PosZ;
                dataA[v * 6 + 3] = va.NormX;
                dataA[v * 6 + 4] = va.NormY;
                dataA[v * 6 + 5] = va.NormZ;

                var vb = surf.Vertices[vertOffset_B + v];
                dataB[v * 6 + 0] = vb.PosX;
                dataB[v * 6 + 1] = vb.PosY;
                dataB[v * 6 + 2] = vb.PosZ;
                dataB[v * 6 + 3] = vb.NormX;
                dataB[v * 6 + 4] = vb.NormY;
                dataB[v * 6 + 5] = vb.NormZ;
            }

            int vboA = GL.GenBuffer();
            int vboB = GL.GenBuffer();
            int vboTex = GL.GenBuffer();
            int ebo = GL.GenBuffer();

            // Frame A positions + normals
            GL.BindBuffer(BufferTarget.ArrayBuffer, vboA);
            GL.BufferData(BufferTarget.ArrayBuffer, dataA.Length * sizeof(float), dataA, BufferUsageHint.StreamDraw);
            GL.EnableVertexAttribArray(_locPosA);
            GL.VertexAttribPointer(_locPosA, 3, VertexAttribPointerType.Float, false, 6 * sizeof(float), 0);
            GL.EnableVertexAttribArray(_locNormalA);
            GL.VertexAttribPointer(_locNormalA, 3, VertexAttribPointerType.Float, false, 6 * sizeof(float), 3 * sizeof(float));

            // Frame B positions + normals
            GL.BindBuffer(BufferTarget.ArrayBuffer, vboB);
            GL.BufferData(BufferTarget.ArrayBuffer, dataB.Length * sizeof(float), dataB, BufferUsageHint.StreamDraw);
            GL.EnableVertexAttribArray(_locPosB);
            GL.VertexAttribPointer(_locPosB, 3, VertexAttribPointerType.Float, false, 6 * sizeof(float), 0);
            GL.EnableVertexAttribArray(_locNormalB);
            GL.VertexAttribPointer(_locNormalB, 3, VertexAttribPointerType.Float, false, 6 * sizeof(float), 3 * sizeof(float));

            // Texture coordinates
            GL.BindBuffer(BufferTarget.ArrayBuffer, vboTex);
            GL.BufferData(BufferTarget.ArrayBuffer, surf.TexCoords.Length * sizeof(float), surf.TexCoords, BufferUsageHint.StreamDraw);
            GL.EnableVertexAttribArray(_locTexCoord);
            GL.VertexAttribPointer(_locTexCoord, 2, VertexAttribPointerType.Float, false, 0, 0);

            // Index buffer
            GL.BindBuffer(BufferTarget.ElementArrayBuffer, ebo);
            GL.BufferData(BufferTarget.ElementArrayBuffer, surf.Triangles.Length * sizeof(int), surf.Triangles, BufferUsageHint.StreamDraw);

            GL.DrawElements(PrimitiveType.Triangles, surf.NumTriangles * 3, DrawElementsType.UnsignedInt, 0);

            GL.DeleteBuffer(vboA);
            GL.DeleteBuffer(vboB);
            GL.DeleteBuffer(vboTex);
            GL.DeleteBuffer(ebo);
        }

        GL.BindVertexArray(0);
        GL.UseProgram(0);
    }

    public void Cleanup()
    {
        if (_program != 0)
        {
            GL.DeleteProgram(_program);
            _program = 0;
        }
        if (_vao != 0)
        {
            GL.DeleteVertexArray(_vao);
            _vao = 0;
        }
    }

    private static void BuildModelMatrix(TagTransform t, float[] o)
    {
        // Column-major 4x4 from origin + axis[3,3]
        // Q3 axis: axis[0] = forward, axis[1] = left, axis[2] = up
        o[0]  = t.Axis[0,0]; o[1]  = t.Axis[0,1]; o[2]  = t.Axis[0,2]; o[3]  = 0;
        o[4]  = t.Axis[1,0]; o[5]  = t.Axis[1,1]; o[6]  = t.Axis[1,2]; o[7]  = 0;
        o[8]  = t.Axis[2,0]; o[9]  = t.Axis[2,1]; o[10] = t.Axis[2,2]; o[11] = 0;
        o[12] = t.Origin[0]; o[13] = t.Origin[1]; o[14] = t.Origin[2]; o[15] = 1;
    }

    private static void ExtractNormalMatrix(float[] m4, float[] m3)
    {
        // Upper-left 3x3 of the model matrix
        m3[0] = m4[0]; m3[1] = m4[1]; m3[2] = m4[2];
        m3[3] = m4[4]; m3[4] = m4[5]; m3[5] = m4[6];
        m3[6] = m4[8]; m3[7] = m4[9]; m3[8] = m4[10];
    }

    private static int CompileShader(ShaderType type, string source)
    {
        int shader = GL.CreateShader(type);
        GL.ShaderSource(shader, source);
        GL.CompileShader(shader);
        GL.GetShader(shader, ShaderParameter.CompileStatus, out int status);
        if (status == 0)
        {
            var log = GL.GetShaderInfoLog(shader);
            System.Diagnostics.Debug.WriteLine($"Shader compile error: {log}");
            GL.DeleteShader(shader);
            return 0;
        }
        return shader;
    }
}
