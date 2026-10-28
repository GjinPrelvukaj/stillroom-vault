using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Stillroom.Model;

/// <summary>One row of the list: a folder inside the one open, or an item (the Mac's `FolderRow` and `FileRow`).</summary>
public sealed class Row
{
    public string Glyph { get; init; } = "";
    public string Name { get; init; } = "";
    public IReadOnlyList<TagChip> Tags { get; init; } = [];
    /// <summary>Out of folder browsing, the folder it sits in; for a search that matched inside it, the words around
    /// the match.</summary>
    public string Detail { get; init; } = "";
    public string Versions { get; init; } = "";
    public string Kind { get; init; } = "";
    public string Size { get; init; } = "";
    public string Date { get; init; } = "";
    public Brush GlyphBrush { get; init; } = new SolidColorBrush(Colors.White) { Opacity = 0.6 };
    public Visibility VersionsShown => Versions.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
    public Visibility DetailShown => Detail.Length > 0 ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>A folder row's path; null for an item.</summary>
    internal string? FolderPath { get; init; }
    internal VaultItem? Item { get; init; }
}

/// <summary>A tag as a small coloured chip.</summary>
public sealed class TagChip
{
    public string Text { get; init; } = "";
    public Brush Fill { get; init; } = new SolidColorBrush(Colors.Transparent);
    public Brush Ink { get; init; } = new SolidColorBrush(Colors.White);
}

/// <summary>A tag's colour, the same every time for the same word: Tally's palette, picked by the word, as the Mac's
/// `TagColor`.</summary>
internal static class TagColors
{
    private static readonly uint[] Palette = [0x60A5FA, 0xF472B6, 0x34D399, 0xFBBF24, 0xB08CFF, 0xFB923C, 0x22D3EE, 0xF87171];

    public static Color Of(string tag)
    {
        var hash = 0;
        foreach (var rune in tag.EnumerateRunes()) hash = (hash * 31 + rune.Value) & 0xFFFF;
        var rgb = Palette[hash % Palette.Length];
        return Color.FromArgb(0xFF, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
    }

    public static TagChip Chip(string tag)
    {
        var color = Of(tag);
        return new TagChip
        {
            Text = tag,
            Ink = new SolidColorBrush(color),
            Fill = new SolidColorBrush(Color.FromArgb(0x2E, color.R, color.G, color.B)),
        };
    }
}
