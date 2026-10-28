using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Stillroom.Native;

namespace Stillroom.Platform;

/// <summary>Edit in Place (the Mac's `EditDesk`): a file from the vault opens in its own app (Word, Photos, Paint...)
/// from a working copy, and each time that app saves, the copy is sealed back in. Windows has no RAM disk of its own
/// (PORT.md, "Edit in Place"), so the working copy is on disk:
///
///     %LOCALAPPDATA%\Stillroom\Desk\        readable by this account only, left out of Windows Search
///       &lt;random&gt;\name                    one folder per item, the file under its own name so the app's title is right
///
/// A copy is overwritten and then deleted when it's done with, when the vault locks and when Stillroom quits; one left
/// by a crash goes at the next start. On an SSD, overwriting isn't a guarantee the old bytes are gone: BitLocker or
/// Device encryption is what protects them, and the warning before opening says so when it's off.</summary>
internal sealed class EditDesk
{
    public static readonly string Root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Stillroom", "Desk");

    private sealed class Item
    {
        public required string Id;
        public required string File;
        public required string Folder;
        public (DateTime Written, long Size)? Saved;
        public (DateTime Written, long Size)? Seen;
    }

    private readonly Dictionary<string, Item> items = new(StringComparer.OrdinalIgnoreCase);
    private readonly DispatcherQueueTimer tick;
    private readonly Func<Vault?> vault;

    /// <summary>An item being edited changed, or the set of them did (the window's editing bar).</summary>
    public event Action? Changed;

    /// <summary>A save that couldn't be sealed back in: say so.</summary>
    public event Action<string>? Problem;

    public int Count => items.Count;

    public EditDesk(Func<Vault?> vault)
    {
        this.vault = vault;
        // Looked at once a second, as the Mac does: a change that then holds still for a tick is one save.
        tick = DispatcherQueue.GetForCurrentThread().CreateTimer();
        tick.Interval = TimeSpan.FromSeconds(1);
        tick.Tick += (_, _) => Look();
    }

