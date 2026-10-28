# stillroom-core

Stillroom's vault engine for Windows, in Rust: everything the Mac app's `AppState` and storage do, without the interface. It reads and writes the Mac app's format unchanged (`docs/FORMAT.md`), so a vault opens on either. The plan behind it is in [`../PORT.md`](../PORT.md).

## Building

Needs Rust (MSVC toolchain) and Visual Studio 2022 Build Tools with the C++ workload, for the Argon2 C.

```bash
cargo build
cargo test          # everything, about 10 s (passwords are stretched at a low cost in tests)
cargo test --test decoy
```

`build.rs` compiles the Argon2 reference C straight from `macos/Sources/CArgon2`, the same unchanged files the Mac app uses, at `-O3` in every profile. Don't copy or edit them here.

## What's here

| Rust | Mac original |
|---|---|
| `vault.rs` | `Storage/VaultStore.swift` and `AppState`'s unlocking: slots, covers written in pairs, the list and its item keys, `makeSlot`, pruning, adding files |
| `session.rs` | `AppState`'s actions: adding, notes and secrets, versions, checking, names, tags and folders, every key, the decoy, the kit, intruders, search, import |
| `crypto.rs`, `argon2.rs` | `Crypto/CryptoEngine.swift`, `Crypto/Argon2.swift` |
| `names.rs` | `Names`: item files tagged so only a slot can tell its own |
| `kit.rs` | `Crypto/EmergencyKit.swift` |
| `list.rs` | `Models/VaultFile.swift`, `Models/Secret.swift` |
| `blob.rs` | `Storage/Chunked.swift` and one-piece items: sealing, reading, range reads for playback |
| `search.rs` | `Storage/SearchIndex.swift` (PDFs and pictures are read by the platform, through `Extra`) |
| `backup.rs` | `Storage/Backup.swift` |
| `originals.rs` | `Storage/Originals.swift` |
| `intruder.rs` | `Security/IntruderLog.swift` |
| `strength.rs` | `Security/PasswordStrength.swift` |
| `otp.rs` | `Crypto/OneTimeCode.swift` |
| `import.rs` | `Models/PasswordImport.swift` |
| `email.rs` | `Models/Email.swift` |
| `export.rs`, `bin/stillroom-open.rs` | `exportAll`, and `tools/stillroom-open.py` as a Windows command |
| `tries.rs` | `TryLimit` (in `Views/LockView.swift`): wrong tries, kept beside the vault folder |
| `kinds.rs` | What the Mac learns from `UTType`: an extension's UTI, whether a kind is text, a picture, a PDF, audio or video, and `canEdit`'s allowlist |
| `fsx.rs` | Windows' file system: atomic writes, evened dates (made and changed, folders too), the folder swap, and the Mark of the Web |
| `secure.rs` | Keys in locked memory (`VirtualLock`), out of the page file; the app out of crash reports |
| `ffi.rs` | The C interface the WinUI app calls (`include/stillroom.h`) |
| `tpm.rs` | Lock to this PC (`MacLock.swift`'s counterpart): a TPM key wraps the outer key that seals both password keys again; `pc.key` |
| `hello.rs` | Windows Hello's way in (`TouchIDKey.swift`'s counterpart): the app asks Hello to sign a challenge, the signature seals the slot key; `hello.key` and the list's `hello` field |
| `platform.rs` | Process hardening (mitigation policies), and the vault folder readable by this account only |
| `desktop.rs` | Typing a secret on a desktop of its own, out of other programs' keyboard hooks' sight |

Not here, because the platform layer will do them: Windows Hello and the TPM (Touch ID and Lock to this Mac), the camera, the RAM disk, the Recycle Bin, reading PDFs and pictures for search, and remembering when the last backup was made.

### Where Windows differs from the Mac

- **No atomic folder swap.** The Mac swaps a slot (or the whole vault, on restore) in one `renamex_np` call. Here it's three renames through a `<name>.swapping` folder, and `Store::recover`, run before anything reads the folder, finishes or undoes one a crash cut short. `backup.rs` and `vault_flow.rs` stop a swap at every step and check a whole vault opens.
- **A Mac's lock can't move here.** A vault locked to a Mac opens here only with its recovery key or kit; setting a new password afterwards removes `mac.key` and writes the password key plain. The other slot's password key stays sealed to that Mac until its own recovery key is used, as the Mac does when the lock moves.
- **Opening tidies; taking out doesn't.** `Store::read_only()` opens without pruning or rewriting anything, for `stillroom-open` and the tests of the committed fixtures.
- **Exports are marked as downloaded.** Where the Mac sets its quarantine flag on everything taken out, Windows gets the Mark of the Web (a `Zone.Identifier` stream), so SmartScreen checks a program before it runs. It's written before the file's dates are set, so they survive.
- **A backup can't race a save, by construction.** The Mac counts saves and packs a backup of an open vault again if one landed. Here `Vault::backup` holds the vault borrowed, so nothing in the process can save to it meanwhile, and `Vault::restore_backup` takes the vault, so it's locked before the restore.
- **`TryLimit` lives beside the vault folder** (`tries.json` in `%APPDATA%\Stillroom`), where the Mac keeps it in its preferences. The engine counts each check of a new password against the other slot; the lock screen will count its wrong tries and clear it on a good one.
- **Windows' own ways in.** Lock to this PC (`pc.key`) and Windows Hello (`hello.key`, the list's `hello` field) are Windows' files; the Mac doesn't know them yet (see `../PORT.md`, "For the Mac, after the port"). A vault locked to a Mac or a PC opens on the other only with its recovery key or kit, and one computer holds the lock at a time.
- **Process hardening can't be as strict as the Mac's.** A .NET app can't take "Microsoft-signed DLLs only" or "no dynamic code"; what's on is listed in `platform.rs`.

