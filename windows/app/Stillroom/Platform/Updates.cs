using System.Diagnostics;
using System.Globalization;
using System.Reflection;

namespace Stillroom.Platform;

/// <summary>How people hear about a new version, since Stillroom never connects (the Mac's `Updates`). Check for
/// Updates opens the changelog in the browser with this version in the address, and that page says whether a newer one
/// is out: the browser makes the connection, never the app. And from the build date alone, offline, Settings says when
/// this copy is getting old.</summary>
internal static class Updates
{
    /// <summary>This copy's version (the project's &lt;Version&gt;), without a build's commit suffix.</summary>
    public static string Version =>
        (typeof(Updates).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0.0.0").Split('+')[0];

    /// <summary>The day this copy was built (written into release builds by Stillroom.csproj). Null in a debug build.</summary>
    public static DateTime? Built =>
        typeof(Updates).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>().FirstOrDefault(a => a.Key == "StillroomBuilt")?.Value is { } day
        && DateTime.TryParseExact(day, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var built) ? built : null;

    /// <summary>After this long, Settings suggests looking for a newer version.</summary>
    public const int OldAfterDays = 180;

    /// <summary>The Mac's address with `os=windows`, so the page can tell a Windows copy's version from a Mac's.</summary>
    public static string PageUrl(string version) => $"https://stillroomvault.com/changelog/?v={Uri.EscapeDataString(version)}&os=windows";

    /// <summary>Opens the release notes in the browser; Stillroom itself connects to nothing.</summary>
    public static void Check() => Process.Start(new ProcessStartInfo(PageUrl(Version)) { UseShellExecute = true });

    public static bool IsOld(DateTime? built, DateTime now) => built is { } day && (now - day).TotalDays > OldAfterDays;

    /// <summary>The line under Check for Updates in Settings.</summary>
    public static string Detail()
    {
        if (Built is not { } built) return $"Version {Version}. Opens the release notes in your browser, which say whether a newer one is out.";
        var month = built.ToString("MMMM yyyy", CultureInfo.CurrentCulture);
        return IsOld(built, DateTime.Now)
            ? $"Version {Version}, from {month}: over six months old, so there may well be a newer one. Opens the release notes in your browser."
            : $"Version {Version}, from {month}. Opens the release notes in your browser, which say whether a newer one is out.";
    }
}
