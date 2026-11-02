# Security rules: Windows

The Windows app's counterpart of [`docs/SECURITY.md`](../docs/SECURITY.md), rule by rule. The vault itself is the Mac's: the same engine logic, the same format, the same item keys, two slots and decoy, so everything the Mac's file says about them (rule 2, Item keys, Streamed files, Argon2id, the emergency kit, the licence, What still shows on disk) holds here unchanged, and isn't repeated. This file says what differs: what Windows gives, what it doesn't, and what was done instead. Read it before changing anything security-related in `windows/`. The plan behind it is [`PORT.md`](PORT.md), "Security parity plan".

## What Stillroom for Windows protects against, and what it doesn't

**It protects against:**
- a stolen or borrowed PC (with BitLocker or Device Encryption on: see rule 1)
- a copied vault folder, on this PC or any other; with Lock to this PC, a copy opens on no other PC even with the password
- anyone taking the app apart: there's no secret in it, and the format is public
- tampering with the vault: every byte is authenticated and bound to what it is (`docs/SECURITY.md`, Item keys)
- other accounts on the PC: the vault folder is readable by this account only (rule 3)
- screenshots, screen recording and screen sharing
- keyloggers on the unlock screen. Said exactly this way, in the app and anywhere it's sold: "Typing is protected from keyloggers on the unlock screen. Once the vault is open, Stillroom can't stop software already running on your PC from reading keystrokes."

**It does not protect against:**
- a weak password: the strength check refuses guessable ones
- software running as you, while the vault is open: it can read Stillroom's memory, what you type in the vault, and the clipboard. At the lock screen it can't see the password being typed, but it can find the secure desktop and type into it (rule 9)
- anything running as an administrator, at any time
- the Windows Hello PIN: Windows Hello always takes a PIN as well as a face or finger, so whoever knows the PIN opens the vault where Hello is on (rule 10)
- hibernation and old SSD blocks without BitLocker: keys are kept out of the page file, but nothing keeps them out of hiberfil.sys, and a deleted Edit in Place copy can survive on an SSD (rule 1)
- copies another app keeps after Edit in Place: the warning says so

## Rules

**1. Plaintext never lands on the disk, as far as Windows allows.**

The Mac keeps every copy on a RAM disk. Windows has none built in (a driver such as ImDisk would need installing as an administrator; still open, `PORT.md`), so two things are written to disk, and BitLocker or Device Encryption is what protects them afterwards:

- **Edit in Place** copies go in `%LOCALAPPDATA%\Stillroom\Desk\<random>\<name>`: a folder only this account can read, left out of Windows Search. Each copy is overwritten with zeros and deleted when editing is done, when the vault locks, at quit, and (left by a crash) at the next start. **On an SSD, overwriting isn't a guarantee:** the drive may write the zeros elsewhere and keep the old blocks until it reuses them. The warning before opening says when BitLocker is off. Delete-on-close and the temporary-file attribute were left out on purpose: apps open, save and reopen their file, and either would break that.
- **The fallback preview** (bitmap fonts and 3MF models, through Windows' previewers) needs a file too, in `%TEMP%\Stillroom Look\<random>\<name>`, with the same protections and wiping: when the card closes, at lock, quit and start. It's in Temp because Windows' font previewer won't draw a file elsewhere in AppData.

Nothing else is written. Pictures, PDFs, audio and video are read from memory or straight from the sealed chunks (`VaultStream`); words for search are read from pictures and PDF pages drawn in memory; email is drawn from the engine's blocks.

**Keys** live only in the Rust engine, in pages of their own locked with `VirtualLock`, so they never reach the page file, and each is wiped when dropped and all of them when the vault locks (`engine/src/secure.rs`). If Windows ever refuses to lock more pages, keys still work and `stillroom_keys_are_locked()` says so. **Locking doesn't reach hiberfil.sys:** hibernation writes all of memory, locked or not. Only BitLocker or Device Encryption protects that; the app locks the vault when the PC goes to sleep, which empties it of keys before most hibernation.

**Crash reports:** the app takes itself out of Windows Error Reporting at start (`WerAddExcludedApplication`), so a crash writes no report or dump of its memory. .NET's own dump writer, `createdump.exe`, isn't shipped (rule 5).

**2. The decoy works as on the Mac.**

`docs/SECURITY.md` rule 2 holds word for word, with these Windows things added:
- **Windows Hello opens one vault**, the one where it was last turned on, as Touch ID does. If you rely on the decoy, turn Hello on in the decoy or not at all.
- **Lock to this PC covers both** (`pc.key`), as Lock to this Mac does. Whether `pc.key` and `hello.key` exist shows on disk, not which vault they belong to.
- **Beside the folder**, in `%APPDATA%\Stillroom`: `tries.json` (the wrong-try count), `settings.json` (preferences, rule 3) and `License`. None of them says which vault is open.
- **Names on disk.** An Edit in Place or preview copy keeps the file's own name (so its app's title is right), in a random folder, and is wiped afterwards. Windows' Recent items, an app's own recent list and jump lists can remember the name, and a name not in the decoy points to another vault. Don't Edit in Place or preview names you'd need to deny.

