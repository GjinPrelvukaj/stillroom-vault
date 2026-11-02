using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Stillroom.Model;
using Stillroom.Native;
using Stillroom.Platform;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Storage.Streams;

namespace Stillroom;

/// <summary>A song or a video played straight from the vault (the Mac's `VaultPlayer`): Windows' media player reads it
/// a piece at a time through the engine (`VaultStream`), so nothing unsealed is ever written to disk. Kept out of
/// Windows' own media controls (the volume overlay, the lock screen), which would show what's playing outside the
/// window: that takes the player's command manager off, which WinUI's own transport controls can't play without, so
/// the controls here are Stillroom's (play and pause, the time, seeking, mute; Space plays and pauses). Without WinUI's
/// controls there's no Cast to Device either, which would send it over the network. Stops, and lets go of the item's
/// key, as the card closes or the vault locks.</summary>
internal sealed class MediaViewer : UserControl
{
    private const string PlayGlyph = "";
    private const string PauseGlyph = "";
    private const string SoundGlyph = "";
    private const string MutedGlyph = "";

    private readonly MediaPlayer player = new() { AutoPlay = false };
    private readonly MediaPlayerElement element = new() { AreTransportControlsEnabled = false, Stretch = Stretch.Uniform };
    private readonly Button play = Plain(PlayGlyph, "Play");
    private readonly Button mute = Plain(SoundGlyph, "Mute");
    private readonly Slider seek = new() { Minimum = 0, Maximum = 1, StepFrequency = 0.1, IsThumbToolTipEnabled = false, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock at = Time();
    private readonly TextBlock length = Time();
    private readonly DispatcherQueueTimer ticking;
    private VaultStream? stream;
    private IRandomAccessStream? whole;
    /// <summary>The slider is being moved to where the player is, not by a person: no seek.</summary>
    private bool following;
    private bool closed;

    /// <summary>`reader`: the item, read a piece at a time. `data`: an earlier version, small enough to be held whole
    /// (copied in; the caller wipes its own copy). One of the two.</summary>
    public MediaViewer(VaultItem item, Reader? reader, byte[]? data, Func<UIElement> unplayable)
    {
        // Nothing of it in Windows' media flyout or on the lock screen: with the command manager on, Windows lists it as
        // a session playing (seen in GlobalSystemMediaTransportControlsSessionManager), whatever the transport
        // controls' own switch says.
        player.CommandManager.IsEnabled = false;
        player.SystemMediaTransportControls.IsEnabled = false;

        IRandomAccessStream source;
        if (reader is not null)
        {
            source = stream = new VaultStream(reader);
        }
        else
        {
            var memory = new InMemoryRandomAccessStream();
            var writer = new DataWriter(memory);
            writer.WriteBytes(data ?? []);
            writer.StoreAsync().AsTask().Wait();
            writer.DetachStream();
            memory.Seek(0);
            source = whole = memory;
        }
        player.Source = MediaSource.CreateFromStream(source, ContentType(item));
        player.MediaFailed += (_, _) => DispatcherQueue.TryEnqueue(() =>
        {
            if (closed) return;
            Close();
            Content = unplayable();
        });
        player.PlaybackSession.PlaybackStateChanged += (_, _) => DispatcherQueue.TryEnqueue(Follow);
        player.PlaybackSession.NaturalDurationChanged += (_, _) => DispatcherQueue.TryEnqueue(Follow);
        player.MediaEnded += (_, _) => DispatcherQueue.TryEnqueue(Follow);
        element.SetMediaPlayer(player);

        play.Click += (_, _) => Toggle();
        mute.Click += (_, _) =>
        {
            player.IsMuted = !player.IsMuted;
            Follow();
        };
        seek.ValueChanged += (_, e) =>
        {
            if (!following && !closed) player.PlaybackSession.Position = TimeSpan.FromSeconds(e.NewValue);
        };
        AutomationProperties.SetName(seek, "Seek");
        // Space plays and pauses wherever the focus is in the player (on the play button, a click does it already).
        KeyDown += (_, e) =>
        {
            if (e.Key != Windows.System.VirtualKey.Space || ReferenceEquals(e.OriginalSource, play)) return;
            e.Handled = true;
            Toggle();
        };

        var bar = new Grid { ColumnSpacing = 10, Padding = new Thickness(12, 6, 12, 8) };
        foreach (var width in new[] { GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto, GridLength.Auto })
            bar.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
        FrameworkElement[] parts = [play, at, seek, length, mute];
        for (var i = 0; i < parts.Length; i++)
        {
            Grid.SetColumn(parts[i], i);
            bar.Children.Add(parts[i]);
        }

        var layout = new Grid();
        layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        layout.Children.Add(element);
        // A song has nothing to show: its symbol where the picture would be.
        if (item.Look == Look.Audio)
            layout.Children.Add(new FontIcon { Glyph = item.Glyph, FontSize = 48, Opacity = 0.35, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        Grid.SetRow(bar, 1);
        layout.Children.Add(bar);
        Content = layout;

        // The time moves on four times a second while it plays.
        ticking = DispatcherQueue.GetForCurrentThread().CreateTimer();
        ticking.Interval = TimeSpan.FromMilliseconds(250);
        ticking.Tick += (_, _) => Follow();
        Loaded += (_, _) =>
        {
            ticking.Start();
            Follow();
            play.Focus(FocusState.Programmatic);
        };
        Unloaded += (_, _) => Close();
    }

    private void Toggle()
    {
        if (closed) return;
        var session = player.PlaybackSession;
        if (session.PlaybackState == MediaPlaybackState.Playing)
        {
            player.Pause();
        }
        else
        {
            // Played to the end: from the start again.
            if (session.NaturalDuration > TimeSpan.Zero && session.Position >= session.NaturalDuration - TimeSpan.FromMilliseconds(250))
                session.Position = TimeSpan.Zero;
            player.Play();
        }
        Follow();
    }

    /// <summary>The controls brought up to what the player is doing.</summary>
    private void Follow()
    {
        if (closed) return;
        var session = player.PlaybackSession;
        var playing = session.PlaybackState is MediaPlaybackState.Playing or MediaPlaybackState.Buffering;
        Set(play, playing ? PauseGlyph : PlayGlyph, playing ? "Pause" : "Play");
        Set(mute, player.IsMuted ? MutedGlyph : SoundGlyph, player.IsMuted ? "Unmute" : "Mute");
        var total = session.NaturalDuration;
        following = true;
        seek.Maximum = Math.Max(0.1, total.TotalSeconds);
        seek.Value = Math.Min(seek.Maximum, session.Position.TotalSeconds);
        following = false;
        at.Text = Clock(session.Position);
        length.Text = Clock(total);
        play.IsEnabled = seek.IsEnabled = total > TimeSpan.Zero;
    }

    private static string Clock(TimeSpan time) => time.TotalHours >= 1 ? time.ToString(@"h\:mm\:ss") : time.ToString(@"m\:ss");

    private static Button Plain(string glyph, string name)
    {
        var button = new Button
        {
            Content = new FontIcon { Glyph = glyph, FontSize = 15 },
            Padding = new Thickness(8, 6, 8, 6),
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        Set(button, glyph, name);
        return button;
    }

    private static void Set(Button button, string glyph, string name)
    {
        ((FontIcon)button.Content).Glyph = glyph;
        AutomationProperties.SetName(button, name);
        ToolTipService.SetToolTip(button, name);
    }

    private static TextBlock Time() => new() { FontSize = 12, Opacity = 0.6, VerticalAlignment = VerticalAlignment.Center, MinWidth = 36, Text = "0:00" };

    /// <summary>What it is, for Windows to pick a decoder; it looks at the bytes too, so a near guess is enough.</summary>
    private static string ContentType(VaultItem item) => Path.GetExtension(item.Name).ToLowerInvariant() switch
    {
        ".mp3" => "audio/mpeg",
        ".m4a" or ".aac" => "audio/mp4",
        ".wav" => "audio/wav",
        ".flac" => "audio/flac",
        ".ogg" or ".oga" => "audio/ogg",
        ".wma" => "audio/x-ms-wma",
        ".mov" => "video/quicktime",
        ".m4v" => "video/x-m4v",
        ".avi" => "video/x-msvideo",
        ".wmv" => "video/x-ms-wmv",
        ".mkv" => "video/x-matroska",
        ".webm" => "video/webm",
        ".mpg" or ".mpeg" => "video/mpeg",
        _ => item.Look == Look.Audio ? "audio/mpeg" : "video/mp4",
    };

    /// <summary>Stopped, and everything let go of: the player, then the reader (and the key in it) for every copy of
    /// the stream the player made.</summary>
    private void Close()
    {
        if (closed) return;
        closed = true;
        ticking.Stop();
        player.Pause();
        element.SetMediaPlayer(null);
        player.Source = null;
        player.Dispose();
        stream?.CloseAll();
        stream?.Dispose();
        whole?.Dispose();
    }
}
