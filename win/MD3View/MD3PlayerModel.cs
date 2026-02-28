using System.Diagnostics;

namespace MD3View;

public class MD3PlayerModel
{
    private readonly MD3Model _lower;
    private readonly MD3Model _upper;
    private readonly MD3Model _head;
    private readonly AnimationConfig? _animConfig;
    private Dictionary<string, string> _lowerSkin = new();
    private Dictionary<string, string> _upperSkin = new();
    private Dictionary<string, string> _headSkin = new();
    private readonly string _modelPath;
    private readonly PK3Archive _archive;

    private AnimState _torsoState;
    private AnimState _legsState;
    private bool _playing;

    private static readonly Stopwatch _stopwatch = Stopwatch.StartNew();

    public string ModelName { get; }
    public AnimationConfig? AnimConfig => _animConfig;
    public List<string> AvailableSkins { get; private set; } = new();
    public string CurrentSkin { get; private set; } = "default";
    public float CenterHeight { get; private set; }
    public float BoundingRadius { get; private set; }

    public AnimNumber TorsoAnim
    {
        get => _torsoState.AnimIndex;
        set => SetTorsoAnimation(value);
    }

    public AnimNumber LegsAnim
    {
        get => _legsState.AnimIndex;
        set => SetLegsAnimation(value);
    }

    public bool Playing
    {
        get => _playing;
        set => _playing = value;
    }

    public MD3PlayerModel(PK3Archive archive, string modelPath)
    {
        _archive = archive;
        _modelPath = modelPath;
        ModelName = Path.GetFileName(modelPath);

        // Enumerate available skins
        EnumerateSkins();

        // Load MD3 files
        var lowerData = archive.ReadFile(modelPath + "/lower.md3");
        var upperData = archive.ReadFile(modelPath + "/upper.md3");
        var headData = archive.ReadFile(modelPath + "/head.md3");

        if (lowerData == null || upperData == null || headData == null)
            throw new InvalidDataException($"Missing .md3 files in {modelPath}");

        _lower = new MD3Model(lowerData, "lower.md3");
        _upper = new MD3Model(upperData, "upper.md3");
        _head = new MD3Model(headData, "head.md3");

        // Load default skin
        CurrentSkin = "default";
        LoadSkin(CurrentSkin);

        // Load animation config
        var animData = archive.ReadFile(modelPath + "/animation.cfg");
        if (animData != null)
            _animConfig = new AnimationConfig(animData);

        // Compute center height from frame 0 bounding boxes
        ComputeCenterHeight();

        // Default animations
        _playing = true;
        InitAnimState(ref _torsoState, AnimNumber.TORSO_STAND);
        InitAnimState(ref _legsState, AnimNumber.LEGS_IDLE);
    }

    private static double CurrentTimeMs() => _stopwatch.Elapsed.TotalMilliseconds;

    private void InitAnimState(ref AnimState state, AnimNumber anim)
    {
        state.AnimIndex = anim;
        state.CurrentFrame = 0;
        state.NextFrame = 0;
        state.Fraction = 0;
        state.FrameTime = CurrentTimeMs();
        state.Playing = true;
    }

    private static void TransformPoint(float px, float py, float pz,
        float[] origin, float[,] axis, out float ox, out float oy, out float oz)
    {
        ox = origin[0] + px * axis[0, 0] + py * axis[1, 0] + pz * axis[2, 0];
        oy = origin[1] + px * axis[0, 1] + py * axis[1, 1] + pz * axis[2, 1];
        oz = origin[2] + px * axis[0, 2] + py * axis[1, 2] + pz * axis[2, 2];
    }

