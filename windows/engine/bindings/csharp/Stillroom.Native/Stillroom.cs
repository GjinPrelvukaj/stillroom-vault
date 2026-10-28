// The engine for .NET: a Store (a vault folder) opens a Vault (one slot unlocked); disposing a Vault is locking it, and
// its keys are wiped in the engine. No key ever reaches .NET. Failures are StillroomExceptions with the engine's words.
//
// Secrets (passwords, recovery keys, kit pieces) go in as UTF-8 bytes the caller can wipe: pass a span over a buffer
// you clear afterwards. The string overloads are a convenience for code that already holds the secret as a string
// (which .NET can't wipe); they wipe the bytes they make.

using System.Buffers;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace Stillroom.Native;

/// <summary>What a call to the engine said (include/stillroom.h, STILLROOM_*).</summary>
public enum Status
{
    Ok = 0,
    WrongPassword = 1,
    WrongRecoveryKey = 2,
    Damaged = 3,
    Folder = 4,
    HelloUnavailable = 5,
    HelloChanged = 6,
    NotThisComputer = 7,
    SameAsOther = 8,
    WrongKit = 9,
    NewerVault = 10,
    TooSoon = 11,
    KitMistyped = 20,
    KitMixed = 21,
    KitNotEnough = 22,
    Disk = 30,
    ReadOnly = 31,
    NotFound = 32,
    FolderExists = 33,
    FolderIntoItself = 34,
    NotABackup = 35,
    NotAnExport = 36,
    LockedElsewhere = 37,
    NoTpm = 38,
    InvalidArgument = 40,
    Panicked = 41,
}

/// <summary>How a kind of file looks (stillroom_look): pictures go on Images; audio and video on Audio &amp; Video; PDFs,
/// text and documents on Documents; the rest on Other.</summary>
public enum Look : byte
{
    Other = 0,
    Picture = 1,
    Audio = 2,
    Video = 3,
    Pdf = 4,
    Text = 5,
    Document = 6,
    Archive = 7,
}

/// <summary>A call the engine refused, with its reason in plain words, ready to show.</summary>
public sealed class StillroomException(Status status, string message) : Exception(message)
{
    public Status Status { get; } = status;
}

internal static unsafe class Call
{
    /// <summary>Throws for anything but OK, with this thread's last error from the engine.</summary>
    public static void Check(int status)
    {
        if (status == 0) return;
        var message = Marshal.PtrToStringUTF8(NativeMethods.stillroom_last_error()) ?? "";
        throw new StillroomException((Status)status, message);
    }

    /// <summary>A string the engine gave, freed (and wiped) in the engine. Null stays null.</summary>
    public static string? Take(IntPtr value)
    {
        if (value == IntPtr.Zero) return null;
        try { return Marshal.PtrToStringUTF8(value); }
        finally { NativeMethods.stillroom_string_free(value); }
    }

    public static JsonElement TakeJson(IntPtr value) => JsonDocument.Parse(Take(value) ?? "null").RootElement.Clone();

    /// <summary>Bytes the engine gave, copied out and then wiped and freed in the engine.</summary>
    public static byte[] Take(StillroomBytes value)
    {
        try { return new ReadOnlySpan<byte>((void*)value.Data, checked((int)value.Length)).ToArray(); }
        finally { NativeMethods.stillroom_bytes_free(value); }
    }

    /// <summary>Runs `body` over a secret's UTF-8 bytes, then wipes them.</summary>
    public static T WithUtf8<T>(string secret, SpanFunc<T> body)
    {
        var buffer = ArrayPool<byte>.Shared.Rent(Encoding.UTF8.GetMaxByteCount(secret.Length));
        try
        {
            var length = Encoding.UTF8.GetBytes(secret, buffer);
            return body(buffer.AsSpan(0, length));
        }
        finally
        {
            CryptographicOperationsZero(buffer);
            ArrayPool<byte>.Shared.Return(buffer);
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining | MethodImplOptions.NoOptimization)]
    private static void CryptographicOperationsZero(byte[] buffer) => System.Security.Cryptography.CryptographicOperations.ZeroMemory(buffer);

    public static string Json<T>(T value) => JsonSerializer.Serialize(value);
}

