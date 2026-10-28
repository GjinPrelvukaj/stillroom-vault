using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Stillroom.Model;

namespace Stillroom;

/// <summary>The first time, before a vault is made (the Mac's `WelcomeTour`): four short pages on what Stillroom does
/// and the few things to know. Shown whenever there's no vault yet, so nothing about it needs remembering.</summary>
internal sealed class WelcomeTour : UserControl
{
    private readonly (string Glyph, string Title, string Text)[] pages;
    private readonly Action done;
    private readonly FontIcon glyph = new() { FontSize = 22, Opacity = 0.75 };
    private readonly Ellipse ring = new() { StrokeThickness = 2, StrokeDashArray = [1, 3] };
    private readonly TextBlock title = new() { Style = (Style)Application.Current.Resources["TitleText"] };
    private readonly TextBlock text = new() { Style = (Style)Application.Current.Resources["BodyText"], Height = 104 };
    private readonly StackPanel dots = new() { Orientation = Orientation.Horizontal, Spacing = 6, HorizontalAlignment = HorizontalAlignment.Center };
    private readonly Button back = new() { Content = "Back" };
    private readonly Button next = new() { Style = (Style)Application.Current.Resources["AccentButtonStyle"], MinWidth = 120 };
    private readonly HyperlinkButton skip = new() { Content = "Skip", Style = (Style)Application.Current.Resources["QuietButton"], HorizontalAlignment = HorizontalAlignment.Center };
    private int page;

    public WelcomeTour(string? hotKey, Action done)
    {
        this.done = done;
        pages =
        [
            (Glyphs.Shield, "Everything stays on this PC",
                "Files, notes and passwords are encrypted right here. No account, no server, no cloud, so nobody else can open your vault. Not even whoever made Stillroom."),
            (Glyphs.Secret, "Your password is the way in",
                "It can't be reset or sent to you, so pick one you won't forget. Next you'll get a recovery key to write on paper: the only other way in."),
            ("", "A second password, if you need one",
                "In Settings you can add a decoy password. It opens a separate, harmless vault, for when someone makes you open Stillroom."),
            ("", "Quick to lock",
                $"Stillroom locks itself when Windows locks, the PC sleeps or it sits untouched.{(hotKey is null ? "" : $" {hotKey} in any app locks and hides it at once.")}"),
        ];

        var mark = new Grid { Width = 84, Height = 84, HorizontalAlignment = HorizontalAlignment.Center };
        mark.Children.Add(ring);
        mark.Children.Add(glyph);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) };
        buttons.Children.Add(back);
        buttons.Children.Add(next);
        back.Click += (_, _) => Go(-1);
        next.Click += (_, _) => { if (page == pages.Length - 1) done(); else Go(1); };
        next.KeyboardAccelerators.Add(new KeyboardAccelerator { Key = Windows.System.VirtualKey.Enter });
        skip.Click += (_, _) => done();

        var words = new StackPanel { Spacing = 6 };
        words.Children.Add(title);
        words.Children.Add(text);
        var column = new StackPanel { Width = 340, Spacing = 16, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 0, 60) };
        column.Children.Add(mark);
        column.Children.Add(words);
        column.Children.Add(dots);
        column.Children.Add(buttons);
        column.Children.Add(skip);
        Content = column;
        Draw();
    }

    private void Go(int step)
    {
        page = Math.Clamp(page + step, 0, pages.Length - 1);
        Draw();
    }

    private void Draw()
    {
        var current = pages[page];
        glyph.Glyph = current.Glyph;
        title.Text = current.Title;
        text.Text = current.Text;
        // The ring fills as the pages go.
        ring.Stroke = (Brush)Application.Current.Resources["VaultBrush"];
        ring.Opacity = 0.3 + 0.7 * (page + 1) / pages.Length;
        dots.Children.Clear();
        for (var i = 0; i < pages.Length; i++)
        {
            dots.Children.Add(new Border
            {
                Width = i == page ? 16 : 6,
                Height = 6,
                CornerRadius = new CornerRadius(3),
                Background = i == page ? (Brush)Application.Current.Resources["VaultBrush"] : new SolidColorBrush(Windows.UI.Color.FromArgb(0x26, 0xFF, 0xFF, 0xFF)),
            });
        }
        AutomationProperties.SetName(dots, $"Page {page + 1} of {pages.Length}");
        back.Visibility = page > 0 ? Visibility.Visible : Visibility.Collapsed;
        next.Content = page == pages.Length - 1 ? "Make My Vault" : "Next";
        skip.Opacity = page == pages.Length - 1 ? 0 : 1;
        skip.IsEnabled = page < pages.Length - 1;
    }
}
