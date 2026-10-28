using System.Text.Json;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Stillroom.Native;
using Windows.Storage.Streams;

namespace Stillroom;

/// <summary>Who tried to get in (the Mac's `IntruderView`): each wrong password, recovery key or kit typed at the lock
/// screen, when, and a photo when the camera allowed one. Both vaults show the same log, and only once open.</summary>
internal sealed class IntruderPage : UserControl
{
    private readonly AppState state;
    private readonly StackPanel rows = new();
    private readonly TextBlock title = new() { FontSize = 24, FontWeight = FontWeights.SemiBold };
    private readonly Button clear = new() { Content = "Clear All…" };
    private readonly UIElement empty;
    private readonly ScrollViewer list;
    private List<Entry> entries = [];

    private sealed record Entry(string Id, DateTimeOffset Date, bool RecoveryKey, byte[]? Photo);

    public IntruderPage(AppState state, Settings settings)
    {
        this.state = state;
        var eyebrow = new TextBlock { Text = "INTRUDER LOG", FontSize = 10.5, FontWeight = FontWeights.SemiBold, CharacterSpacing = 80, Foreground = (Brush)Application.Current.Resources["QuietBrush"] };
        var heading = new Grid();
        heading.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        heading.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var words = new StackPanel { Spacing = 4 };
        words.Children.Add(eyebrow);
        words.Children.Add(title);
        heading.Children.Add(words);
        clear.VerticalAlignment = VerticalAlignment.Bottom;
        clear.Click += async (_, _) => await ClearAll();
        Grid.SetColumn(clear, 1);
        heading.Children.Add(clear);

        var note = new TextBlock { Text = "Your own typos show here too. Only your open vault can read this log.", FontSize = 12, Opacity = 0.45 };

        var nothing = new StackPanel { Spacing = 14, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 380 };
        nothing.Children.Add(new FontIcon { Glyph = "", FontSize = 34, Opacity = 0.5 });
        nothing.Children.Add(new TextBlock
        {
            Text = "Every wrong password typed at the lock screen will be listed here, with a photo when the camera is allowed.",
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = TextAlignment.Center,
            Opacity = 0.5,
        });
        empty = nothing;
        list = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
            Content = new Border { Background = (Brush)Application.Current.Resources["PanelBrush"], CornerRadius = new CornerRadius(12), Child = rows, VerticalAlignment = VerticalAlignment.Top },
        };

        var page = new Grid { RowSpacing = 12, Padding = new Thickness(0, 4, 0, 0) };
        page.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        page.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        page.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        page.Children.Add(heading);
        Grid.SetRow(note, 1);
        page.Children.Add(note);
        Grid.SetRow(nothing, 2);
        page.Children.Add(nothing);
        Grid.SetRow(list, 2);
        page.Children.Add(list);
        Content = page;

        Load();
        // Seen now: the sidebar stops marking it until there are more.
        settings.IntrudersSeen = entries.Count;
        try { settings.Save(); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    private void Load()
    {
        entries = [];
        try
        {
            foreach (var entry in state.Vault!.Intruders().EnumerateArray())
            {
                var photo = entry.TryGetProperty("photo", out var p) && p.ValueKind == JsonValueKind.String ? Convert.FromBase64String(p.GetString()!) : null;
                entries.Add(new Entry(
                    entry.GetProperty("id").GetString()!,
                    new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero).AddSeconds(entry.GetProperty("date").GetDouble()),
                    entry.GetProperty("kind").GetString() != "wrongPassword",
                    photo));
            }
        }
        catch (Exception e) when (e is StillroomException or ObjectDisposedException or NullReferenceException) { }
        Draw();
    }