    private void ComputeCenterHeight()
    {
        int legsFrame = 0;
        int torsoFrame = 0;
        if (_animConfig != null)
        {
            var anims = _animConfig.Animations;
            legsFrame = anims[(int)AnimNumber.LEGS_IDLE].FirstFrame;
            torsoFrame = anims[(int)AnimNumber.TORSO_STAND].FirstFrame;
        }
        if (legsFrame >= _lower.NumFrames) legsFrame = 0;
        if (torsoFrame >= _upper.NumFrames) torsoFrame = 0;

        float minX = 1e9f, maxX = -1e9f;
        float minY = 1e9f, maxY = -1e9f;
        float minZ = 1e9f, maxZ = -1e9f;

        // Lower body verts at idle frame
        foreach (var surf in _lower.Surfaces)
        {
            int baseIdx = legsFrame * surf.NumVerts;
            for (int v = 0; v < surf.NumVerts; v++)
            {
                var vert = surf.Vertices[baseIdx + v];
                if (vert.PosX < minX) minX = vert.PosX; if (vert.PosX > maxX) maxX = vert.PosX;
                if (vert.PosY < minY) minY = vert.PosY; if (vert.PosY > maxY) maxY = vert.PosY;
                if (vert.PosZ < minZ) minZ = vert.PosZ; if (vert.PosZ > maxZ) maxZ = vert.PosZ;
            }
        }

        // Get tag_torso at legs idle frame
        var torsoTag = _lower.TagForName("tag_torso", legsFrame);
        float[] tOrigin = { 0, 0, 0 };
        float[,] tAxis = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
        if (torsoTag.HasValue)
        {
            Array.Copy(torsoTag.Value.Origin, tOrigin, 3);
            Array.Copy(torsoTag.Value.Axis, tAxis, 9);
        }

        // Upper body verts at torso stand frame, transformed through tag_torso
        foreach (var surf in _upper.Surfaces)
        {
            int baseIdx = torsoFrame * surf.NumVerts;
            for (int v = 0; v < surf.NumVerts; v++)
            {
                var vert = surf.Vertices[baseIdx + v];
                TransformPoint(vert.PosX, vert.PosY, vert.PosZ, tOrigin, tAxis,
                    out float wx, out float wy, out float wz);
                if (wx < minX) minX = wx; if (wx > maxX) maxX = wx;
                if (wy < minY) minY = wy; if (wy > maxY) maxY = wy;
                if (wz < minZ) minZ = wz; if (wz > maxZ) maxZ = wz;
            }
        }

        // Get tag_head at torso stand frame, transformed through tag_torso
        var headTag = _upper.TagForName("tag_head", torsoFrame);
        float[] hOrigin = { 0, 0, 0 };
        float[,] hAxis = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
        if (headTag.HasValue)
        {
            TransformPoint(headTag.Value.Origin[0], headTag.Value.Origin[1], headTag.Value.Origin[2],
                tOrigin, tAxis, out hOrigin[0], out hOrigin[1], out hOrigin[2]);
            MatrixMultiply3x3(headTag.Value.Axis, tAxis, hAxis);
        }

        // Head verts at frame 0, transformed through both tags
        foreach (var surf in _head.Surfaces)
        {
            for (int v = 0; v < surf.NumVerts; v++)
            {
                var vert = surf.Vertices[v];
                TransformPoint(vert.PosX, vert.PosY, vert.PosZ, hOrigin, hAxis,
                    out float wx, out float wy, out float wz);
                if (wx < minX) minX = wx; if (wx > maxX) maxX = wx;
                if (wy < minY) minY = wy; if (wy > maxY) maxY = wy;
                if (wz < minZ) minZ = wz; if (wz > maxZ) maxZ = wz;
            }
        }

        float cx = (minX + maxX) * 0.5f;
        float cy = (minY + maxY) * 0.5f;
        float cz = (minZ + maxZ) * 0.5f;
        CenterHeight = cz;

        float dx = MathF.Max(maxX - cx, cx - minX);
        float dy = MathF.Max(maxY - cy, cy - minY);
        float dz = MathF.Max(maxZ - cz, cz - minZ);
        BoundingRadius = MathF.Sqrt(dx * dx + dy * dy + dz * dz);
    }

    private void EnumerateSkins()
    {
        var skinNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var prefix = (_modelPath + "/lower_").ToLowerInvariant();

        foreach (var file in _archive.AllFiles)
        {
            var lower = file.ToLowerInvariant();
            if (lower.StartsWith(prefix) && lower.EndsWith(".skin"))
            {
                var filename = Path.GetFileName(lower);
                // "lower_red.skin" -> "red"
                var skinName = filename[6..]; // skip "lower_"
                skinName = Path.GetFileNameWithoutExtension(skinName);
                if (skinName.Length > 0)
                    skinNames.Add(skinName);
            }
        }

        var sorted = skinNames.ToList();
        sorted.Sort(StringComparer.OrdinalIgnoreCase);
        if (sorted.Contains("default"))
        {
            sorted.Remove("default");
            sorted.Insert(0, "default");
        }
        AvailableSkins = sorted;
    }