Say exactly this, in the app and anywhere it's sold: protection against thieves and abusers, not police.

**3. Nothing that weakens protection goes in preferences, with one exception.**
- Preferences are `%APPDATA%\Stillroom\settings.json`, which any program running as you can change. They hold auto-lock, the tray icon, appearance, the intruder photo switch, "don't ask again", and one protection switch (below).
- The "show in screenshots" switch lives in the sealed list, as on the Mac, and the lock screen is always hidden.
- **The exception: keeping Windows' extension DLLs out** (rule 9). It must take effect as the process starts, before any vault is open, so it can't come from the sealed list. It's on unless someone types with an input method editor (IME), which it also keeps out. A program able to change `settings.json` already runs as you, and can read your keystrokes in an open vault anyway.
- The vault folder's permissions are replaced by one entry, this account's, inherited by everything inside and nothing from above (`engine/src/platform.rs`): the Mac's 0700. An administrator can still take ownership and read it, sealed.

**4. The activity log keeps no secrets.** There's no activity log on Windows yet. When there is one, the Mac's rule 4 applies to it in full.

**5. Stillroom never goes online.**

- **Email has no HTML engine at all.** The engine reads the message into blocks of words and pictures (`engine/src/mail_page.rs`), keeping only pictures from inside the email (`cid:` parts and `data:` bitmaps); every other address is dropped, so nothing in a message can load. The app draws the blocks with Windows' own text controls. Links don't open; clicking one shows where it goes. `engine/tests/mail_page.rs` checks that no address survives in a hostile email but a link's words, and `app/tests/lockdown.ps1` is the Windows port of `MailLockdownTests`: the real viewer shows the hostile email while a server on this PC counts connections, on 127.0.0.1 and ::1, and there must be none. The script was checked to catch a leak by planting one.
- **No web view.** WebView2 starts Edge's Chromium, with its own networking. WinUI ships it, so the build deletes the two files that would start one (`WebView2Loader.dll`, `Microsoft.Web.WebView2.Core.dll`), and nothing in the process can.
- **The fallback preview uses only Windows' font and 3MF previewers.** Office's are left out: Word's fetched a document's linked picture from the test server (29 October 2026), and Excel, PowerPoint and Visio can link pictures too. `lockdown.ps1` checks a Word document isn't previewed.
- **The media player can't cast.** WinUI's transport controls offer Cast to Device, which sends the video over the network, so the player has Stillroom's own controls. Windows' media session is off too (`CommandManager` and the system transport controls), so nothing of what plays shows in the volume overlay or on the lock screen.
- **Check for Updates opens the release notes in the browser.** Stillroom itself connects to nothing.
- **The tamper check is offline** (rule 12): no revocation check, nothing fetched.

