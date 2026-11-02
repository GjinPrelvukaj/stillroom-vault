using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace Stillroom;

/// <summary>Light, dark, or as Windows is set (the Mac's `Appearance`): a comfort setting, so it's a preference
/// (docs/SECURITY.md rule 3), the same whichever vault is open, and it covers the lock screen too.</summary>
internal enum Appearance { System, Light, Dark }

/// <summary>The window's theme, for what's built in code. XAML uses {ThemeResource …} and follows by itself; a brush
/// made in code is fixed once made, so pages draw themselves again when `Changed` says the theme did.</summary>
internal static class Theme
{
    private static FrameworkElement? root;

    /// <summary>The theme changed: chosen in Settings, or Windows' own while following it.</summary>
    public static event Action? Changed;

    /// <summary>The window's root, whose theme everything inside it takes.</summary>
    public static void Follow(FrameworkElement element, Appearance appearance)
    {
        root = element;
        element.ActualThemeChanged += (_, _) => Changed?.Invoke();
        Set(appearance);
    }

    public static void Set(Appearance appearance)
    {
        if (root is null) return;
        root.RequestedTheme = appearance switch
        {
            Appearance.Light => ElementTheme.Light,
            Appearance.Dark => ElementTheme.Dark,
            _ => ElementTheme.Default,
        };
    }

    public static bool IsLight => root?.ActualTheme == ElementTheme.Light;

    /// <summary>One of App.xaml's theme brushes (VaultBrush, InkBrush, PanelBrush…), as the window's theme has it now.</summary>
    public static Brush Brush(string key)
    {
        var themes = Application.Current.Resources.ThemeDictionaries;
        return (Brush)((ResourceDictionary)themes[IsLight ? "Light" : "Default"])[key];
    }

    /// <summary>Text's own colour at an opacity, as a brush of its own (a shared one mustn't have its opacity changed).</summary>
    public static Brush Ink(double opacity) =>
        new SolidColorBrush(((SolidColorBrush)Brush("InkBrush")).Color) { Opacity = opacity };
}