/// <summary>A vault folder: makes a vault, or opens one.</summary>
public sealed unsafe class Store : IDisposable
{
    private IntPtr handle;

    private Store(IntPtr handle) => this.handle = handle;

    /// <summary>The vault folder at `root`, or the usual one (%APPDATA%\Stillroom\Store). `readOnly` opens it only to
    /// take things out.</summary>
    public static Store Open(string? root = null, bool readOnly = false)
    {
        Call.Check(NativeMethods.stillroom_store_open(root, readOnly, out var handle));
        return new Store(handle);
    }

    internal IntPtr Handle => handle != IntPtr.Zero ? handle : throw new ObjectDisposedException(nameof(Store));

    /// <summary>Tests only: stretch passwords at a low cost, as the Mac's tests do.</summary>
    public void LowerCostForTests() => Call.Check(NativeMethods.stillroom_store_lower_cost_for_tests(Handle));

    public bool Exists { get { Call.Check(NativeMethods.stillroom_store_exists(Handle, out var r)); return r; } }
    public bool IsOldFormat { get { Call.Check(NativeMethods.stillroom_store_is_old_format(Handle, out var r)); return r; } }
    public bool IsLockedToAMac { get { Call.Check(NativeMethods.stillroom_store_is_locked_to_a_mac(Handle, out var r)); return r; } }
    public bool IsLockedToAPc { get { Call.Check(NativeMethods.stillroom_store_is_locked_to_a_pc(Handle, out var r)); return r; } }

    /// <summary>The challenge to ask Windows Hello to sign at the lock screen, or null when Hello isn't on.</summary>
    public byte[]? HelloChallenge()
    {
        var status = NativeMethods.stillroom_store_hello_challenge(Handle, out var bytes);
        if (status == (int)Status.NotFound) return null;
        Call.Check(status);
        return Call.Take(bytes);
    }

    /// <summary>Windows Hello's signature of the challenge opens the vault that turned Hello on. Wipe the signature
    /// afterwards: it opens the vault.</summary>
    public Vault UnlockWithHello(ReadOnlySpan<byte> signature)
    {
        fixed (byte* p = signature)
        {
            Call.Check(NativeMethods.stillroom_store_unlock_with_hello(Handle, p, (nuint)signature.Length, out var vault));
            return new Vault(vault);
        }
    }

    /// <summary>A new vault. Gives it open, and its recovery key, to be shown once.</summary>
    public (Vault Vault, string RecoveryKey) Create(ReadOnlySpan<byte> password)
    {
        fixed (byte* p = password)
        {
            Call.Check(NativeMethods.stillroom_store_create(Handle, p, (nuint)password.Length, out var vault, out var key));
            return (new Vault(vault), Call.Take(key)!);
        }
    }

    public (Vault Vault, string RecoveryKey) Create(string password) => Call.WithUtf8(password, b => Create(b));

    public Vault UnlockWithPassword(ReadOnlySpan<byte> password)
    {
        fixed (byte* p = password)
        {
            Call.Check(NativeMethods.stillroom_store_unlock_with_password(Handle, p, (nuint)password.Length, out var vault));
            return new Vault(vault);
        }
    }

    public Vault UnlockWithPassword(string password) => Call.WithUtf8(password, b => UnlockWithPassword(b));

    /// <summary>Any case, with or without dashes. A new password must then be set before anything else.</summary>
    public Vault UnlockWithRecoveryKey(ReadOnlySpan<byte> key)
    {
        fixed (byte* p = key)
        {
            Call.Check(NativeMethods.stillroom_store_unlock_with_recovery_key(Handle, p, (nuint)key.Length, out var vault));
            return new Vault(vault);
        }
    }

    public Vault UnlockWithRecoveryKey(string key) => Call.WithUtf8(key, b => UnlockWithRecoveryKey(b));

    /// <summary>Kit pieces as typed, a piece per line. A new password must then be set before anything else.</summary>
    public Vault UnlockWithKit(ReadOnlySpan<byte> pieces)
    {
        fixed (byte* p = pieces)
        {
            Call.Check(NativeMethods.stillroom_store_unlock_with_kit(Handle, p, (nuint)pieces.Length, out var vault));
            return new Vault(vault);
        }
    }

