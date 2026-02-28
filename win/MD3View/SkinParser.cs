using System.Text;

namespace MD3View;

public static class SkinParser
{
    public static Dictionary<string, string> Parse(byte[]? data)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (data == null) return result;

        string? text;
        try
        {
            text = Encoding.UTF8.GetString(data);
        }
        catch
        {
            text = Encoding.Latin1.GetString(data);
        }

        if (text == null) return result;

        var lines = text.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (trimmed.Length == 0) continue;

            var commaIdx = trimmed.IndexOf(',');
            if (commaIdx < 0) continue;

            var surfName = trimmed[..commaIdx].Trim();
            var texPath = trimmed[(commaIdx + 1)..].Trim();

            // Skip tag_ entries
            if (surfName.StartsWith("tag_", StringComparison.OrdinalIgnoreCase)) continue;
            if (surfName.Length == 0 || texPath.Length == 0) continue;

            result[surfName.ToLowerInvariant()] = texPath;
        }

        return result;
    }
}
