using System.Runtime.InteropServices;
using static Stillroom.Platform.Win32;

namespace Stillroom.Platform;

/// <summary>A window of Stillroom's own, never shown, that hears Windows: the lock hot key from any app, the tray
/// icon and its menu, Windows locking or switching user, the PC going to sleep, the display going off, and a second
/// copy of Stillroom asking this one to come forward. Made on the UI thread, so everything it raises arrives there.
/// The Mac does the same with `LockKey`, `MenuBarExtra` and `RootView`'s sleep and screen-lock notifications.</summary>
internal sealed unsafe partial class SystemWatch : IDisposable
{
    public const string ClassName = "Stillroom.SystemWatch";

    /// <summary>Sent by a second copy of Stillroom, started while this one runs: come forward instead.</summary>
    public const uint ComeForward = WM_APP + 2;

    private const uint WM_COPYDATA = 0x004A;
    /// <summary>Marks a WM_COPYDATA as Stillroom's list of paths (any other is ignored).</summary>
    private static readonly IntPtr CopyPaths = 0x53524D31; // "SRM1"

    [StructLayout(LayoutKind.Sequential)]
    private struct COPYDATASTRUCT
    {
        public IntPtr dwData;
        public uint cbData;
        public IntPtr lpData;
    }

    [LibraryImport("user32.dll")]
    private static partial IntPtr SendMessageW(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    /// <summary>From a second Stillroom: hands the copy already running the paths it was started with.</summary>
    public static void Hand(IntPtr running, IReadOnlyList<string> paths, bool moving)
    {
        var text = (moving ? "1" : "0") + "\0" + string.Join('\0', paths) + "\0";
        fixed (char* data = text)
        {
            var copy = new COPYDATASTRUCT { dwData = CopyPaths, cbData = (uint)(text.Length * 2), lpData = (IntPtr)data };
            SendMessageW(running, WM_COPYDATA, IntPtr.Zero, (IntPtr)(&copy));
        }
    }

    /// <summary>⌃⌥⌘L on the Mac. Win+L is Windows' own lock, so Shift stands in for ⌘ here.</summary>
    public const string HotKeyName = "Ctrl+Alt+Shift+L";

    private const uint TrayMessage = WM_APP + 1;
    private const int HotKeyId = 1;
    private const uint TrayId = 1;
    private const nuint MenuLock = 1, MenuShow = 2, MenuQuit = 3;

    private static SystemWatch? current;

    private readonly IntPtr hwnd;
    private readonly IntPtr suspendNotification;
    private readonly IntPtr displayNotification;
    private readonly uint taskbarCreated;
    private IntPtr icon;
    private bool trayShown;
    private bool open;

    /// <summary>Windows locked, the PC going to sleep, the display going off: lock, with why.</summary>
    public event Action<string>? Lock;

    /// <summary>The hot key, or Lock and Hide in the tray menu.</summary>
    public event Action? LockAndHide;

    public event Action? Show;
    public event Action? Quit;

    /// <summary>Whether the hot key is Stillroom's: another app may have it already, and then the tray's menu still locks.</summary>
    public bool HotKeyRegistered { get; }

    public SystemWatch()
    {
        current = this;
        var instance = GetModuleHandleW(null);
        fixed (char* name = ClassName)
        {
            var windowClass = new WNDCLASSEXW
            {
                cbSize = (uint)sizeof(WNDCLASSEXW),
                lpfnWndProc = &WindowProc,
                hInstance = instance,
                lpszClassName = name,
            };
            RegisterClassExW(&windowClass);
        }
        // Top-level rather than message-only: sleep and display broadcasts only reach top-level windows.
        hwnd = CreateWindowExW(WS_EX_TOOLWINDOW, ClassName, "Stillroom", WS_POPUP, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, instance, IntPtr.Zero);
        if (hwnd == IntPtr.Zero) throw new InvalidOperationException($"No window to hear Windows with ({Marshal.GetLastPInvokeError()}).");

        HotKeyRegistered = RegisterHotKey(hwnd, HotKeyId, MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT, 'L');
        WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION);
        // Modern Standby PCs only tell windows that asked that they're going to sleep.
        suspendNotification = RegisterSuspendResumeNotification(hwnd, DEVICE_NOTIFY_WINDOW_HANDLE);
        var display = GUID_CONSOLE_DISPLAY_STATE;
        displayNotification = RegisterPowerSettingNotification(hwnd, &display, DEVICE_NOTIFY_WINDOW_HANDLE);
        // Explorer restarting takes every tray icon with it, and says so with this message.
        taskbarCreated = RegisterWindowMessageW("TaskbarCreated");
    }

    /// <summary>Whether the tray icon is there.</summary>
    public void ShowTrayIcon(bool show)
    {
        if (show == trayShown) return;
        var data = TrayData();
        if (show)
        {
            Shell_NotifyIconW(NIM_ADD, &data);
            data.uVersion = NOTIFYICON_VERSION_4;
            Shell_NotifyIconW(NIM_SETVERSION, &data);
        }
        else
        {
            Shell_NotifyIconW(NIM_DELETE, &data);
        }
        trayShown = show;
    }

    /// <summary>Whether the vault is open, for the tray's words and menu.</summary>
    public void Follow(bool isOpen)
    {
        open = isOpen;
        if (!trayShown) return;
        var data = TrayData();
        Shell_NotifyIconW(NIM_MODIFY, &data);
    }

