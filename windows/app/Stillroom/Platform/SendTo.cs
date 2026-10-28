namespace Stillroom.Platform;

/// <summary>"Move to Stillroom" in Explorer's Send to menu (the Mac's Finder service): a shortcut in this account's
/// SendTo folder that starts Stillroom with "--move" and the chosen files. Only there when the person turns it on.</summary>
internal static class SendTo
{
    private static string Shortcut => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.SendTo), "Move to Stillroom.lnk");

    public static bool IsOn => File.Exists(Shortcut);

    public static void Set(bool on)
    {
        if (!on)
        {
            if (File.Exists(Shortcut)) File.Delete(Shortcut);
            return;
        }
        var app = Environment.ProcessPath ?? throw new InvalidOperationException("Stillroom couldn't find its own program file.");
        var shellType = Type.GetTypeFromProgID("WScript.Shell") ?? throw new InvalidOperationException("Windows Script Host isn't available.");
        dynamic shell = Activator.CreateInstance(shellType)!;
        dynamic link = shell.CreateShortcut(Shortcut);
        link.TargetPath = app;
        link.Arguments = "--move";
        link.IconLocation = app + ",0";
        link.Description = "Encrypt into Stillroom, then delete the originals";
        link.Save();
    }
}