## The interface the app calls

`include/stillroom.h` is the C interface, generated from `src/ffi.rs` (`tests/header.rs` fails when they drift; `STILLROOM_WRITE_HEADER=1 cargo test --test header` writes it again). `cargo build` makes `target/debug/stillroom_core.dll` and its import library.

- The app holds opaque handles (a store, an open vault, a reader for playback) and never a key. Freeing a vault handle is locking it. A vault handle may be used from several threads; calls on it take turns, so a backup can't race a save.
- Passwords, recovery keys and kit pieces go in as UTF-8 byte buffers the app can wipe. Lists and reports come back as JSON; contents as buffers the engine wipes when they're freed.
- Every call returns a status (0: done); `stillroom_last_error()` has the words, ready to show. A panic is caught at the boundary and reported, never let through.
- `stillroom_keys_are_locked()` says whether keys are in locked memory; `stillroom_exclude_from_crash_reports()` keeps the app out of Windows Error Reporting (call it at start).

`bindings/csharp/Stillroom.Native` is the interface for .NET, as the WinUI app uses it: a `Store` opens a `Vault` (dispose it to lock), failures are `StillroomException`s, secrets go in as spans. A `Vault` holds its handle as a `SafeHandle`, so locking from one thread while a call runs on another refuses new calls at once and locks in the engine when the running one returns, never under it. `bindings/csharp/Stillroom.Native.Tests` drives a real vault through it:

```bash
cargo build
cd bindings/csharp/Stillroom.Native.Tests && dotnet run
```

`tests/ffi.rs` calls the interface from Rust as the app would, and `tests/c_abi.rs` builds `tests/c/smoke.c` with MSVC (at `/W4 /WX`) against the header and the DLL and runs it.

## Taking a vault out by hand

```bash
cargo run --bin stillroom-open -- STORE_FOLDER OUT_FOLDER              # asks for the password
cargo run --bin stillroom-open -- STORE_FOLDER OUT_FOLDER --recovery   # asks for the recovery key
cargo run --bin stillroom-open -- STORE_FOLDER OUT_FOLDER --kit        # asks for kit pieces
```

## Tests

Each Mac test suite has its Rust counterpart, test for test: `vault_flow.rs` (VaultFlow, ItemKey, ChunkBinding, Check, Folder, Originals, ExportKit and the import flow), `decoy.rs` (one test per tell in `docs/SECURITY.md` rule 2), `review_fixes.rs` (ReviewFixTests), `backup.rs`, `chunked.rs`, `intruder.rs`, `kit.rs`, `crypto.rs`, `argon2.rs` and `small_pieces.rs` (two-factor codes, password strength, import, email). `stretches.rs` counts the Argon2 runs per try, so every try is checked to cost the same whichever slots can answer. Each test makes a vault of its own in a temp folder.

Windows' own protections: `pc_lock.rs` (against this PC's real TPM, skipped without one; every TPM key a test makes is deleted), `hello.rs` (with a stand-in for Windows Hello's signature; `tests/hello/windows-hello.ps1` runs the real thing by hand, asking for your PIN), `hardening.rs` and `secure.rs` (each alone, as they change the whole process), `folder_permissions.rs`, and `secure_desktop.rs` (the prompt made on its own desktop and typed into, without switching the screen). `cargo run --example secure_prompt` shows the secure desktop for real.

Two fixtures check the format both ways:

- **`tests/fixtures/`, written by the Mac app** (`writesFormatFixture`). `mac_fixture.rs` opens it read only, with the password, the recovery key, every pair of kit pieces and the decoy, and checks every byte and date; it also checks the Mac's file names read as the right slot's and that opening a copy deletes nothing.
- **`tests/fixtures-windows/`, written by this engine**, laid out the same way. `tools/stillroom-open.py` opens it through `tools/test-stillroom-open.sh`'s checks, and the Mac app through `macos/Tests/StillroomTests/WindowsFixtureTests.swift`. To write a new one: `STILLROOM_WINDOWS_FIXTURE_DIR=<empty folder> cargo test --test windows_fixture writes_windows_fixture`.

Don't regenerate either fixture unless the format changes: each run makes new random keys and files. Both have a `.gitattributes` marking them binary, because git on Windows (with `core.autocrlf`) would otherwise turn LF into CRLF in them.

The WinUI app built on it is in [`../app`](../app).
