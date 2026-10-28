using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Stillroom.Model;
using Stillroom.Native;
using Stillroom.Platform;
using Windows.Storage.Streams;
using Windows.System;

namespace Stillroom;

/// <summary>A file, or an earlier version of anything, shown in a card (the Mac's `PreviewCard`): pictures and text
/// drawn here from memory, never written to disk. PDFs, audio, video and email get their viewers in Phase 5; until
/// then they offer a copy to open elsewhere.</summary>
internal sealed class PreviewCard : UserControl
{
    /// <summary>Bigger than this isn't read into memory for a look.</summary>
    private const long Largest = 64 << 20;

    /// <summary>`edit`: Edit in Place, for a kind that may open in another app; null hides the button.</summary>
    public PreviewCard(AppState state, VaultItem item, VersionInfo? version, Action close, Action save, Action? edit = null)
    {
        var size = version?.Size ?? item.Size;
        var date = version?.Date ?? item.ShownDate;

        var heading = new StackPanel { Spacing = 4 };
        heading.Children.Add(new TextBlock
        {
            Text = (version is null ? item.KindName : $"{item.KindName}, as it was").ToUpperInvariant(),
            FontSize = 10.5,
            FontWeight = FontWeights.SemiBold,
            CharacterSpacing = 80,
            Foreground = (Brush)Application.Current.Resources["QuietBrush"],
        });
        heading.Children.Add(new TextBlock { Text = item.Name, FontSize = 24, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis });

        var footer = new Grid { ColumnSpacing = 8 };
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.Children.Add(new TextBlock
        {
            Text = $"{(item.IsFile ? Shell.Size(size) + " · " : "")}{date.LocalDateTime:d MMMM yyyy}",
            FontSize = 12,
            Opacity = 0.45,
            VerticalAlignment = VerticalAlignment.Center,
        });
        var closeButton = new Button { Content = "Close" };
        closeButton.Click += (_, _) => close();
        closeButton.KeyboardAccelerators.Add(new KeyboardAccelerator { Key = VirtualKey.Escape });
        Grid.SetColumn(closeButton, 1);
        footer.Children.Add(closeButton);
        if (item.IsFile && version is null)
        {
            var saveButton = new Button { Content = "Save a Copy…" };
            saveButton.Click += (_, _) => save();
            Grid.SetColumn(saveButton, 2);
            footer.Children.Add(saveButton);
        }
        if (edit is not null && version is null)
        {
            var editButton = new Button { Content = "Edit in Place", Style = (Style)Application.Current.Resources["AccentButtonStyle"] };
            editButton.Click += (_, _) => edit();
            Grid.SetColumn(editButton, 3);
            footer.Children.Add(editButton);
        }

        var shown = new Border
        {
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x0A, 0xFF, 0xFF, 0xFF)),
            CornerRadius = new CornerRadius(12),
            Child = Contents(state, item, version, size),
        };
        var card = new Grid { RowSpacing = 16, Padding = new Thickness(0, 8, 0, 0) };
        card.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        card.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        card.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        card.Children.Add(heading);
        Grid.SetRow(shown, 1);
        card.Children.Add(shown);
        Grid.SetRow(footer, 2);
        card.Children.Add(footer);
        Content = card;
    }

    private static UIElement Contents(AppState state, VaultItem item, VersionInfo? version, long size)
    {
        var showable = item.Look is Look.Picture or Look.Text || !item.IsFile;
        if (!showable) return Message(item.Glyph, "No preview here yet", "Save a copy to open it in its own app. Viewers for this kind come in a later version.");
        if (size > Largest) return Message(item.Glyph, "Too big to show here", "Save a copy to open it in its app.");
        byte[] data;
        try
        {
            data = state.Vault!.Read(item.Id, version?.Id);
        }
        catch (Exception e) when (e is StillroomException or ObjectDisposedException or NullReferenceException)
        {
            return Message(item.Glyph, "Couldn't be read", e is StillroomException failure ? failure.Message : "");
        }
        try
        {
            if (item.IsSecret) return SecretFields(data);
            if (item.Look == Look.Picture && item.Uti != "public.svg-image") return Picture(data);
            return Text(Encoding.UTF8.GetString(data));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(data);
        }
    }

    private static UIElement Picture(byte[] data)
    {
        var image = new Image { Stretch = Stretch.Uniform, Margin = new Thickness(16) };
        var bitmap = new BitmapImage();
        // Decoded from memory: the picture never touches the disk.
        var stream = new InMemoryRandomAccessStream();
        var writer = new DataWriter(stream);
        writer.WriteBytes(data);
        _ = writer.StoreAsync().AsTask().ContinueWith(_ =>
        {
            writer.DetachStream();
            stream.Seek(0);
            image.DispatcherQueue.TryEnqueue(async () =>
            {
                try { await bitmap.SetSourceAsync(stream); }
                catch (Exception) { /* Not a picture Windows can draw: the card stays empty. */ }
                finally { stream.Dispose(); }
            });
        }, TaskScheduler.Default);
        image.Source = bitmap;
        return image;
    }

    private static UIElement Text(string text) => new ScrollViewer
    {
        Content = new TextBlock
        {
            Text = text,
            FontFamily = new FontFamily("Consolas"),
            FontSize = 12,
            Opacity = 0.85,
            IsTextSelectionEnabled = true,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(16),
        },
    };

    /// <summary>An earlier version of a secret: concealed values stay hidden here too.</summary>
    private static UIElement SecretFields(byte[] data)
    {
        var secret = JsonSerializer.Deserialize<SecretContent>(data) ?? new SecretContent();
        var list = new StackPanel { Spacing = 8, Margin = new Thickness(16) };
        foreach (var field in secret.Fields)
        {
            var row = new Grid();
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(140) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.Children.Add(new TextBlock { Text = field.Label, FontSize = 12, Opacity = 0.55 });
            var value = new TextBlock { Text = field.Concealed ? new string('•', 10) : field.Value };
            Grid.SetColumn(value, 1);
            row.Children.Add(value);
            list.Children.Add(row);
        }
        return new ScrollViewer { Content = list };
    }

    private static UIElement Message(string glyph, string title, string line)
    {
        var panel = new StackPanel { Spacing = 6, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 380 };
        panel.Children.Add(new FontIcon { Glyph = glyph, FontSize = 28, Opacity = 0.45, Margin = new Thickness(0, 0, 0, 6) });
        panel.Children.Add(new TextBlock { Text = title, FontSize = 14, HorizontalAlignment = HorizontalAlignment.Center });
        panel.Children.Add(new TextBlock { Text = line, FontSize = 12, Opacity = 0.45, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center });
        return panel;
    }
}

