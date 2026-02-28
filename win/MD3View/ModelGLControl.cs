using OpenTK.Graphics.OpenGL4;
using OpenTK.GLControl;
using OpenTK.Windowing.Common;

namespace MD3View;

public class ModelGLControl : GLControl
{
    private float _rotationX;
    private float _rotationY = -90; // Start facing camera
    private float _zoom = 100.0f;
    private Point _lastMouse;
    private bool _dragging;
    private bool _shadersReady;

    public MD3PlayerModel? PlayerModel { get; set; }
    public ModelRenderer? Renderer { get; private set; }
    public TextureCache? TextureCache { get; set; }
    public float Gamma { get; set; } = 1.0f;

    public ModelGLControl() : base(new GLControlSettings
    {
        API = ContextAPI.OpenGL,
        APIVersion = new Version(3, 2),
        Flags = ContextFlags.Default,
        Profile = ContextProfile.Core,
    })
    {
    }

    protected override void OnLoad(EventArgs e)
    {
        base.OnLoad(e);
        MakeCurrent();

        GL.Enable(EnableCap.DepthTest);
        GL.Enable(EnableCap.CullFace);
        GL.FrontFace(FrontFaceDirection.Cw); // Q3 winding order
        GL.CullFace(CullFaceMode.Back);
        GL.Enable(EnableCap.Blend);
        GL.BlendFunc(BlendingFactor.SrcAlpha, BlendingFactor.OneMinusSrcAlpha);
        GL.ClearColor(0.2f, 0.2f, 0.25f, 1.0f);

        Renderer = new ModelRenderer();
        _shadersReady = Renderer.SetupShaders();
        if (!_shadersReady)
            System.Diagnostics.Debug.WriteLine("ModelGLControl: shader setup failed");
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);

        if (!_shadersReady || !IsHandleCreated) return;

        MakeCurrent();
        GL.Viewport(0, 0, ClientSize.Width, ClientSize.Height);
        GL.Clear(ClearBufferMask.ColorBufferBit | ClearBufferMask.DepthBufferBit);

        if (PlayerModel != null && TextureCache != null)
        {
            float aspect = (float)ClientSize.Width / ClientSize.Height;
            float[] projMatrix = new float[16];
            BuildPerspective(projMatrix, 45.0f, aspect, 1.0f, 2000.0f);

            float centerZ = PlayerModel.CenterHeight;
            float radX = _rotationX * MathF.PI / 180.0f;
            float radY = _rotationY * MathF.PI / 180.0f;
            float camX = _zoom * MathF.Cos(radX) * MathF.Cos(radY);
            float camY = _zoom * MathF.Cos(radX) * MathF.Sin(radY);
            float camZ = centerZ + _zoom * MathF.Sin(radX);

            float[] viewMatrix = new float[16];
            BuildLookAt(viewMatrix, camX, camY, camZ, 0, 0, centerZ, 0, 0, 1);

            PlayerModel.Render(Renderer!, TextureCache, viewMatrix, projMatrix, Gamma);
        }

