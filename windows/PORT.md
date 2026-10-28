# Stillroom → Windows: port analysis

Scope of what it would take to bring Stillroom (macOS 26+, Apple silicon, SwiftUI) to Windows.

## TL;DR

**This is a rewrite, not a port.** Swift runs on Windows, but SwiftUI, AppKit, CryptoKit, Security.framework and the Secure Enclave do not. Those frameworks make up nearly all of the app.

What carries over almost for free is the part that matters most: **the vault format**. It's public and fully documented (`docs/FORMAT.md`), the password stretching is portable C, and `tools/stillroom-open.py` proves in about 300 lines that the format can be read without any Apple API. A Windows app that writes the same format gives you **vaults that open on either OS**.

## The codebase at a glance

About 8,700 lines of app Swift, plus the vendored Argon2 C.

| Layer | Lines | Portability |
|---|---|---|
| `Views/` (lock screen, vault, viewers, editors, settings) | ~3,450 | 🔴 Full rebuild (SwiftUI) |
| `Storage/` (VaultStore, chunked, backup, search, RAM disk) | ~1,390 | 🟢 Logic ports, 🟡 RAM disk doesn't |
| `AppState.swift` (the source of truth, every action) | ~1,060 | 🟢 Logic ports, but it's tied to `@Observable` |
| `Security/` (activity log, intruder log/cam, strength, hotkey) | ~890 | 🟡 Mixed |
| `Models/` (items, secrets, email, password import) | ~700 | 🟢 Mostly portable |
| `Crypto/` (sealing, Argon2, kit, Touch ID, Mac lock, TOTP) | ~540 | 🟢 Algorithms port, 🔴 Enclave doesn't |
| `Design/` (the design kit, capture shield) | ~500 | 🔴 Rebuild |
| `macos/Sources/CArgon2` | C | 🟢 **Compiles on Windows unchanged** |

Framework imports across the app: SwiftUI (16 files), AppKit (13), CryptoKit (12), UniformTypeIdentifiers (10), plus PDFKit, AVFoundation, AVKit, PencilKit, Vision, Quartz, WebKit, LocalAuthentication, Carbon and CoreImage.

## 🟢 Ports directly: the vault engine

These are plain algorithms with no OS dependency. Translate them straight across and test against `docs/FORMAT.md` and the Python reader.

- **AES-256-GCM** with authenticated-data binding (`seal`/`unseal`, `Bound`), available on any crypto library.
- **Argon2id** (512 MB, 3 passes, 4 lanes): `macos/Sources/CArgon2` is the unchanged reference C and builds with MSVC or MinGW as-is.
- **HKDF-SHA256, SHA-256, P-256 key agreement.**
- **Shamir secret sharing**, the emergency kit (`EmergencyKit.swift`).
- **Padmé size padding** (`paddedLength`).
- **The VLT2 chunked format** and its range reader (`Chunked.swift`).
- **RFC 6238 two-factor codes** (`OneTimeCode.swift`).
- **The two-slot / decoy layout**, covers, item keys and the sealed search index.
- **Atomic backup restore** (stage beside the vault, then one atomic rename). On Windows, use `MoveFileEx` / `ReplaceFile`, and test it the way `BackupTests` does.

⚠️ **Keep the format labels byte-identical** (`"Vault list 3"`, `"Vault cover 4"`, `"Vault Touch ID"`…). They're part of the format, and changing one makes every vault unreadable. That includes cross-platform ones.

## 🟡 Same idea, needs a Windows replacement

