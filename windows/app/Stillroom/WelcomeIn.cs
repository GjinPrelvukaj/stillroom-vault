using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Stillroom.Native;

namespace Stillroom;

/// <summary>The moment a licence checks out (the Mac's `WelcomeIn`): a card that welcomes the buyer by name. The same
/// in either vault (the licence is shared), so it tells nothing about which is open. The Mac's filling ring and
/// confetti aren't here: a dialog, in the window's own colours, is the Windows way.</summary>
internal static class WelcomeIn
{
    /// <summary>"Ada" from "Ada Lovelace"; a company or an email address stays whole.</summary>
    private static string FirstName(Licence licence) =>
        licence.Edition == "teams" || licence.Name.Contains('@') ? licence.Name : licence.Name.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? licence.Name;

    private static string Message(Licence licence) => licence.Edition switch
    {
        "family" => $"Thank you for bringing your family in. The same key works for up to {licence.Seats} people: each adds it on their own computer, and each vault stays their own.",
        "teams" => $"Thank you for trusting Stillroom with your team's work. The key covers {licence.Seats} people, each with a vault of their own that nobody else can open.",
        _ => "Thank you for backing a small, independent app. Your vault has no limit now, on every computer of yours, and every 1.x update is yours.",
    };

    public static async Task ShowAsync(XamlRoot root, Licence licence)
    {
        var title = $"Welcome in, {FirstName(licence)}.";
        var card = new StackPanel { Spacing = 10, Width = 380, Padding = new Thickness(0, 8, 0, 0) };
        card.Children.Add(new FontIcon { Glyph = "", FontSize = 34, Foreground = Theme.Brush("VaultBrush"), HorizontalAlignment = HorizontalAlignment.Center });
        card.Children.Add(new TextBlock
        {
            Text = licence.EditionName.ToUpperInvariant(),
            FontSize = 10.5,
            FontWeight = FontWeights.SemiBold,
            CharacterSpacing = 80,
            Foreground = Theme.Brush("QuietBrush"),
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 6, 0, 0),
        });
        card.Children.Add(new TextBlock { Text = title, Style = (Style)Application.Current.Resources["TitleText"] });
        card.Children.Add(new TextBlock { Text = Message(licence), Style = (Style)Application.Current.Resources["BodyText"] });
        AutomationProperties.SetName(card, $"{title} {Message(licence)}");
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Content = card,
            PrimaryButtonText = "Start Using It",
            DefaultButton = ContentDialogButton.Primary,
        };
        await dialog.ShowAsync();
    }
}
