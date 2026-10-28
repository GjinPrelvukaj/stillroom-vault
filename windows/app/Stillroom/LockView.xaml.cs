using System.Security.Cryptography;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Stillroom.Native;
using Stillroom.Platform;
using Windows.Storage.Pickers;

namespace Stillroom;

/// <summary>The lock screen (the Mac's `LockView`). Windows Hello is asked at once when it's on; the password is
/// always there, and the recovery key and emergency kit. Every secret is typed on the secure desktop, not here. After a
/// few wrong tries, each next try waits longer (the engine's TryLimit, kept beside the vault folder).</summary>
public sealed partial class LockView : UserControl
{
    private readonly AppState state;
    private readonly MainWindow window;
    private readonly DispatcherQueueTimer clock;
    /// <summary>Typing the recovery key instead of the password.</summary>
    private bool recovering;
    /// <summary>Typing pieces of the emergency kit instead.</summary>
    private bool usingKit;
    private bool working;
    private bool helloAvailable;
    private string? problem;

    private bool OldFormat => state.Store.IsOldFormat;
    private bool Making => !state.Store.Exists && !OldFormat;

    /// <summary>One attempt's outcome: a vault opened, or a problem to show that wasn't a wrong try.</summary>
    private sealed record Attempt(Vault? Opened, string? RecoveryKey = null, string? Problem = null);

    internal LockView(AppState state, MainWindow window)
    {
        this.state = state;
        this.window = window;
        InitializeComponent();
        problem = state.LockNotice;
        state.LockNotice = null;
        // While a try has to wait, the line counts down each second.
        clock = DispatcherQueue.CreateTimer();
        clock.Interval = TimeSpan.FromSeconds(1);
        clock.Tick += (_, _) => Refresh();
        Loaded += async (_, _) =>
        {
            helloAvailable = await WindowsHello.IsAvailableAsync();
            Refresh();
        };
        Unloaded += (_, _) => { clock.Stop(); Inbox.Changed -= Refresh; };
        Inbox.Changed += Refresh;
        Refresh();
    }

    private void Refresh()
    {
        var making = Making;
        var wait = making ? TimeSpan.Zero : state.Store.WaitBeforeNextTry;
        var helloOn = !making && !recovering && !usingKit && state.Store.HelloChallenge() is not null;

        Waiting.Visibility = Inbox.Count > 0 && !OldFormat ? Visibility.Visible : Visibility.Collapsed;
        WaitingText.Text = $"Unlock to put {Inbox.Count} {(Inbox.Count == 1 ? "item" : "items")} in the vault.";

        Heading.Text = making ? "Make your vault" : recovering ? "Use your recovery key" : usingKit ? "Use the emergency kit" : "Stillroom is locked";
        Body.Text = making ? "Pick a password you won't forget. Next you'll get a recovery key to write down: the only other way in."
            : recovering ? "The recovery key you wrote down. You'll set a new password next."
            : usingKit ? "The pieces from the printed sheets, a piece per line. You'll set a new password next."
            : OldFormat ? "This vault was made by an earlier test version of Stillroom, which this one can't open. Nothing in it has been changed."
            : "Everything inside is encrypted on this PC.";

        var seconds = (int)Math.Ceiling(wait.TotalSeconds);
        Line.Text = seconds > 0 ? $"Too many wrong tries. Try again in {seconds} s." : problem ?? " ";
        Line.Foreground = seconds > 0 || problem is not null ? (Brush)Application.Current.Resources["ProblemBrush"] : (Brush)Application.Current.Resources["QuietBrush"];
        if (seconds > 0) clock.Start(); else clock.Stop();

        GoButton.Content = making ? "Make Vault…" : "Unlock…";
        GoButton.IsEnabled = !working && seconds == 0 && !OldFormat;
        HelloButton.Visibility = helloOn ? Visibility.Visible : Visibility.Collapsed;
        HelloButton.IsEnabled = !working;
        HelloChoice.Visibility = making && helloAvailable ? Visibility.Visible : Visibility.Collapsed;
        Protected.Visibility = OldFormat ? Visibility.Collapsed : Visibility.Visible;

        var choosing = !making && !recovering && !usingKit && !OldFormat;
        RecoveryLink.Visibility = KitLink.Visibility = choosing ? Visibility.Visible : Visibility.Collapsed;
        PasswordLink.Visibility = recovering || usingKit ? Visibility.Visible : Visibility.Collapsed;
        RestoreLink.Visibility = making ? Visibility.Visible : Visibility.Collapsed;
        foreach (var link in new[] { RecoveryLink, KitLink, PasswordLink, RestoreLink }) link.IsEnabled = !working;

        Working.IsActive = working;
        LockGlyph.Opacity = working ? 0 : 0.75;
    }

