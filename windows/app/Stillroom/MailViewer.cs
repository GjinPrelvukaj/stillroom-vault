using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Stillroom.Native;
using Stillroom.Platform;
using Windows.Storage.Streams;

namespace Stillroom;

/// <summary>An email as Mail shows it (the Mac's `EmailView`): who, when, the subject, its attachments, then the
/// message. There's no web view: the engine reads the sender's HTML into blocks of words and pictures
/// (`mail_page.rs`), drawn here with Windows' own text controls, so nothing in a message can load anything. Pictures
/// come only from inside the email; remote ones (and tracking pixels) aren't shown, and links don't open: clicking
/// one says where it goes. The message keeps the app's colours, not the sender's, so it reads in light and dark.</summary>
internal sealed class MailViewer : UserControl
{
    /// <summary>The widest a picture is drawn.</summary>
    private const double Widest = 620;

    private readonly byte[] data;
    private readonly Action<string, byte[]> keep;
    private readonly Func<string, byte[], Task> save;
    private readonly Grid layout = new();
    private readonly TextBlock linkLine = new() { FontSize = 12, Opacity = 0.7, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center, IsTextSelectionEnabled = true };
    private readonly Grid linkBar = new() { ColumnSpacing = 8, Padding = new Thickness(16, 8, 12, 8), Visibility = Visibility.Collapsed };
    private string? shownLink;

    /// <summary>The message is on the screen (or, not being an email, its bytes are).</summary>
    public event Action? Shown;

    /// <summary>`data`: the email's bytes, copied in (the caller wipes its own copy), wiped here when the card goes.
    /// `keep` seals an attachment into the vault beside the email; `save` saves one out, unencrypted.</summary>
    public MailViewer(byte[] data, Action<string, byte[]> keep, Func<string, byte[], Task> save)
    {
        this.data = data.ToArray();
        this.keep = keep;
        this.save = save;
        Content = layout;
        layout.Children.Add(new ProgressRing { IsActive = true, Width = 24, Height = 24 });
        Unloaded += (_, _) => CryptographicOperations.ZeroMemory(this.data);
        _ = Show();
    }

    private async Task Show()
    {
        var bytes = data;
        JsonElement? email;
        try { email = await Task.Run(() => Engine.ReadEmail(bytes)); }
        catch (StillroomException) { email = null; }
        layout.Children.Clear();
        if (email is not { } read)
        {
            // Not an email after all: its bytes as text, as the Mac shows it.
            layout.Children.Add(new ScrollViewer
            {
                Content = new TextBlock
                {
                    Text = Encoding.UTF8.GetString(data),
                    FontFamily = new FontFamily("Consolas"),
                    FontSize = 12,
                    Opacity = 0.85,
                    IsTextSelectionEnabled = true,
                    TextWrapping = TextWrapping.Wrap,
                    Margin = new Thickness(16),
                },
            });
            Shown?.Invoke();
            return;
        }
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.Children.Add(Header(read));
        var line = new Border { Height = 1, Background = Theme.Brush("HairlineBrush") };
        Grid.SetRow(line, 1);
        layout.Children.Add(line);
        var message = new ScrollViewer { Content = Message(read.GetProperty("document")), HorizontalScrollMode = ScrollMode.Disabled };
        Grid.SetRow(message, 2);
        layout.Children.Add(message);

        linkBar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        linkBar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        linkBar.Background = Theme.Brush("PanelBrush");
        linkBar.Children.Add(linkLine);
        var copy = new Button { Content = "Copy Address" };
        copy.Click += (_, _) =>
        {
            // The address may be a private one (a sign-in or reset link): copied as a secret is.
            if (shownLink is not null) SecretClipboard.Copy(shownLink, App.Window?.Handle ?? IntPtr.Zero);
        };
        Grid.SetColumn(copy, 1);
        linkBar.Children.Add(copy);
        Grid.SetRow(linkBar, 3);
        layout.Children.Add(linkBar);
        Shown?.Invoke();
    }

    // MARK: Who, when, attachments

