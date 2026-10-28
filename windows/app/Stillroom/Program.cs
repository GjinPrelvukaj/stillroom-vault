using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Stillroom.Native;
using Stillroom.Platform;

namespace Stillroom;

/// <summary>Stillroom's start, before WinUI: Windows' protections go on first, so nothing loads before them.</summary>
internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        var settings = Settings.Load();
        // A crash must never write the process, keys and all, to a dump on disk.
        Engine.ExcludeFromCrashReports();
        // No extension DLLs (keyboard-hook DLLs among them), no DLLs from the network, invalid handles fatal.
        Engine.HardenProcess(settings.BlockExtensionDlls);

        // Files sent from Explorer ("Send to › Move to Stillroom"), if any.
        var (sent, moving) = Inbox.FromArguments(args);

        // One Stillroom at a time: a second start brings the first forward instead, handing it what it was sent.
        using var only = new Mutex(initiallyOwned: true, @"Local\Stillroom", out var first);
        if (!first)
        {
            var running = Win32.FindWindowW(SystemWatch.ClassName, null);
            if (running != IntPtr.Zero)
            {
                Win32.GetWindowThreadProcessId(running, out var process);
                Win32.AllowSetForegroundWindow(process);
                if (sent.Count > 0) SystemWatch.Hand(running, sent, moving);
                Win32.PostMessageW(running, SystemWatch.ComeForward, IntPtr.Zero, IntPtr.Zero);
            }
            return 0;
        }
        Inbox.Receive(sent, moving);

        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(start =>
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            new App(settings);
        });
        return 0;
    }
}
