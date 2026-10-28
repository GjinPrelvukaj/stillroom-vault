using System.Text.Json;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Stillroom.Model;
using Stillroom.Native;
using Stillroom.Platform;

namespace Stillroom;

/// <summary>Making an emergency kit (the Mac's `KitSheet`): how many pieces and how many open it, then the pieces,
/// printed once on paper and not shown again.</summary>
internal static class KitDialog
{
    private sealed record Plan(string Name, byte Threshold, byte Count, string Example);

    private static readonly Plan[] Plans =
    [
        new("2 of 2", 2, 2, "Both pieces are needed. Losing either one makes the kit useless."),
        new("2 of 3", 2, 3, "For example: your partner, your lawyer, and your safe. Any two together open it."),
        new("3 of 5", 3, 5, "For a family: five people, any three together open it. Two alone never can."),
    ];

    public static async Task ShowAsync(XamlRoot root, Vault vault, bool hasKit, IntPtr owner)
    {
        var plan = Plans[1];
        string[]? pieces = null;
        var problem = new TextBlock { TextWrapping = TextWrapping.Wrap, Foreground = (Brush)Application.Current.Resources["ProblemBrush"], FontSize = 12 };
        var example = new TextBlock { Text = plan.Example, TextWrapping = TextWrapping.Wrap, FontSize = 12, Opacity = 0.55 };
        var choice = new RadioButtons { MaxColumns = 3 };
        foreach (var p in Plans) choice.Items.Add(p.Name);
        choice.SelectedIndex = 1;
        choice.SelectionChanged += (_, _) => { plan = Plans[Math.Max(0, choice.SelectedIndex)]; example.Text = plan.Example; };
        var choose = new StackPanel { Spacing = 12, Width = 440 };
        choose.Children.Add(Quiet("Printed pieces for people you trust, so they can open the vault if something happens to you. One piece alone opens nothing. No server and no account are involved."));
        choose.Children.Add(new TextBlock
        {
            Text = "Print on a real printer. \"Printers\" like Microsoft Print to PDF or OneNote keep the pieces on this PC, or in the cloud.",
            TextWrapping = TextWrapping.Wrap,
            FontSize = 12,
            Opacity = 0.55,
        });
        choose.Children.Add(choice);
        choose.Children.Add(example);
        if (hasKit)
        {
            choose.Children.Add(new TextBlock
            {
                Text = "A new kit stops the old pieces opening this vault. Backups made before it still open with them.",
                TextWrapping = TextWrapping.Wrap,
                FontSize = 12,
                Foreground = new SolidColorBrush(Microsoft.UI.Colors.Orange),
            });
        }
        choose.Children.Add(problem);

        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = "Emergency kit",
            Content = choose,
            PrimaryButtonText = "Make Kit",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
        };
        var printed = false;
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            args.Cancel = true;
            if (pieces is null)
            {
                var deferral = args.GetDeferral();
                dialog.IsPrimaryButtonEnabled = false;
                try
                {
                    pieces = await Task.Run(() => vault.MakeKit(plan.Threshold, plan.Count));
                    ShowPieces(dialog, pieces);
                }
                catch (Exception e) when (e is StillroomException or ObjectDisposedException)
                {
                    problem.Text = e.Message;
                }
                finally
                {
                    dialog.IsPrimaryButtonEnabled = true;
                    deferral.Complete();
                }
            }
            else
            {
                var deferral = args.GetDeferral();
                try { printed = await KitPrinter.PrintAsync(owner, pieces, plan.Threshold, () => !vault.IsLocked) || printed; }
                finally { deferral.Complete(); }
                if (printed) dialog.DefaultButton = ContentDialogButton.Close;
            }
        };
        await dialog.ShowAsync();
    }

    private static void ShowPieces(ContentDialog dialog, string[] pieces)
    {
        var list = new StackPanel();
        for (var i = 0; i < pieces.Length; i++)
        {
            if (i > 0) list.Children.Add(new Border { Height = 1, Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x0D, 0xFF, 0xFF, 0xFF)) });
            var row = new Grid { Padding = new Thickness(12, 8, 12, 8) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(56) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.Children.Add(new TextBlock { Text = $"Piece {i + 1}", FontSize = 12, Opacity = 0.5 });
            var code = new TextBlock { Text = pieces[i], FontFamily = new FontFamily("Consolas"), FontSize = 11.5, TextWrapping = TextWrapping.Wrap };
            Grid.SetColumn(code, 1);
            row.Children.Add(code);
            list.Children.Add(row);
        }
        var body = new StackPanel { Spacing = 12, Width = 440 };
        body.Children.Add(Quiet("One page per piece, with plain instructions on it. Print on paper; don't print to a PDF or take a photo. They won't be shown again."));
        body.Children.Add(new Border { Background = (Brush)Application.Current.Resources["PanelBrush"], CornerRadius = new CornerRadius(12), Child = list });
        dialog.Title = "Print the pieces";
        dialog.Content = body;
        dialog.PrimaryButtonText = "Print Pieces…";
        dialog.CloseButtonText = "Done";
    }

    internal static TextBlock Quiet(string text) => new()
    {
        Text = text,
        TextWrapping = TextWrapping.Wrap,
        Foreground = (Brush)Application.Current.Resources["QuietBrush"],
    };
}

