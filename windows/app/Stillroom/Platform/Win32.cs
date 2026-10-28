// The parts of Win32 the window's protections use: the capture shield, the hot key, the tray icon, and hearing when
// Windows locks, sleeps or turns the display off. Values are from winuser.h, shellapi.h, wtsapi32.h and winnt.h.

using System.Runtime.InteropServices;

namespace Stillroom.Platform;

internal static unsafe partial class Win32
{
    // Messages
    public const uint WM_NULL = 0x0000;
    public const uint WM_DESTROY = 0x0002;
    public const uint WM_COMMAND = 0x0111;
    public const uint WM_CONTEXTMENU = 0x007B;
    public const uint WM_LBUTTONUP = 0x0202;
    public const uint WM_HOTKEY = 0x0312;
    public const uint WM_POWERBROADCAST = 0x0218;
    public const uint WM_WTSSESSION_CHANGE = 0x02B1;
    public const uint WM_APP = 0x8000;

    // Capture shield
    public const uint WDA_NONE = 0x00;
    public const uint WDA_EXCLUDEFROMCAPTURE = 0x11;

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool SetWindowDisplayAffinity(IntPtr hwnd, uint affinity);

    // Every window this process makes, as it's made (flyouts and menus are windows of their own).
    public const uint EVENT_OBJECT_CREATE = 0x8000;
    public const uint EVENT_OBJECT_DESTROY = 0x8001;
    public const uint EVENT_OBJECT_SHOW = 0x8002;
    public const uint WINEVENT_OUTOFCONTEXT = 0x0000;
    public const int OBJID_WINDOW = 0;
    public const uint GA_ROOT = 2;