| macOS today | Windows replacement | Notes |
|---|---|---|
| CryptoKit | CNG/BCrypt, or libsodium / RustCrypto | Same AES-GCM behaviour |
| `~/Library/Application Support/Stillroom/Store` | `%APPDATA%\Stillroom\Store` | File-date evening (`evenDates`) needs Win32 `SetFileTime` |
| **Hidden from capture** (`sharingType = .none`) | `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` | ✅ Good match (Windows 10 2004+) |
| Lock hot key, ⌃⌥⌘L (Carbon) | `RegisterHotKey` | ✅ Good match |
| Menu bar extra | System tray (`NotifyIcon`) | ✅ Good match |
| Intruder camera (AVFoundation) | Media Foundation / `MediaCapture` | ✅ Good match; needs the camera permission |
| PDF viewer (PDFKit) | PDFium | Rebuild. Not WebView2 (see "Keep 'never goes online' true") |
| Image viewer | WIC | Rebuild |
| Audio/video streamed from chunks (AVPlayer) | Media Foundation with a custom byte-stream source, or libVLC | The chunk-reading logic ports; only the player is new |
| Email `.eml` viewer **with network lockdown** | A sanitized HTML renderer with no networking | ⚠️ Must re-prove "loads nothing remote" (see `MailLockdownTests`) |
| Quick Look fallback | Windows preview handlers (`IPreviewHandler`) | Best effort |
| Edit in Place on a **RAM disk** (hdiutil) | ImDisk/Arsenal driver, or a temp file with a secure wipe | ⚠️ Windows has no built-in user RAM disk: needs a driver (and admin rights) or a weaker guarantee |

## 🔴 Apple-only: no direct equivalent

| Feature | Windows reality |
|---|---|
| **Touch ID via the Secure Enclave** (`TouchIDKey`) | **Windows Hello** (`KeyCredentialManager`), with a TPM-backed key. Similar concept, different API; machines without Hello lose it |
| **Lock to this Mac** (`MacLock`, an Enclave outer seal) | A **TPM 2.0**-sealed key (CNG Platform Crypto Provider). Machines without a TPM lose it |
| **Secure Keyboard Entry**, the anti-keylogger (`EnableSecureEventInput`) | ❌ **No Windows equivalent.** No API stops other apps reading keystrokes system-wide. This protection is lost |
| Document scan with an iPhone (Vision / Continuity) | ❌ Drop it, or use WIA/TWAIN scanners |
| Sketches (PencilKit) | ❌ Build a custom ink canvas (Windows Ink) |
| Import from Apple Passwords | Replace with CSV import from browsers and Bitwarden |
| The whole SwiftUI interface | ❌ Rebuild in a Windows UI framework |
| Notarization + `check-offline.sh` | Authenticode signing; rewrite the "no networking" build check against Windows imports (`ws2_32`, `winhttp`, `wininet`…) |

## Security parity plan

The goal is the same app with the same protections. Almost all of them carry over; keylogger protection is the one that can only be approximated.

### 1. Require Windows 11

The Mac app requires macOS 26; the Windows app should require Windows 11. That guarantees a **TPM 2.0** chip (the Windows counterpart of the Secure Enclave) on every supported PC, and guarantees `WDA_EXCLUDEFROMCAPTURE` works.

### 2. Rust core for everything that touches keys

- Keys live only in Rust memory, each in a 32-byte slot of pages kept for keys alone and locked with `VirtualLock`, so they never reach the page file; each is wiped with `zeroize` when dropped, and all of them when the vault locks (done: `engine/src/secure.rs`, tested with 40,000 keys). If Windows ever refuses to lock more, keys still work and `stillroom_keys_are_locked()` says so, for the app to warn. Locking doesn't keep pages out of hiberfil.sys: only BitLocker or Device Encryption protects that.
- C# moves objects around in memory, so it can't promise that a key was wiped everywhere. The UI shell never holds a slot key, cover key or item key; it only gets decrypted content to display.
- Exclude the process from Windows Error Reporting dumps, so a crash never writes keys to disk (done: `stillroom_exclude_from_crash_reports()`, for the app to call at start).

### 3. Mac protection → Windows equivalent

