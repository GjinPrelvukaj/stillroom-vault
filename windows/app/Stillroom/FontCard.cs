using System.Buffers.Binary;
using System.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Stillroom.Platform;

namespace Stillroom;

/// <summary>A font, shown by Stillroom itself (where the Mac's Quick Look shows one): its name, the alphabet and the
/// digits, then a sample at growing sizes, each line shrinking to fit the card as it narrows. Windows' own font
/// previewer draws its lines at fixed sizes and cuts them at the edge. The font is read by Windows' text engine in this
/// process, as pictures and PDFs are, from a copy put out as the fallback preview's are (`EditDesk.PutOutForLook`),
/// wiped as the card closes. TrueType and OpenType (.ttf, .otf, .ttc); older bitmap fonts go to Windows' previewer.</summary>
internal sealed class FontCard : UserControl
{
    private static readonly int[] Sizes = [12, 18, 24, 36, 48, 60, 72];
    private const string Sample = "The quick brown fox jumps over the lazy dog. 1234567890";

    private readonly Func<string> stage;
    private readonly Func<UIElement> failed;
    private string? file;
    private bool closed;

    /// <summary>The sample is on the screen.</summary>
    public event Action? Shown;

    /// <summary>The font couldn't be read, and `failed` shows instead.</summary>
    public event Action? Failed;

    public FontCard(Func<string> stage, Func<UIElement> failed)
    {
        this.stage = stage;
        this.failed = failed;
        Content = new ProgressRing { IsActive = true, Width = 24, Height = 24 };
        Loaded += (_, _) => _ = Show();
        Unloaded += (_, _) =>
        {
            closed = true;
            if (file is not null) EditDesk.TakeBack(file);
        };
    }

    /// <summary>Whether a file of this name is a font this card shows.</summary>
    public static bool Shows(string name) => Path.GetExtension(name).ToLowerInvariant() is ".ttf" or ".otf" or ".ttc";

    private async Task Show()
    {
        if (file is not null) return;
        string? family;
        try
        {
            file = await Task.Run(stage);
            family = await Task.Run(() => FamilyName(File.ReadAllBytes(file)));
        }
        catch (Exception)
        {
            family = null;
        }
        if (closed)
        {
            if (file is not null) EditDesk.TakeBack(file);
            return;
        }
        if (family is null || file is null)
        {
            Content = failed();
            Failed?.Invoke();
            return;
        }
        var font = new FontFamily($"{file}#{family}");
        var page = new StackPanel { Spacing = 6, Padding = new Thickness(20, 16, 20, 20) };
        page.Children.Add(new TextBlock { Text = family, FontSize = 12, Opacity = 0.55, IsTextSelectionEnabled = true });
        page.Children.Add(Fitted(new TextBlock { Text = "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ", FontFamily = font, FontSize = 22 }));
        page.Children.Add(Fitted(new TextBlock { Text = "1234567890.:,; ' \" (!?) +-*/= &@#%", FontFamily = font, FontSize = 22 }));
        page.Children.Add(new Border { Height = 1, Background = Theme.Brush("HairlineBrush"), Margin = new Thickness(0, 8, 0, 8) });
        foreach (var size in Sizes)
        {
            var row = new Grid { ColumnSpacing = 12 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.Children.Add(new TextBlock { Text = size.ToString(), FontSize = 11, Opacity = 0.45, VerticalAlignment = VerticalAlignment.Center });
            var line = Fitted(new TextBlock { Text = Sample, FontFamily = font, FontSize = size });
            Grid.SetColumn(line, 1);
            row.Children.Add(line);
            page.Children.Add(row);
        }
        Content = new ScrollViewer { Content = page, HorizontalScrollMode = ScrollMode.Disabled };
        Shown?.Invoke();
    }

    /// <summary>A line at its own size while it fits the card's width, shrunk to fit when it doesn't.</summary>
    private static Viewbox Fitted(TextBlock text)
    {
        text.TextWrapping = TextWrapping.NoWrap;
        return new Viewbox { Child = text, Stretch = Stretch.Uniform, StretchDirection = StretchDirection.DownOnly, HorizontalAlignment = HorizontalAlignment.Left };
    }

    /// <summary>The font's family name from its `name` table (the first font of a collection), as Windows names it;
    /// null when the bytes aren't a font this reads.</summary>
    public static string? FamilyName(ReadOnlySpan<byte> data)
    {
        if (data.Length < 12) return null;
        var start = 0;
        if (data[..4].SequenceEqual("ttcf"u8))
        {
            if (data.Length < 16) return null;
            start = checked((int)BinaryPrimitives.ReadUInt32BigEndian(data[12..]));
        }
        if (start < 0 || start + 12 > data.Length) return null;
        int tables = BinaryPrimitives.ReadUInt16BigEndian(data[(start + 4)..]);
        for (var i = 0; i < tables; i++)
        {
            var record = start + 12 + i * 16;
            if (record + 16 > data.Length) return null;
            if (!data.Slice(record, 4).SequenceEqual("name"u8)) continue;
            var at = BinaryPrimitives.ReadUInt32BigEndian(data[(record + 8)..]);
            return at < (uint)data.Length ? Names(data[(int)at..]) : null;
        }
        return null;
    }

    /// <summary>The family (name 1) from a `name` table: Windows' English one first, then any Windows one, then a
    /// Mac Roman one.</summary>
    private static string? Names(ReadOnlySpan<byte> table)
    {
        if (table.Length < 6) return null;
        int count = BinaryPrimitives.ReadUInt16BigEndian(table[2..]), strings = BinaryPrimitives.ReadUInt16BigEndian(table[4..]);
        string? windows = null, mac = null;
        for (var i = 0; i < count; i++)
        {
            var record = 6 + i * 12;
            if (record + 12 > table.Length) break;
            int platform = BinaryPrimitives.ReadUInt16BigEndian(table[record..]);
            int language = BinaryPrimitives.ReadUInt16BigEndian(table[(record + 4)..]);
            int id = BinaryPrimitives.ReadUInt16BigEndian(table[(record + 6)..]);
            int length = BinaryPrimitives.ReadUInt16BigEndian(table[(record + 8)..]);
            int offset = strings + BinaryPrimitives.ReadUInt16BigEndian(table[(record + 10)..]);
            if (id != 1 || offset + length > table.Length || length == 0) continue;
            var bytes = table.Slice(offset, length);
            if (platform == 3)
            {
                var name = Encoding.BigEndianUnicode.GetString(bytes);
                if (language == 0x409) return Clean(name);
                windows ??= name;
            }
            else if (platform == 1)
            {
                mac ??= Encoding.Latin1.GetString(bytes);
            }
        }
        return Clean(windows ?? mac);
    }

    /// <summary>A name fit to go after "#" in a font address: no control characters, nothing that ends it early.</summary>
    private static string? Clean(string? name)
    {
        var kept = name is null ? null : new string(name.Where(c => !char.IsControl(c) && c != '#').ToArray()).Trim();
        return string.IsNullOrEmpty(kept) ? null : kept;
    }
}