    public Vault UnlockWithKit(IEnumerable<string> pieces) => Call.WithUtf8(string.Join('\n', pieces), b => UnlockWithKit(b));

    /// <summary>A wrong try at the lock screen, for both vaults' intruder logs. What was typed is never kept.</summary>
    public void RecordIntruder(bool recoveryKey, ReadOnlySpan<byte> photo = default)
    {
        fixed (byte* p = photo)
            Call.Check(NativeMethods.stillroom_store_record_intruder(Handle, recoveryKey ? 1 : 0, p, (nuint)photo.Length));
    }

    public TimeSpan WaitBeforeNextTry
    {
        get { Call.Check(NativeMethods.stillroom_store_wait_before_next_try(Handle, out var s)); return TimeSpan.FromSeconds(s); }
    }

    public void CountWrongTry() => Call.Check(NativeMethods.stillroom_store_count_wrong_try(Handle));
    public void ClearWrongTries() => Call.Check(NativeMethods.stillroom_store_clear_wrong_tries(Handle));

    /// <summary>A backup of the locked vault into one file.</summary>
    public void Backup(string to) => Call.Check(NativeMethods.stillroom_store_backup(Handle, to));

    /// <summary>Puts the vault back from a backup (lock it first). Gives where the old one was set aside, if any.</summary>
    public string? Restore(string file)
    {
        Call.Check(NativeMethods.stillroom_store_restore(Handle, file, out var aside));
        return Call.Take(aside);
    }

    public static void CheckBackup(string file) => Call.Check(NativeMethods.stillroom_backup_check(file));

    public void Dispose()
    {
        if (handle == IntPtr.Zero) return;
        NativeMethods.stillroom_store_free(handle);
        handle = IntPtr.Zero;
    }
}

/// <summary>One vault, unlocked. Dispose to lock it: its keys are wiped in the engine.</summary>
public sealed unsafe class Vault : IDisposable
{
    private readonly VaultHandle handle;

    internal Vault(IntPtr handle) => this.handle = new VaultHandle(handle);

    private VaultHandle Handle => !handle.Locking ? handle : throw new ObjectDisposedException(nameof(Vault));

    /// <summary>Locked, or locking: no new call will be taken.</summary>
    public bool IsLocked => handle.Locking;

    /// <summary>Everything the window shows: files, folders, tags and settings (see stillroom_vault_state).</summary>
    public JsonElement State()
    {
        Call.Check(NativeMethods.stillroom_vault_state(Handle, out var json));
        return Call.TakeJson(json);
    }

    /// <summary>Files and folders in, each checked against its original. See stillroom_vault_add for the report.</summary>
    public JsonElement Add(IEnumerable<string> paths, string? folder = null)
    {
        Call.Check(NativeMethods.stillroom_vault_add(Handle, Call.Json(paths), folder, out var json));
        return Call.TakeJson(json);
    }

    /// <summary>Deletes the originals an add checked (its "originals"). Gives the names that couldn't be.</summary>
    public static JsonElement DeleteOriginals(JsonElement originals)
    {
        Call.Check(NativeMethods.stillroom_delete_originals(originals.GetRawText(), out var json));
        return Call.TakeJson(json);
    }

    /// <summary>What DeleteOriginals would remove (folders whole only when everything in them went in), for moving
    /// to the Recycle Bin by the same rule.</summary>
    public static string[] OriginalsRemovals(JsonElement originals)
    {
        Call.Check(NativeMethods.stillroom_originals_removals(originals.GetRawText(), out var json));
        return Call.TakeJson(json).EnumerateArray().Select(p => p.GetString()!).ToArray();
    }

    public string AddData(ReadOnlySpan<byte> data, string name, string? folder = null)
    {
        fixed (byte* p = data)
        {
            Call.Check(NativeMethods.stillroom_vault_add_data(Handle, p, (nuint)data.Length, name, folder, out var id));
            return Call.Take(id)!;
        }
    }

    private string NewEntry(int kind, string name, ReadOnlySpan<byte> content, string? folder)
    {
        fixed (byte* p = content)
        {
            Call.Check(NativeMethods.stillroom_vault_new_entry(Handle, kind, name, p, (nuint)content.Length, folder, out var id));
            return Call.Take(id)!;
        }
    }

