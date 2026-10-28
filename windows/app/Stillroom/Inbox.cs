namespace Stillroom;

/// <summary>Files sent to Stillroom from outside it (the Mac's `Inbox`): Explorer's "Send to › Move to Stillroom", which
/// starts Stillroom with them or hands them to the copy already running. They wait here until the vault is open, then
/// go in.</summary>
internal static class Inbox
{
    private static readonly List<string> waiting = [];
    private static bool moving;

    /// <summary>Something arrived (on the UI thread).</summary>
    public static event Action? Changed;

    public static int Count => waiting.Count;

    /// <summary>`moving`: the originals go once they're in ("Move to Stillroom").</summary>
    public static void Receive(IEnumerable<string> paths, bool move)
    {
        var fresh = paths.Where(p => p.Length > 0 && !waiting.Contains(p, StringComparer.OrdinalIgnoreCase)).ToList();
        if (fresh.Count == 0) return;
        waiting.AddRange(fresh);
        moving |= move;
        Changed?.Invoke();
    }

    /// <summary>Everything waiting, handed over once.</summary>
    public static (List<string> Paths, bool Moving) Take()
    {
        var taken = (waiting.ToList(), moving);
        waiting.Clear();
        moving = false;
        return taken;
    }

    /// <summary>The command line Explorer's Send to gives: "--move" then the paths.</summary>
    public static (List<string> Paths, bool Moving) FromArguments(IReadOnlyList<string> args)
    {
        var move = args.Count > 0 && args[0] == "--move";
        return (args.Skip(move ? 1 : 0).Where(a => File.Exists(a) || Directory.Exists(a)).ToList(), move);
    }
}
