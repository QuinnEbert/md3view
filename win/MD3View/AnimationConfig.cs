using System.Text;

namespace MD3View;

public class AnimationConfig
{
    private readonly Animation[] _animations = new Animation[(int)AnimNumber.MAX_TOTALANIMATIONS];

    public bool FixedLegs { get; private set; }
    public bool FixedTorso { get; private set; }

    public Animation[] Animations => _animations;

    public AnimationConfig(byte[] data)
    {
        string? text;
        try
        {
            text = Encoding.UTF8.GetString(data);
        }
        catch
        {
            text = Encoding.Latin1.GetString(data);
        }

        if (text == null) return;

        Parse(text);
    }

    private void Parse(string text)
    {
        int pos = 0;
        int skip = 0;

        // Skip optional header keywords
        while (pos < text.Length)
        {
            SkipWhitespace(text, ref pos);
            if (pos >= text.Length) break;

            // Skip comment lines
            if (pos + 1 < text.Length && text[pos] == '/' && text[pos + 1] == '/')
            {
                SkipToEndOfLine(text, ref pos);
                continue;
            }

            // If starts with digit or minus, we've reached animation data
            if (char.IsDigit(text[pos]) || text[pos] == '-') break;

            // Parse known keywords
            var token = ReadToken(text, ref pos);

            if (string.Equals(token, "footsteps", StringComparison.OrdinalIgnoreCase))
            {
                SkipSpaces(text, ref pos);
                SkipToken(text, ref pos);
            }
            else if (string.Equals(token, "headoffset", StringComparison.OrdinalIgnoreCase))
            {
                for (int i = 0; i < 3; i++)
                {
                    SkipSpaces(text, ref pos);
                    SkipToken(text, ref pos);
                }
            }
            else if (string.Equals(token, "sex", StringComparison.OrdinalIgnoreCase))
            {
                SkipSpaces(text, ref pos);
                SkipToken(text, ref pos);
            }
            else if (string.Equals(token, "fixedlegs", StringComparison.OrdinalIgnoreCase))
            {
                FixedLegs = true;
            }
            else if (string.Equals(token, "fixedtorso", StringComparison.OrdinalIgnoreCase))
            {
                FixedTorso = true;
            }
        }

        // Parse animation entries
        for (int i = 0; i < (int)AnimNumber.MAX_ANIMATIONS; i++)
        {
            // Skip whitespace, newlines, comments
            while (pos < text.Length)
            {
                SkipWhitespace(text, ref pos);
                if (pos + 1 < text.Length && text[pos] == '/' && text[pos + 1] == '/')
                {
                    SkipToEndOfLine(text, ref pos);
                    continue;
                }
                break;
            }

            if (pos >= text.Length)
            {
                // Handle missing team animations
                if (i >= (int)AnimNumber.TORSO_GETFLAG && i <= (int)AnimNumber.TORSO_NEGATIVE)
                {
                    _animations[i] = _animations[(int)AnimNumber.TORSO_GESTURE];
                    continue;
                }
                break;
            }

            // firstFrame
            _animations[i].FirstFrame = ReadInt(text, ref pos);

            // Compute leg frame offset at LEGS_WALKCR
            if (i == (int)AnimNumber.LEGS_WALKCR)
            {
                skip = _animations[(int)AnimNumber.LEGS_WALKCR].FirstFrame -
                       _animations[(int)AnimNumber.TORSO_GESTURE].FirstFrame;
            }
            if (i >= (int)AnimNumber.LEGS_WALKCR && i < (int)AnimNumber.TORSO_GETFLAG)
            {
                _animations[i].FirstFrame -= skip;
            }

            // numFrames
            SkipSpaces(text, ref pos);
            int numFrames = ReadInt(text, ref pos);
            _animations[i].Reversed = 0;
            _animations[i].Flipflop = 0;
            if (numFrames < 0)
            {
                numFrames = -numFrames;
                _animations[i].Reversed = 1;
            }
            _animations[i].NumFrames = numFrames;

            // loopFrames
            SkipSpaces(text, ref pos);
            _animations[i].LoopFrames = ReadInt(text, ref pos);

            // fps
            SkipSpaces(text, ref pos);
            float fps = ReadFloat(text, ref pos);
            if (fps == 0) fps = 1;
            _animations[i].FrameLerp = (int)(1000.0f / fps);

            // Skip rest of line
            SkipToEndOfLine(text, ref pos);
        }

        // Extra animations
        _animations[(int)AnimNumber.LEGS_BACKCR] = _animations[(int)AnimNumber.LEGS_WALKCR];
        _animations[(int)AnimNumber.LEGS_BACKCR].Reversed = 1;
        _animations[(int)AnimNumber.LEGS_BACKWALK] = _animations[(int)AnimNumber.LEGS_WALK];
        _animations[(int)AnimNumber.LEGS_BACKWALK].Reversed = 1;

        _animations[(int)AnimNumber.FLAG_RUN].FirstFrame = 0;
        _animations[(int)AnimNumber.FLAG_RUN].NumFrames = 16;
        _animations[(int)AnimNumber.FLAG_RUN].LoopFrames = 16;
        _animations[(int)AnimNumber.FLAG_RUN].FrameLerp = (int)(1000.0f / 15.0f);
        _animations[(int)AnimNumber.FLAG_RUN].Reversed = 0;

        _animations[(int)AnimNumber.FLAG_STAND].FirstFrame = 16;
        _animations[(int)AnimNumber.FLAG_STAND].NumFrames = 5;
        _animations[(int)AnimNumber.FLAG_STAND].LoopFrames = 0;
        _animations[(int)AnimNumber.FLAG_STAND].FrameLerp = (int)(1000.0f / 20.0f);
        _animations[(int)AnimNumber.FLAG_STAND].Reversed = 0;

        _animations[(int)AnimNumber.FLAG_STAND2RUN].FirstFrame = 16;
        _animations[(int)AnimNumber.FLAG_STAND2RUN].NumFrames = 5;
        _animations[(int)AnimNumber.FLAG_STAND2RUN].LoopFrames = 1;
        _animations[(int)AnimNumber.FLAG_STAND2RUN].FrameLerp = (int)(1000.0f / 15.0f);
        _animations[(int)AnimNumber.FLAG_STAND2RUN].Reversed = 1;
    }