    /// <summary>A new note (Markdown). Gives its id.</summary>
    public string NewNote(string name, string markdown, string? folder = null) => NewEntry(0, name, Encoding.UTF8.GetBytes(markdown), folder);

    /// <summary>A new secret (its JSON, as the Mac writes it). Gives its id.</summary>
    public string NewSecret(string name, ReadOnlySpan<byte> json, string? folder = null) => NewEntry(1, name, json, folder);

    /// <summary>An item's contents (or one earlier version's), copied into a new array.</summary>
    public byte[] Read(string item, string? version = null)
    {
        Call.Check(NativeMethods.stillroom_vault_read(Handle, item, version, out var bytes));
        return Call.Take(bytes);
    }

    /// <summary>An item's contents shown to `body` straight from the engine's buffer, which is wiped as soon as it
    /// returns: no copy left in managed memory, where it can't be wiped.</summary>
    public T Read<T>(string item, SpanFunc<T> body, string? version = null)
    {
        Call.Check(NativeMethods.stillroom_vault_read(Handle, item, version, out var bytes));
        try { return body(new ReadOnlySpan<byte>((void*)bytes.Data, checked((int)bytes.Length))); }
        finally { NativeMethods.stillroom_bytes_free(bytes); }
    }


    /// <summary>An item written out to `to`, with its dates, marked as downloaded.</summary>
    public void ExportItem(string item, string to) => Call.Check(NativeMethods.stillroom_vault_export_item(Handle, item, to));

    /// <summary>Everything out, unencrypted, in a new "Stillroom Export &lt;date&gt;" folder inside `parent`.</summary>
    public JsonElement ExportAll(string parent)
    {
        Call.Check(NativeMethods.stillroom_vault_export_all(Handle, parent, out var json));
        return Call.TakeJson(json);
    }

    public void Delete(string item) => Call.Check(NativeMethods.stillroom_vault_delete(Handle, item));

    /// <summary>New contents (and a new name, if given). What it held is kept as a version after ten quiet minutes.</summary>
    public void Update(string item, ReadOnlySpan<byte> data, string? name = null)
    {
        fixed (byte* p = data)
            Call.Check(NativeMethods.stillroom_vault_update(Handle, item, p, (nuint)data.Length, name));
    }

    public void UpdateFromFile(string item, string file) => Call.Check(NativeMethods.stillroom_vault_update_from_file(Handle, item, file));
    public void RestoreVersion(string item, string version) => Call.Check(NativeMethods.stillroom_vault_restore_version(Handle, item, version));
    public void DropVersion(string item, string version) => Call.Check(NativeMethods.stillroom_vault_drop_version(Handle, item, version));
    public void FallBack(string item, string version) => Call.Check(NativeMethods.stillroom_vault_fall_back(Handle, item, version));

    /// <summary>Reads everything through; gives what doesn't open.</summary>
    public JsonElement Check()
    {
        Call.Check(NativeMethods.stillroom_vault_check(Handle, out var json));
        return Call.TakeJson(json);
    }

    public void Rename(string item, string name) => Call.Check(NativeMethods.stillroom_vault_rename(Handle, item, name));
    public void SetTags(string item, IEnumerable<string> tags) => Call.Check(NativeMethods.stillroom_vault_set_tags(Handle, item, Call.Json(tags)));
    public void MakeFolder(string name, string? parent = null) => Call.Check(NativeMethods.stillroom_vault_make_folder(Handle, name, parent));
    public void MoveItems(IEnumerable<string> items, string? folder) => Call.Check(NativeMethods.stillroom_vault_move_items(Handle, Call.Json(items), folder));

    public string? RenameFolder(string folder, string name)
    {
        Call.Check(NativeMethods.stillroom_vault_rename_folder(Handle, folder, name, out var path));
        return Call.Take(path);
    }

    public void MoveFolder(string folder, string? into) => Call.Check(NativeMethods.stillroom_vault_move_folder(Handle, folder, into));
    public void DeleteFolder(string folder) => Call.Check(NativeMethods.stillroom_vault_delete_folder(Handle, folder));
    public void SetShowInCapture(bool on) => Call.Check(NativeMethods.stillroom_vault_set_show_in_capture(Handle, on));

