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
#if DEBUG
        if (Environment.GetEnvironmentVariable("STILLROOM_READ_WORDS") is { Length: > 0 } read)
        {
            ShowAlone.ReadWords(read);
            return;
        }
        // tests/lockdown.ps1: one file in its viewer, alone, with no vault.
        if (Environment.GetEnvironmentVariable("STILLROOM_SHOW_FILE") is { Length: > 0 } shown)
        {
            ShowAlone.Show(shown);
            return;
        }
#endif
        Window = new MainWindow(settings);
        Window.Activate();
    }
}