        SwapBuffers();
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button == MouseButtons.Left)
        {
            _dragging = true;
            _lastMouse = e.Location;
            Capture = true;
        }
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (e.Button == MouseButtons.Left)
        {
            _dragging = false;
            Capture = false;
        }
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (_dragging)
        {
            float dx = e.X - _lastMouse.X;
            float dy = e.Y - _lastMouse.Y;
            _rotationY += dx * 0.5f;
            _rotationX -= dy * 0.5f; // Inverted Y (WinForms Y is top-down)
            if (_rotationX > 89) _rotationX = 89;
            if (_rotationX < -89) _rotationX = -89;
            _lastMouse = e.Location;
            Invalidate();
        }
    }

    protected override void OnMouseWheel(MouseEventArgs e)
    {
        base.OnMouseWheel(e);
        _zoom -= e.Delta / 120.0f * 4.0f;
        if (_zoom < 10) _zoom = 10;
        if (_zoom > 500) _zoom = 500;
        Invalidate();
    }

    public void HandleKeyDown(Keys keyCode)
    {
        if (keyCode == Keys.Left)
        {
            PlayerModel?.StepFrame(-1);
            Invalidate();
        }
        else if (keyCode == Keys.Right)
        {
            PlayerModel?.StepFrame(1);
            Invalidate();
        }
    }

    // Screenshot: capture current view at higher scale
    public System.Drawing.Bitmap? CaptureScreenshot(int scale)
    {
        MakeCurrent();

        int w = ClientSize.Width * scale;
        int h = ClientSize.Height * scale;

        return CaptureToFBO(w, h, false);
    }

    // Render: smart-framed at specified resolution
    public System.Drawing.Bitmap? CaptureRender(int w, int h)
    {
        MakeCurrent();
        return CaptureToFBO(w, h, true);
    }

    private System.Drawing.Bitmap? CaptureToFBO(int w, int h, bool smartFrame)
    {
        // Create FBO
        int fbo = GL.GenFramebuffer();
        GL.BindFramebuffer(FramebufferTarget.Framebuffer, fbo);

        int colorTex = GL.GenTexture();
        GL.BindTexture(TextureTarget.Texture2D, colorTex);
        GL.TexImage2D(TextureTarget.Texture2D, 0, PixelInternalFormat.Rgba8, w, h, 0,
            PixelFormat.Rgba, PixelType.UnsignedByte, IntPtr.Zero);
        GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMinFilter, (int)TextureMinFilter.Linear);
        GL.FramebufferTexture2D(FramebufferTarget.Framebuffer, FramebufferAttachment.ColorAttachment0,
            TextureTarget.Texture2D, colorTex, 0);

        int depthRB = GL.GenRenderbuffer();
        GL.BindRenderbuffer(RenderbufferTarget.Renderbuffer, depthRB);
        GL.RenderbufferStorage(RenderbufferTarget.Renderbuffer, RenderbufferStorage.DepthComponent24, w, h);
        GL.FramebufferRenderbuffer(FramebufferTarget.Framebuffer, FramebufferAttachment.DepthAttachment,
            RenderbufferTarget.Renderbuffer, depthRB);

        if (GL.CheckFramebufferStatus(FramebufferTarget.Framebuffer) != FramebufferErrorCode.FramebufferComplete)
        {
            GL.BindFramebuffer(FramebufferTarget.Framebuffer, 0);
            GL.DeleteFramebuffer(fbo);
            GL.DeleteTexture(colorTex);
            GL.DeleteRenderbuffer(depthRB);
            return null;
        }

        GL.Viewport(0, 0, w, h);
        GL.Clear(ClearBufferMask.ColorBufferBit | ClearBufferMask.DepthBufferBit);

        if (PlayerModel != null && TextureCache != null && Renderer != null)
        {
            float renderAspect = (float)w / h;
            float fovY = 45.0f;
            float[] projMatrix = new float[16];
            BuildPerspective(projMatrix, fovY, renderAspect, 1.0f, 2000.0f);

            float zoom = _zoom;
            if (smartFrame)
            {
                // Smart framing: compute zoom to fit model's bounding sphere
                float radius = PlayerModel.BoundingRadius;
                float padding = 1.4f;
                float halfFovRad = fovY * 0.5f * MathF.PI / 180.0f;
                float distV = (radius * padding) / MathF.Sin(halfFovRad);
                float halfHFov = MathF.Atan(MathF.Tan(halfFovRad) * renderAspect);
                float distH = (radius * padding) / MathF.Sin(halfHFov);
                zoom = MathF.Max(distV, distH);
            }

            float centerZ = PlayerModel.CenterHeight;
            float radX = _rotationX * MathF.PI / 180.0f;
            float radY = _rotationY * MathF.PI / 180.0f;
            float camX = zoom * MathF.Cos(radX) * MathF.Cos(radY);
            float camY = zoom * MathF.Cos(radX) * MathF.Sin(radY);
            float camZ = centerZ + zoom * MathF.Sin(radX);

            float[] viewMatrix = new float[16];
            BuildLookAt(viewMatrix, camX, camY, camZ, 0, 0, centerZ, 0, 0, 1);

            PlayerModel.Render(Renderer, TextureCache, viewMatrix, projMatrix, Gamma);
        }

        // Read pixels
        byte[] pixels = new byte[w * h * 4];
        GL.ReadPixels(0, 0, w, h, PixelFormat.Rgba, PixelType.UnsignedByte, pixels);

        // Cleanup FBO
        GL.BindFramebuffer(FramebufferTarget.Framebuffer, 0);
        GL.DeleteFramebuffer(fbo);
        GL.DeleteTexture(colorTex);
        GL.DeleteRenderbuffer(depthRB);

        // Restore viewport
        GL.Viewport(0, 0, ClientSize.Width, ClientSize.Height);

        // Create bitmap (flip vertically, RGB no alpha)
        var bitmap = new System.Drawing.Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format24bppRgb);
        var bmpData = bitmap.LockBits(
            new System.Drawing.Rectangle(0, 0, w, h),
            System.Drawing.Imaging.ImageLockMode.WriteOnly,
            System.Drawing.Imaging.PixelFormat.Format24bppRgb);

        unsafe
        {
            byte* dst = (byte*)bmpData.Scan0;
            for (int row = 0; row < h; row++)
            {
                int srcRow = h - 1 - row; // flip
                int srcOffset = srcRow * w * 4;
                int dstOffset = row * bmpData.Stride;
                for (int x = 0; x < w; x++)
                {
                    // RGBA -> BGR (Bitmap format)
                    dst[dstOffset + x * 3 + 0] = pixels[srcOffset + x * 4 + 2]; // B
                    dst[dstOffset + x * 3 + 1] = pixels[srcOffset + x * 4 + 1]; // G
                    dst[dstOffset + x * 3 + 2] = pixels[srcOffset + x * 4 + 0]; // R
                }
            }
        }

        bitmap.UnlockBits(bmpData);
        return bitmap;
    }

    private static void BuildPerspective(float[] m, float fovY, float aspect, float nearZ, float farZ)
    {
        float f = 1.0f / MathF.Tan(fovY * 0.5f * MathF.PI / 180.0f);
        Array.Clear(m, 0, 16);
        m[0] = f / aspect;
        m[5] = f;
        m[10] = (farZ + nearZ) / (nearZ - farZ);
        m[11] = -1.0f;
        m[14] = (2.0f * farZ * nearZ) / (nearZ - farZ);
    }

    private static void BuildLookAt(float[] m, float eyeX, float eyeY, float eyeZ,
        float cx, float cy, float cz, float upX, float upY, float upZ)
    {
        float fx = cx - eyeX, fy = cy - eyeY, fz = cz - eyeZ;
        float flen = MathF.Sqrt(fx * fx + fy * fy + fz * fz);
        fx /= flen; fy /= flen; fz /= flen;

        float sx = fy * upZ - fz * upY, sy = fz * upX - fx * upZ, sz = fx * upY - fy * upX;
        float slen = MathF.Sqrt(sx * sx + sy * sy + sz * sz);
        sx /= slen; sy /= slen; sz /= slen;

        float ux = sy * fz - sz * fy, uy = sz * fx - sx * fz, uz = sx * fy - sy * fx;

        Array.Clear(m, 0, 16);
        m[0] = sx;  m[4] = sy;  m[8]  = sz;  m[12] = -(sx * eyeX + sy * eyeY + sz * eyeZ);
        m[1] = ux;  m[5] = uy;  m[9]  = uz;  m[13] = -(ux * eyeX + uy * eyeY + uz * eyeZ);
        m[2] = -fx; m[6] = -fy; m[10] = -fz; m[14] =  (fx * eyeX + fy * eyeY + fz * eyeZ);
        m[3] = 0;   m[7] = 0;   m[11] = 0;   m[15] = 1;
    }
}