    // Keys

    public void ChangePassword(ReadOnlySpan<byte> current, ReadOnlySpan<byte> next)
    {
        fixed (byte* pc = current)
        fixed (byte* pn = next)
            Call.Check(NativeMethods.stillroom_vault_change_password(Handle, pc, (nuint)current.Length, pn, (nuint)next.Length));
    }

    public void ChangePassword(string current, string next)
    {
        var (c, n) = (Encoding.UTF8.GetBytes(current), Encoding.UTF8.GetBytes(next));
        try { ChangePassword(c, n); }
        finally
        {
            System.Security.Cryptography.CryptographicOperations.ZeroMemory(c);
            System.Security.Cryptography.CryptographicOperations.ZeroMemory(n);
        }
    }

    public void SetPasswordAfterRecovery(ReadOnlySpan<byte> next)
    {
        fixed (byte* p = next)
            Call.Check(NativeMethods.stillroom_vault_set_password_after_recovery(Handle, p, (nuint)next.Length));
    }

    public void SetPasswordAfterRecovery(string next) => Call.WithUtf8(next, n => { SetPasswordAfterRecovery(n); return 0; });

    /// <summary>A decoy password: the other slot becomes a new, empty vault. Gives its recovery key, to show once.</summary>
    public string SetOtherSlot(ReadOnlySpan<byte> password)
    {
        fixed (byte* p = password)
        {
            Call.Check(NativeMethods.stillroom_vault_set_other_slot(Handle, p, (nuint)password.Length, out var key));
            return Call.Take(key)!;
        }
    }

    public string SetOtherSlot(string password) => Call.WithUtf8(password, b => SetOtherSlot(b));

    public void ResetOtherSlot() => Call.Check(NativeMethods.stillroom_vault_reset_other_slot(Handle));

    public string NewRecoveryKey()
    {
        Call.Check(NativeMethods.stillroom_vault_new_recovery_key(Handle, out var key));
        return Call.Take(key)!;
    }

    /// <summary>A new emergency kit: `count` pieces, any `threshold` of which open this vault. Print them once.</summary>
    public string[] MakeKit(byte threshold, byte count)
    {
        Call.Check(NativeMethods.stillroom_vault_make_kit(Handle, threshold, count, out var json));
        return Call.TakeJson(json).EnumerateArray().Select(p => p.GetString()!).ToArray();
    }

    public void RemoveKit() => Call.Check(NativeMethods.stillroom_vault_remove_kit(Handle));

    /// <summary>Locks both vaults' password keys to this PC's TPM. Gives a new recovery key to show once, or null when
    /// it was already locked.</summary>
    public string? LockToThisPc()
    {
        Call.Check(NativeMethods.stillroom_vault_lock_to_this_pc(Handle, out var key));
        return Call.Take(key);
    }

    public void UnlockFromThisPc() => Call.Check(NativeMethods.stillroom_vault_unlock_from_this_pc(Handle));

    /// <summary>Windows Hello opens this vault from now on: the challenge (Engine.HelloNewChallenge), Windows Hello's
    /// signature of it, and the credential's public key. Turning it on should say plainly that the Windows Hello PIN
    /// opens the vault too.</summary>
    public void TurnOnHello(ReadOnlySpan<byte> challenge, ReadOnlySpan<byte> signature, ReadOnlySpan<byte> publicKey)
    {
        fixed (byte* c = challenge)
        fixed (byte* s = signature)
        fixed (byte* k = publicKey)
            Call.Check(NativeMethods.stillroom_vault_turn_on_hello(Handle, c, (nuint)challenge.Length, s, (nuint)signature.Length, k, (nuint)publicKey.Length));
    }

    public void TurnOffHello() => Call.Check(NativeMethods.stillroom_vault_turn_off_hello(Handle));

    public bool KitReminderDue() { Call.Check(NativeMethods.stillroom_vault_kit_reminder_due(Handle, out var due)); return due; }

    // Intruders

    public JsonElement Intruders()
    {
        Call.Check(NativeMethods.stillroom_vault_intruders(Handle, out var json));
        return Call.TakeJson(json);
    }