**The offline check.** `tools/CheckOffline` runs on every build `make-app.ps1` makes, and a build that fails it is deleted. It reads every program file in the app folder, Microsoft's included, and fails on:
1. a native import, direct or delay-loaded, of a networking DLL: Winsock (`ws2_32`, `wsock32`, `mswsock`), HTTP and URL loading (`winhttp`, `wininet`, `webio`, `urlmon`, `websocket`, `httpapi`), names and interfaces (`dnsapi`, `iphlpapi`, `nsi`, `winnsi`), shares (`netapi32`, `mpr`), and the rest of the list in `Program.cs` (RAS, Wi-Fi, connection management, the firewall API, ping, background transfers), or an API set standing for one;
2. a file that starts a web view;
3. in Stillroom's own .NET code (`Stillroom.dll`, `Stillroom.Native.dll`): a reference to a networking assembly or namespace (.NET's `System.Net`, WinRT's `Windows.Networking` and `Windows.Web`, WebView2, Cast and Play To, DIAL, adaptive streaming, remote systems, the Store, web sign-in, Wi-Fi, the Windows App SDK's OAuth and push notifications), a P/Invoke into a networking DLL, a networking DLL's name in a string (for `NativeLibrary.Load`), or a web address other than the release notes' and XAML's namespace names.

`tools/CheckOffline/test.ps1` proves it catches each kind: a DLL importing sockets, one delay-loading WinHTTP, the engine replaced by one importing sockets, a web view's loader, and an assembly standing in for Stillroom's that uses `HttpClient`, P/Invokes WinINet, loads Winsock by name and names a web address. Each fails the check; Stillroom's own files pass.

