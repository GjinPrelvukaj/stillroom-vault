# Stillroom for Windows

The app: WinUI 3 (.NET 8, Windows App SDK 1.8, unpackaged and self-contained) on the engine in `../engine`, through its .NET bindings. Windows 11 only. The plan behind it is in [`../PORT.md`](../PORT.md).

## Building and running

Needs what the engine needs, plus the .NET 8 SDK. The Windows App SDK comes from NuGet on the first build.

```bash
cd ../engine && cargo build
cd ../app/Stillroom && dotnet run
```

A development build opens the folder in `STILLROOM_STORE_DIR` instead of the real vault (`%APPDATA%\Stillroom\Store`), so trying it never touches one. Release builds ignore it.

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
| `Preview.cs` | `PreviewCard` (pictures and text from memory; the other viewers are Phase 5) and `VersionsSheet` |
| `SettingsPage.cs` | `SettingsPane` and `SecurityFacts`: Access (password, Windows Hello, Lock to this PC, recovery key, emergency kit, decoy), Protection (auto-lock, tray, capture, keeping other programs out, the intruder photo), Security (the facts, and what Stillroom can't protect against), Data (check, where it lives, back up, restore, export everything, delete) |
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

Not yet tried: a page actually printed (this PC has no printer), restoring a backup from the lock screen, versions (kept only for changes a while apart, as on the Mac), dropping files from Explorer onto the window, and real sleep and a real Win+L.