    public void DeleteIntruder(string entry) => Call.Check(NativeMethods.stillroom_vault_delete_intruder(Handle, entry));
    public void ClearIntruders() => Call.Check(NativeMethods.stillroom_vault_clear_intruders(Handle));

    // Search

    /// <summary>Reads what's new or changed for search. `readText` reads what only Windows can (a PDF, the words in a
    /// picture): given the item's JSON and its contents, the text or null. Gives whether anything changed.</summary>
    public bool RefreshSearch(ReadText? readText = null)
    {
        if (readText is null)
        {
            Call.Check(NativeMethods.stillroom_vault_refresh_search(Handle, null, IntPtr.Zero, out var changed));
            return changed;
        }
        var reading = new Reading(readText);
        var context = GCHandle.Alloc(reading);
        try
        {
            Call.Check(NativeMethods.stillroom_vault_refresh_search(Handle, &ReadTextFromEngine, GCHandle.ToIntPtr(context), out var changed));
            return changed;
        }
        finally
        {
            context.Free();
            reading.Release();
        }
    }

    /// <summary>The app's reader and the last text it gave, kept alive until the engine's next call.</summary>
    private sealed class Reading(ReadText read)
    {
        public readonly ReadText Read = read;
        public IntPtr Last;

        public void Release()
        {
            if (Last != IntPtr.Zero) Marshal.FreeCoTaskMem(Last);
            Last = IntPtr.Zero;
        }
    }

    [UnmanagedCallersOnly]
    private static byte* ReadTextFromEngine(IntPtr context, byte* item, byte* data, nuint length)
    {
        var reading = (Reading)GCHandle.FromIntPtr(context).Target!;
        reading.Release();
        try
        {
            using var json = JsonDocument.Parse(Marshal.PtrToStringUTF8((IntPtr)item) ?? "null");
            var text = reading.Read(json.RootElement, new ReadOnlySpan<byte>(data, checked((int)length)));
            if (text is null) return null;
            reading.Last = Marshal.StringToCoTaskMemUTF8(text);
            return (byte*)reading.Last;
        }
        catch
        {
            // An exception can't cross back into the engine: the item just isn't read.
            return null;
        }
    }

    public string[] Search(string query)
    {
        Call.Check(NativeMethods.stillroom_vault_search(Handle, query, out var json));
        return Call.TakeJson(json).EnumerateArray().Select(i => i.GetString()!).ToArray();
    }

    public string? Snippet(string item, string query)
    {
        Call.Check(NativeMethods.stillroom_vault_snippet(Handle, item, query, out var snippet));
        return Call.Take(snippet);
    }

    /// <summary>Accounts from a password export (CSV), each a Login secret in "Imported".</summary>
    public (int Added, int Skipped) ImportLogins(ReadOnlySpan<byte> csv)
    {
        fixed (byte* p = csv)
        {
            Call.Check(NativeMethods.stillroom_vault_import_logins(Handle, p, (nuint)csv.Length, out var json));
            var result = Call.TakeJson(json);
            return (result.GetProperty("added").GetInt32(), result.GetProperty("skipped").GetInt32());
        }
    }

    // Backups and endings

    public void Backup(string to) => Call.Check(NativeMethods.stillroom_vault_backup(Handle, to));

    /// <summary>Puts the vault back from a backup. This vault is locked first, whatever happens.</summary>
    public string? RestoreBackup(string file)
    {
        var aside = IntPtr.Zero;
        Handle.EndWith(vault => NativeMethods.stillroom_vault_restore_backup(vault, file, out aside));
        return Call.Take(aside);
    }

    /// <summary>The vault and every file in it, for good. This vault is locked, whatever happens.</summary>
    public void Wipe() => Handle.EndWith(NativeMethods.stillroom_vault_wipe);

    /// <summary>A reader for audio or video (anything sealed in chunks), for a player.</summary>
    public Reader OpenReader(string item)
    {
        Call.Check(NativeMethods.stillroom_vault_open_reader(Handle, item, out var reader, out var size));
        return new Reader(reader, size);
    }

    /// <summary>Locks the vault: at once for new calls, and in the engine (its keys wiped) as soon as any call still
    /// running on another thread returns.</summary>
    public void Dispose() => handle.Dispose();
}

