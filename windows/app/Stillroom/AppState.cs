using System.Text.Json;
using Stillroom.Native;

namespace Stillroom;

/// <summary>The one source of truth, as the Mac's `AppState`: the vault folder, and the vault while it's open. The
/// window shows the lock screen or the vault from this; every way of locking (the hot key, the tray, Windows locking,
/// sleep, auto-lock, quitting) ends here. The keys themselves stay in the engine.</summary>
internal sealed class AppState : IDisposable
{
    public Store Store { get; }

    /// <summary>The open vault, or null while locked.</summary>
    public Vault? Vault { get; private set; }

    public bool IsOpen => Vault is not null;

    /// <summary>A recovery key just made, to show once and then forget.</summary>
    public string? FreshRecoveryKey { get; set; }

    /// <summary>Something to say once the vault is open (Windows Hello not turned on after making it, say).</summary>
    public string? Notice { get; set; }

    /// <summary>Something for the lock screen to say (a restore that failed, after the vault locked for it).</summary>
    public string? LockNotice { get; set; }

    /// <summary>Where the vault folder is.</summary>
    public string StoreRoot { get; }

    /// <summary>Opened or locked.</summary>
    public event Action? Changed;

    /// <summary>About to lock, with the vault still open: an editor saves what's typed since its last save.</summary>
    public event Action? Locking;

    private AppState(Store store, string root) => (Store, StoreRoot) = (store, root);

    /// <summary>The usual vault folder (%APPDATA%\Stillroom\Store). Development builds can be pointed elsewhere with
    /// STILLROOM_STORE_DIR, so trying the app never touches a real vault.</summary>
    public static AppState Open()
    {
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Stillroom", "Store");
#if DEBUG
        if (Environment.GetEnvironmentVariable("STILLROOM_STORE_DIR") is { Length: > 0 } elsewhere) root = elsewhere;
#endif
        return new AppState(Store.Open(root), root);
    }

    /// <summary>The vault folder changed on disk while locked (a restore): the lock screen looks again.</summary>
    public void Reloaded() => Changed?.Invoke();

    /// <summary>A vault just opened (or made): a good try, so the wait after wrong ones is cleared.</summary>
    public void Opened(Vault vault, string? recoveryKey = null)
    {
        Vault?.Dispose();
        Vault = vault;
        FreshRecoveryKey = recoveryKey;
        Store.ClearWrongTries();
        Changed?.Invoke();
    }

    /// <summary>Shut: the engine wipes the keys (once any call still running returns), and nothing decrypted is kept
    /// here. `reason` says why, for the activity log to come.</summary>
    public void Lock(string reason)
    {
        if (Vault is not { } open) return;
        try { Locking?.Invoke(); }
        catch (Exception) { /* Locking must happen whatever a last save does. */ }
        Vault = null;
        FreshRecoveryKey = null;
        Notice = null;
        open.Dispose();
        Changed?.Invoke();
    }

    /// <summary>What the open vault holds, for the window (see stillroom_vault_state).</summary>
    public JsonElement Contents() => (Vault ?? throw new ObjectDisposedException(nameof(Vault))).State();

    public void Dispose()
    {
        Lock("quitting");
        Store.Dispose();
    }
}