| Mac protection | Windows equivalent | Same strength? |
|---|---|---|
| AES-256-GCM, Argon2id, item keys, two slots / decoy | Identical code and format | ✅ Yes |
| Hidden from screen capture | `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` on every window and dialog; the lock screen is always hidden | ✅ Yes |
| Touch ID through the Secure Enclave | Windows Hello (`KeyCredentialManager`, TPM-backed key). Hello signs a fixed challenge; RSA PKCS#1 v1.5 signatures are deterministic, so the signature goes through HKDF to give the key that unlocks the slot | 🟡 Close. Hello always allows a PIN as well as a fingerprint or face. The PIN is protected against guessing by the TPM, but the Mac version is fingerprint-only. Windows also has no counterpart to `biometryCurrentSet` (enrolling a new finger cutting off the key) |
| Lock to this Mac | Lock to this PC (done: `engine/src/tpm.rs`): a non-exportable RSA key in the TPM (Platform Crypto Provider) wraps the outer key that seals both password keys again; `pc.key` | ✅ Yes |
| Other user accounts can't read it | The vault folder's permissions replaced by one entry, this account's, inherited by everything inside (done: `engine/src/platform.rs`) | ✅ Yes |
| Hardened runtime / library validation | Process mitigation policies (done: `engine/src/platform.rs`): no extension DLLs (`ProcessExtensionPointDisablePolicy`: the DLLs Windows injects for keyboard hooks, AppInit_DLLs, layered providers), no images from the network or low-integrity files, System32 first, invalid handles fatal | 🟡 Partly. A .NET app can't take "Microsoft-signed DLLs only" (it would refuse the app's own code) or "no dynamic code" (it would stop .NET's JIT); worth looking at again with NativeAOT and signed builds in Phase 6. Blocking extension DLLs also turns off IMEs, so it's a setting, on unless someone types with one |
| No networking (`check-offline.sh`) | A build check that fails if the binary imports `ws2_32`, `winhttp`, `wininet`, `dnsapi`, `webio` and similar | ✅ Yes |
| Tamper-evident vault | Unchanged (authenticated data on every seal) | ✅ Yes |

### 4. Keyloggers: the one real gap

Windows has no Secure Keyboard Entry, so nothing can hide every keystroke from every other app. Three layers get close:

1. **Type the password on a separate secure desktop** (`CreateDesktop` and `SwitchDesktop`), the technique behind the Windows admin prompt and KeePass's "Enter master key on secure desktop". Keyboard hooks on the normal desktop don't see input there. Use it for the password, recovery key, emergency-kit pieces and the decoy password.
2. **Unlock with Windows Hello** wherever possible, so usually nothing is typed at all.
3. **Block extension DLLs** (`ProcessExtensionPointDisablePolicy`, above), so keyloggers that work by injecting a DLL through a keyboard hook can't load into the app.

The secure desktop is done (`engine/src/desktop.rs`, `stillroom_secure_prompt`); `cargo run --example secure_prompt` shows it.

Found by testing the app (26 October 2026):

- **The screen didn't come back** after a prompt: the switch back to the normal desktop never ran, so the screen stayed on the prompt's empty desktop. Fixed: the prompt now switches back while it's still the window in front (Windows refuses the switch to a process with no window left on that desktop), with the old fallback made to work too.
- **What it stops, and what it doesn't, as tested:** keyboard hooks on the normal desktop don't see the prompt. A program running as you that goes looking for the prompt's desktop can join it, though, and type into the box (the test helper did exactly that). It couldn't read the password box back, which Windows protects; the emergency kit's box isn't a password box, so its pieces should be readable that way (not tried: nothing in the app makes a kit yet). Worth considering: refusing `WM_GETTEXT` from other processes in the prompt's boxes. Either way the Windows `SECURITY.md` must say that the secure desktop is protection from keyloggers, not from software already running with your rights.

**What remains:** typing *inside* an open vault (editing a note or a secret) can still be seen by an unprivileged low-level keyboard hook. The Windows `SECURITY.md` must say this, and the README must not claim the Mac's "keyloggers that use event taps" protection word for word. The agreed wording: "Typing is protected from keyloggers on the unlock screen. Once the vault is open, Stillroom can't stop software already running on your PC from reading keystrokes."

### 5. Keep "never goes online" true

- **No WebView2 and no Tauri.** Both are built on Chromium, which carries a full networking stack, so the offline build check would be meaningless. Render email with a sanitized HTML renderer that has no networking, and keep a Windows port of `MailLockdownTests` (a hostile email aimed at a local server must cause zero connections).
- PDFium has no networking and is fine.
- **Consider MSIX packaging without the `internetClient` / `privateNetwork` capabilities.** Windows itself then blocks every connection, which is stronger than the Mac's build check. The trade-off is that files can only be reached through file pickers and drag and drop. That's enough for adding files and for deleting originals after the SHA-256 read-back, but needs testing.

### 6. Edit in Place

- **Done (`app/Stillroom/Platform/EditDesk.cs`):** the working copy goes into `%LOCALAPPDATA%\Stillroom\Desk`, a folder only the current user can read and Windows Search leaves out, is overwritten before it's deleted (when done, on locking, at quit, and at the next start after a crash), and the warning the Mac shows comes first. Delete-on-close and the temporary-file attribute were left out: another app opens, saves and reopens the file, and either would break that. On SSDs, overwriting isn't a guarantee, and the Windows `SECURITY.md` should say so.
- **Done:** whether BitLocker or Device encryption is on is checked (as Explorer reports it), and the warning says when it's off, since that's what protects any copy left on disk.
- **Optional, still open:** a RAM disk (ImDisk) for people who want the Mac's no-trace guarantee.

### Result

| | Windows vs Mac |
|---|---|
| Encryption, format, tamper evidence, offline, other accounts, device lock, screen capture | Same |
| Biometric unlock | Slightly weaker (Hello's PIN fallback, no new-finger cut-off) |
| Keyloggers | Strong at unlock, partial inside an open vault |
| Edit in Place | Same with a RAM disk, best effort without |

These need their own Windows `SECURITY.md`. Don't copy the Mac one across.

## Recommended stack

**A Rust core with a C# / WinUI 3 interface.**

| Part | Choice | Why |
|---|---|---|
| Vault engine and every key | **Rust** (`aes-gcm`, `hkdf`, `p256`, `zeroize`, the vendored `CArgon2`) | Keys can be locked in memory and reliably wiped; memory-safe; the same engine could later serve macOS too |
| Interface | **C# / .NET 8 + WinUI 3**, calling the core over FFI | Windows Hello, TPM, WIC, Media Foundation, the tray and capture affinity are all first-class |
| Not used | WebView2, Tauri, Electron | Chromium brings a networking stack (see "Keep 'never goes online' true") |

The engine must pass the existing format fixtures and the Python reader before any UI is built. Keeping it separate from the UI is what makes cross-platform vaults trustworthy.

## Rough effort (one experienced developer)

| Workstream | Estimate |
|---|---|
| Vault engine: crypto, format, Argon2, Shamir, VLT2, TOTP, two slots, covers, item keys | 3–5 weeks |
| Storage: search index, verified deletion, atomic backup/restore | 2–3 weeks |
| Platform security: Hello, TPM, capture shield, hot key, tray, intruder camera | 3–4 weeks |
| UI: lock screen, vault browser, editors, settings, tour, design kit | 6–10 weeks |
| Viewers: PDF, image, streamed AV, locked-down email, preview fallback | 2–4 weeks |
| Parity testing, cross-OS vault round-trips, security review | ongoing |

**About 4–6 months to 1.0 parity.** Cutting iPhone scan, sketches and the RAM disk from v1 brings it nearer the lower end.

## Suggested order

1. ✅ **Engine first, no UI.** Done (`engine/`): the whole of `AppState` and storage, with every Mac test suite ported. It opens the vault the Mac app wrote (`engine/tests/fixtures/`), and `tools/stillroom-open.py` opens the one it wrote (`engine/tests/fixtures-windows/`).
2. ✅ **The tests that guard the format**: `DecoyTests`, `ItemKeyTests`, `ChunkBindingTests`, `BackupTests` and the rest, test for test.
3. ✅ **The Mac opening a Windows vault**: `macos/Tests/StillroomTests/WindowsFixtureTests.swift` opens `engine/tests/fixtures-windows/` every way in, and keeps using it. Passes on the Mac.
4. ✅ **The C interface for the WinUI app, and keys kept out of the page file**: `engine/include/stillroom.h`, called from C and from the .NET bindings (`engine/bindings/csharp`) in tests; keys in locked memory; out of crash reports.
5. ✅ **Platform security, in the engine**: process hardening, the vault folder for this account only, the secure desktop, Lock to this PC through the TPM, and Windows Hello's way in (the engine side: the app asks Windows Hello to sign, the engine does the rest). Tested on a PC with a TPM, and with real Windows Hello (a PIN) by `engine/tests/hello/windows-hello.ps1`: Hello signs the same challenge the same way every time, and its signature opens the vault.
6. UI and viewers, starting with what belongs to the window. **Begun** (`app/`): the WinUI 3 app with the capture shield on every window, the lock hot key (Ctrl+Alt+Shift+L), the tray, locking on sleep, the display going off, Windows locking and when idle, the lock screen with every secret typed on the secure desktop, and the Windows Hello prompt. Then the vault itself: the sidebar, folders, tags, search, adding with the originals question, each item's menu, notes and secrets with their editors, the clipboard, Save a Copy and versions. Then Settings (all four tabs), the intruder log and its camera, Edit in Place, the welcome tour, dragging between folders and "Move to Stillroom" from Explorer, all tried by hand. **Phase 4 is done**, but for printing a page of the kit on a real printer. Next: the viewers (Phase 5).
7. Windows `SECURITY.md`, an offline build check, signing.

## For the Mac, after the port

The Windows files and fields the Mac doesn't know yet. None of them stops the Mac opening a vault; each is a gap until it's done.

- **`hello` in the list** (`engine/src/hello.rs`): the SHA-256 of the Windows Hello credential's public key, base64, or 32 zero bytes. `VaultIndex` should keep it (`decodeIfPresent`, zeros by default). Today a save on the Mac drops it, and Windows then shows Hello as off for that vault (it still opens it).
- **`hello.key`**: a key file, to even with the others; deleted when the slot it opens is replaced, as `touchid.key` is.
- **`pc.key`** (`engine/src/tpm.rs`): with it, the Mac should say the vault is locked to the PC that made it and to use the recovery key or kit (not "wrong password", and not a wrong try), and remove it when a new password is set after a recovery key, as Windows does with `mac.key`. It's a key file too.
- **`<name>.swapping` folders**: put right on opening, as `Store::recover` does (decided).
- **The vault never goes into itself** (`Store::own_paths`, test `the_vault_never_goes_into_itself`): adding a folder that holds the vault folder skips the vault and what's beside it. Without it, Delete Originals afterwards deletes the vault's own keys and list one by one (found testing the Windows app). The Mac's hidden `~/Library` keeps a home folder safe, but adding `~/Library` or Application Support directly would do it there too.
- **`docs/FORMAT.md` and `tools/stillroom-open.py`**: `hello.key`, `pc.key` and the `hello` field; the Python reader should give `pc.key` the message it gives `mac.key`.

## Decided (Gjin, 26 October 2026)

- **One format, cross-platform vaults.** A vault opens on either; each side's tests open the other's fixture.
- **`.swapping` folders: the Mac learns them too.** A vault can be copied from Windows to a Mac after a crash, and a slot left under `<name>.swapping` would look missing. The Mac should put it right on opening as `Store::recover` does: a slot or a whole vault missing with its `.swapping` folder there goes back; both there, the `.swapping` one is the old copy (a slot's goes, a restored vault's is kept as `Store-before-restore-…`). **To do on the Mac (Gjin)**, and a line for `docs/FORMAT.md`.
- **Keyloggers, as the product says it:** "Typing is protected from keyloggers on the unlock screen. Once the vault is open, Stillroom can't stop software already running on your PC from reading keystrokes."
- **Windows Hello: off by default, like Touch ID.** Turning it on says plainly that the Windows Hello PIN opens the vault too, not only a finger or face.
- **Licensing: one license key for both platforms.** They're the same product.
- **The search index's JSON** is now in `docs/FORMAT.md`: a flat `["UUID", {"changed", "size", "text"}, …]` array.

## Still open

- **MSIX without network access**: worth the file-access trade-off?
- **The RAM disk**: optional ImDisk support, or temp files with a warning only?
