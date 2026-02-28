using System.Runtime.InteropServices;
using System.Text;

namespace MD3View;

public class MD3Model
{
    public int NumFrames { get; }
    public int NumTags { get; }
    public int NumSurfaces { get; }

    public MD3Surface[] Surfaces { get; }
    public MD3Tag[] Tags { get; }   // numTags * numFrames
    public MD3Frame[] Frames { get; }

    public MD3Model(byte[] data, string name)
    {
        if (data.Length < Marshal.SizeOf<MD3DiskHeader>())
            throw new InvalidDataException($"MD3 data too small for {name}");

        var header = ReadStruct<MD3DiskHeader>(data, 0);
        if (header.Ident != MD3Constants.MD3_IDENT || header.Version != MD3Constants.MD3_VERSION)
            throw new InvalidDataException($"MD3: invalid ident/version for {name}");

        NumFrames = header.NumFrames;
        NumTags = header.NumTags;
        NumSurfaces = header.NumSurfaces;

        // Parse frames
        Frames = new MD3Frame[NumFrames];
        int frameSize = Marshal.SizeOf<MD3DiskFrame>();
        for (int i = 0; i < NumFrames; i++)
        {
            var df = ReadStruct<MD3DiskFrame>(data, header.OfsFrames + i * frameSize);
            Frames[i] = new MD3Frame
            {
                Bounds = new float[6],
                LocalOrigin = new float[3],
                Radius = df.Radius,
                Name = ""
            };
            unsafe
            {
                for (int j = 0; j < 6; j++) Frames[i].Bounds[j] = df.Bounds[j];
                for (int j = 0; j < 3; j++) Frames[i].LocalOrigin[j] = df.LocalOrigin[j];
                Frames[i].Name = ReadCString(df.Name, 16);
            }
        }

        // Parse tags (numTags * numFrames)
        int totalTags = NumTags * NumFrames;
        Tags = new MD3Tag[totalTags];
        int tagSize = Marshal.SizeOf<MD3DiskTag>();
        for (int i = 0; i < totalTags; i++)
        {
            var dt = ReadStruct<MD3DiskTag>(data, header.OfsTags + i * tagSize);
            Tags[i] = new MD3Tag();
            unsafe
            {
                Tags[i].Name = ReadCString(dt.Name, MD3Constants.MAX_QPATH);
                for (int j = 0; j < 3; j++)
                    Tags[i].Origin[j] = dt.Origin[j];
                for (int r = 0; r < 3; r++)
                    for (int c = 0; c < 3; c++)
                        Tags[i].Axis[r, c] = dt.Axis[r * 3 + c];
            }
        }

        // Parse surfaces
        Surfaces = new MD3Surface[NumSurfaces];
        int surfPtr = header.OfsSurfaces;

        for (int i = 0; i < NumSurfaces; i++)
        {
            if (surfPtr < 0 || surfPtr >= data.Length) break;

            var ds = ReadStruct<MD3DiskSurface>(data, surfPtr);
            var surf = new MD3Surface();

            // Copy name and lowercase it
            unsafe
            {
                surf.Name = ReadCString(ds.Name, MD3Constants.MAX_QPATH).ToLowerInvariant();
            }

            // Strip trailing _1 or _2
            if (surf.Name.Length > 2 && surf.Name[^2] == '_' &&
                (surf.Name[^1] == '1' || surf.Name[^1] == '2'))
            {
                surf.Name = surf.Name[..^2];
            }

            surf.NumFrames = ds.NumFrames;
            surf.NumVerts = ds.NumVerts;
            surf.NumTriangles = ds.NumTriangles;

            // Read shader name
            if (ds.NumShaders > 0)
            {
                var shader = ReadStruct<MD3DiskShader>(data, surfPtr + ds.OfsShaders);
                unsafe
                {
                    surf.ShaderName = ReadCString(shader.Name, MD3Constants.MAX_QPATH);
                }
            }

            // Read triangles
            surf.Triangles = new int[surf.NumTriangles * 3];
            int triSize = Marshal.SizeOf<MD3DiskTriangle>();
            for (int j = 0; j < surf.NumTriangles; j++)
            {
                var tri = ReadStruct<MD3DiskTriangle>(data, surfPtr + ds.OfsTriangles + j * triSize);
                surf.Triangles[j * 3 + 0] = tri.Index0;
                surf.Triangles[j * 3 + 1] = tri.Index1;
                surf.Triangles[j * 3 + 2] = tri.Index2;
            }

            // Read texture coordinates
            surf.TexCoords = new float[surf.NumVerts * 2];
            int tcSize = Marshal.SizeOf<MD3DiskTexCoord>();
            for (int j = 0; j < surf.NumVerts; j++)
            {
                var tc = ReadStruct<MD3DiskTexCoord>(data, surfPtr + ds.OfsSt + j * tcSize);
                surf.TexCoords[j * 2 + 0] = tc.S;
                surf.TexCoords[j * 2 + 1] = tc.T;
            }

            // Read and decompress vertices (all frames)
            int totalVerts = surf.NumVerts * surf.NumFrames;
            surf.Vertices = new MD3Vertex[totalVerts];
            int vertSize = Marshal.SizeOf<MD3DiskVertex>();
            for (int j = 0; j < totalVerts; j++)
            {
                var dv = ReadStruct<MD3DiskVertex>(data, surfPtr + ds.OfsXyzNormals + j * vertSize);
                surf.Vertices[j].PosX = dv.X * MD3Constants.MD3_XYZ_SCALE;
                surf.Vertices[j].PosY = dv.Y * MD3Constants.MD3_XYZ_SCALE;
                surf.Vertices[j].PosZ = dv.Z * MD3Constants.MD3_XYZ_SCALE;
                DecompressNormal(dv.Normal,
                    out surf.Vertices[j].NormX,
                    out surf.Vertices[j].NormY,
                    out surf.Vertices[j].NormZ);
            }

            Surfaces[i] = surf;
            surfPtr += ds.OfsEnd;
        }
    }

    public MD3Tag? TagForName(string name, int frame)
    {
        if (frame < 0 || frame >= NumFrames) return null;
        int baseIdx = frame * NumTags;
        for (int i = 0; i < NumTags; i++)
        {
            if (string.Equals(Tags[baseIdx + i].Name, name, StringComparison.OrdinalIgnoreCase))
                return Tags[baseIdx + i];
        }
        return null;
    }

    private static void DecompressNormal(short encoded, out float nx, out float ny, out float nz)
    {
        float lat = ((encoded >> 8) & 0xFF) * (2.0f * MathF.PI / 255.0f);
        float lng = (encoded & 0xFF) * (2.0f * MathF.PI / 255.0f);
        nx = MathF.Cos(lat) * MathF.Sin(lng);
        ny = MathF.Sin(lat) * MathF.Sin(lng);
        nz = MathF.Cos(lng);
    }

    private static T ReadStruct<T>(byte[] data, int offset) where T : struct
    {
        int size = Marshal.SizeOf<T>();
        var handle = GCHandle.Alloc(data, GCHandleType.Pinned);
        try
        {
            return Marshal.PtrToStructure<T>(handle.AddrOfPinnedObject() + offset);
        }
        finally
        {
            handle.Free();
        }
    }

    private static unsafe string ReadCString(byte* ptr, int maxLen)
    {
        int len = 0;
        while (len < maxLen && ptr[len] != 0) len++;
        return Encoding.ASCII.GetString(ptr, len);
    }
}