/// <summary>An open vault's handle. Every call holds it while it runs, so locking (disposing) refuses new calls at
/// once and the engine locks the vault when the last running one returns: a lock from the UI thread (a hot key,
/// auto-lock) can never free the vault under an add or a backup running on another.</summary>
internal sealed class VaultHandle : SafeHandle
{
    private Func<IntPtr, int>? ending;
    private (int Status, string Message) ended;
    private readonly ManualResetEventSlim done = new();

    private volatile bool locking;

    public VaultHandle(IntPtr vault) : base(IntPtr.Zero, ownsHandle: true) => SetHandle(vault);

    public override bool IsInvalid => handle == IntPtr.Zero;

    /// <summary>Locking has begun: no new call may start. (A SafeHandle alone still lends itself out until the last
    /// running call returns.)</summary>
    public bool Locking => locking || IsClosed;

    /// <summary>Ends the vault with `call` (one that takes the vault: a restore, a wipe) in place of a plain lock,
    /// once calls still running have returned. Throws what `call` failed with.</summary>
    public void EndWith(Func<IntPtr, int> call)
    {
        lock (done)
        {
            ObjectDisposedException.ThrowIf(Locking, typeof(Vault));
            ending = call;
        }
        Dispose();
        done.Wait();
        if (ended.Status != 0) throw new StillroomException((Status)ended.Status, ended.Message);
    }

    protected override void Dispose(bool disposing)
    {
        lock (done) locking = true;
        base.Dispose(disposing);
    }

    protected override bool ReleaseHandle()
    {
        if (ending is { } call)
        {
            // Read here: the engine's last error is per thread, and this may run on whichever thread let go last.
            var status = call(handle);
            ended = (status, status == 0 ? "" : Marshal.PtrToStringUTF8(NativeMethods.stillroom_last_error()) ?? "");
        }
        else
        {
            NativeMethods.stillroom_vault_lock(handle);
        }
        done.Set();
        return true;
    }
}

/// <summary>An item sealed in chunks, read a range at a time straight from its sealed file.</summary>
public sealed unsafe class Reader : IDisposable
{
    private IntPtr handle;

    internal Reader(IntPtr handle, ulong size) => (this.handle, Size) = (handle, size);

    public ulong Size { get; }

    /// <summary>Up to buffer.Length bytes from `offset`; gives how many (0 past the end).</summary>
    public int Read(ulong offset, Span<byte> buffer)
    {
        if (handle == IntPtr.Zero) throw new ObjectDisposedException(nameof(Reader));
        fixed (byte* p = buffer)
        {
            Call.Check(NativeMethods.stillroom_reader_read(handle, offset, p, (nuint)buffer.Length, out var read));
            return (int)read;
        }
    }

    public void Dispose()
    {
        if (handle == IntPtr.Zero) return;
        NativeMethods.stillroom_reader_free(handle);
        handle = IntPtr.Zero;
    }
}

/// <summary>What needs no vault.</summary>
public static unsafe class Engine
{
    public static uint AbiVersion => NativeMethods.stillroom_abi_version();

    /// <summary>The version these bindings were written for (STILLROOM_ABI_VERSION).</summary>
    public const uint ExpectedAbiVersion = 1;

    /// <summary>Whether every key is in locked memory, out of the page file. False is worth telling someone.</summary>
    public static bool KeysAreLocked => NativeMethods.stillroom_keys_are_locked();

    /// <summary>Keeps this program out of Windows Error Reporting. Call once at start.</summary>
    public static void ExcludeFromCrashReports() => Call.Check(NativeMethods.stillroom_exclude_from_crash_reports());

    /// <summary>What HardenProcess turned on.</summary>
    [Flags]
    public enum Hardening : uint { None = 0, ExtensionDllsBlocked = 1, ImageLoadsRestricted = 2, StrictHandles = 4 }

    /// <summary>Windows' process protections; can't be undone, so call once, early. `blockExtensionDlls` also turns off
    /// input method editors (IMEs): make it a setting for people who type with one.</summary>
    public static Hardening HardenProcess(bool blockExtensionDlls = true)
    {
        Call.Check(NativeMethods.stillroom_harden_process(blockExtensionDlls, out var hardened));
        return (Hardening)hardened;
    }

