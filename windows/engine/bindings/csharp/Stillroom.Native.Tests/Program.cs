// The .NET bindings against the engine's DLL, as the WinUI app will use them. Each check gets a vault of its own in a
// temp folder. Prints each check and exits non-zero if any failed.

using System.Text;
using System.Text.Json;
using Stillroom.Native;

var checks = new List<(string Name, Action<string> Run)>
{
    ("the engine is the version these bindings expect, and keys are locked", _ =>
    {
        Expect(Engine.AbiVersion == Engine.ExpectedAbiVersion, $"ABI {Engine.AbiVersion}");
        Expect(Engine.KeysAreLocked, "keys in locked memory");
    }),

    ("a vault is made, used, locked and opened again", dir =>
    {
        using var store = QuickStore(dir);
        Expect(!store.Exists, "no vault yet");
        var (vault, recovery) = store.Create("a password typed in C#");
        Expect(recovery.Length == 29, "recovery key shape");
        var note = vault.NewNote("Plans", "first");
        Expect(Encoding.UTF8.GetString(vault.Read(note)) == "first", "read back");
        Expect(vault.Read(note, span => span.SequenceEqual("first"u8)), "read without a copy");
        var state = vault.State();
        Expect(state.GetProperty("files")[0].GetProperty("name").GetString() == "Plans", "listed");
        Expect(!state.GetProperty("files")[0].TryGetProperty("key", out _), "no key reaches .NET");
        vault.Dispose();
        using var again = store.UnlockWithPassword("a password typed in C#");
        Expect(again.State().GetProperty("files").GetArrayLength() == 1, "still there");
    }),

    ("failures are exceptions with the engine's status and words", dir =>
    {
        using var store = QuickStore(dir);
        store.Create("right password 1").Vault.Dispose();
        var error = Throws(() => store.UnlockWithPassword("wrong"));
        Expect(error.Status == Status.WrongPassword && error.Message == "That password doesn't open this vault.", error.Message);
        Expect(Throws(() => store.UnlockWithKit(["VK-0000"])).Status == Status.KitMistyped, "kit mistyped");
        using var vault = store.UnlockWithPassword("right password 1");
        Expect(Throws(() => vault.Delete(Guid.NewGuid().ToString())).Status == Status.NotFound, "not found");
        Expect(Throws(() => vault.Delete("not an id")).Status == Status.InvalidArgument, "bad id");
        vault.MakeFolder("Archive");
        vault.MakeFolder("Taxes", "Archive");
        Expect(Throws(() => vault.MoveFolder("Archive", "Archive/Taxes")).Status == Status.FolderIntoItself, "into itself");
    }),

    ("files in by path, versions, search through the app's reader, playback in ranges", dir =>
    {
        using var store = QuickStore(dir);
        var (vault, _) = store.Create("right password 1");
        using var _v = vault;
        var folder = Directory.CreateDirectory(Path.Combine(dir, "in")).FullName;
        var clip = Enumerable.Range(0, (2 << 20) + 7).Select(i => (byte)(i * 7)).ToArray();
        File.WriteAllBytes(Path.Combine(folder, "clip.mp3"), clip);
        File.WriteAllBytes(Path.Combine(folder, "scan.png"), [0x89, (byte)'P', (byte)'N', (byte)'G']);
        var added = vault.Add([Path.Combine(folder, "clip.mp3"), Path.Combine(folder, "scan.png")]);
        Expect(added.GetProperty("items").GetArrayLength() == 2, "added");
        var clipId = added.GetProperty("items")[0].GetString()!;
        var scanId = added.GetProperty("items")[1].GetString()!;

        using (var reader = vault.OpenReader(clipId))
        {
            Expect(reader.Size == (ulong)clip.Length, "size");
            var buffer = new byte[50_000];
            var read = reader.Read((1 << 20) - 5, buffer);
            Expect(buffer.AsSpan(0, read).SequenceEqual(clip.AsSpan((1 << 20) - 5, read)), "a range across chunks");
        }

        var asked = 0;
        Expect(vault.RefreshSearch((item, data) =>
        {
            asked++;
            return item.GetProperty("uti").GetString() == "public.png" ? "receipt for the oak table" : null;
        }), "search refreshed");
        Expect(asked == 1, $"the reader was asked {asked} times");
        Expect(vault.Search("OAK TABLE").SequenceEqual([scanId]), "found by the picture's words");

        var note = vault.NewNote("Diary", "day one");
        vault.Update(note, "day two"u8, "Diary 2");
        Expect(Encoding.UTF8.GetString(vault.Read(note)) == "day two", "updated");
        Expect(Vault.OriginalsRemovals(added.GetProperty("originals")).Length == 2, "two originals to remove, for the Recycle Bin");
        Expect(Vault.DeleteOriginals(added.GetProperty("originals")).GetArrayLength() == 0, "originals deleted");
        Expect(!File.Exists(Path.Combine(folder, "scan.png")), "original gone once its copy checked out");
    }),

    ("the decoy, the kit, the recovery key and the wait after wrong tries", dir =>
    {
        using var store = QuickStore(dir);
        var (vault, recovery) = store.Create("real password 123");
        var decoyKey = vault.SetOtherSlot("decoy password 456");
        Expect(decoyKey.Length == 29, "decoy's own recovery key");
        var pieces = vault.MakeKit(2, 3);
        vault.Dispose();

        using (var decoy = store.UnlockWithPassword("decoy password 456"))
            Expect(decoy.State().GetProperty("files").GetArrayLength() == 0, "the decoy is empty");
        using (var byKit = store.UnlockWithKit([pieces[2].ToLowerInvariant(), pieces[0]]))
        {
            Expect(byKit.State().GetProperty("mustSetPassword").GetBoolean(), "asks for a new password");
            byKit.SetPasswordAfterRecovery("a brand new password");
        }
        store.UnlockWithRecoveryKey(recovery.ToLowerInvariant()).Dispose();
        store.UnlockWithPassword("a brand new password").Dispose();

        for (var i = 0; i < 4; i++) store.CountWrongTry();
        Expect(store.WaitBeforeNextTry > TimeSpan.Zero, "a wait after four wrong tries");
        store.RecordIntruder(recoveryKey: false);
        store.ClearWrongTries();
        Expect(store.WaitBeforeNextTry == TimeSpan.Zero, "cleared by a good try");
        using var open = store.UnlockWithPassword("a brand new password");
        Expect(open.Intruders().GetArrayLength() == 1, "the wrong try is in the intruder log");
    }),

    ("backup, restore and wipe", dir =>
    {
        using var store = QuickStore(dir);
        var (vault, _) = store.Create("real password 123");
        vault.NewNote("Kept", "in the backup");
        var file = Path.Combine(dir, "vault.stillroombackup");
        vault.Backup(file);
        Store.CheckBackup(file);
        vault.NewNote("Later", "not in the backup");
        var aside = vault.RestoreBackup(file);
        Expect(aside is not null && aside.Contains("Store-before-restore-"), "old vault set aside");
        // The vault was locked for the restore: its object is spent.
        var locked = false;
        try { vault.State(); } catch (ObjectDisposedException) { locked = true; }
        Expect(locked, "the vault was locked for the restore");
        var restored = store.UnlockWithPassword("real password 123");
        Expect(restored.State().GetProperty("files").GetArrayLength() == 1, "only what the backup held");
        restored.Wipe();
        Expect(!store.Exists, "wiped");
    }),

    ("lock to this PC through the TPM, and off again", dir =>
    {
        if (!Engine.TpmAvailable) return;
        using var store = QuickStore(dir);
        var (vault, _) = store.Create("real password 123");
        var recovery = vault.LockToThisPc();
        Expect(recovery is { Length: 29 } && store.IsLockedToAPc, "locked, with a new recovery key");
        Expect(vault.State().GetProperty("lockedToAPc").GetBoolean(), "the window knows");
        vault.Dispose();
        store.UnlockWithPassword("real password 123").Dispose();
        using var again = store.UnlockWithRecoveryKey(recovery!);
        again.UnlockFromThisPc();
        Expect(!store.IsLockedToAPc, "unlocked, and its TPM key deleted");
    }),

    ("Windows Hello's signature opens the vault that turned it on", dir =>
    {
        // A stand-in for Windows Hello: one challenge, one signature, only from this "device".
        static byte[] Sign(byte[] challenge) => System.Security.Cryptography.HMACSHA256.HashData("this pc"u8, challenge);
        using var store = QuickStore(dir);
        var (vault, _) = store.Create("real password 123");
        Expect(store.HelloChallenge() is null, "off to begin with");
        var challenge = Engine.HelloNewChallenge();
        vault.TurnOnHello(challenge, Sign(challenge), "public key"u8);
        Expect(vault.State().GetProperty("helloIsMine").GetBoolean(), "on for this vault");
        vault.Dispose();
        using var byHello = store.UnlockWithHello(Sign(store.HelloChallenge()!));
        Expect(Throws(() => store.UnlockWithHello("someone else"u8)).Status == Status.HelloChanged, "another signature opens nothing");
    }),

    ("locking from another thread waits for a call already running, and refuses new ones", dir =>
    {
        using var store = QuickStore(dir);
        var (vault, _) = store.Create("real password 123");
        vault.AddData("a picture"u8, "scan.png");
        var refusedMeanwhile = false;
        // The search's reader runs inside an engine call that holds the vault: lock it from elsewhere right then.
        vault.RefreshSearch((_, _) =>
        {
            Task.Run(vault.Dispose).Wait();
            try { vault.State(); } catch (ObjectDisposedException) { refusedMeanwhile = true; }
            return "words";
        });
        Expect(refusedMeanwhile, "a new call is refused at once");
        var locked = false;
        try { vault.State(); } catch (ObjectDisposedException) { locked = true; }
        Expect(locked, "still locked once the running call returned");
        using var again = store.UnlockWithPassword("real password 123");
        Expect(again.State().GetProperty("files").GetArrayLength() == 1, "the vault is whole");
    }),

    ("the helpers that need no vault", _ =>
    {
        Expect(Engine.PasswordStrength("correct horse battery staple").Enough, "strong");
        Expect(!Engine.PasswordStrength("Password123").Enough, "weak");
        var code = Engine.OneTimeCode("Two-factor setup", "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", DateTimeOffset.FromUnixTimeSeconds(59));
        Expect(code is { Code: "287082", SecondsLeft: 1 }, $"{code}");
        Expect(Engine.OneTimeCode("Password", "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", DateTimeOffset.UtcNow) is null, "not under a password label");
        Expect(Engine.UtiForName("w2.pdf") == "com.adobe.pdf", "uti");
        Expect(Engine.LookOf("public.jpeg") == Look.Picture && Engine.LookOf("public.zip-archive") == Look.Archive, "look");
        Expect(!Engine.CanEdit("public.html", "page.html", true) && Engine.CanEdit("com.adobe.pdf", "w2.pdf", true), "can edit");
        var mail = "From: a@example.com\r\nSubject: Hi\r\nContent-Type: multipart/mixed; boundary=b\r\n\r\n--b\r\nContent-Type: text/plain\r\n\r\nBody\r\n--b\r\nContent-Type: application/pdf; name=\"x.pdf\"\r\n\r\n%PDF\r\n--b--\r\n"u8.ToArray();
        var email = Engine.ReadEmail(mail)!.Value;
        Expect(email.GetProperty("subject").GetString() == "Hi", "subject");
        Expect(Encoding.ASCII.GetString(Engine.EmailAttachment(mail, 0)) == "%PDF", "attachment");
        Expect(Engine.ReadEmail([0, 0xFF]) is null, "not an email");
    }),
};

var failed = 0;
foreach (var (name, run) in checks)
{
    var dir = Directory.CreateTempSubdirectory("stillroom-cs-").FullName;
    try
    {
        run(dir);
        Console.WriteLine($"ok    {name}");
    }
    catch (Exception e)
    {
        failed++;
        Console.WriteLine($"FAIL  {name}: {e.Message}");
    }
    finally
    {
        try { Directory.Delete(dir, recursive: true); } catch { }
    }
}
Console.WriteLine(failed == 0 ? $"all {checks.Count} passed" : $"{failed} of {checks.Count} failed");
return failed == 0 ? 0 : 1;

static Store QuickStore(string dir)
{
    var store = Store.Open(Path.Combine(dir, "Store"));
    store.LowerCostForTests();
    return store;
}

static void Expect(bool condition, string what)
{
    if (!condition) throw new Exception($"expected: {what}");
}

static StillroomException Throws(Action action)
{
    try { action(); }
    catch (StillroomException e) { return e; }
    throw new Exception("expected the engine to refuse");
}
