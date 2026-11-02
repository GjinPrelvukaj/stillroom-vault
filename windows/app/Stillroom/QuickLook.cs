using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Stillroom.Platform;

namespace Stillroom;

/// <summary>Any other kind of file, drawn by Windows' own previewer for it (the Mac's `QuickLookView`), as Explorer's
/// preview pane draws it. Only the previewers in `Trusted` are used, for kinds that can't name anything elsewhere
/// (fonts, 3D models): Explorer's others include ones that go online (the HTML one is Internet Explorer's engine, and
/// Word's fetches a document's linked pictures, as tests/lockdown.ps1 found) or that anyone's software may have put
/// there. Each previewer runs in a process of Windows', apart from Stillroom, and draws into a small window of
/// Stillroom's own kept over the card (WinUI's window has no surface for an old-style child window to draw into), so
/// the capture shield covers it as it covers every window Stillroom makes.
///
/// Those previewers read only a file, never bytes in memory, so a copy goes out (`EditDesk.PutOutForLook`, beside Edit
/// in Place's copies): this account's only, out of Windows Search, overwritten and deleted when the card closes, and
/// at lock, quit and the next start whatever happens.</summary>
internal sealed class QuickLook : UserControl
{
    /// <summary>The biggest file put out for a look; past it, a copy or Edit in Place is the way.</summary>
    public const long Largest = 512L << 20;

    /// <summary>Windows' previewers for kinds that hold everything they show. Office's aren't here: Word's previewer
    /// fetched a document's linked picture from a server on this PC (tests/lockdown.ps1), and Excel, PowerPoint and
    /// Visio files can link pictures the same way.</summary>
    private static readonly HashSet<Guid> Trusted =
    [
        new("8A7CAE0E-5951-49CB-BF20-AB3FA1E44B01"), // Windows Font previewer (.ttf, .otf, .ttc, .fon)
        new("E64164EB-1AE0-4C50-BAEF-A413C2B3A4BC"), // Microsoft 3MF previewer
    ];

    private readonly Func<string> stage;
    private readonly Func<UIElement> failed;
    private readonly Grid layout = new();
    private string? file;
    private IntPtr host;
    private IntPtr owner;
    private AppWindow? window;
    private (int, int, int, int) placed;
    private (int, int) sized;
    private bool placing;
    /// <summary>The previewer has drawn, so its window may show.</summary>
    private bool shown;
    private IntPtr handler;
    private bool closed;
    private bool started;

    /// <summary>The previewer has drawn it.</summary>
    public event Action? Shown;

    /// <summary>The previewer couldn't, and `failed` shows instead.</summary>
    public event Action? Failed;

    /// <summary>`stage` puts the copy out and gives its path (off the UI thread); `failed` is what shows instead when
    /// the previewer can't draw it.</summary>
    public QuickLook(Func<string> stage, Func<UIElement> failed)
    {
        this.stage = stage;
        this.failed = failed;
        Content = layout;
        layout.Children.Add(new ProgressRing { IsActive = true, Width = 24, Height = 24 });
        Loaded += (_, _) => _ = Show();
        Unloaded += (_, _) => Close();
        SizeChanged += (_, _) => PlaceSoon();
        LayoutUpdated += (_, _) => PlaceSoon();
    }

    /// <summary>Whether a file of this name has a previewer Stillroom uses.</summary>
    public static bool CanShow(string name) => Handler(name) is { } clsid && Trusted.Contains(clsid);

    private async Task Show()
    {
        // Loaded comes again when the card is moved in the tree: one look per card.
        if (started) return;
        started = true;
        try
        {
            file = await Task.Run(stage);
        }
        catch (Exception)
        {
            Fail();
            return;
        }
        if (closed || XamlRoot is null)
        {
            EditDesk.TakeBack(file);
            return;
        }
        if (Handler(file) is not { } clsid || !Trusted.Contains(clsid) || !Open(clsid, file))
        {
            Fail();
            return;
        }
        Shown?.Invoke();
    }

