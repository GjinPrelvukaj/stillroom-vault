using Microsoft.UI.Xaml;
using Stillroom.Platform;

namespace Stillroom;

public partial class App : Application
{
    private readonly Settings settings;

    /// <summary>The one window, for what needs its handle (the clipboard's owner, pickers).</summary>
    internal static MainWindow? Window { get; private set; }

    internal App(Settings settings)
    {
        this.settings = settings;
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // Before the window: every window this process makes is kept out of capture as it's made.
        CaptureShield.Start();
        // Working copies a crash left behind go before anything else happens.
        EditDesk.ClearLeftovers();
        Window = new MainWindow(settings);
        Window.Activate();
    }
}
