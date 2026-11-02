# Stillroom for Windows

The app: WinUI 3 (.NET 8, Windows App SDK 1.8, unpackaged, carrying its own .NET and Windows App SDK) on the engine in `../engine`, through its .NET bindings. Windows 11 only. The plan behind it is in [`../PORT.md`](../PORT.md).

## Building and running

Needs what the engine needs, plus the .NET 8 SDK. The Windows App SDK comes from NuGet on the first build.

```bash
cd ../engine && cargo build
cd ../app/Stillroom && dotnet run
```

A development build opens the folder in `STILLROOM_STORE_DIR` instead of the real vault (`%APPDATA%\Stillroom\Store`), so trying it never touches one (nor the licence beside it). `STILLROOM_LICENCE_SIGNER` (a public key, base64) makes it trust licences from a test key pair instead of the real one: the website's test pair is in `website/server/fixtures/test-licence.json`. Release builds ignore both. Preferences (`%APPDATA%\Stillroom\settings.json`) aren't redirected.

A build as it ships: `../make-app.ps1` (release, self-contained, into `../build/Stillroom`), which runs the offline check (`../tools/CheckOffline`) and deletes a build that fails it, then signs if given a certificate (`../sign.ps1`). The build leaves out WebView2, .NET's `msquic.dll` and `createdump.exe`, and the Windows App SDK's AI and Widgets (`Stillroom.csproj`); `../SECURITY.md` rule 5 says why.

`make-icon.ps1` draws `Stillroom/Assets/Stillroom.ico` from the Mac's `macos/Resources/AppIcon.png`; run it again when that changes.

## What's here