/// <summary>Earlier contents of an item, newest first: open one to look, or put it back (the Mac's `VersionsSheet`).</summary>
internal static class VersionsDialog
{
    /// <summary>The version chosen, and whether to put it back (else just look); null when closed.</summary>
    public static async Task<(VersionInfo Version, bool PutBack)?> ShowAsync(XamlRoot root, VaultItem item)
    {
        (VersionInfo, bool)? chosen = null;
        var list = new StackPanel();
        ContentDialog? dialog = null;
        foreach (var version in item.Versions.Reverse())
        {
            if (list.Children.Count > 0) list.Children.Add(new Border { Height = 1, Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x0D, 0xFF, 0xFF, 0xFF)) });
            var row = new Grid { Height = 42, ColumnSpacing = 8, Padding = new Thickness(14, 0, 8, 0) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var when = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
            when.Children.Add(new TextBlock { Text = version.Date.LocalDateTime.ToString("d MMM yyyy, HH:mm") });
            if (item.IsFile) when.Children.Add(new TextBlock { Text = Shell.Size(version.Size), FontSize = 12, Opacity = 0.45, VerticalAlignment = VerticalAlignment.Center });
            row.Children.Add(when);
            var open = new HyperlinkButton { Content = "Open" };
            open.Click += (_, _) => { chosen = (version, false); dialog?.Hide(); };
            Grid.SetColumn(open, 1);
            row.Children.Add(open);
            var putBack = new Button { Content = "Put Back" };
            putBack.Click += (_, _) => { chosen = (version, true); dialog?.Hide(); };
            Grid.SetColumn(putBack, 2);
            row.Children.Add(putBack);
            list.Children.Add(row);
        }
        var body = new StackPanel { Spacing = 16, Width = 460 };
        body.Children.Add(new TextBlock
        {
            Text = $"“{item.Name}” as it was before each change. Putting one back keeps today's as a version too.",
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.Resources["QuietBrush"],
        });
        body.Children.Add(new ScrollViewer
        {
            MaxHeight = 320,
            Content = new Border { Background = (Brush)Application.Current.Resources["PanelBrush"], CornerRadius = new CornerRadius(12), Child = list },
        });
        dialog = new ContentDialog { XamlRoot = root, Title = "Versions", Content = body, CloseButtonText = "Done", DefaultButton = ContentDialogButton.Close };
        await dialog.ShowAsync();
        return chosen;
    }
}