**What it allows, and why** (it fails on anything new until it's looked at):
- **WinUI imports `urlmon`** (`CreateURLMonikerEx`): it loads a picture or resource it's given a web address for. Stillroom gives it pictures from memory only, and check 3 keeps web addresses out of Stillroom's code.
- **.NET's and the Windows App SDK's networking assemblies ship** (22 of them: `System.Net.Http`, `System.Net.Sockets` and the rest, and the projections for OAuth, push notifications and WebView2). They come with a self-contained .NET and run only when called. Nothing of Stillroom's references them. Trimming them out (.NET's trimming, or NativeAOT) would need WinUI's trimming support tried first; not done.
- **What isn't shipped:** besides the web view files, the build deletes .NET's `msquic.dll` (QUIC, for HTTP/3, which imports Winsock) and `createdump.exe` (which imports Winsock, and writes a crashed process's memory to a file when `DOTNET_DbgEnableMiniDump` is set). It also leaves out the Windows App SDK's on-device AI, ONNX Runtime, DirectML, vision, semantic search and Widgets (47 MB that nothing calls).

The check catches mistakes; it isn't a proof. Code could build a web address at run time and hand it to WinUI, `MediaSource.CreateFromUri` or `Process.Start`, or reach the network through COM by a class id (WinHTTP's or BITS's). Never pass any of them an address that didn't come from a file.

**MSIX without network access** would let Windows itself refuse every connection (no `internetClient` or `privateNetwork` capability), which is stronger than any build check. It's still open (`PORT.md`): files could then be reached only through pickers and drag and drop, which needs trying with adding, deleting originals and Send to.

**6. Edit in Place opens only documents.**
- The same allowlist as the Mac (`engine/src/kinds.rs`, `canEdit`): no programs, scripts, installers, disk images, packages, web pages or sketches.
- Copies are marked as downloaded (the Mark of the Web, a `Zone.Identifier` stream), so Office opens them in Protected View and SmartScreen checks a program before it runs. So is every file taken out of the vault: Save a Copy, attachments, Export Everything.

**7. Originals are deleted only after the vault copy checks out.**
- Each copy is read back and compared by SHA-256 first, and a dropped folder goes whole only if everything in it went in (the engine's `originals.rs`, as the Mac's).
- With BitLocker off, originals go to the Recycle Bin instead of being deleted: deleting wouldn't make them unreadable, and the Recycle Bin at least lets you see what's left. Don't add "secure overwrite": on SSDs it does nothing.
- **A restore can't swap folders in one step.** Windows has no `renamex_np` with `RENAME_SWAP`, so it's three renames through a `<name>.swapping` folder, and `Store::recover`, run before anything reads the folder, finishes or undoes a swap a crash cut short. `engine/tests/backup.rs` and `vault_flow.rs` stop it at every step and check a whole vault opens. Keep it that way: a crash must never leave no vault.

**8. Copied secrets don't spread and don't stay long.**
- Windows has no "this device only" flag, so a copied secret is marked out of clipboard history (`CanIncludeInClipboardHistory`), out of the cloud clipboard (`CanUploadToCloudClipboard`), and out of clipboard managers (`ExcludeClipboardContentFromMonitorProcessing`).
- It's cleared after 30 seconds, or at once when the vault locks or Stillroom quits, if nothing else was copied since.
- Two-factor setups are as secret as passwords, as on the Mac. There's no QR reading on Windows yet.
- A program running as you can still read the clipboard while a secret is on it.

**9. Windows are hidden from capture, and typing at unlock is hidden from keyloggers.**
- **The capture shield:** every top-level window the process makes, menus and flyouts included, is excluded with `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` (`app/Stillroom/Platform/CaptureShield.cs`). The lock screen always is; an open vault follows its sealed "show in screenshots" setting. Menus and flyouts are excluded as Windows reports them made, which can be a frame after they first draw: never put anything secret in one. The fallback preview's window is Stillroom's own, owned by the main one, so the shield covers it too.
- **The secure desktop** stands in for the Mac's Secure Keyboard Entry. The password, recovery key, kit pieces and decoy password are typed on a desktop of their own (`engine/src/desktop.rs`), the technique behind Windows' admin prompt, read straight into memory that's wiped, never a .NET string. Keyboard hooks on the normal desktop see nothing. **What it doesn't stop** (as tested, 26 October 2026): a program running as you can open the prompt's desktop and type into its box. It can't read the password box back (Windows protects those); the kit's box isn't a password box, so a piece could be read that way (not tried; refusing `WM_GETTEXT` from other processes is worth doing).
- **Extension DLLs are kept out** (`ProcessExtensionPointDisablePolicy`): Windows won't load the DLLs it injects for keyboard hooks, AppInit_DLLs or Winsock layered providers, so a keylogger that works by injecting itself can't get into Stillroom. It also keeps IMEs out, hence the setting (rule 3).
- **Inside an open vault, typing isn't protected.** Windows has no API that hides keystrokes from an unprivileged low-level keyboard hook. Hence the agreed wording above; never claim the Mac's "keyloggers that use event taps" protection for Windows.
- **The hot key is Ctrl+Alt+Shift+L**, registered with `RegisterHotKey`: it sees no other keys. Win+L is Windows' own.

**Process protections.** The Mac runs with the hardened runtime and library validation. Windows' counterparts are mitigation policies, set as the process starts (`engine/src/platform.rs`): no extension DLLs (above), no images from the network or from low-integrity files, System32 first when a DLL's name is ambiguous, invalid handles fatal. **What a .NET app can't take:** "Microsoft-signed DLLs only" would refuse Stillroom's own code, and signing doesn't help (the policy's only other option is Store-signed), and "no dynamic code" would stop .NET's JIT. NativeAOT could make "no dynamic code" possible; it's untried with WinUI here.

**10. Every way in seals that slot's key, as on the Mac.**
- Password, recovery key, emergency kit, and **Windows Hello** in place of Touch ID: Hello signs a fixed challenge with its TPM key, and the signature, through HKDF, seals the slot key (`engine/src/hello.rs`). Off by default; turning it on says plainly that the Windows Hello PIN opens the vault too. The PIN is guarded against guessing by the TPM, but it isn't a finger. Windows has nothing like `biometryCurrentSet`: enrolling a new finger or face doesn't cut the key off.
- **Lock to this PC** in place of Lock to this Mac: a non-exportable RSA key in the TPM (the Platform Crypto Provider) wraps an outer key that seals both slots' password keys again (`engine/src/tpm.rs`, `pc.key`). Recovery keys and kits still open the vault on any PC. A vault locked to a Mac opens here only with its recovery key or kit, and the other way round.
- Rotating keys isn't built, as on the Mac (rule 10 there).