    [LibraryImport("user32.dll")]
    public static partial IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr module,
        delegate* unmanaged<IntPtr, uint, IntPtr, int, int, uint, uint, void> callback, uint processId, uint threadId, uint flags);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool UnhookWinEvent(IntPtr hook);

    [LibraryImport("user32.dll")]
    public static partial IntPtr GetAncestor(IntPtr hwnd, uint flags);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool EnumWindows(delegate* unmanaged<IntPtr, IntPtr, int> callback, IntPtr param);

    // A window of our own, never shown, to hear Windows
    public const uint WS_POPUP = 0x80000000;
    public const uint WS_EX_TOOLWINDOW = 0x00000080;

    [StructLayout(LayoutKind.Sequential)]
    public struct WNDCLASSEXW
    {
        public uint cbSize;
        public uint style;
        public delegate* unmanaged<IntPtr, uint, IntPtr, IntPtr, IntPtr> lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public char* lpszMenuName;
        public char* lpszClassName;
        public IntPtr hIconSm;
    }

    [LibraryImport("user32.dll", SetLastError = true)]
    public static partial ushort RegisterClassExW(WNDCLASSEXW* windowClass);

    [LibraryImport("user32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    public static partial IntPtr CreateWindowExW(uint exStyle, string className, string windowName, uint style,
        int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool DestroyWindow(IntPtr hwnd);

    [LibraryImport("user32.dll")]
    public static partial IntPtr DefWindowProcW(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [LibraryImport("user32.dll", StringMarshalling = StringMarshalling.Utf16)]
    public static partial IntPtr FindWindowW(string className, string? windowName);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool PostMessageW(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [LibraryImport("user32.dll", StringMarshalling = StringMarshalling.Utf16)]
    public static partial uint RegisterWindowMessageW(string name);

    [LibraryImport("kernel32.dll", StringMarshalling = StringMarshalling.Utf16)]
    public static partial IntPtr GetModuleHandleW(string? name);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool SetForegroundWindow(IntPtr hwnd);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool AllowSetForegroundWindow(uint processId);

    [LibraryImport("user32.dll")]
    public static partial IntPtr GetForegroundWindow();

    [LibraryImport("user32.dll")]
    public static partial uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    // The lock hot key
    public const uint MOD_ALT = 0x0001;
    public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_SHIFT = 0x0004;
    public const uint MOD_NOREPEAT = 0x4000;

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool UnregisterHotKey(IntPtr hwnd, int id);

    // Windows locking, switching user, sleeping, and the display going off
    public const uint NOTIFY_FOR_THIS_SESSION = 0;
    public const int WTS_CONSOLE_DISCONNECT = 0x2;
    public const int WTS_REMOTE_DISCONNECT = 0x4;
    public const int WTS_SESSION_LOCK = 0x7;
    public const int PBT_APMSUSPEND = 0x4;
    public const int PBT_POWERSETTINGCHANGE = 0x8013;
    public const uint DEVICE_NOTIFY_WINDOW_HANDLE = 0;
    public static readonly Guid GUID_CONSOLE_DISPLAY_STATE = new("6FE69556-704A-47A0-8F24-C28D936FDA47");

    [StructLayout(LayoutKind.Sequential)]
    public struct POWERBROADCAST_SETTING
    {
        public Guid PowerSetting;
        public uint DataLength;
        public uint Data;
    }

    [LibraryImport("wtsapi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool WTSRegisterSessionNotification(IntPtr hwnd, uint flags);

    [LibraryImport("wtsapi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool WTSUnRegisterSessionNotification(IntPtr hwnd);

    [LibraryImport("user32.dll")]
    public static partial IntPtr RegisterSuspendResumeNotification(IntPtr recipient, uint flags);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool UnregisterSuspendResumeNotification(IntPtr handle);

    [LibraryImport("user32.dll")]
    public static partial IntPtr RegisterPowerSettingNotification(IntPtr recipient, Guid* setting, uint flags);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool UnregisterPowerSettingNotification(IntPtr handle);

    // Untouched for how long
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool GetLastInputInfo(ref LASTINPUTINFO info);

    // The tray icon
    public const uint NIM_ADD = 0x0;
    public const uint NIM_MODIFY = 0x1;
    public const uint NIM_DELETE = 0x2;
    public const uint NIM_SETVERSION = 0x4;
    public const uint NIF_MESSAGE = 0x01;
    public const uint NIF_ICON = 0x02;
    public const uint NIF_TIP = 0x04;
    public const uint NIF_SHOWTIP = 0x80;
    public const uint NOTIFYICON_VERSION_4 = 4;
    public const uint NIN_SELECT = 0x0400;
    public const uint NIN_KEYSELECT = 0x0401;

    [StructLayout(LayoutKind.Sequential)]
    public struct NOTIFYICONDATAW
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public IntPtr hIcon;
        public fixed char szTip[128];
        public uint dwState;
        public uint dwStateMask;
        public fixed char szInfo[256];
        public uint uVersion;
        public fixed char szInfoTitle[64];
        public uint dwInfoFlags;
        public Guid guidItem;
        public IntPtr hBalloonIcon;
    }

    [LibraryImport("shell32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool Shell_NotifyIconW(uint message, NOTIFYICONDATAW* data);

    public const uint IMAGE_ICON = 1;
    public const uint LR_LOADFROMFILE = 0x10;
    public const int SM_CXSMICON = 49;
    public const int SM_CYSMICON = 50;

    [LibraryImport("user32.dll", StringMarshalling = StringMarshalling.Utf16)]
    public static partial IntPtr LoadImageW(IntPtr instance, string name, uint type, int width, int height, uint flags);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool DestroyIcon(IntPtr icon);

    [LibraryImport("user32.dll")]
    public static partial int GetSystemMetrics(int index);

    [LibraryImport("user32.dll")]
    public static partial uint GetDpiForWindow(IntPtr hwnd);

    // The tray icon's menu
    public const uint MF_STRING = 0x0000;
    public const uint MF_GRAYED = 0x0001;
    public const uint MF_SEPARATOR = 0x0800;
    public const uint TPM_RIGHTBUTTON = 0x0002;
    public const uint TPM_RETURNCMD = 0x0100;
    public const uint TPM_BOTTOMALIGN = 0x0020;

    [LibraryImport("user32.dll")]
    public static partial IntPtr CreatePopupMenu();

    [LibraryImport("user32.dll", StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool AppendMenuW(IntPtr menu, uint flags, nuint id, string? text);

    [LibraryImport("user32.dll")]
    public static partial uint TrackPopupMenuEx(IntPtr menu, uint flags, int x, int y, IntPtr hwnd, IntPtr parameters);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool DestroyMenu(IntPtr menu);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool GetCursorPos(out POINT point);

    public static short LowWord(IntPtr value) => (short)((long)value & 0xFFFF);
}