    /// <summary>The previewer made, given the file and a window to draw in, and drawn. False if any step fails.</summary>
    private unsafe bool Open(Guid clsid, string path)
    {
        layout.Children.Clear();
        var id = XamlRoot.ContentIslandEnvironment.AppWindowId;
        owner = Win32Interop.GetWindowFromWindowId(id);
        // A window of its own, owned by Stillroom's (so it stays just above it, and hides when it's minimized), with
        // no frame, never taking the focus from it. A child of WinUI's window would draw nothing: its window has no
        // surface for old-style drawing, and a layered child turns Windows' own text into black boxes.
        host = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, "STATIC", "", WS_POPUP | WS_CLIPCHILDREN, 0, 0, 1, 1, owner, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        window = AppWindow.GetFromWindowId(id);
        window.Changed += Moved;
        Place();
        var iid = IID_IUnknown;
        // Out of process: Windows runs the previewer in its own host, apart from Stillroom.
        var created = CoCreateInstance(&clsid, IntPtr.Zero, CLSCTX_LOCAL_SERVER, &iid, out var unknown);
        if (created < 0 || host == IntPtr.Zero) return Step($"made {created:X8}, window {host}");
        try
        {
            var initIid = IID_IInitializeWithFile;
            var handlerIid = IID_IPreviewHandler;
            if (Marshal.QueryInterface(unknown, ref initIid, out var init) < 0) return Step("no file reading");
            int done;
            fixed (char* name = path)
                done = ((delegate* unmanaged[Stdcall]<IntPtr, char*, uint, int>)(*(IntPtr**)init)[3])(init, name, STGM_READ);
            Marshal.Release(init);
            if (done < 0) return Step($"file {done:X8}");
            if (Marshal.QueryInterface(unknown, ref handlerIid, out handler) < 0) return Step("not a previewer");
            // Its colours, as Explorer gives them: unset, a previewer draws its words black on black.
            var visualsIid = IID_IPreviewHandlerVisuals;
            if (Marshal.QueryInterface(unknown, ref visualsIid, out var visuals) >= 0)
            {
                var (background, text) = Theme.IsLight ? (0xFFFFFFu, 0x1F1517u) : (0x1E1E1Eu, 0xFFFFFFu);
                var table = *(IntPtr**)visuals;
                ((delegate* unmanaged[Stdcall]<IntPtr, uint, int>)table[3])(visuals, background);
                ((delegate* unmanaged[Stdcall]<IntPtr, uint, int>)table[5])(visuals, text);
                Marshal.Release(visuals);
            }
        }
        finally
        {
            Marshal.Release(unknown);
        }
        var (_, _, width, height) = Visible() ?? (0, 0, 1, 1);
        var rect = new Rect { Right = width, Bottom = height };
        sized = (width, height);
        var vtable = *(IntPtr**)handler;
        var set = ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, Rect*, int>)vtable[3])(handler, host, &rect);
        // Drawing may take a moment the first time (Windows starting the previewer's host); the window waits on it, as
        // Explorer's preview pane does.
        var drawn = set < 0 ? set : ((delegate* unmanaged[Stdcall]<IntPtr, int>)vtable[5])(handler);
        if (drawn < 0) return Step($"window {set:X8}, drawing {drawn:X8}");
        if (!closed)
        {
            shown = true;
            Place();
        }
        return true;
    }

    private void Moved(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (args.DidPositionChange || args.DidSizeChange || args.DidPresenterChange) PlaceSoon();
    }

    /// <summary>`Place`, just after the layout or window change that asked for it, once however often it was asked:
    /// telling the previewer its size is a call to another process, and making one in the middle of WinUI's layout
    /// lets layout start again inside itself, which WinUI ends the app for.</summary>
    private void PlaceSoon()
    {
        if (placing || host == IntPtr.Zero || closed) return;
        placing = true;
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
        {
            placing = false;
            Place();
        });
    }

    /// <summary>The previewer's window kept over the part of this control that shows in the window: what WinUI cuts
    /// off at the window's edge, it cuts off too, and the previewer draws for the size that shows.</summary>
    private unsafe void Place()
    {
        if (host == IntPtr.Zero || closed) return;
        if (Visible() is not { } part)
        {
            ShowWindow(host, SW_HIDE);
            return;
        }
        var (x, y, width, height) = part;
        var corner = new Point { X = x, Y = y };
        ClientToScreen(owner, ref corner);
        if (placed != (corner.X, corner.Y, width, height))
        {
            placed = (corner.X, corner.Y, width, height);
            SetWindowPos(host, IntPtr.Zero, corner.X, corner.Y, width, height, SWP_NOACTIVATE | SWP_NOZORDER);
        }
        if (shown) ShowWindow(host, SW_SHOWNA);
        if (handler != IntPtr.Zero && sized != (width, height))
        {
            sized = (width, height);
            var rect = new Rect { Right = width, Bottom = height };
            ((delegate* unmanaged[Stdcall]<IntPtr, Rect*, int>)(*(IntPtr**)handler)[4])(handler, &rect);
        }
    }

    /// <summary>This control's part inside the window's client area, in its pixels (inset a pixel from the card's
    /// edge); null when none of it shows, or it isn't in the window.</summary>
    private (int X, int Y, int Width, int Height)? Visible()
    {
        if (XamlRoot is null || owner == IntPtr.Zero) return null;
        Windows.Foundation.Point at;
        try { at = TransformToVisual(null).TransformPoint(new Windows.Foundation.Point(0, 0)); }
        catch (ArgumentException) { return null; }
        var scale = XamlRoot.RasterizationScale;
        GetClientRect(owner, out var client);
        int left = (int)Math.Round(at.X * scale) + 1, top = (int)Math.Round(at.Y * scale) + 1;
        int right = Math.Min(client.Right, left + (int)Math.Round(ActualWidth * scale) - 2);
        int bottom = Math.Min(client.Bottom, top + (int)Math.Round(ActualHeight * scale) - 2);
        left = Math.Max(left, 0);
        top = Math.Max(top, 0);
        return right - left < 8 || bottom - top < 8 ? null : (left, top, right - left, bottom - top);
    }

    /// <summary>Which step failed, for the troubleshooting a failed look needs (no names or contents in it).</summary>
    public string? Problem { get; private set; }

    private bool Step(string problem)
    {
        Problem = problem;
        return false;
    }

    private void Fail()
    {
        Release();
        layout.Children.Clear();
        layout.Children.Add(failed());
        Failed?.Invoke();
    }

    /// <summary>The previewer let go of the file, its window gone, then the copy overwritten and deleted.</summary>
    private void Close()
    {
        closed = true;
        Release();
        if (file is not null) EditDesk.TakeBack(file);
    }

    private unsafe void Release()
    {
        if (handler != IntPtr.Zero)
        {
            ((delegate* unmanaged[Stdcall]<IntPtr, int>)(*(IntPtr**)handler)[6])(handler);
            Marshal.Release(handler);
            handler = IntPtr.Zero;
        }
        if (window is not null)
        {
            window.Changed -= Moved;
            window = null;
        }
        if (host != IntPtr.Zero)
        {
            DestroyWindow(host);
            host = IntPtr.Zero;
        }
    }

    /// <summary>The previewer Explorer would use for a file of this name, as its class id.</summary>
    private static Guid? Handler(string name)
    {
        var extension = Path.GetExtension(name);
        if (extension.Length < 2) return null;
        uint length = 64;
        var buffer = new char[length];
        if (AssocQueryStringW(ASSOCF_INIT_DEFAULTTOSTAR, ASSOCSTR_SHELLEXTENSION, extension, PreviewHandlerShellExtension, buffer, ref length) != 0) return null;
        return Guid.TryParse(new string(buffer, 0, (int)Math.Max(0, length - 1)), out var clsid) ? clsid : null;
    }

    // MARK: Windows

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left, Top, Right, Bottom;
    }

    private const string PreviewHandlerShellExtension = "{8895b1c6-b41f-4c1c-a562-0d564250836f}";
    private static readonly Guid IID_IUnknown = new("00000000-0000-0000-C000-000000000046");
    private static readonly Guid IID_IInitializeWithFile = new("b7d14566-0509-4cce-a71f-0a554233bd9b");
    private static readonly Guid IID_IPreviewHandler = new("8895b1c6-b41f-4c1c-a562-0d564250836f");
    private static readonly Guid IID_IPreviewHandlerVisuals = new("196bf9a5-b346-4ef0-aa1e-5dcdb76768b1");
    private const int ASSOCF_INIT_DEFAULTTOSTAR = 0x4;
    private const int ASSOCSTR_SHELLEXTENSION = 16;
    private const uint CLSCTX_LOCAL_SERVER = 0x4;
    private const uint STGM_READ = 0;
    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X, Y;
    }

    private const uint WS_EX_NOACTIVATE = 0x08000000, WS_EX_TOOLWINDOW = 0x80;
    private const uint WS_POPUP = 0x80000000, WS_CLIPCHILDREN = 0x02000000;
    private const uint SWP_NOACTIVATE = 0x10, SWP_NOZORDER = 0x4;
    private const int SW_SHOWNA = 8, SW_HIDE = 0;

    [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
    private static extern int AssocQueryStringW(int flags, int str, string assoc, string? extra, [Out] char[] output, ref uint length);

    [DllImport("ole32.dll")]
    private static extern unsafe int CoCreateInstance(Guid* clsid, IntPtr outer, uint context, Guid* iid, out IntPtr result);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowExW(uint exStyle, string className, string windowName, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);

    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern bool ClientToScreen(IntPtr hwnd, ref Point point);

    [DllImport("user32.dll")]
    private static extern bool GetClientRect(IntPtr hwnd, out Rect rect);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hwnd, int command);
}
