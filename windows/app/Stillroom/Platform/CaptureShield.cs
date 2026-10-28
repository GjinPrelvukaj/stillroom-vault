using System.Runtime.InteropServices;
using static Stillroom.Platform.Win32;

namespace Stillroom.Platform;

/// <summary>Keeps Stillroom out of screenshots, screen recordings and screen sharing: every top-level window this
/// process makes is excluded from capture as it's made, menus and flyouts included (WinUI draws those in windows of
/// their own). The lock screen is always hidden; an open vault follows its own "show in screenshots" setting.</summary>
internal static unsafe class CaptureShield
{
    private static IntPtr hook;
    private static volatile bool visible;
    private static readonly uint process = (uint)Environment.ProcessId;

    /// <summary>Call once, on the UI thread, before the first window is made.</summary>
    public static void Start()
    {
        hook = SetWinEventHook(EVENT_OBJECT_CREATE, EVENT_OBJECT_SHOW, IntPtr.Zero, &Seen, process, 0, WINEVENT_OUTOFCONTEXT);
    }

    /// <summary>Hidden (the default, and always while locked) or visible to capture, for every window there is now
    /// and every one made after.</summary>
    public static void Follow(bool showInCapture)
    {
        visible = showInCapture;
        EnumWindows(&Each, IntPtr.Zero);
    }

    public static void Stop()
    {
        if (hook != IntPtr.Zero) UnhookWinEvent(hook);
        hook = IntPtr.Zero;
    }

    private static void Apply(IntPtr hwnd)
    {
        GetWindowThreadProcessId(hwnd, out var owner);
        if (owner == process && GetAncestor(hwnd, GA_ROOT) == hwnd)
            SetWindowDisplayAffinity(hwnd, visible ? WDA_NONE : WDA_EXCLUDEFROMCAPTURE);
    }

    [UnmanagedCallersOnly]
    private static void Seen(IntPtr hook, uint @event, IntPtr hwnd, int objectId, int childId, uint thread, uint time)
    {
        // Made, then shown: both, so a window is covered before its first frame and again if it was made elsewhere.
        if (hwnd != IntPtr.Zero && objectId == OBJID_WINDOW && childId == 0 && @event != EVENT_OBJECT_DESTROY) Apply(hwnd);
    }

    [UnmanagedCallersOnly]
    private static int Each(IntPtr hwnd, IntPtr param)
    {
        Apply(hwnd);
        return 1;
    }
}