    private UIElement Header(JsonElement email)
    {
        var header = new StackPanel { Spacing = 5, Padding = new Thickness(16, 14, 16, 14) };
        var subject = email.GetProperty("subject").GetString() ?? "";
        header.Children.Add(new TextBlock
        {
            Text = subject.Length == 0 ? "No subject" : subject,
            FontSize = 15,
            FontWeight = FontWeights.SemiBold,
            MaxLines = 2,
            TextWrapping = TextWrapping.Wrap,
            TextTrimming = TextTrimming.CharacterEllipsis,
            IsTextSelectionEnabled = true,
            Margin = new Thickness(0, 0, 0, 3),
        });
        foreach (var (label, key) in new[] { ("From", "from"), ("To", "to"), ("Cc", "cc") })
            Line(header, label, email.GetProperty(key).GetString() ?? "");
        if (email.GetProperty("date") is { ValueKind: JsonValueKind.Number } seconds)
            Line(header, "Date", Since2001.AddSeconds(seconds.GetDouble()).ToLocalTime().ToString("d MMMM yyyy, HH:mm"));

        var attachments = email.GetProperty("attachments").EnumerateArray().ToList();
        if (attachments.Count > 0)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            for (var i = 0; i < attachments.Count; i++)
            {
                var index = i;
                var name = attachments[i].GetProperty("name").GetString() ?? "Attachment";
                var size = attachments[i].GetProperty("size").GetInt64();
                var label = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
                label.Children.Add(new FontIcon { Glyph = "", FontSize = 12 });
                label.Children.Add(new TextBlock { Text = $"{name} · {Shell.Size(size)}", FontSize = 12, MaxWidth = 260, TextTrimming = TextTrimming.CharacterEllipsis });
                var menu = new MenuFlyout();
                var add = new MenuFlyoutItem { Text = "Add to Stillroom" };
                add.Click += (_, _) => { if (Attachment(index) is { } bytes) keep(name, bytes); };
                var saveCopy = new MenuFlyoutItem { Text = "Save a Copy…" };
                saveCopy.Click += async (_, _) => { if (Attachment(index) is { } bytes) await save(name, bytes); };
                menu.Items.Add(add);
                menu.Items.Add(saveCopy);
                row.Children.Add(new DropDownButton { Content = label, Flyout = menu, Padding = new Thickness(10, 4, 8, 4) });
            }
            header.Children.Add(new ScrollViewer
            {
                Content = row,
                HorizontalScrollMode = ScrollMode.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden,
                VerticalScrollMode = ScrollMode.Disabled,
                Margin = new Thickness(0, 6, 0, 0),
            });
        }
        return header;
    }

    private static readonly DateTimeOffset Since2001 = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    private static void Line(StackPanel header, string label, string value)
    {
        if (value.Length == 0) return;
        var row = new Grid { ColumnSpacing = 8 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.Children.Add(new TextBlock { Text = label, FontSize = 12, Opacity = 0.45 });
        var text = new TextBlock { Text = value, FontSize = 12, Opacity = 0.8, MaxLines = 2, TextWrapping = TextWrapping.Wrap, TextTrimming = TextTrimming.CharacterEllipsis, IsTextSelectionEnabled = true };
        Grid.SetColumn(text, 1);
        row.Children.Add(text);
        header.Children.Add(row);
    }

    /// <summary>An attachment's bytes, read from the email again; null if the card has gone.</summary>
    private byte[]? Attachment(int index)
    {
        try { return Engine.EmailAttachment(data, index); }
        catch (StillroomException) { return null; }
    }

    // MARK: The message

    /// <summary>The engine's blocks, drawn: runs of blocks at one quote depth share a text control (so they select
    /// together), a quote has a bar down its side, a rule is a hairline.</summary>
    private UIElement Message(JsonElement document)
    {
        var page = new StackPanel { Padding = new Thickness(16, 14, 16, 18) };
        var pictures = document.GetProperty("pictures").EnumerateArray()
            .Select(p => (Kind: p.GetProperty("kind").GetString()!, Data: p.GetProperty("data").GetString()!)).ToList();
        RichTextBlock? text = null;
        var depth = -1;
        foreach (var block in document.GetProperty("blocks").EnumerateArray())
        {
            if (block.TryGetProperty("rule", out _))
            {
                page.Children.Add(new Border { Height = 1, Background = Theme.Brush("DividerBrush"), Margin = new Thickness(0, 6, 0, 14) });
                text = null;
                continue;
            }
            var quoted = Number(block, "quoted");
            if (text is null || quoted != depth)
            {
                text = new RichTextBlock { IsTextSelectionEnabled = true, TextWrapping = TextWrapping.Wrap, FontSize = 14, LineHeight = 21 };
                depth = quoted;
                page.Children.Add(quoted == 0 ? text : new Border
                {
                    Child = text,
                    BorderBrush = Theme.Brush("DotBrush"),
                    BorderThickness = new Thickness(3, 0, 0, 0),
                    Padding = new Thickness(12, 0, 0, 0),
                    Margin = new Thickness((quoted - 1) * 15, 0, 0, 8),
                    Opacity = 0.8,
                });
            }
            text.Blocks.Add(Paragraph(block, pictures));
        }
        if (document.TryGetProperty("cut", out _))
            page.Children.Add(new TextBlock { Text = "The rest is too long to show here. Save a copy to read it all.", FontSize = 12, Opacity = 0.45, Margin = new Thickness(0, 8, 0, 0) });
        return page;
    }

    private Paragraph Paragraph(JsonElement block, List<(string Kind, string Data)> pictures)
    {
        var indent = Number(block, "indent") * 20.0;
        var paragraph = new Paragraph { Margin = new Thickness(indent, 0, 0, 10) };
        var pre = block.TryGetProperty("pre", out _);
        if (block.TryGetProperty("heading", out var level))
        {
            paragraph.FontSize = level.GetInt32() switch { 1 => 22, 2 => 18, 3 => 16, _ => 14 };
            paragraph.FontWeight = FontWeights.SemiBold;
            paragraph.Margin = new Thickness(indent, 4, 0, 10);
        }
        if (block.TryGetProperty("marker", out var marker))
        {
            // The marker hangs to the left of the item's lines.
            paragraph.Margin = new Thickness(indent + 18, 0, 0, 4);
            paragraph.TextIndent = -18;
            paragraph.Inlines.Add(new Run { Text = marker.GetString() + " ", Foreground = Theme.Brush("QuietBrush") });
        }
        foreach (var run in block.GetProperty("runs").EnumerateArray())
        {
            if (run.TryGetProperty("picture", out var index))
            {
                var at = index.GetInt32();
                if (at >= 0 && at < pictures.Count) paragraph.Inlines.Add(new InlineUIContainer { Child = Picture(pictures[at].Data, run) });
                continue;
            }
            var words = Words(run.GetProperty("text").GetString() ?? "", pre || run.TryGetProperty("mono", out _));
            if (Flag(run, "bold")) Wrap(ref words, new Bold());
            if (Flag(run, "italic")) Wrap(ref words, new Italic());
            if (Flag(run, "underline") && !run.TryGetProperty("link", out _)) Wrap(ref words, new Underline());
            if (Flag(run, "strike")) words.TextDecorations |= Windows.UI.Text.TextDecorations.Strikethrough;
            if (run.TryGetProperty("link", out var link))
            {
                // A link that goes nowhere: no NavigateUri, ever. Clicking it says where it points.
                var address = link.GetString() ?? "";
                var hyperlink = new Hyperlink();
                hyperlink.Inlines.Add(words);
                hyperlink.Click += (_, _) => ShowLink(address);
                paragraph.Inlines.Add(hyperlink);
            }
            else
            {
                paragraph.Inlines.Add(words);
            }
        }
        return paragraph;
    }

    /// <summary>Words, with their line breaks as breaks.</summary>
    private static Span Words(string text, bool mono)
    {
        var span = new Span();
        if (mono)
        {
            span.FontFamily = new FontFamily("Consolas");
            span.FontSize = 13;
        }
        var lines = text.Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            if (i > 0) span.Inlines.Add(new LineBreak());
            if (lines[i].Length > 0) span.Inlines.Add(new Run { Text = lines[i] });
        }
        return span;
    }

    private static void Wrap(ref Span words, Span outer)
    {
        outer.Inlines.Add(words);
        words = outer;
    }

    private static bool Flag(JsonElement run, string name) => run.TryGetProperty(name, out var value) && value.GetBoolean();

    private static int Number(JsonElement block, string name) => block.TryGetProperty(name, out var value) ? value.GetInt32() : 0;

    /// <summary>A picture from inside the email, decoded from memory: never from an address.</summary>
    private static Image Picture(string base64, JsonElement run)
    {
        var image = new Image { Stretch = Stretch.Uniform, MaxWidth = Widest };
        double? width = run.TryGetProperty("width", out var w) ? w.GetInt32() : null;
        double? height = run.TryGetProperty("height", out var h) ? h.GetInt32() : null;
        if (width is { } shownWidth)
        {
            var scale = Math.Min(1, Widest / shownWidth);
            image.Width = shownWidth * scale;
            if (height is { } shownHeight) image.Height = shownHeight * scale;
        }
        else if (height is { } shownHeight)
        {
            image.Height = shownHeight;
        }
        var bitmap = new BitmapImage();
        image.Source = bitmap;
        byte[] bytes;
        try { bytes = Convert.FromBase64String(base64); }
        catch (FormatException) { return image; }
        var stream = new InMemoryRandomAccessStream();
        var writer = new DataWriter(stream);
        writer.WriteBytes(bytes);
        _ = writer.StoreAsync().AsTask().ContinueWith(_ =>
        {
            writer.DetachStream();
            stream.Seek(0);
            image.DispatcherQueue.TryEnqueue(async () =>
            {
                try { await bitmap.SetSourceAsync(stream); }
                catch (Exception) { /* Not a picture Windows can draw: left empty. */ }
                finally { stream.Dispose(); }
            });
        }, TaskScheduler.Default);
        return image;
    }

    private void ShowLink(string address)
    {
        shownLink = address;
        linkLine.Text = $"Links don't open from Stillroom. This one goes to {address}";
        linkBar.Visibility = Visibility.Visible;
    }
}
