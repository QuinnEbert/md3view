using System.IO.Compression;

namespace MD3View;

public class PK3Archive : IDisposable
{
    private readonly FileStream _fileStream;
    private readonly ZipArchive _zip;
    private readonly List<string> _fileList = new();
    private readonly Dictionary<string, ZipArchiveEntry> _entryMap = new(StringComparer.OrdinalIgnoreCase);

    public string ArchivePath { get; }

    public PK3Archive(string path)
    {
        ArchivePath = path;
        _fileStream = File.OpenRead(path);
        _zip = new ZipArchive(_fileStream, ZipArchiveMode.Read);

        foreach (var entry in _zip.Entries)
        {
            _fileList.Add(entry.FullName);
            _entryMap[entry.FullName] = entry;
        }
    }

    public List<string> AllFiles => _fileList;

    public List<string> PlayerModelPaths()
    {
        var playerDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var file in _fileList)
        {
            var lower = file.ToLowerInvariant();
            if (lower.EndsWith("lower.md3") || lower.EndsWith("upper.md3") || lower.EndsWith("head.md3"))
            {
                var dir = Path.GetDirectoryName(file)?.Replace('\\', '/') ?? "";
                playerDirs.Add(dir);
            }
        }

        var valid = new List<string>();
        foreach (var dir in playerDirs)
        {
            var lowerPath = dir + "/lower.md3";
            var upperPath = dir + "/upper.md3";
            var headPath = dir + "/head.md3";

            bool hasLower = false, hasUpper = false, hasHead = false;
            foreach (var file in _fileList)
            {
                if (string.Equals(file, lowerPath, StringComparison.OrdinalIgnoreCase)) hasLower = true;
                if (string.Equals(file, upperPath, StringComparison.OrdinalIgnoreCase)) hasUpper = true;
                if (string.Equals(file, headPath, StringComparison.OrdinalIgnoreCase)) hasHead = true;
            }

            if (hasLower && hasUpper && hasHead)
                valid.Add(dir);
        }

        valid.Sort(StringComparer.Ordinal);
        return valid;
    }

    public byte[]? ReadFile(string filePath)
    {
        if (_entryMap.TryGetValue(filePath, out var entry))
        {
            using var stream = entry.Open();
            using var ms = new MemoryStream();
            stream.CopyTo(ms);
            return ms.ToArray();
        }
        return null;
    }

    public void Dispose()
    {
        _zip.Dispose();
        _fileStream.Dispose();
    }
}
