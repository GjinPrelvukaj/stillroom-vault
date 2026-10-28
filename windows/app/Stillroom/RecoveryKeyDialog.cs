using System.Security.Cryptography;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Stillroom.Native;

namespace Stillroom;

/// <summary>A recovery key, shown once, then checked: two of its groups typed back (on the secure desktop) from the
/// paper it was written on, as the Mac's `RecoveryKeySheet`.</summary>
internal static class RecoveryKeyDialog
{
    private static readonly string[] Ordinals = ["first", "second", "third", "fourth", "fifth"];

    public static async Task ShowAsync(XamlRoot root, string key)
    {
        var groups = key.Split('-');
        // Which two groups are asked for, picked at random each time.
        var asked = Enumerable.Range(0, groups.Length).OrderBy(_ => RandomNumberGenerator.GetInt32(int.MaxValue)).Take(2).Order().ToArray();
        var line = new TextBlock { Style = (Style)Application.Current.Resources["QuietText"], TextAlignment = TextAlignment.Left, Foreground = (Brush)Application.Current.Resources["ProblemBrush"] };
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = "Your recovery key",
            PrimaryButtonText = "I've Written It Down",
            DefaultButton = ContentDialogButton.Primary,
            Content = new StackPanel
            {
                Spacing = 16,
                Width = 440,
                Children =
                {
                    new TextBlock
                    {
                        Style = (Style)Application.Current.Resources["BodyText"],
                        TextAlignment = TextAlignment.Left,
                        Text = "Write it on paper and keep it somewhere safe. If you forget your password, it's the only other way in. It also opens this vault on any computer, so treat it like the vault itself. It won't be shown again.",
                    },
                    new Border
                    {
                        Background = (Brush)Application.Current.Resources["PanelBrush"],
                        CornerRadius = new CornerRadius(10),
                        Padding = new Thickness(0, 16, 0, 16),
                        Child = new TextBlock
                        {
                            Text = key,
                            FontFamily = new FontFamily("Consolas"),
                            FontSize = 19,
                            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                            CharacterSpacing = 60,
                            HorizontalAlignment = HorizontalAlignment.Center,
                        },
                    },
                    line,
                },
            },
        };
        // Closing is only by typing the two groups back: the key won't be shown again.
        var checkedBack = false;
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            var deferral = args.GetDeferral();
            args.Cancel = true;
            var expected = groups[asked[0]] + groups[asked[1]];
            var matches = await Task.Run(() => Engine.SecurePrompt(Secrets.PromptTitle,
                $"Type the {Ordinals[asked[0]]} and {Ordinals[asked[1]]} groups from your paper.", false,
                typed => (bool?)Matches(typed, expected)));
            if (matches == true) checkedBack = true;
            else if (matches == false) line.Text = "That doesn't match. Check your paper, and the key above.";
            args.Cancel = !checkedBack;
            deferral.Complete();
        };
        dialog.Closing += (_, args) => args.Cancel = !checkedBack;
        await dialog.ShowAsync();
    }

    /// <summary>The typed groups against the expected ones: any case, dashes and spaces ignored.</summary>
    private static bool Matches(ReadOnlySpan<byte> typed, string expected)
    {
        Span<byte> plain = stackalloc byte[64];
        var length = 0;
        foreach (var b in typed)
        {
            if (!char.IsAsciiLetterOrDigit((char)b)) continue;
            if (length == plain.Length) return false;
            plain[length++] = (byte)char.ToUpperInvariant((char)b);
        }
        var result = CryptographicOperations.FixedTimeEquals(plain[..length], System.Text.Encoding.ASCII.GetBytes(expected));
        plain.Clear();
        return result;
    }
}
