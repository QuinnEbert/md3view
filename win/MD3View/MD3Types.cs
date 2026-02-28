using System.Runtime.InteropServices;

namespace MD3View;

// ============================================================
// On-disk MD3 binary format structures
// ============================================================

public static class MD3Constants
{
    public const int MD3_IDENT = ('3' << 24) + ('P' << 16) + ('D' << 8) + 'I';
    public const int MD3_VERSION = 15;
    public const float MD3_XYZ_SCALE = 1.0f / 64.0f;
    public const int MAX_QPATH = 64;

    public const int MD3_MAX_FRAMES = 1024;
    public const int MD3_MAX_TAGS = 16;
    public const int MD3_MAX_SURFACES = 32;
    public const int MD3_MAX_TRIANGLES = 8192;
    public const int MD3_MAX_VERTS = 4096;
    public const int MD3_MAX_SHADERS = 256;
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct MD3DiskHeader
{
    public int Ident;
    public int Version;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 64)]
    public byte[] Name;
    public int Flags;
    public int NumFrames;
    public int NumTags;
    public int NumSurfaces;
    public int NumSkins;
    public int OfsFrames;
    public int OfsTags;
    public int OfsSurfaces;
    public int OfsEnd;
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public unsafe struct MD3DiskFrame
{
    public fixed float Bounds[6]; // [2][3]
    public fixed float LocalOrigin[3];
    public float Radius;
    public fixed byte Name[16];
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public unsafe struct MD3DiskTag
{
    public fixed byte Name[64]; // MAX_QPATH
    public fixed float Origin[3];
    public fixed float Axis[9]; // [3][3]
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public unsafe struct MD3DiskSurface
{
    public int Ident;
    public fixed byte Name[64]; // MAX_QPATH
    public int SurfFlags;
    public int NumFrames;
    public int NumShaders;
    public int NumVerts;
    public int NumTriangles;
    public int OfsTriangles;
    public int OfsShaders;
    public int OfsSt;
    public int OfsXyzNormals;
    public int OfsEnd;
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public unsafe struct MD3DiskShader
{
    public fixed byte Name[64]; // MAX_QPATH
    public int ShaderIndex;
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct MD3DiskTriangle
{
    public int Index0;
    public int Index1;
    public int Index2;
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct MD3DiskTexCoord
{
    public float S;
    public float T;
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct MD3DiskVertex
{
    public short X;
    public short Y;
    public short Z;
    public short Normal;
}

// ============================================================
// Runtime structures (decompressed, ready for rendering)
// ============================================================

public struct MD3Vertex
{
    public float PosX, PosY, PosZ;
    public float NormX, NormY, NormZ;
}

public class MD3Surface
{
    public string Name = "";
    public int NumFrames;
    public int NumVerts;
    public int NumTriangles;
    public int[] Triangles = Array.Empty<int>();     // numTriangles * 3
    public float[] TexCoords = Array.Empty<float>(); // numVerts * 2
    public MD3Vertex[] Vertices = Array.Empty<MD3Vertex>(); // numVerts * numFrames
    public string ShaderName = "";
    public int TextureID; // GL texture ID
}

public struct MD3Tag
{
    public string Name;
    public float[] Origin;    // [3]
    public float[,] Axis;    // [3,3]

    public MD3Tag()
    {
        Name = "";
        Origin = new float[3];
        Axis = new float[3, 3];
    }
}

public struct MD3Frame
{
    public float[] Bounds;       // [6] = [2][3]
    public float[] LocalOrigin;  // [3]
    public float Radius;
    public string Name;
}

// ============================================================
// Animation enum (matches Q3 bg_public.h)
// ============================================================

public enum AnimNumber
{
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
}

public static class AnimationNames
{
    public static readonly string[] Names =
    {
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
}

public struct Animation
{
    public int FirstFrame;
    public int NumFrames;
    public int LoopFrames;
    public int FrameLerp; // msec between frames
    public int Reversed;
    public int Flipflop;
}

public struct AnimState
{
    public AnimNumber AnimIndex;
    public int CurrentFrame;
    public int NextFrame;
    public float Fraction;    // lerp fraction between frames
    public double FrameTime;  // time of last frame change (ms)
    public bool Playing;
}

public struct TagTransform
{
    public float[] Origin;    // [3]
    public float[,] Axis;    // [3,3]

    public TagTransform()
    {
        Origin = new float[3];
        Axis = new float[3, 3];
    }

    public static TagTransform Identity()
    {
        var t = new TagTransform();
        t.Axis[0, 0] = 1;
        t.Axis[1, 1] = 1;
        t.Axis[2, 2] = 1;
        return t;
    }
}