    private void Draw()
    {
        title.Text = entries.Count == 0 ? "No one has tried" : $"{entries.Count} wrong {(entries.Count == 1 ? "try" : "tries")}";
        clear.Visibility = entries.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        empty.Visibility = entries.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        list.Visibility = entries.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        rows.Children.Clear();
        foreach (var entry in entries)
        {
            if (rows.Children.Count > 0) rows.Children.Add(new Border { Height = 1, Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x0D, 0xFF, 0xFF, 0xFF)) });
            rows.Children.Add(Row(entry));
        }
    }

    private Grid Row(Entry entry)
    {
        var row = new Grid { Padding = new Thickness(14, 8, 8, 8), ColumnSpacing = 16 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(64) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        FrameworkElement picture;
        if (entry.Photo is { } photo)
        {
            var button = new Button { Padding = new Thickness(0), BorderThickness = new Thickness(0), Content = Photo(photo, 64, 48) };
            ToolTipService.SetToolTip(button, "Show the photo");
            AutomationProperties.SetName(button, "Show the photo");
            button.Click += async (_, _) => await Enlarge(entry);
            picture = button;
        }
        else
        {
            picture = new Border
            {
                Width = 64,
                Height = 48,
                CornerRadius = new CornerRadius(8),
                Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x0A, 0xFF, 0xFF, 0xFF)),
                Child = new FontIcon { Glyph = "", FontSize = 16, Opacity = 0.35 },
            };
            AutomationProperties.SetName(picture, "No photo");
        }
        row.Children.Add(picture);

        var words = new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center };
        words.Children.Add(new TextBlock { Text = entry.RecoveryKey ? "Wrong recovery key" : "Wrong password" });
        words.Children.Add(new TextBlock { Text = entry.Date.LocalDateTime.ToString("d MMM yyyy, HH:mm:ss"), FontSize = 12, Opacity = 0.45 });
        Grid.SetColumn(words, 1);
        row.Children.Add(words);

        var delete = new Button { Content = new FontIcon { Glyph = "", FontSize = 14 }, Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), BorderThickness = new Thickness(0), VerticalAlignment = VerticalAlignment.Center };
        ToolTipService.SetToolTip(delete, "Delete this entry");
        AutomationProperties.SetName(delete, "Delete this entry");
        delete.Click += (_, _) =>
        {
            try { state.Vault?.DeleteIntruder(entry.Id); }
            catch (StillroomException) { return; }
            entries.Remove(entry);
            Draw();
        };
        Grid.SetColumn(delete, 2);
        row.Children.Add(delete);
        return row;
    }

    /// <summary>The camera's photo as a mirror shows a face, the way the person saw themselves; drawn from memory.</summary>
    private static Border Photo(byte[] jpeg, double width, double height)
    {
        var bitmap = new BitmapImage();
        var stream = new InMemoryRandomAccessStream();
        var writer = new DataWriter(stream);
        writer.WriteBytes(jpeg);
        var image = new Image
        {
            Source = bitmap,
            Stretch = width > 100 ? Stretch.Uniform : Stretch.UniformToFill,
            RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5),
            RenderTransform = new ScaleTransform { ScaleX = -1 },
        };
        _ = writer.StoreAsync().AsTask().ContinueWith(_ =>
        {
            writer.DetachStream();
            stream.Seek(0);
            image.DispatcherQueue.TryEnqueue(async () =>
            {
                try { await bitmap.SetSourceAsync(stream); }
                catch (Exception) { }
                finally { stream.Dispose(); }
            });
        }, TaskScheduler.Default);
        return new Border { Width = width, Height = height, CornerRadius = new CornerRadius(width > 100 ? 12 : 8), Child = image };
    }

    private async Task Enlarge(Entry entry)
    {
        var body = new StackPanel { Spacing = 12 };
        body.Children.Add(Photo(entry.Photo!, 520, 390));
        body.Children.Add(new TextBlock { Text = entry.Date.LocalDateTime.ToString("d MMMM yyyy, HH:mm:ss"), FontSize = 12, Opacity = 0.5 });
        await new ContentDialog { XamlRoot = XamlRoot, Content = body, CloseButtonText = "Done", DefaultButton = ContentDialogButton.Close }.ShowAsync();
    }

    private async Task ClearAll()
    {
        if (await Ask.Choose(XamlRoot, "Clear the intruder log?", "Every entry and photo goes for good.", "Clear All", destructive: true) != ContentDialogResult.Primary) return;
        try { state.Vault?.ClearIntruders(); }
        catch (StillroomException) { return; }
        entries = [];
        Draw();
    }
}