    /// <summary>Whether this PC has a TPM the vault can be locked to.</summary>
    public static bool TpmAvailable => NativeMethods.stillroom_tpm_available();

    /// <summary>A folder made readable by this account only (made first if need be), as the vault folder is.</summary>
    public static void ProtectFolder(string folder) => Call.Check(NativeMethods.stillroom_protect_folder(folder));

    /// <summary>32 random bytes for Windows Hello to sign, to turn it on.</summary>
    public static byte[] HelloNewChallenge()
    {
        Call.Check(NativeMethods.stillroom_hello_new_challenge(out var bytes));
        return Call.Take(bytes);
    }

    /// <summary>Asks for a secret on a desktop of its own, where other programs' keyboard hooks can't see it. `body`
    /// sees the typed UTF-8 straight from the engine, which wipes it as soon as `body` returns; null when cancelled.</summary>
    public static T? SecurePrompt<T>(string title, string message, bool multiline, SpanFunc<T> body)
    {
        Call.Check(NativeMethods.stillroom_secure_prompt(title, message, multiline, out var typed, out var cancelled));
        if (cancelled) return default;
        try { return body(new ReadOnlySpan<byte>((void*)typed.Data, checked((int)typed.Length))); }
        finally { NativeMethods.stillroom_bytes_free(typed); }
    }

    public static (double Bits, bool Enough) PasswordStrength(ReadOnlySpan<byte> password)
    {
        fixed (byte* p = password)
        {
            Call.Check(NativeMethods.stillroom_password_strength(p, (nuint)password.Length, out var bits, out var enough));
            return (bits, enough);
        }
    }

    public static (double Bits, bool Enough) PasswordStrength(string password) => Call.WithUtf8(password, b => PasswordStrength(b));

    /// <summary>The two-factor code a secret's field shows at `when`, or null when it holds no setup.</summary>
    public static (string Code, int SecondsLeft)? OneTimeCode(string label, string value, DateTimeOffset when) => Call.WithUtf8(value, b =>
    {
        fixed (byte* p = b)
        {
            Call.Check(NativeMethods.stillroom_one_time_code(label, p, (nuint)b.Length, when.ToUnixTimeMilliseconds() / 1000.0, out var code, out var left));
            var text = Call.Take(code);
            return text is null ? ((string, int)?)null : (text, (int)left);
        }
    });

    public static string UtiForName(string name)
    {
        Call.Check(NativeMethods.stillroom_uti_for_name(name, out var uti));
        return Call.Take(uti)!;
    }

    /// <summary>How a kind looks, for its symbol and its shelf (see Look).</summary>
    public static Look LookOf(string uti)
    {
        Call.Check(NativeMethods.stillroom_look(uti, out var look));
        return (Look)look;
    }

    public static bool CanEdit(string uti, string name, bool isFile)
    {
        Call.Check(NativeMethods.stillroom_can_edit(uti, name, isFile, out var can));
        return can;
    }

    /// <summary>An email read into JSON (see stillroom_email_read), or null when the bytes aren't one.</summary>
    public static JsonElement? ReadEmail(ReadOnlySpan<byte> data)
    {
        fixed (byte* p = data)
        {
            Call.Check(NativeMethods.stillroom_email_read(p, (nuint)data.Length, out var json));
            return json == IntPtr.Zero ? null : Call.TakeJson(json);
        }
    }

    public static byte[] EmailAttachment(ReadOnlySpan<byte> data, int index)
    {
        fixed (byte* p = data)
        {
            Call.Check(NativeMethods.stillroom_email_attachment(p, (nuint)data.Length, (nuint)index, out var bytes));
            return Call.Take(bytes);
        }
    }
}

/// <summary>Code given bytes for as long as it runs: a secret's UTF-8, or contents straight from the engine.</summary>
public delegate T SpanFunc<T>(ReadOnlySpan<byte> bytes);

/// <summary>Reads the text of what only Windows can (a PDF, the words in a picture): given the item and its contents,
/// the text, or null for none.</summary>
public delegate string? ReadText(JsonElement item, ReadOnlySpan<byte> contents);