    private NOTIFYICONDATAW TrayData()
    {
        if (icon == IntPtr.Zero)
        {
            icon = LoadImageW(IntPtr.Zero, Path.Combine(AppContext.BaseDirectory, "Assets", "Stillroom.ico"), IMAGE_ICON,
                GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE);
        }
        var data = new NOTIFYICONDATAW
        {
            cbSize = (uint)sizeof(NOTIFYICONDATAW),
            hWnd = hwnd,
            uID = TrayId,
            uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP,
            uCallbackMessage = TrayMessage,
            hIcon = icon,
        };
        var tip = open ? "Stillroom is open" : "Stillroom is locked";
        tip.AsSpan().CopyTo(new Span<char>(data.szTip, 127));
        return data;
    }

    /// <summary>The tray's menu, at the pointer: as the Mac's menu bar icon.</summary>
    private void ShowMenu()
    {
        var menu = CreatePopupMenu();
        try
        {
            if (open) AppendMenuW(menu, MF_STRING, MenuLock, HotKeyRegistered ? $"Lock and Hide Stillroom\t{HotKeyName}" : "Lock and Hide Stillroom");
            else AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, "Stillroom is locked");
            AppendMenuW(menu, MF_STRING, MenuShow, "Show Stillroom");
            AppendMenuW(menu, MF_SEPARATOR, 0, null);
            AppendMenuW(menu, MF_STRING, MenuQuit, "Quit Stillroom");
            GetCursorPos(out var at);
            // Without this the menu stays up when clicking elsewhere (a long-standing Windows quirk).
            SetForegroundWindow(hwnd);
            var chosen = TrackPopupMenuEx(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, at.X, at.Y, hwnd, IntPtr.Zero);
            PostMessageW(hwnd, WM_NULL, IntPtr.Zero, IntPtr.Zero);
            switch (chosen)
            {
                case (uint)MenuLock: LockAndHide?.Invoke(); break;
                case (uint)MenuShow: Show?.Invoke(); break;
                case (uint)MenuQuit: Quit?.Invoke(); break;
            }
        }
        finally
        {
            DestroyMenu(menu);
        }
    }

    /// <summary>What Windows said; true when it was handled here.</summary>
    private bool Heard(uint message, IntPtr wParam, IntPtr lParam)
    {
        switch (message)
        {
            case WM_HOTKEY when wParam == HotKeyId:
                LockAndHide?.Invoke();
                return true;
            case WM_WTSSESSION_CHANGE:
                // Locked, or switched away from (another user at this PC, or a remote session cut).
                if ((int)wParam is WTS_SESSION_LOCK or WTS_CONSOLE_DISCONNECT or WTS_REMOTE_DISCONNECT) Lock?.Invoke("Windows locked");
                return true;
            case WM_POWERBROADCAST:
                if ((int)wParam == PBT_APMSUSPEND) Lock?.Invoke("going to sleep");
                if ((int)wParam == PBT_POWERSETTINGCHANGE)
                {
                    var setting = (POWERBROADCAST_SETTING*)lParam;
                    if (setting->PowerSetting == GUID_CONSOLE_DISPLAY_STATE && setting->Data == 0) Lock?.Invoke("display off");
                }
                return true;
            case TrayMessage:
                switch ((uint)LowWord(lParam))
                {
                    case WM_CONTEXTMENU: ShowMenu(); break;
                    case NIN_SELECT or NIN_KEYSELECT: Show?.Invoke(); break;
                }
                return true;
            case ComeForward:
                Show?.Invoke();
                return true;
            case WM_COPYDATA when lParam != IntPtr.Zero:
                // Paths from a second Stillroom started by Explorer's Send to: "1" or "0" (moving) then the paths,
                // each ended by a null.
                var copied = (COPYDATASTRUCT*)lParam;
                if (copied->dwData != CopyPaths || copied->lpData == IntPtr.Zero) return false;
                var text = new string((char*)copied->lpData, 0, (int)(copied->cbData / 2));
                var parts = text.Split('\0', StringSplitOptions.RemoveEmptyEntries);
                if (parts.Length > 1) Inbox.Receive(parts[1..].Where(p => File.Exists(p) || Directory.Exists(p)), parts[0] == "1");
                return true;
        }
        if (message == taskbarCreated && trayShown)
        {
            trayShown = false;
            ShowTrayIcon(true);
            return true;
        }
        return false;
    }

    [UnmanagedCallersOnly]
    private static IntPtr WindowProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam)
    {
        try
        {
            // Sleep and display messages want TRUE back; the rest don't look.
            if (current is { } watch && hwnd == watch.hwnd && watch.Heard(message, wParam, lParam)) return 1;
        }
        catch (Exception e)
        {
            // Nothing may escape into Windows' call; locking on what follows still works.
            System.Diagnostics.Debug.WriteLine($"SystemWatch: {e}");
        }
        return DefWindowProcW(hwnd, message, wParam, lParam);
    }

    public void Dispose()
    {
        ShowTrayIcon(false);
        if (HotKeyRegistered) UnregisterHotKey(hwnd, HotKeyId);
        WTSUnRegisterSessionNotification(hwnd);
        if (suspendNotification != IntPtr.Zero) UnregisterSuspendResumeNotification(suspendNotification);
        if (displayNotification != IntPtr.Zero) UnregisterPowerSettingNotification(displayNotification);
        DestroyWindow(hwnd);
        if (icon != IntPtr.Zero) DestroyIcon(icon);
        current = null;
    }
}
