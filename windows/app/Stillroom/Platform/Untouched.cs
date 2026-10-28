using static Stillroom.Platform.Win32;

namespace Stillroom.Platform;

/// <summary>How long the whole PC has gone without a key pressed or the mouse or touchpad moved, for auto-lock. The
/// whole PC, not Stillroom's window, as the Mac does: working on a file in another app for an hour isn't being gone.</summary>
internal static class Untouched
{
    public static TimeSpan For
    {
        get
        {
            var info = new LASTINPUTINFO { cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf<LASTINPUTINFO>() };
            if (!GetLastInputInfo(ref info)) return TimeSpan.Zero;
            // Both are milliseconds since Windows started, wrapping every 49.7 days; the difference survives that.
            return TimeSpan.FromMilliseconds(unchecked((uint)Environment.TickCount - info.dwTime));
        }
    }

    /// <summary>Whether `minutes` (0 is never) have passed untouched.</summary>
    public static bool AutoLockDue(int minutes) => minutes > 0 && For >= TimeSpan.FromMinutes(minutes);
}
