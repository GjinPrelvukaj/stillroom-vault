using System.Runtime.InteropServices;

namespace Stillroom.Platform;

/// <summary>Copying a secret (the Mac's `Clipboard`): kept out of Windows' clipboard history and cloud clipboard, marked
/// so clipboard managers skip it, and cleared after 30 seconds if nothing else was copied since. Also cleared at once
/// when the vault locks or Stillroom quits, if it's still the last thing copied.</summary>
internal static unsafe partial class SecretClipboard
{
    /// <summary>The clipboard's sequence number right after Stillroom's last copy; null once cleared or replaced.</summary>
    private static uint? mine;

    public static readonly TimeSpan EmptiesAfter = TimeSpan.FromSeconds(30);

    /// <summary>Copies `text`; gives whether the clipboard took it (another program may hold it open).</summary>
    public static bool Copy(string text, IntPtr owner)
    {
        if (!Open(owner)) return false;
        try
        {
            EmptyClipboard();
            if (!Put(CF_UNICODETEXT, text)) return false;
            // Windows' clipboard history and cloud clipboard skip content marked so (a DWORD 0)...
            PutDword(RegisterClipboardFormatW("CanIncludeInClipboardHistory"), 0);
            PutDword(RegisterClipboardFormatW("CanUploadToCloudClipboard"), 0);
            // ...and clipboard managers skip content carrying this format.
            PutDword(RegisterClipboardFormatW("ExcludeClipboardContentFromMonitorProcessing"), 0);
        }
        finally
        {
            CloseClipboard();
        }
        var copied = GetClipboardSequenceNumber();
        mine = copied;
        _ = Task.Delay(EmptiesAfter).ContinueWith(_ =>
        {
            if (mine == copied) ClearIfOurs();
        }, TaskScheduler.Default);
        return true;
    }

    /// <summary>Empties the clipboard if what's on it is still what Stillroom put there; something copied since is left
    /// alone.</summary>
    public static void ClearIfOurs()
    {
        if (mine is not { } copied) return;
        mine = null;
        if (GetClipboardSequenceNumber() != copied || !Open(IntPtr.Zero)) return;
        try { EmptyClipboard(); }
        finally { CloseClipboard(); }
    }

    /// <summary>Another program may have it open for a moment.</summary>
    private static bool Open(IntPtr owner)
    {
        for (var i = 0; i < 10; i++)
        {
            if (OpenClipboard(owner)) return true;
            Thread.Sleep(20);
        }
        return false;
    }

    private static bool Put(uint format, string text)
    {
        var bytes = (nuint)((text.Length + 1) * 2);
        var memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
        if (memory == IntPtr.Zero) return false;
        var target = (char*)GlobalLock(memory);
        text.AsSpan().CopyTo(new Span<char>(target, text.Length));
        target[text.Length] = '\0';
        GlobalUnlock(memory);
        if (SetClipboardData(format, memory) != IntPtr.Zero) return true;
        GlobalFree(memory);
        return false;
    }

    private static void PutDword(uint format, uint value)
    {
        var memory = GlobalAlloc(GMEM_MOVEABLE, 4);
        if (memory == IntPtr.Zero) return;
        *(uint*)GlobalLock(memory) = value;
        GlobalUnlock(memory);
        if (SetClipboardData(format, memory) == IntPtr.Zero) GlobalFree(memory);
    }

    private const uint CF_UNICODETEXT = 13;
    private const uint GMEM_MOVEABLE = 0x0002;

    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool OpenClipboard(IntPtr owner);
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool CloseClipboard();
    [LibraryImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool EmptyClipboard();
    [LibraryImport("user32.dll")] private static partial IntPtr SetClipboardData(uint format, IntPtr memory);
    [LibraryImport("user32.dll")] private static partial uint GetClipboardSequenceNumber();
    [LibraryImport("user32.dll", StringMarshalling = StringMarshalling.Utf16)] private static partial uint RegisterClipboardFormatW(string name);
    [LibraryImport("kernel32.dll")] private static partial IntPtr GlobalAlloc(uint flags, nuint bytes);
    [LibraryImport("kernel32.dll")] private static partial IntPtr GlobalLock(IntPtr memory);
    [LibraryImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool GlobalUnlock(IntPtr memory);
    [LibraryImport("kernel32.dll")] private static partial IntPtr GlobalFree(IntPtr memory);
}
