using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using Microsoft.VisualBasic.FileIO;

namespace Stillroom.Platform;

/// <summary>What Explorer itself says and does: a kind's name, a size in its words, the Recycle Bin.</summary>
internal static unsafe partial class Shell
{
    private static readonly ConcurrentDictionary<string, string> typeNames = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Windows' name for a file's kind from its extension ("PDF Document", "JPG File"), without touching any
    /// file: there is none outside the vault.</summary>
    public static string TypeName(string name)
    {
        var extension = Path.GetExtension(name);
        if (extension.Length < 2) return "File";
        return typeNames.GetOrAdd(extension, e =>
        {
            var info = new SHFILEINFOW();
            var found = SHGetFileInfoW(e, FILE_ATTRIBUTE_NORMAL, &info, (uint)sizeof(SHFILEINFOW), SHGFI_TYPENAME | SHGFI_USEFILEATTRIBUTES);
            var text = found != 0 ? new string(info.szTypeName) : "";
            return text.Length > 0 ? text : $"{e.TrimStart('.').ToUpperInvariant()} File";
        });
    }

    /// <summary>A size as Explorer writes it ("1.21 MB").</summary>
    public static string Size(long bytes)
    {
        var buffer = stackalloc char[32];
        return StrFormatByteSizeEx((ulong)Math.Max(0, bytes), SFBS_FLAGS_ROUND_TO_NEAREST_DISPLAYED_DIGIT, buffer, 32) == 0
            ? new string(buffer)
            : $"{bytes} bytes";
    }

    /// <summary>Into the Recycle Bin, which can be emptied later (the Mac's Move to Trash).</summary>
    public static void Recycle(string path)
    {
        if (Directory.Exists(path)) FileSystem.DeleteDirectory(path, UIOption.OnlyErrorDialogs, RecycleOption.SendToRecycleBin);
        else if (File.Exists(path)) FileSystem.DeleteFile(path, UIOption.OnlyErrorDialogs, RecycleOption.SendToRecycleBin);
    }

    private const uint FILE_ATTRIBUTE_NORMAL = 0x80;
    private const uint SHGFI_TYPENAME = 0x400;
    private const uint SHGFI_USEFILEATTRIBUTES = 0x10;
    private const int SFBS_FLAGS_ROUND_TO_NEAREST_DISPLAYED_DIGIT = 1;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEINFOW
    {
        public IntPtr hIcon;
        public int iIcon;
        public uint dwAttributes;
        public fixed char szDisplayName[260];
        public fixed char szTypeName[80];
    }

    [LibraryImport("shell32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial IntPtr SHGetFileInfoW(string path, uint attributes, SHFILEINFOW* info, uint size, uint flags);

    [LibraryImport("shlwapi.dll")]
    private static partial int StrFormatByteSizeEx(ulong size, int flags, char* buffer, uint length);
}