    /// <summary>Puts a working copy out and opens it in its app. Already out: shown again, never written over.</summary>
    public async Task OpenAsync(string id, string name)
    {
        if (items.TryGetValue(id, out var open))
        {
            Launch(open.File);
            return;
        }
        if (vault() is not { } v) return;
        Engine.ProtectFolder(Root);
        MarkNotIndexed(Root);
        var folder = Path.Combine(Root, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        var file = Path.Combine(folder, SafeName(name));
        try
        {
            // The engine's export: the item's own dates, and the Mark of the Web (as the Mac quarantines it), so what
            // runs from it is checked first.
            await Task.Run(() => v.ExportItem(id, file));
        }
        catch
        {
            Wipe(folder);
            throw;
        }
        var item = new Item { Id = id, File = file, Folder = folder };
        item.Saved = item.Seen = Signature(file);
        items[id] = item;
        tick.Start();
        Changed?.Invoke();
        Launch(file);
    }

    /// <summary>Every working copy: a last save looked for, then overwritten and deleted. When the vault locks (still
    /// open, so the last save goes in), when editing is done, and at quit.</summary>
    public void ClearAll()
    {
        foreach (var item in items.Values.ToList())
        {
            if (Signature(item.File) is { } now && now != item.Saved) Seal(item);
            Wipe(item.Folder);
        }
        items.Clear();
        tick.Stop();
        Changed?.Invoke();
        // Anything else in the desk is left from before: a copy an app still held open when it was last cleared.
        ClearLeftovers();
    }

    /// <summary>At start, and after a clear: whatever is still in the desk folder (a crash, an app that held a file
    /// open) is overwritten and deleted now.</summary>
    public static void ClearLeftovers()
    {
        if (!Directory.Exists(Root)) return;
        foreach (var folder in Directory.EnumerateDirectories(Root)) Wipe(folder);
    }

    private void Look()
    {
        foreach (var item in items.Values.ToList())
        {
            // Missing for a moment while an app swaps its new file in: wait for it to land.
            if (Signature(item.File) is not { } now) continue;
            if (now != item.Saved && now == item.Seen)
            {
                item.Saved = now;
                Seal(item);
            }
            item.Seen = now;
        }
    }

    /// <summary>The working copy sealed back in, as a new version of the item.</summary>
    private void Seal(Item item)
    {
        try
        {
            vault()?.UpdateFromFile(item.Id, item.File);
            Changed?.Invoke();
        }
        catch (Exception e) when (e is StillroomException or ObjectDisposedException or IOException)
        {
            // An app still writing, or holding the file shut: tried again on the next tick that sees it change.
            item.Saved = null;
            if (e is StillroomException failure) Problem?.Invoke($"A save couldn't be encrypted back in. {failure.Message}");
        }
    }

    private static (DateTime, long)? Signature(string file)
    {
        try
        {
            var info = new FileInfo(file);
            return info.Exists ? (info.LastWriteTimeUtc, info.Length) : null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
    }

    /// <summary>Each file overwritten with zeros, then the folder deleted. A file an app still holds open stays until
    /// the next clear or start.</summary>
    private static void Wipe(string folder)
    {
        if (!Directory.Exists(folder)) return;
        foreach (var file in Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories))
        {
            try
            {
                using (var stream = new FileStream(file, FileMode.Open, FileAccess.Write, FileShare.None))
                {
                    var zeros = new byte[1 << 16];
                    for (long left = stream.Length; left > 0; left -= zeros.Length) stream.Write(zeros, 0, (int)Math.Min(zeros.Length, left));
                    stream.Flush(flushToDisk: true);
                }
                File.Delete(file);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        try { Directory.Delete(folder, recursive: true); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    private static void Launch(string file)
    {
#if DEBUG
        // Tests put copies out without opening an app on whoever's screen it is (the Mac's tests swap `opener`).
        if (Environment.GetEnvironmentVariable("STILLROOM_DESK_NO_OPEN") is { Length: > 0 }) return;
#endif
        Process.Start(new ProcessStartInfo(file) { UseShellExecute = true });
    }

    /// <summary>Windows Search leaves the desk's contents out of its index.</summary>
    private static void MarkNotIndexed(string folder)
    {
        var info = new DirectoryInfo(folder);
        info.Attributes |= FileAttributes.NotContentIndexed;
    }

    /// <summary>A name can't climb out of its folder or name a device.</summary>
    private static string SafeName(string name)
    {
        var flat = string.Concat(name.Replace('∕', '-').Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '-' : c)).Trim().TrimEnd('.');
        return flat.Length == 0 || flat is "." or ".." ? "Untitled" : flat;
    }

    // MARK: What Windows will do with it

    /// <summary>The app a file of this kind opens in ("Microsoft Word", "Photos"), or null when Windows has none.</summary>
    public static string? AppFor(string name)
    {
        var extension = Path.GetExtension(name);
        if (extension.Length < 2) return null;
        uint length = 256;
        var buffer = new char[length];
        return AssocQueryStringW(ASSOCF_NOTRUNCATE, ASSOCSTR_FRIENDLYAPPNAME, extension, null, buffer, ref length) == 0
            ? new string(buffer, 0, (int)Math.Max(0, length - 1))
            : null;
    }

    /// <summary>Whether the system drive is encrypted (BitLocker or Device encryption), as Explorer shows it; null when
    /// it can't tell. Off means a working copy's bytes could be recovered after it's deleted.</summary>
    public static bool? SystemDriveEncrypted()
    {
        try
        {
            var shellType = Type.GetTypeFromProgID("Shell.Application");
            if (shellType is null) return null;
            dynamic shell = Activator.CreateInstance(shellType)!;
            var drive = Path.GetPathRoot(Environment.SystemDirectory)!;
            object? state = shell.NameSpace(drive)?.Self?.ExtendedProperty("System.Volume.BitLockerProtection");
            // 1 on, 2 off, 3 encrypting, 4 decrypting, 5 suspended, 6 on and locked.
            return state is int value ? value is 1 or 3 or 6 : null;
        }
        catch (Exception) { return null; }
    }

    private const int ASSOCF_NOTRUNCATE = 0x20;
    private const int ASSOCSTR_FRIENDLYAPPNAME = 4;

    [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
    private static extern int AssocQueryStringW(int flags, int str, string assoc, string? extra, [Out] char[] output, ref uint length);
}