    private void LoadSkin(string skinName)
    {
        var lowerSkinPath = _modelPath + $"/lower_{skinName}.skin";
        var upperSkinPath = _modelPath + $"/upper_{skinName}.skin";
        var headSkinPath = _modelPath + $"/head_{skinName}.skin";

        _lowerSkin = SkinParser.Parse(_archive.ReadFile(lowerSkinPath));
        _upperSkin = SkinParser.Parse(_archive.ReadFile(upperSkinPath));
        _headSkin = SkinParser.Parse(_archive.ReadFile(headSkinPath));
        CurrentSkin = skinName;
    }

    public void SelectSkin(string skinName) => LoadSkin(skinName);

    public void SetTorsoAnimation(AnimNumber anim) => InitAnimState(ref _torsoState, anim);
    public void SetLegsAnimation(AnimNumber anim) => InitAnimState(ref _legsState, anim);

    public void StepFrame(int direction)
    {
        if (_playing) return;
        StepAnimState(ref _torsoState, direction);
        StepAnimState(ref _legsState, direction);
    }

    private void StepAnimState(ref AnimState state, int dir)
    {
        if (_animConfig == null) return;
        var anim = _animConfig.Animations[(int)state.AnimIndex];
        if (anim.NumFrames <= 0) return;

        state.CurrentFrame += dir;
        if (state.CurrentFrame < 0) state.CurrentFrame = anim.NumFrames - 1;
        if (state.CurrentFrame >= anim.NumFrames) state.CurrentFrame = 0;
        state.NextFrame = state.CurrentFrame;
        state.Fraction = 0;
    }

    public int TorsoCurrentFrame => _torsoState.CurrentFrame;
    public int TorsoNumFrames => _animConfig?.Animations[(int)_torsoState.AnimIndex].NumFrames ?? 0;
    public int LegsCurrentFrame => _legsState.CurrentFrame;
    public int LegsNumFrames => _animConfig?.Animations[(int)_legsState.AnimIndex].NumFrames ?? 0;

    public void ScrubTorsoToFrame(int frame)
    {
        if (_animConfig == null) return;
        var anim = _animConfig.Animations[(int)_torsoState.AnimIndex];
        if (anim.NumFrames <= 0) return;
        _torsoState.CurrentFrame = frame % anim.NumFrames;
        _torsoState.NextFrame = _torsoState.CurrentFrame;
        _torsoState.Fraction = 0;
    }

    public void ScrubLegsToFrame(int frame)
    {
        if (_animConfig == null) return;
        var anim = _animConfig.Animations[(int)_legsState.AnimIndex];
        if (anim.NumFrames <= 0) return;
        _legsState.CurrentFrame = frame % anim.NumFrames;
        _legsState.NextFrame = _legsState.CurrentFrame;
        _legsState.Fraction = 0;
    }

    private void UpdateAnimState(ref AnimState state)
    {
        if (!_playing || _animConfig == null) return;
        var anim = _animConfig.Animations[(int)state.AnimIndex];
        if (anim.NumFrames <= 1) return;

        double now = CurrentTimeMs();
        double elapsed = now - state.FrameTime;

        if (anim.FrameLerp <= 0) return;

        state.Fraction = (float)(elapsed / anim.FrameLerp);
        while (state.Fraction >= 1.0f)
        {
            state.Fraction -= 1.0f;
            state.FrameTime += anim.FrameLerp;
            state.CurrentFrame++;

            if (anim.LoopFrames > 0)
            {
                if (state.CurrentFrame >= anim.NumFrames)
                    state.CurrentFrame = anim.NumFrames - anim.LoopFrames;
            }
            else
            {
                if (state.CurrentFrame >= anim.NumFrames - 1)
                {
                    state.CurrentFrame = anim.NumFrames - 1;
                    state.Fraction = 0;
                }
            }
        }

        state.NextFrame = state.CurrentFrame + 1;
        if (anim.LoopFrames > 0)
        {
            if (state.NextFrame >= anim.NumFrames)
                state.NextFrame = anim.NumFrames - anim.LoopFrames;
        }
        else
        {
            if (state.NextFrame >= anim.NumFrames)
                state.NextFrame = anim.NumFrames - 1;
        }
    }

    private void GetFrameAB(ref AnimState state, out int frameA, out int frameB, out float frac)
    {
        if (_animConfig == null)
        {
            frameA = 0; frameB = 0; frac = 0;
            return;
        }
        var anim = _animConfig.Animations[(int)state.AnimIndex];

        int fa = anim.FirstFrame + state.CurrentFrame;
        int fb = anim.FirstFrame + state.NextFrame;

        if (anim.Reversed != 0)
        {
            fa = anim.FirstFrame + anim.NumFrames - 1 - state.CurrentFrame;
            fb = anim.FirstFrame + anim.NumFrames - 1 - state.NextFrame;
        }

        frameA = fa;
        frameB = fb;
        frac = state.Fraction;
    }