| C# | Mac original |
|---|---|
| `Program.cs` | The start: Windows' protections (`HardenProcess`, out of crash reports) before WinUI loads, and one Stillroom at a time (a second start brings the first forward) |
| `AppState.cs` | `AppState`: the vault folder and the open vault, and every way of locking |
| `MainWindow.xaml(.cs)` | `VaultApp` and `RootView`: one window, closing it quits, locking on Windows locking, sleep, the display going off and after the PC has gone untouched |
| `LockView.xaml(.cs)` | `LockView`: making the vault, the password, the recovery key, the emergency kit, Windows Hello, the wait after wrong tries, restoring a backup |
| `VaultView.xaml(.cs)` | `VaultView`: the sidebar (library, kinds, tags), All Files by folder with its breadcrumb, search by name, folder, tag and contents, adding by picker or drop and the originals question after, each item's and folder's menu, new notes and secrets, importing logins, Save a Copy, and the new password a recovery asks for |
| `Editors.cs` | `NoteEditor` and `SecretEditor`: saved a moment after typing stops, on leaving, and just before the vault locks; concealed fields, generated passwords, two-factor codes |
| `Preview.cs` | `PreviewCard` (pictures, PDFs, email and text from memory, audio and video from the vault, other kinds through `QuickLook`) and `VersionsSheet` |
| `MailViewer.cs` | `EmailView` and `MailPage`: who, when, the subject and attachments, then the message as the engine's blocks (`mail_page.rs`) drawn with Windows' own text controls. No web view, so nothing in a message can load |
| `QuickLook.cs` | `QuickLookView`: Windows' font and 3MF previewers, drawing a copy in `%TEMP%\Stillroom Look` into a small window of Stillroom's kept over the card, in Stillroom's colours |
| `FontCard.cs` | Quick Look's font preview: the alphabet, digits and a sample at growing sizes in the font itself, each line shrinking to fit |
| `Platform/Recognition.cs` | `SearchIndex.recognized` and PDFKit's text: Windows' own text recognition for pictures, and for PDF pages drawn in memory (the first 50), with the vault free |
| `Platform/SelfCheck.cs` | `SelfCheck`: whether this copy is still signed by Stillroom's maker; the lock screen warns if not |
| `ShowAlone.cs` | Development builds only: one file in its viewer with no vault (`STILLROOM_SHOW_FILE`: emails, PDFs, pictures, audio and video, fonts, the fallback), or its words for search (`STILLROOM_READ_WORDS`), for `tests/lockdown.ps1` |
| `MediaViewer.cs`, `Platform/VaultStream.cs` | `VaultPlayer` and `VaultStreamLoader`: Windows' media player reading the sealed chunks as it asks, with Stillroom's own controls |
| `PdfViewer.cs` | `PDFPreview`: Windows' own PDF renderer, pages drawn as they come near the view, zoom by buttons, keys, Ctrl and the wheel, or pinching |
| `SettingsPage.cs` | `SettingsPane` and `SecurityFacts`: Access (password, Windows Hello, Lock to this PC, recovery key, emergency kit, decoy), Protection (auto-lock, tray, appearance, capture, keeping other programs out, the intruder photo), Security (the facts, and what Stillroom can't protect against), Data (check, where it lives, updates, back up, restore, export everything, delete), Licence (free or licensed, pasting a key) |
| `WelcomeIn.cs` | `WelcomeIn`: a licence that checks out, welcomed by name |
| `Theme.cs` | `Appearance` and `Color.ink`/`Color.ground`: light, dark or as Windows is set, and App.xaml's theme brushes for what's drawn in code |
| `Platform/Updates.cs` | `Updates`: Check for Updates opens the release notes in the browser; an old copy says so |
| `IntruderPage.cs` | `IntruderView`: each wrong try, when, and its photo (mirrored, as a mirror shows a face); delete one or clear all |
| `KeyDialogs.cs` | `KitSheet` and `CheckSheet` |
| `RecoveryKeyDialog.cs` | `RecoveryKeySheet`: shown once, then two groups typed back on the secure desktop |
| `Ask.cs` | `NameSheet` and the confirmation dialogs |
| `Model/` | `VaultFile` and `Shelf` (an item's kind from the engine's `stillroom_look`), `Secret` and its templates, the list's rows and tag colours |
| `Secrets.cs` | Every secret typed on the secure desktop (`Engine.SecurePrompt`), never in the window, and never a .NET string |
| `Settings.cs` | The Mac's UserDefaults: auto-lock, the tray icon, blocking extension DLLs (`%APPDATA%\Stillroom\settings.json`) |
| `Platform/CaptureShield.cs` | `.hiddenFromCapture()`: every window the process makes, menus and flyouts too |
| `Platform/SystemWatch.cs` | `LockKey` (the hot key), `MenuBarExtra` (the tray), and the sleep and screen-lock notifications |
| `Platform/WindowsHello.cs` | `TouchIDKey`'s prompt side |
| `Platform/Untouched.cs` | `AutoLock.isDue` |
| `Platform/SecretClipboard.cs` | `Clipboard`: kept out of Windows' clipboard history, the cloud clipboard and clipboard managers, emptied after 30 seconds and on locking or quitting |
| `Platform/Shell.cs` | Explorer's own words for kinds and sizes, and the Recycle Bin |
| `Platform/IntruderCamera.cs` | `IntruderCamera`: one photo, at most 1280 px, given up after 3 seconds, held in memory only |
| `Platform/KitPrinter.cs` | `KitPrint`: the kit's pages drawn straight to the printer, never saved as a document; Windows' print dialog on a thread of its own, so the window can still lock while it's open |
| `Platform/EditDesk.cs` | `EditDesk`: Edit in Place's working copies, each save sealed back in, overwritten and deleted when done, on locking, at quit and (left by a crash) at start |
| `Platform/SendTo.cs`, `Inbox.cs` | The "Move to Stillroom" service and `Inbox`: Explorer's Send to, files waiting while the vault is locked |
| `WelcomeTour.cs` | `WelcomeTour`, before the first vault |

## Where it differs from the Mac

- **The hot key is Ctrl+Alt+Shift+L.** Win+L is Windows' own lock, so ⌃⌥⌘L can't come across as it is. If another app has taken it, the tray's menu still locks.
- **Lock and Hide minimizes** (the Mac hides the app). The taskbar button stays, as the Dock icon does.
- **Nothing is typed in the window.** Unlock, Make Vault, the recovery key, kit pieces, the new password and the recovery key check all ask on the secure desktop, so there are no password fields on the lock screen and no dot ring that lights up as you type.
- **Windows Hello is asked when the window comes forward,** not whenever the lock screen appears, so locking with the hot key doesn't put a Hello prompt over another app.
- **Files and folders are chosen apart** (Add Files ▸ Files… or A Folder…): Windows' pickers can't take both at once, as the Mac's panel does. Dropping takes both.
- **Kinds are named as Explorer names them** ("Text Document", "PNG File"), where the Mac uses the Finder's words.
- **No camera question of Stillroom's own.** Windows gives desktop apps none: "Let desktop apps access your camera" in Windows Settings decides for all of them, so the Mac's "Allow Camera…" step becomes a line saying what that switch is set to, and a Try Camera button.
- **Edit in Place works from a folder on disk, not a RAM disk:** Windows has none built in. The working copy is in `%LOCALAPPDATA%\Stillroom\Desk`, readable by this account only and left out of Windows Search, overwritten before it's deleted; the warning before opening says when BitLocker is off, since on an SSD only that truly protects the deleted bytes. An optional RAM disk is still an open question (`../PORT.md`). Like the Mac's, the copy is marked as downloaded, so Office opens it in Protected View first.
- **"Move to Stillroom" is in Explorer's Send to menu**, when turned on in Settings › Data (off at first: it changes your Explorer menu). The originals go to the Recycle Bin when BitLocker is off, as the Mac's go to the Trash when FileVault is.
- **No activity log yet**, so Settings has no Troubleshooting section.
- **No QR codes for two-factor yet**: Windows has nothing built in to read one, so the setup key is typed or pasted.
- **Email is drawn by Stillroom, not a web view:** Windows has none without Chromium's networking. The message keeps its words, structure, emphasis and its own pictures, in Stillroom's colours rather than the sender's, and its layout is simpler (table cells come one under another). Clicking a link shows where it goes, with Copy Address; the Mac's links just don't open.
- **The fallback preview covers fonts and 3MF models only** (TrueType and OpenType in Stillroom's own font card, bitmap fonts and models through Windows' previewers). The Mac's Quick Look shows Word, Excel and the rest; Windows' Office previewers reach the network for a document's linked pictures (Word's did, in `tests/lockdown.ps1`), so they aren't used. Other kinds offer Save a Copy and Edit in Place.
- **Search reads the first 50 pages of a PDF,** by drawing each page and reading it as a picture (Windows can't take a PDF's text out). The Mac reads a PDF's whole text, but not a scanned one's; Windows finds the words in both. Pictures and PDFs are only read when a text recognition language is installed (Settings › Time & language › Language).
- **The player has Stillroom's own controls,** not WinUI's: theirs can't play once the player is kept out of Windows' media overlay, and they offer Cast to Device.
- **The licence welcome is a dialog,** without the Mac's filling ring and confetti.
- **The tamper warning waits on a certificate:** it's built (`Platform/SelfCheck.cs`, the engine's `selfcheck.rs`), but there's no publisher to check against until Stillroom has its own code-signing certificate, so nothing warns yet. `STILLROOM_SIGNER_TEST` tries it in a development build (`../SECURITY.md` rule 12).
- **Menus and flyouts** are excluded from capture as Windows reports them made, which can come a frame after they first draw. Nothing secret is shown in one yet; keep it that way, or keep such content inside the window.