    private static void SkipWhitespace(string text, ref int pos)
    {
        while (pos < text.Length && (text[pos] == ' ' || text[pos] == '\t' || text[pos] == '\r' || text[pos] == '\n'))
            pos++;
    }

    private static void SkipSpaces(string text, ref int pos)
    {
        while (pos < text.Length && (text[pos] == ' ' || text[pos] == '\t'))
            pos++;
    }

    private static void SkipToEndOfLine(string text, ref int pos)
    {
        while (pos < text.Length && text[pos] != '\n')
            pos++;
    }

    private static void SkipToken(string text, ref int pos)
    {
        while (pos < text.Length && text[pos] != ' ' && text[pos] != '\t' && text[pos] != '\r' && text[pos] != '\n')
            pos++;
    }

    private static string ReadToken(string text, ref int pos)
    {
        int start = pos;
        while (pos < text.Length && text[pos] != ' ' && text[pos] != '\t' && text[pos] != '\r' && text[pos] != '\n')
            pos++;
        return text[start..pos];
    }

    private static int ReadInt(string text, ref int pos)
    {
        int start = pos;
        if (pos < text.Length && (text[pos] == '-' || text[pos] == '+')) pos++;
        while (pos < text.Length && char.IsDigit(text[pos])) pos++;
        if (start == pos) return 0;
        return int.TryParse(text[start..pos], out int val) ? val : 0;
    }

    private static float ReadFloat(string text, ref int pos)
    {
        int start = pos;
        if (pos < text.Length && (text[pos] == '-' || text[pos] == '+')) pos++;
        while (pos < text.Length && (char.IsDigit(text[pos]) || text[pos] == '.')) pos++;
        if (start == pos) return 0;
        return float.TryParse(text[start..pos], System.Globalization.NumberStyles.Float,
            System.Globalization.CultureInfo.InvariantCulture, out float val) ? val : 0;
    }
}
