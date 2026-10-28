using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Stillroom.Native;
using Stillroom.Platform;
using Windows.Graphics;

namespace Stillroom;

/// <summary>One window is the whole app, as on the Mac: closing it quits, and quitting locks. It shows the lock
/// screen or the vault, and every way of locking reaches it: the hot key, the tray, Windows locking or switching
/// user, sleep, the display going off, and auto-lock after the PC has gone untouched.</summary>
public sealed partial class MainWindow : Window
{
    private readonly Settings settings;
    private readonly AppState state;
    private readonly SystemWatch watch;
    private readonly DispatcherQueueTimer autoLock;
    private readonly IntPtr hwnd;
    private LockView? lockView;
    /// <summary>Windows Hello has been asked since the last lock (it's asked once, when the window comes forward).</summary>
    private bool helloAsked;
    /// <summary>The first-time tour has been read (or skipped) this time round.</summary>
    private bool welcomed;

    internal MainWindow(Settings settings)
    {
        this.settings = settings;
        InitializeComponent();
        hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        CaptureShield.Follow(showInCapture: false);

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(TitleBar);
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "Stillroom.ico"));
        var scale = Win32.GetDpiForWindow(hwnd) / 96.0;
        AppWindow.Resize(new SizeInt32((int)(1180 * scale), (int)(760 * scale)));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.PreferredMinimumWidth = (int)(1000 * scale);
            presenter.PreferredMinimumHeight = (int)(660 * scale);
        }

        state = AppState.Open();
        state.Changed += Show;
        // Working copies go with the vault: the last save sealed in while it's still open, then overwritten and deleted.
        Desk = new EditDesk(() => state.Vault);
        state.Locking += Desk.ClearAll;

        watch = new SystemWatch();
        watch.Lock += reason => state.Lock(reason);
        watch.LockAndHide += LockAndHide;
        watch.Show += ComeForward;
        watch.Quit += Close;
        watch.ShowTrayIcon(settings.TrayIcon);

        // Checked every ten seconds, as the Mac does.
        autoLock = DispatcherQueue.CreateTimer();
        autoLock.Interval = TimeSpan.FromSeconds(10);
        autoLock.Tick += (_, _) =>
        {
            if (state.IsOpen && Untouched.AutoLockDue(this.settings.AutoLockMinutes))
                state.Lock($"auto-lock after {this.settings.AutoLockMinutes} min untouched");
        };
        autoLock.Start();

        Activated += (_, e) =>
        {
            if (e.WindowActivationState != WindowActivationState.Deactivated) AskHelloOnce();
        };
        Closed += (_, _) =>
        {
            autoLock.Stop();
            state.Dispose();
            SecretClipboard.ClearIfOurs();
            watch.Dispose();
            CaptureShield.Stop();
        };

        Show();
    }

    /// <summary>The lock screen or the vault, whichever is true now.</summary>
    private void Show()
    {
        watch.Follow(state.IsOpen);
        if (state.IsOpen)
        {
            lockView = null;
            var open = new VaultView(state, this);
            Page.Content = open;
            // An open vault follows its own setting; locked, the window is always hidden from capture.
            CaptureShield.Follow(open.ShowInCapture);
        }
        else
        {
            // A secret copied a moment ago goes with the vault, if it's still the last thing copied.
            SecretClipboard.ClearIfOurs();
            CaptureShield.Follow(showInCapture: false);
            helloAsked = false;
            // No vault yet: the tour first, each time, as the Mac does.
            if (!welcomed && !state.Store.Exists && !state.Store.IsOldFormat)
            {
                lockView = null;
                Page.Content = new WelcomeTour(LockHotKey, () => { welcomed = true; Show(); });
                return;
            }
            lockView = new LockView(state, this);
            Page.Content = lockView;
            AskHelloOnce();
        }
    }

    /// <summary>Windows Hello at once when it's on, as the Mac asks Touch ID: but only with the window in front, so
    /// a lock from the hot key doesn't bring a prompt up over whatever is in front instead.</summary>
    private void AskHelloOnce()
    {
        if (helloAsked || state.IsOpen || lockView is null || Win32.GetForegroundWindow() != hwnd) return;
        helloAsked = true;
        lockView.AskHelloIfOn();
    }

    /// <summary>Shut and out of sight in one go: the hot key from any app, or the tray's menu.</summary>
    private void LockAndHide()
    {
        state.Lock("lock shortcut");
        if (AppWindow.Presenter is OverlappedPresenter presenter) presenter.Minimize();
    }

    /// <summary>The tray's Show, or a second copy of Stillroom started.</summary>
    private void ComeForward()
    {
        if (AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Minimized } presenter) presenter.Restore();
        AppWindow.Show();
        Win32.SetForegroundWindow(hwnd);
        Activate();
    }

    internal IntPtr Handle => hwnd;

    /// <summary>Files open for editing in their own apps.</summary>
    internal EditDesk Desk { get; }

    /// <summary>The app's preferences, changed by Settings and saved there.</summary>
    internal Settings Settings => settings;

    /// <summary>The tray icon shown or not (Settings).</summary>
    internal void ShowTrayIcon(bool show) => watch.ShowTrayIcon(show);

    /// <summary>The open vault's capture setting changed (Settings).</summary>
    internal void FollowCapture(bool showInCapture) => CaptureShield.Follow(state.IsOpen && showInCapture);

    /// <summary>The hot key's name, or null when another app has it.</summary>
    internal string? LockHotKey => watch.HotKeyRegistered ? SystemWatch.HotKeyName : null;
}