## Tried so far

On Windows 11 with a TPM and Windows Hello, driving the app from outside: its buttons through UI Automation, and the secure desktop's prompts answered by a test helper that joins that desktop (with made-up passwords, on a throwaway `STILLROOM_STORE_DIR`). After every prompt, the screen was checked to be back on the normal desktop.

- Making a vault: both prompts, Cancel on the second makes nothing, the recovery key shown and checked (Escape doesn't close it; wrong groups are refused; right ones in any case, with dashes, close it).
- Unlocking: the password, the recovery key (then a new password: a weak one and a mismatch refused, and the old password stops working), four wrong tries and the wait, the Lock button.
- Locking: the hot key (and it minimizes), the tray's menu (Lock and Hide, Show, the greyed "locked" line), the display really turned off, auto-lock at one minute untouched, and Windows locking, switching user and sleep (their messages sent to the app as Windows sends them).
- The capture shield (a screen grab over the window, with it in front, shows what's behind it), one copy at a time, and the process protections (`Get-ProcessMitigation`). The .NET bindings' tests cover locking from another thread during a call.

- Windows Hello, with a real PIN typed by hand: turned on while making the vault, then asked by itself as the lock screen came forward, and it opened the vault.
- The vault (Windows' own pickers driven by their control ids): adding files and a folder, then keeping, deleting and recycling their originals (checked on disk); a note saved as typed, reopened, and saved when locked straight after typing; a login with a generated password copied (on the clipboard, marked out of history, cloud and managers, emptied after 30 seconds and at once on locking); a two-factor code; search by a word inside a file in a folder; the menus by keyboard (Shift+F10): rename, tags (sidebar and chips), delete, Save a Copy (the Mark of the Web and the original's dates kept), Move To; opening a file in the card.

- Settings, Access: changing the password (a wrong current one refused; afterwards the old one fails and the new one opens), a new recovery key (the old key stops opening it, the new one does and asks for a password), a 2-of-3 emergency kit (two pieces, in any case, open the vault), a decoy password (it opens a separate empty vault; the real password the real one) and removing it, Lock to this PC with the real TPM on and off (its key file comes and goes), and Windows Hello turned on with a real PIN, offered on the lock screen, opening the vault, and turned off (the key file and Windows' credential both gone).
- Settings, Protection and Data: auto-lock and the tray saved, screen capture on and off, Try Camera, checking the vault, a backup, restoring it (the vault locks, the backup's contents come back, the vault before it is set aside), exporting everything, and deleting the vault (the set-aside copy goes too).
- The intruder log: a wrong password at the lock screen logged with a photo, the photo shown large, one entry deleted, all cleared.

- The welcome tour; Edit in Place (the warning with its BitLocker line and "Don't ask again", a copy in a folder only this account can read and left out of Windows Search, marked as downloaded, a save sealed back in, Done Editing, locking and quitting all wiping it after a last save, a crash's leftover wiped at start); dragging a file onto a folder with the mouse; "Move to Stillroom" sent while open and while locked (waiting on the lock screen); importing logins (twice: nothing comes in twice); the print dialog opening, cancelling cleanly, and the hot key locking while it's open.
- Development builds take `STILLROOM_DESK_NO_OPEN`, so tests put working copies out without opening an app on the screen (the Mac's tests swap `EditDesk.opener`).

- `tests/lockdown.ps1` (run from here, a development build, no Stillroom running): a hostile email, a TrueType font, a bitmap font and a Word document that reaches for the network, each shown in its real viewer while a server on this PC counts connections on 127.0.0.1 and ::1. None for the email and the fonts; the Word document isn't previewed. Checked to fail by planting a picture loaded from the server.
- Words for search, by `STILLROOM_READ_WORDS`: a photo of a receipt and a two-page PDF, read word for word, page two included.
- In the app by Lis, on a throwaway vault: an HTML email with an inline logo, lists, a quote and an attachment (the hidden preheader and the remote tracker not shown); a TrueType font in the font card, fitting as the window is resized; a Word document saying it has no preview; search finding words in a photo and on page two of a PDF.

Not yet tried: a page actually printed (this PC has no printer), restoring a backup from the lock screen, versions (kept only for changes a while apart, as on the Mac), dropping files from Explorer onto the window, and real sleep and a real Win+L.
