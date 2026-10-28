using System.Text.Json;
using System.Text.Json.Serialization;

namespace Stillroom;

/// <summary>The app's preferences (the Mac keeps them in UserDefaults): %APPDATA%\Stillroom\settings.json, beside the
/// vault folder and tries.json. Nothing here says anything about what's in the vault, or which slot is open.</summary>
internal sealed class Settings
{
    /// <summary>Minutes untouched before the vault locks; 0 is never. As the Mac: 1, 5, 15, 60 or never; 5 to begin.</summary>
    [JsonPropertyName("autoLockMinutes")] public int AutoLockMinutes { get; set; } = 5;

    /// <summary>The icon in the notification area (the Mac's menu bar icon).</summary>
    [JsonPropertyName("trayIcon")] public bool TrayIcon { get; set; } = true;

    /// <summary>Windows' extension DLLs kept out of the app (keyboard-hook DLLs among them). Turning it off is for people
    /// who type with an input method editor, which it also keeps out. Takes effect the next time Stillroom starts.</summary>
    [JsonPropertyName("blockExtensionDlls")] public bool BlockExtensionDlls { get; set; } = true;

    /// <summary>A photo with each wrong try in the intruder log, when Windows lets desktop apps use the camera.</summary>
    [JsonPropertyName("intruderPhoto")] public bool IntruderPhoto { get; set; } = true;

    /// <summary>How many intruder log entries had been seen when it was last opened: more since, and the sidebar
    /// shows it. The log is the same in either vault, so this says nothing about which one is open.</summary>
    [JsonPropertyName("intrudersSeen")] public int IntrudersSeen { get; set; }

    /// <summary>Edit in Place opens without first saying what it gives away (the Mac's "Don't ask again").</summary>
    [JsonPropertyName("editWarningOff")] public bool EditWarningOff { get; set; }

    public static readonly int[] AutoLockChoices = [1, 5, 15, 60, 0];

    public static string AutoLockName(int minutes) => minutes switch
    {
        0 => "Never",
        1 => "After 1 minute",
        60 => "After 1 hour",
        _ => $"After {minutes} minutes",
    };

    private static string Folder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Stillroom");
    private static string FilePath => Path.Combine(Folder, "settings.json");

    /// <summary>What was saved, or the defaults when there's nothing (or nothing readable) yet.</summary>
    public static Settings Load()
    {
        try { return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings(); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return new Settings(); }
    }

    /// <summary>Written whole beside itself and then moved over, so a crash never leaves half a file.</summary>
    public void Save()
    {
        Directory.CreateDirectory(Folder);
        var staged = FilePath + ".new";
        File.WriteAllText(staged, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(staged, FilePath, overwrite: true);
    }
}
