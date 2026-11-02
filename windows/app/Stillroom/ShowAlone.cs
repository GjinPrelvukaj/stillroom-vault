#if DEBUG
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Stillroom.Model;
using Stillroom.Native;
using Stillroom.Platform;

namespace Stillroom;

/// <summary>Development builds only: one file in the viewer the card would use for it (an email in `MailViewer`, a PDF,
/// picture, song or video in the card's own viewer, any other kind in `QuickLook`), in a window of its own and with no vault, for `tests/lockdown.ps1` (the Mac's
/// `MailLockdownTests`). The script runs a server on this PC that counts connections, writes a hostile file aimed at
/// it, and starts the app with `STILLROOM_SHOW_FILE` naming it; the window's title says once it's on the screen. The
/// app itself never listens or connects. `STILLROOM_SHOW_FILE_CAPTURE` lets screenshots see the window (the files are
/// made up).</summary>
internal static class ShowAlone
{
    /// <summary>`STILLROOM_READ_WORDS`: the words search would find in one picture or PDF, written beside it as
    /// "&lt;name&gt;.words.txt" (or "(none)" when Windows has no text recognition installed), then quits.</summary>
    public static void ReadWords(string path)
    {
        // Off the UI thread, as the app reads them.
        var words = Task.Run(() => Recognition.Read(Engine.UtiForName(Path.GetFileName(path)), File.ReadAllBytes(path))).GetAwaiter().GetResult();
        File.WriteAllText(path + ".words.txt", words ?? "(none)");
        Application.Current.Exit();
    }

    public static void Show(string path)
    {
        if (Environment.GetEnvironmentVariable("STILLROOM_SHOW_FILE_CAPTURE") is { Length: > 0 }) CaptureShield.Follow(true);
        var window = new Window { Title = "Stillroom look" };
        UserControl viewer;
        if (path.EndsWith(".eml", StringComparison.OrdinalIgnoreCase))
        {
            var mail = new MailViewer(File.ReadAllBytes(path), (_, _) => { }, (_, _) => Task.CompletedTask);
            mail.Shown += () => window.Title = "Stillroom look: shown";
            viewer = mail;
        }
        else if (Path.GetExtension(path).ToLowerInvariant() is ".pdf" or ".png" or ".jpg" or ".mp4" or ".mp3")
        {
            // The card's own viewers, for trying a build's Windows App SDK files (`STILLROOM_SHOW_FILE` alone shows
            // that it draws; nothing here connects anywhere to count).
            var data = File.ReadAllBytes(path);
            var item = new VaultItem { Id = "", Name = Path.GetFileName(path), Uti = Engine.UtiForName(Path.GetFileName(path)) };
            viewer = new UserControl
            {
                Content = Path.GetExtension(path).ToLowerInvariant() switch
                {
                    ".pdf" => new PdfViewer(data, () => new TextBlock { Text = "Couldn't show it" }),
                    ".png" or ".jpg" => PreviewCard.Picture(data),
                    _ => new MediaViewer(item, null, data, () => new TextBlock { Text = "Couldn't play it" }),
                },
            };
            window.Title = "Stillroom look: shown";
        }
        else if (FontCard.Shows(path))
        {
            var font = new FontCard(
                () => EditDesk.PutOutForLook(Path.GetFileName(path), copy => File.Copy(path, copy)),
                () => new TextBlock { Text = "Couldn't show it" });
            font.Shown += () => window.Title = "Stillroom look: shown";
            font.Failed += () => window.Title = "Stillroom look: failed (not a font)";
            viewer = font;
        }
        else
        {
            var look = new QuickLook(
                () => EditDesk.PutOutForLook(Path.GetFileName(path), copy => File.Copy(path, copy)),
                () => new TextBlock { Text = "Couldn't show it" });
            look.Shown += () => window.Title = "Stillroom look: shown";
            look.Failed += () => window.Title = $"Stillroom look: failed ({look.Problem})";
            viewer = look;
        }
        window.Content = new Grid { Background = Theme.Brush("PanelBrush"), Children = { viewer } };
        window.Activate();
    }
}
#endif
