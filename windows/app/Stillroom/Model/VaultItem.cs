using System.Text.Json;
using Stillroom.Native;
using Stillroom.Platform;

namespace Stillroom.Model;

/// <summary>One thing in the vault as the window shows it (the Mac's `VaultFile`): a file, a note or a secret, read
/// from the engine's list. No key ever reaches here.</summary>
internal sealed class VaultItem
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    /// <summary>Its kind as the Mac names kinds (public.jpeg, com.adobe.pdf).</summary>
    public required string Uti { get; init; }
    public long Size { get; init; }
    public DateTimeOffset AddedAt { get; init; }
    /// <summary>The folder it sits in ("Taxes/2025"); null at the top.</summary>
    public string? Folder { get; init; }
    public DateTimeOffset? ModifiedAt { get; init; }
    public DateTimeOffset? ContentModified { get; init; }
    public IReadOnlyList<string> Tags { get; init; } = [];
    /// <summary>"note" or "secret"; null for a file.</summary>
    public string? Entry { get; init; }
    /// <summary>Earlier contents, oldest first.</summary>
    public IReadOnlyList<VersionInfo> Versions { get; init; } = [];
    public Look Look { get; init; }

    public bool IsFile => Entry is null;
    public bool IsNote => Entry == "note";
    public bool IsSecret => Entry == "secret";
    public DateTimeOffset ChangedAt => ModifiedAt ?? AddedAt;
    /// <summary>Last changed in the vault, else last changed before it came in, else when it came in.</summary>
    public DateTimeOffset ShownDate => ModifiedAt ?? ContentModified ?? AddedAt;

    public Shelf Kind => Entry switch
    {
        "note" => Shelf.Notes,
        "secret" => Shelf.Secrets,
        _ => Look switch
        {
            Look.Picture => Shelf.Images,
            Look.Audio or Look.Video => Shelf.Media,
            Look.Pdf or Look.Text or Look.Document => Shelf.Documents,
            _ => Shelf.Other,
        },
    };

    /// <summary>"PDF Document", "JPG File": Windows' own words for the kind, as the Mac uses the Finder's.</summary>
    public string KindName => Entry switch
    {
        "note" => "Note",
        "secret" => "Secret",
        _ => Shell.TypeName(Name),
    };

    /// <summary>Its symbol (Segoe Fluent Icons), as the Mac's `VaultFile.symbol`.</summary>
    public string Glyph => Entry switch
    {
        "note" => Glyphs.Note,
        "secret" => Glyphs.Secret,
        _ => Look switch
        {
            Look.Picture => Glyphs.Picture,
            Look.Audio => Glyphs.Audio,
            Look.Video => Glyphs.Video,
            Look.Pdf => Glyphs.Pdf,
            Look.Archive => Glyphs.Archive,
            Look.Text => Glyphs.Text,
            _ => Glyphs.File,
        },
    };

    /// <summary>Whether it's in `folder` or anywhere below it.</summary>
    public bool IsInside(string folder) => Folder is { } mine && (mine == folder || mine.StartsWith(folder + "/", StringComparison.Ordinal));

    /// <summary>The engine's dates are seconds since 2001, as the Mac's.</summary>
    private static readonly DateTimeOffset Reference = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    private static DateTimeOffset? Date(JsonElement item, string name) =>
        item.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number ? Reference.AddSeconds(value.GetDouble()) : null;

    private static string? Text(JsonElement item, string name) =>
        item.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    public static VaultItem From(JsonElement item)
    {
        var uti = Text(item, "uti") ?? "public.data";
        return new VaultItem
        {
            Id = Text(item, "id")!,
            Name = Text(item, "name") ?? "",
            Uti = uti,
            Size = item.TryGetProperty("size", out var size) ? size.GetInt64() : 0,
            AddedAt = Date(item, "addedAt") ?? Reference,
            Folder = Text(item, "folder"),
            ModifiedAt = Date(item, "modifiedAt"),
            ContentModified = Date(item, "contentModified"),
            Tags = item.TryGetProperty("tags", out var tags) && tags.ValueKind == JsonValueKind.Array
                ? tags.EnumerateArray().Select(t => t.GetString() ?? "").Where(t => t.Length > 0).ToList()
                : [],
            Entry = Text(item, "entry"),
            Versions = item.TryGetProperty("versions", out var versions) && versions.ValueKind == JsonValueKind.Array
                ? versions.EnumerateArray().Select(v => new VersionInfo(Text(v, "id")!, Date(v, "date") ?? Reference, v.TryGetProperty("size", out var s) ? s.GetInt64() : 0)).ToList()
                : [],
            Look = Engine.LookOf(uti),
        };
    }
}

/// <summary>An earlier version of an item: when it was replaced, and its size.</summary>
internal sealed record VersionInfo(string Id, DateTimeOffset Date, long Size);

/// <summary>What the sidebar shows: everything, notes, secrets, or one kind of file (the Mac's `Shelf`).</summary>
internal enum Shelf { All, Notes, Secrets, Images, Documents, Media, Other }

internal static class Shelves
{
    public static readonly Shelf[] Library = [Shelf.All, Shelf.Notes, Shelf.Secrets];
    public static readonly Shelf[] Kinds = [Shelf.Images, Shelf.Documents, Shelf.Media, Shelf.Other];

    /// <summary>All Files holds files only; notes and secrets have their own.</summary>
    public static bool Holds(this Shelf shelf, VaultItem item) => shelf == Shelf.All ? item.IsFile : item.Kind == shelf;

    public static string Title(this Shelf shelf) => shelf switch
    {
        Shelf.All => "All Files",
        Shelf.Notes => "Notes",
        Shelf.Secrets => "Secrets",
        Shelf.Images => "Images",
        Shelf.Documents => "Documents",
        Shelf.Media => "Audio & Video",
        _ => "Other",
    };

    public static string Glyph(this Shelf shelf) => shelf switch
    {
        Shelf.All => Glyphs.Library,
        Shelf.Notes => Glyphs.Note,
        Shelf.Secrets => Glyphs.Secret,
        Shelf.Images => Glyphs.Picture,
        Shelf.Documents => Glyphs.Text,
        Shelf.Media => Glyphs.Video,
        _ => Glyphs.Box,
    };
}

/// <summary>Folder paths as people see them. "/" divides a path, so a "/" typed in a name is kept as a look-alike
/// (U+2215) and drawn as a real one again here, as on the Mac.</summary>
internal static class FolderPaths
{
    public static string Shown(this string name) => name.Replace('∕', '/');
    public static string ShownPath(this string path) => string.Join(" › ", path.Split('/').Select(Shown));
    public static string ShownLast(this string path) => path.Split('/')[^1].Shown();
    public static string? Parent(this string path) => path.LastIndexOf('/') is var at and > 0 ? path[..at] : null;
}

/// <summary>Segoe Fluent Icons code points standing in for the Mac's SF Symbols.</summary>
internal static class Glyphs
{
    public const string Library = "";
    public const string Note = "";
    public const string Secret = "";
    public const string Picture = "";
    public const string Audio = "";
    public const string Video = "";
    public const string Pdf = "";
    public const string Archive = "";
    public const string Text = "";
    public const string File = "";
    public const string Box = "";
    public const string Folder = "";
    public const string Settings = "";
    public const string Shield = "";
    public const string Lock = "";
    public const string Add = "";
    public const string NewFolder = "";
    public const string Search = "";
}
