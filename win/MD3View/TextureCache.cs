using OpenTK.Graphics.OpenGL4;
using StbImageSharp;

namespace MD3View;

public class TextureCache
{
    private readonly PK3Archive _archive;
    private readonly Dictionary<string, int> _cache = new(StringComparer.OrdinalIgnoreCase);
    private int _whiteTexture;

    public TextureCache(PK3Archive archive)
    {
        _archive = archive;
    }

    public int WhiteTexture
    {
        get
        {
            if (_whiteTexture == 0)
            {
                _whiteTexture = GL.GenTexture();
                GL.BindTexture(TextureTarget.Texture2D, _whiteTexture);
                byte[] white = { 255, 255, 255, 255 };
                GL.TexImage2D(TextureTarget.Texture2D, 0, PixelInternalFormat.Rgba, 1, 1, 0,
                    PixelFormat.Rgba, PixelType.UnsignedByte, white);
                GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMinFilter, (int)TextureMinFilter.Nearest);
                GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMagFilter, (int)TextureMagFilter.Nearest);
            }
            return _whiteTexture;
        }
    }

    public int TextureForPath(string? path)
    {
        if (string.IsNullOrEmpty(path)) return WhiteTexture;

        var key = path.ToLowerInvariant();
        if (_cache.TryGetValue(key, out int cached))
            return cached;

        // Try loading the file directly
        byte[]? data = _archive.ReadFile(path);

        // Try alternate extensions if not found
        if (data == null)
        {
            var basePath = Path.ChangeExtension(path, null);
            string[] exts = { ".tga", ".jpg", ".jpeg", ".png", ".TGA", ".JPG", ".PNG" };
            foreach (var ext in exts)
            {
                data = _archive.ReadFile(basePath + ext);
                if (data != null) break;
            }
        }

        if (data == null)
        {
            _cache[key] = WhiteTexture;
            return WhiteTexture;
        }

        ImageResult image;
        try
        {
            // StbImageSharp default: no vertical flip (matches Q3 UV convention)
            image = ImageResult.FromMemory(data, ColorComponents.RedGreenBlueAlpha);
        }
        catch
        {
            _cache[key] = WhiteTexture;
            return WhiteTexture;
        }

        int tex = GL.GenTexture();
        GL.BindTexture(TextureTarget.Texture2D, tex);
        GL.TexImage2D(TextureTarget.Texture2D, 0, PixelInternalFormat.Rgba,
            image.Width, image.Height, 0,
            PixelFormat.Rgba, PixelType.UnsignedByte, image.Data);
        GL.GenerateMipmap(GenerateMipmapTarget.Texture2D);
        GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMinFilter, (int)TextureMinFilter.LinearMipmapLinear);
        GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMagFilter, (int)TextureMagFilter.Linear);
        GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureWrapS, (int)TextureWrapMode.Repeat);
        GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureWrapT, (int)TextureWrapMode.Repeat);

        _cache[key] = tex;
        return tex;
    }

    public void Flush()
    {
        foreach (var texID in _cache.Values)
        {
            if (texID != _whiteTexture)
                GL.DeleteTexture(texID);
        }
        _cache.Clear();
        if (_whiteTexture != 0)
        {
            GL.DeleteTexture(_whiteTexture);
            _whiteTexture = 0;
        }
    }
}