/// <summary>Check vault (the Mac's `CheckSheet`): everything read back all the way through, then what doesn't open,
/// each with what can be done.</summary>
internal static class CheckDialog
{
    public static async Task ShowAsync(XamlRoot root, Vault vault, IReadOnlyList<VaultItem> items)
    {
        var total = items.Count + items.Sum(i => i.Versions.Count);
        var summary = new TextBlock { Text = "Reading every item back…", TextWrapping = TextWrapping.Wrap, Foreground = (Brush)Application.Current.Resources["QuietBrush"] };
        var list = new StackPanel();
        var body = new StackPanel { Spacing = 14, Width = 460 };
        body.Children.Add(summary);
        var working = new ProgressBar { IsIndeterminate = true };
        body.Children.Add(working);
        var dialog = new ContentDialog { XamlRoot = root, Title = "Check vault", Content = body, CloseButtonText = "Cancel" };
        var shown = dialog.ShowAsync();

        JsonElement damage;
        try { damage = await Task.Run(vault.Check); }
        catch (Exception e) when (e is StillroomException or ObjectDisposedException)
        {
            summary.Text = e.Message;
            working.Visibility = Visibility.Collapsed;
            dialog.CloseButtonText = "Done";
            await shown;
            return;
        }
        working.Visibility = Visibility.Collapsed;
        dialog.CloseButtonText = "Done";
        var found = damage.EnumerateArray().ToList();
        var fixedCount = 0;
        void Summarize() => summary.Text = found.Count == 0
            ? fixedCount > 0 ? "All dealt with. Run the check again any time." : $"Everything opens as it should. {total} checked, nothing damaged."
            : $"{found.Count} of {total} didn't open. If you have a backup from before this, restoring it brings them back; otherwise fix each below.";
        Summarize();

        foreach (var entry in found.ToList())
        {
            var id = entry.GetProperty("item").GetString()!;
            var item = items.FirstOrDefault(i => string.Equals(i.Id, id, StringComparison.OrdinalIgnoreCase));
            string? version = entry.GetProperty("version").ValueKind == JsonValueKind.String ? entry.GetProperty("version").GetString() : null;
            string? fallback = entry.GetProperty("fallback").ValueKind == JsonValueKind.String ? entry.GetProperty("fallback").GetString() : null;
            var row = new Grid { Padding = new Thickness(14, 10, 14, 10), ColumnSpacing = 12 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var words = new StackPanel { Spacing = 2 };
            words.Children.Add(new TextBlock { Text = item?.Name ?? "An item", TextTrimming = TextTrimming.CharacterEllipsis });
            var when = version is null ? "Current contents"
                : $"Earlier version from {item?.Versions.FirstOrDefault(v => string.Equals(v.Id, version, StringComparison.OrdinalIgnoreCase))?.Date.LocalDateTime.ToString("d MMM yyyy, HH:mm") ?? "before"}";
            words.Children.Add(new TextBlock { Text = when, FontSize = 12, Opacity = 0.45 });
            row.Children.Add(words);
            var action = new Button { Content = version is not null ? "Remove Version" : fallback is not null ? "Use Earlier Version" : "Delete" };
            action.Click += (_, _) =>
            {
                try
                {
                    if (version is not null) vault.DropVersion(id, version);
                    else if (fallback is not null) vault.FallBack(id, fallback);
                    else vault.Delete(id);
                    found.Remove(entry);
                    fixedCount++;
                    list.Children.Remove(row);
                    Summarize();
                }
                catch (Exception e) when (e is StillroomException or ObjectDisposedException)
                {
                    summary.Text = e.Message;
                }
            };
            Grid.SetColumn(action, 1);
            row.Children.Add(action);
            list.Children.Add(row);
        }
        if (found.Count > 0)
        {
            body.Children.Add(new ScrollViewer
            {
                MaxHeight = 260,
                Content = new Border { Background = (Brush)Application.Current.Resources["PanelBrush"], CornerRadius = new CornerRadius(12), Child = list },
            });
        }
        await shown;
    }
}
