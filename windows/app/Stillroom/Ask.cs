using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Stillroom;

/// <summary>Questions put to the person, drawn inside the window (so they're under its capture shield): a yes or no, a
/// choice of three, or a name.</summary>
internal static class Ask
{
    /// <summary>One dialog at a time is all WinUI allows; a second waits for none and is simply not shown.</summary>
    private static bool showing;

    public static async Task<ContentDialogResult> Choose(XamlRoot root, string title, string message, string primary, string? secondary = null, string close = "Cancel", bool destructive = false)
    {
        if (showing) return ContentDialogResult.None;
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = title,
            Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, MaxWidth = 440 },
            PrimaryButtonText = primary,
            SecondaryButtonText = secondary ?? "",
            CloseButtonText = close,
            DefaultButton = destructive ? ContentDialogButton.Close : ContentDialogButton.Primary,
        };
        showing = true;
        try { return await dialog.ShowAsync(); }
        finally { showing = false; }
    }

    /// <summary>A name typed in (a folder, a rename): null when cancelled or left blank.</summary>
    public static async Task<string?> Name(XamlRoot root, string title, string action, string initial = "", string? hint = null)
    {
        if (showing) return null;
        var box = new TextBox { Text = initial, Width = 360, PlaceholderText = hint ?? "" };
        box.SelectAll();
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = title,
            Content = box,
            PrimaryButtonText = action,
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
        };
        box.TextChanged += (_, _) => dialog.IsPrimaryButtonEnabled = box.Text.Trim().Length > 0;
        dialog.IsPrimaryButtonEnabled = box.Text.Trim().Length > 0;
        showing = true;
        try { return await dialog.ShowAsync() == ContentDialogResult.Primary ? box.Text.Trim() : null; }
        finally { showing = false; }
    }
}