    private static void LerpTag(out MD3Tag outTag, MD3Model model, string tagName,
        int frameA, int frameB, float frac)
    {
        outTag = new MD3Tag();
        var tagA = model.TagForName(tagName, frameA);
        var tagB = model.TagForName(tagName, frameB);

        if (!tagA.HasValue || !tagB.HasValue)
        {
            outTag.Axis[0, 0] = 1; outTag.Axis[1, 1] = 1; outTag.Axis[2, 2] = 1;
            return;
        }

        float backLerp = 1.0f - frac;
        for (int i = 0; i < 3; i++)
        {
            outTag.Origin[i] = tagA.Value.Origin[i] * backLerp + tagB.Value.Origin[i] * frac;
            outTag.Axis[0, i] = tagA.Value.Axis[0, i] * backLerp + tagB.Value.Axis[0, i] * frac;
            outTag.Axis[1, i] = tagA.Value.Axis[1, i] * backLerp + tagB.Value.Axis[1, i] * frac;
            outTag.Axis[2, i] = tagA.Value.Axis[2, i] * backLerp + tagB.Value.Axis[2, i] * frac;
        }
        VectorNormalize(outTag.Axis, 0);
        VectorNormalize(outTag.Axis, 1);
        VectorNormalize(outTag.Axis, 2);
    }

    private static void VectorNormalize(float[,] axis, int row)
    {
        float x = axis[row, 0], y = axis[row, 1], z = axis[row, 2];
        float len = MathF.Sqrt(x * x + y * y + z * z);
        if (len > 0.0001f)
        {
            axis[row, 0] = x / len;
            axis[row, 1] = y / len;
            axis[row, 2] = z / len;
        }
    }

    private static void MatrixMultiply3x3(float[,] in1, float[,] in2, float[,] result)
    {
        for (int i = 0; i < 3; i++)
            for (int j = 0; j < 3; j++)
                result[i, j] = in1[i, 0] * in2[0, j] + in1[i, 1] * in2[1, j] + in1[i, 2] * in2[2, j];
    }

    private static TagTransform PositionChildOnTag(TagTransform parent, MD3Tag tag)
    {
        var child = new TagTransform();

        // child.origin = parent.origin + tag.origin[0]*parent.axis[0] + ...
        for (int i = 0; i < 3; i++)
        {
            child.Origin[i] = parent.Origin[i];
            for (int j = 0; j < 3; j++)
                child.Origin[i] += tag.Origin[j] * parent.Axis[j, i];
        }

        // child.axis = tag.axis * parent.axis
        MatrixMultiply3x3(tag.Axis, parent.Axis, child.Axis);

        return child;
    }

    public void Render(ModelRenderer renderer, TextureCache texCache,
        float[] viewMatrix, float[] projMatrix, float gamma)
    {
        UpdateAnimState(ref _torsoState);
        UpdateAnimState(ref _legsState);

        // --- Lower body (legs) ---
        GetFrameAB(ref _legsState, out int legsFrameA, out int legsFrameB, out float legsFrac);

        var legsTransform = TagTransform.Identity();

        renderer.RenderModel(_lower, legsFrameA, legsFrameB, legsFrac,
            legsTransform, texCache, _lowerSkin, viewMatrix, projMatrix, gamma);

        // --- Upper body (torso) ---
        LerpTag(out var torsoTag, _lower, "tag_torso", legsFrameA, legsFrameB, legsFrac);
        var torsoTransform = PositionChildOnTag(legsTransform, torsoTag);

        GetFrameAB(ref _torsoState, out int torsoFrameA, out int torsoFrameB, out float torsoFrac);

        renderer.RenderModel(_upper, torsoFrameA, torsoFrameB, torsoFrac,
            torsoTransform, texCache, _upperSkin, viewMatrix, projMatrix, gamma);

        // --- Head ---
        LerpTag(out var headTag, _upper, "tag_head", torsoFrameA, torsoFrameB, torsoFrac);
        var headTransform = PositionChildOnTag(torsoTransform, headTag);

        renderer.RenderModel(_head, 0, 0, 0,
            headTransform, texCache, _headSkin, viewMatrix, projMatrix, gamma);
    }
}