    private async void OnGo(object sender, RoutedEventArgs e)
    {
        if (working) return;
        working = true;
        problem = null;
        Refresh();
        var (making, kit, recovery) = (Making, usingKit, recovering);
        var wantsHello = making && helloAvailable && HelloBox.IsChecked == true;
        try
        {
            var attempt = await Task.Run(() => making ? Make() : Open(kit, recovery));
            if (attempt is null) return;
            if (attempt.Opened is not { } vault)
            {
                problem = attempt.Problem;
                return;
            }
            if (wantsHello) state.Notice = await TurnOnHello(vault);
            state.Opened(vault, attempt.RecoveryKey);
        }
        catch (StillroomException failure)
        {
            Fail(failure);
        }
        finally
        {
            working = false;
            Refresh();
        }
    }

    /// <summary>A new vault, its password typed twice on the secure desktop.</summary>
    private Attempt? Make()
    {
        var password = Secrets.AskNewPassword($"Choose a password for your vault: {Secrets.Shortest} characters or more.", out var weak);
        if (password is null) return weak is null ? null : new Attempt(null, Problem: weak);
        try
        {
            var (vault, recoveryKey) = state.Store.Create(password);
            return new Attempt(vault, recoveryKey);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(password);
        }
    }

    /// <summary>The vault opened by what's typed on the secure desktop. What's typed never leaves the engine's
    /// wiped buffer: it goes straight to the unlock.</summary>
    private Attempt? Open(bool kit, bool recovery)
    {
        var message = kit ? "Type the pieces from your emergency kit, a piece per line."
            : recovery ? "Type your recovery key."
            : "Type your vault's password.";
        return Engine.SecurePrompt(Secrets.PromptTitle, message, kit, typed => typed.IsEmpty ? null : new Attempt(
            kit ? state.Store.UnlockWithKit(typed)
            : recovery ? state.Store.UnlockWithRecoveryKey(typed)
            : state.Store.UnlockWithPassword(typed)));
    }

    /// <summary>Windows Hello turned on for a vault just made, when that was asked for. Gives what to say if it wasn't.</summary>
    private static async Task<string?> TurnOnHello(Vault vault)
    {
        try
        {
            await WindowsHello.TurnOnAsync(vault);
            return null;
        }
        catch (HelloCancelled)
        {
            return "Windows Hello wasn't turned on. You can turn it on in Settings.";
        }
        catch (StillroomException failure)
        {
            return $"Windows Hello wasn't turned on: {failure.Message}";
        }
    }

    /// <summary>Asks Windows Hello when it's on for this vault folder; the window calls it as it comes forward.</summary>
    internal void AskHelloIfOn()
    {
        if (!working && !Making && !recovering && !usingKit && state.Store.HelloChallenge() is not null) OnHello(this, new RoutedEventArgs());
    }

    private async void OnHello(object sender, RoutedEventArgs e)
    {
        if (working || state.Store.HelloChallenge() is not { } challenge) return;
        working = true;
        problem = null;
        Refresh();
        try
        {
            state.Opened(await WindowsHello.UnlockAsync(state.Store, challenge));
        }
        catch (HelloCancelled)
        {
        }
        catch (StillroomException failure)
        {
            // Never a wrong try: Hello itself guards against guessing.
            problem = failure.Message;
        }
        finally
        {
            working = false;
            Refresh();
        }
    }

    private void Fail(StillroomException failure)
    {
        // Only a guess counts towards the wait; a vault locked to another computer isn't a wrong guess.
        if (failure.Status is Status.WrongPassword or Status.WrongRecoveryKey or Status.WrongKit)
        {
            state.Store.CountWrongTry();
            // Into the intruder log, sealed so only the vault, open, can read it, with a photo when that's on and
            // Windows allows the camera. Kit pieces count as a recovery key there; what was typed is never kept.
            var (store, recoveryKey, photo) = (state.Store, failure.Status != Status.WrongPassword, window.Settings.IntruderPhoto);
            _ = Task.Run(async () =>
            {
                var picture = photo ? await IntruderCamera.SnapAsync() : null;
                try { store.RecordIntruder(recoveryKey, picture); }
                catch (Exception e) when (e is StillroomException or ObjectDisposedException) { }
            });
        }
        if (failure.Status == Status.NotThisComputer) (recovering, usingKit) = (true, false);
        problem = failure.Message;
    }

    private void Switch(bool recovery, bool kit)
    {
        (recovering, usingKit, problem) = (recovery, kit, null);
        Refresh();
    }

    private void OnUseRecovery(object sender, RoutedEventArgs e) => Switch(recovery: true, kit: false);
    private void OnUseKit(object sender, RoutedEventArgs e) => Switch(recovery: false, kit: true);
    private void OnUsePassword(object sender, RoutedEventArgs e) => Switch(recovery: false, kit: false);

    /// <summary>A vault put back from a backup file, before any vault is made here.</summary>
    private async void OnRestore(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        WinRT.Interop.InitializeWithWindow.Initialize(picker, window.Handle);
        picker.FileTypeFilter.Add(".stillroombackup");
        if (await picker.PickSingleFileAsync() is not { } file) return;
        working = true;
        problem = null;
        Refresh();
        try
        {
            await Task.Run(() => state.Store.Restore(file.Path));
        }
        catch (StillroomException failure)
        {
            problem = failure.Message;
        }
        finally
        {
            working = false;
            Refresh();
        }
    }
}