**11. Hostile files must not crash the app, or run inside it.**
- The engine's limits are the Mac's or tighter: email parts nest at most 16 deep, at most 256 inline pictures and 64 MB of them, a message read in time in step with its length (shapes built to be slow were tested, and text is cut past a million characters); chunk sizes and Argon2 costs bounds-checked as on the Mac.
- **Windows parses some files inside Stillroom's own process**, while the vault is open and its keys are in memory: pictures (WIC, through WinUI), PDFs (`Windows.Data.Pdf`), TrueType and OpenType fonts (DirectWrite, for the font card), audio and video (Media Foundation), and the words in pictures and PDF pages (`Windows.Media.Ocr`). A file built to exploit a bug in one of them would run as Stillroom. That's the same trade the Mac makes with ImageIO, PDFKit and AVFoundation; Windows Update patches them. Email is parsed by the engine, in Rust, and never by an HTML engine.
- **Bitmap fonts and 3MF models are parsed by Windows' previewers in a process of their own** (`prevhost.exe`), drawing into Stillroom's window from outside, from the copy in `%TEMP%\Stillroom Look` (rule 1).

**12. A changed copy warns before a password is typed.**

The Mac's `SelfCheck`, by Authenticode. `engine/src/selfcheck.rs` checks Stillroom's own four files (`Stillroom.exe`, `Stillroom.dll`, `Stillroom.Native.dll`, `stillroom_core.dll`) with `WinVerifyTrust`: the hash, a code-signing certificate, a chain to a root this PC trusts, and then a signer whose name is `PUBLISHER`. If any fails, the lock screen says, as the Mac's does: "This copy isn't signed by Stillroom's maker, so it may have been changed. Download Stillroom again from stillroomvault.com." It protects people from a doctored download; whoever changes the app can take the check out too (`docs/SECURITY.md`, Tampering and cracking: no obfuscation, no hidden checks).

- **It pins a name, not a certificate.** Certificates are renewed, and a signing service may issue a new one every few days, so the app checks the subject name as the Mac checks its team. A certificate authority vouches for the name; anyone else's certificate has another.
- **Offline:** revocation isn't checked and nothing is fetched (`WTD_REVOKE_NONE`, `WTD_CACHE_ONLY_URL_RETRIEVAL`), so a revoked certificate's signatures still pass. That's the price of never going online. Release signatures are timestamped, so they stay good after the certificate expires.
- **There's no certificate yet**, so `PUBLISHER` is unset and nothing warns. Development builds try it with a throwaway self-signed certificate: `sign.ps1 -Test` signs, and `STILLROOM_SIGNER_TEST` names the publisher to expect (an untrusted root is then accepted; release builds ignore the variable). `engine/tests/selfcheck.rs` checks an unsigned copy, a signed one, one changed after signing, one signed again by someone else, and .NET's own Microsoft-signed `dotnet.exe` against a trusted root. Tried on the app (30 October 2026): no warning signed; the warning unsigned, signed by another name, and with one byte of `Stillroom.dll` changed after signing.
- **Without a signature, Windows warns too:** SmartScreen shows "Windows protected your PC" for a download it doesn't know, signed or not, until the certificate has a reputation.

## Things decided against

The Mac's list holds (no server, account or sync; no back door; no forced updates; the decoy not sold as fooling police), and:

- **WebView2, Tauri, Electron:** Chromium brings a networking stack, and the offline check would mean nothing.
- **Office's previewers:** they reach the network for linked pictures.
- **Delete-on-close for Edit in Place copies:** apps reopen their file after saving.
