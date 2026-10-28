using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Stillroom.Model;
using Stillroom.Native;
using Stillroom.Platform;
using Windows.Storage;
using Windows.Storage.Pickers;

namespace Stillroom;

/// <summary>Settings (the Mac's `SettingsPane`): how the vault is kept, in plain words, and what can be changed. The
/// same four tabs and rows in either vault; nothing on them says which vault is open (docs/SECURITY.md rule 2). Every
/// password is typed on the secure desktop, never here.</summary>
internal sealed class SettingsPage : UserControl
{
    private readonly AppState state;
    private readonly MainWindow window;
    private readonly Action changed;
    private readonly InfoBar problem = new() { IsClosable = true };
    private readonly ContentControl body = new() { HorizontalContentAlignment = HorizontalAlignment.Stretch };
    private string tab = "Access";
    private JsonElement contents;
    private bool helloAvailable;
    /// <summary>Drawing sets switches; only a person's flip of one should act.</summary>
    private bool drawing;
    private bool busy;

    private Settings Settings => window.Settings;
    private Vault? Vault => state.Vault;

    /// <summary>`changed`: the vault's list changed underneath (a restore, a check that deleted something).</summary>
    public SettingsPage(AppState state, MainWindow window, Action changed)
    {
        this.state = state;
        this.window = window;
        this.changed = changed;

        var heading = new StackPanel { Spacing = 4 };
        heading.Children.Add(Eyebrow("Settings"));
        heading.Children.Add(new TextBlock { Text = "How it's kept", FontSize = 24, FontWeight = FontWeights.SemiBold });

        var tabs = new SelectorBar();
        foreach (var name in new[] { "Access", "Protection", "Security", "Data" }) tabs.Items.Add(new SelectorBarItem { Text = name });
        tabs.SelectedItem = tabs.Items[0];
        tabs.SelectionChanged += (_, _) => { tab = ((SelectorBarItem)tabs.SelectedItem).Text; Draw(); };

        var page = new StackPanel { Spacing = 16, Padding = new Thickness(0, 4, 0, 24) };
        page.Children.Add(heading);
        page.Children.Add(problem);
        page.Children.Add(tabs);
        page.Children.Add(body);
        Content = new ScrollViewer { Content = page, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden };

        Loaded += async (_, _) =>
        {
            helloAvailable = await WindowsHello.IsAvailableAsync();
            Draw();
        };
        Draw();
    }

    private void Draw()
    {
        try { contents = state.Contents(); }
        catch (ObjectDisposedException) { return; }
        drawing = true;
        body.Content = tab switch
        {
            "Protection" => Protection(),
            "Security" => SecurityFacts(),
            "Data" => Data(),
            _ => Access(),
        };
        drawing = false;
    }

    private bool Has(string name) => contents.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;

    // MARK: Access

    private UIElement Access()
    {
        var kitAge = contents.TryGetProperty("kitMade", out var made) && made.ValueKind == JsonValueKind.Number
            ? $" (made {Ago(new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero).AddSeconds(made.GetDouble()))})"
            : "";
        var hasKit = Has("hasKit");
        var helloMine = Has("helloIsMine");
        var lockedToPc = Has("lockedToAPc");
        return Section("Getting in",
            Row("Password", "The way in that always works. At least 12 characters. You'll type it on a screen of its own.",
                Button("Change…", ChangePassword)),
            Row("Open with Windows Hello",
                helloAvailable
                    ? "Your face, finger or Windows Hello PIN opens this vault, with a key kept in this PC's TPM. The PIN opens it too, not only a face or finger. It opens one vault: turning it on here moves it from any other. If you rely on a decoy, turn it on there or nowhere, since a forced face or PIN opens the vault it belongs to."
                    : "Windows Hello isn't set up on this PC. Set up a PIN in Windows Settings › Accounts › Sign-in options.",
                Switch("Open with Windows Hello", helloMine, helloAvailable, SetHello)),
            Row("Lock to this PC",
                Engine.TpmAvailable || lockedToPc
                    ? "The vault opens only on this PC, even with the password: a copy of its folder is useless anywhere else. Your recovery key opens it if this PC is lost or repaired. Turning it on gives you a new recovery key."
                    : "This PC has no TPM to lock the vault to.",
                Switch("Lock to this PC", lockedToPc, Engine.TpmAvailable || lockedToPc, SetPcLock)),
            Row("Recovery key",
                "Opens the vault on any computer without the password. A new one stops the old one opening this vault, though backups made before still open with it.",
                Button("New Key…", NewRecoveryKey)),
            Row("Emergency kit",
                hasKit
                    ? $"Printed pieces you gave out open the vault if something happens to you{kitAge}. A new kit stops the old pieces opening this vault, though backups made before still open with them."
                    : "Printed pieces for people you trust: any two of three (or your choice) open the vault if something happens to you. One alone opens nothing.",
                Buttons(hasKit ? Button("Remove…", RemoveKit, quiet: true, name: "Remove the emergency kit") : null, Button(hasKit ? "New Kit…" : "Make Kit…", () => MakeKit(hasKit)))),
            Row("Decoy password",
                "A second password that opens a separate, harmless vault with its own recovery key and kit, for when someone makes you open Stillroom in front of them. It won't stand up to someone who has one password and a copy of this PC's files. Setting one deletes whatever the other vault held.",
                Buttons(Button("Remove…", RemoveDecoy, quiet: true, name: "Remove the decoy"), Button("Set…", SetDecoy, name: "Set a decoy password"))));
    }

    private Task ChangePassword() => Work(async vault =>
    {
        var outcome = await Task.Run(() =>
        {
            var current = Secrets.Ask("Type your current password.");
            if (current is null) return "";
            try
            {
                var next = Secrets.AskNewPassword($"Choose a new password: {Secrets.Shortest} characters or more. The old one stops working.", out var weak);
                if (next is null) return weak ?? "";
                try { vault.ChangePassword(current, next); }
                finally { CryptographicOperations.ZeroMemory(next); }
                return "Password changed.";
            }
            finally
            {
                CryptographicOperations.ZeroMemory(current);
            }
        });
        if (outcome.Length > 0) Say(outcome, outcome == "Password changed." ? InfoBarSeverity.Success : InfoBarSeverity.Warning);
    });

    private async Task SetHello(bool on)
    {
        if (Vault is not { } vault) return;
        if (on)
        {
            try { await WindowsHello.TurnOnAsync(vault); }
            catch (HelloCancelled) { }
        }
        else
        {
            await Task.Run(vault.TurnOffHello);
            // The credential was this vault's: it goes too.
            await WindowsHello.ForgetAsync();
        }
    }

    private Task SetPcLock(bool on) => Work(async vault =>
    {
        if (on && await Task.Run(vault.LockToThisPc) is { } key) await RecoveryKeyDialog.ShowAsync(XamlRoot, key);
        else if (!on) await Task.Run(vault.UnlockFromThisPc);
    });

    private async Task NewRecoveryKey()
    {
        if (await Ask.Choose(XamlRoot, "Make a new recovery key?", "Any recovery key you wrote down before stops opening this vault. Backups made before still open with it.", "Make New Key") != ContentDialogResult.Primary) return;
        await Work(async vault => await RecoveryKeyDialog.ShowAsync(XamlRoot, await Task.Run(vault.NewRecoveryKey)));
    }

    private Task MakeKit(bool hasKit) => Work(vault => KitDialog.ShowAsync(XamlRoot, vault, hasKit, window.Handle));

    private async Task RemoveKit()
    {
        if (await Ask.Choose(XamlRoot, "Remove the emergency kit?", "The printed pieces stop opening this vault. Backups made before still open with them, so collect and destroy the pieces too.", "Remove Kit", destructive: true) != ContentDialogResult.Primary) return;
        await Work(vault => Task.Run(vault.RemoveKit));
    }

    private async Task SetDecoy()
    {
        if (await Ask.Choose(XamlRoot, "Set a decoy password?",
                "It opens a second, empty vault, with a recovery key of its own. Put a few harmless files in it so it looks used. Everything in the other vault is deleted and it starts empty. You'll type the password on a screen of its own.",
                "Choose Password…") != ContentDialogResult.Primary) return;
        await Work(async vault =>
        {
            string? key = null;
            var weak = await Task.Run(() =>
            {
                var password = Secrets.AskNewPassword($"Choose the decoy password: {Secrets.Shortest} characters or more.", out var weakness);
                if (password is null) return weakness;
                try { key = vault.SetOtherSlot(password); return null; }
                finally { CryptographicOperations.ZeroMemory(password); }
            });
            if (weak is not null) Say(weak, InfoBarSeverity.Warning);
            if (key is not null) await RecoveryKeyDialog.ShowAsync(XamlRoot, key);
        });
    }

    private async Task RemoveDecoy()
    {
        if (await Ask.Choose(XamlRoot, "Remove the decoy?", "The decoy password stops opening anything, and everything in the other vault is deleted.", "Remove Decoy", destructive: true) != ContentDialogResult.Primary) return;
        await Work(vault => Task.Run(vault.ResetOtherSlot));
    }

    // MARK: Protection

    private UIElement Protection()
    {
        var autoLock = new ComboBox { MinWidth = 170 };
        AutomationProperties.SetName(autoLock, "Locks by itself");
        foreach (var minutes in Settings.AutoLockChoices) autoLock.Items.Add(Settings.AutoLockName(minutes));
        autoLock.SelectedIndex = Math.Max(0, Array.IndexOf(Settings.AutoLockChoices, Settings.AutoLockMinutes));
        autoLock.SelectionChanged += (_, _) =>
        {
            if (drawing || autoLock.SelectedIndex < 0) return;
            Settings.AutoLockMinutes = Settings.AutoLockChoices[autoLock.SelectedIndex];
            Save();
        };

        var camera = IntruderCamera.WindowsAllows();
        var cameraLine = new TextBlock { FontSize = 12, Opacity = 0.6, TextWrapping = TextWrapping.Wrap };
        var tryCamera = Button("Try Camera", async () =>
        {
            cameraLine.Text = "Taking a photo…";
            var photo = await IntruderCamera.SnapAsync();
            cameraLine.Text = photo is not null
                ? "The camera works. That photo was thrown away."
                : "No photo: there's no camera, or Windows doesn't let desktop apps use it.";
            if (photo is not null) CryptographicOperations.ZeroMemory(photo);
        }, quiet: true);
        var photoRow = Row("Take a photo",
            camera == IntruderCamera.Access.Allowed
                ? "A photo of whoever types a wrong password. The camera light comes on for a second."
                : "Windows doesn't let desktop apps use the camera. Turn on \"Let desktop apps access your camera\" in Windows Settings › Privacy & security › Camera.",
            Buttons(tryCamera, Switch("Take a photo", Settings.IntruderPhoto, true, on => { Settings.IntruderPhoto = on; Save(); return Task.CompletedTask; })));
        var photoWith = new StackPanel();
        photoWith.Children.Add(photoRow);
        cameraLine.Margin = new Thickness(14, 0, 14, 10);
        photoWith.Children.Add(cameraLine);

        var page = new StackPanel { Spacing = 16 };
        page.Children.Add(Section("Protection",
            Row("Locks by itself",
                "When Windows locks, the PC sleeps or its display goes off, another user switches in, Stillroom quits, or nothing on the PC is touched for this long. Three wrong passwords in a row make each next try wait longer.",
                autoLock),
            Row("Tray icon",
                $"Shows whether Stillroom is open, and locks it. Either way, {window.LockHotKey ?? SystemWatch.HotKeyName} in any app locks Stillroom and hides it at once.",
                Switch("Tray icon", Settings.TrayIcon, true, on => { Settings.TrayIcon = on; Save(); window.ShowTrayIcon(on); return Task.CompletedTask; })),
            Row("Show in screenshots & screen sharing",
                "When off, screenshots, recordings and screen sharing see Stillroom blank. Turn on to show someone. Remembered with the vault; the lock screen always stays hidden.",
                Switch("Show in screenshots and screen sharing", Has("showInCapture"), true, on => Work(async vault =>
                {
                    await Task.Run(() => vault.SetShowInCapture(on));
                    window.FollowCapture(on);
                }))),
            Row("Keep other programs out",
                "Windows can load other programs' code into any app: keyboard hooks, input add-ons and the like. With this on, Stillroom refuses them. It also turns off input method editors (IMEs): turn it off if you type with one. Takes effect the next time Stillroom starts.",
                Switch("Keep other programs out", Settings.BlockExtensionDlls, true, on => { Settings.BlockExtensionDlls = on; Save(); return Task.CompletedTask; })),
            Row("Keyloggers",
                "Typing is protected from keyloggers on the unlock screen. Once the vault is open, Stillroom can't stop software already running on your PC from reading keystrokes.",
                null)));
        page.Children.Add(Section("Intruder log", photoWith));
        return page;
    }

    // MARK: Security

    private UIElement SecurityFacts()
    {
        var shown = Has("showInCapture");
        var facts = new (string Figure, string Title, string Detail, bool Off)[]
        {
            ("AES-256-GCM", "Every file sealed", "Each file, note, secret and earlier version has its own 256-bit key, made fresh every time it's saved, with a fresh nonce for every seal.", false),
            ("512 MB", "Of memory per password guess", "Your password is stretched with Argon2id (RFC 9106): 3 passes, 4 lanes, a random 16-byte salt. Graphics cards and custom chips run short of memory, so guessing stays slow.", false),
            ("Bound", "No file can stand in for another", "Every sealed file, the list and the search index carry what they are. Swapped, copied over or changed by one byte, they refuse to open.", false),
            ("±12%", "Sizes hidden", "Files are padded before sealing, so a sealed size gives little away. Names, folders, kinds, tags and dates are sealed inside the list.", false),
            ("0", "Network connections", "Stillroom has no networking code. No account, no server, no sync, no tracking.", false),
            ("Locked", "Keys kept out of the page file", "The vault key and every file key are held in locked memory only while the vault is open, never written to the page file, and let go the moment it locks. Previews are drawn from memory.", false),
            shown
                ? ("Visible", "To screen capture, as you chose", "Show in screenshots & screen sharing is on, so recordings and screen sharing can see Stillroom while it's open. The lock screen stays hidden.", true)
                : ("Hidden", "From screen capture", "Screenshots, recordings and screen sharing see nothing while Stillroom is open, its menus and dialogs included.", false),
            ("Own desktop", "Passwords typed out of sight", "The password, recovery key, kit pieces and new passwords are typed on a desktop of their own, where other programs' keyboard hooks don't reach.", false),
            ("SHA-256", "Checked before anything is deleted", "When Stillroom removes the originals of what you added, each sealed copy is read back and compared byte for byte first. A copy that doesn't match keeps its original.", false),
            ("Open", "A published format", "Every byte on disk is documented, and a short script opens a vault without the app. Nothing secret is hidden in Stillroom, and there's no back door.", false),
        };
        var grid = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = 262, ItemHeight = 190 };
        foreach (var fact in facts)
        {
            var card = new StackPanel { Spacing = 6, Padding = new Thickness(14) };
            card.Children.Add(new TextBlock
            {
                Text = fact.Figure,
                FontSize = 24,
                FontWeight = FontWeights.SemiBold,
                Foreground = fact.Off ? new SolidColorBrush(Microsoft.UI.Colors.Orange) : (Brush)Application.Current.Resources["VaultBrush"],
            });
            card.Children.Add(new TextBlock { Text = fact.Title });
            card.Children.Add(new TextBlock { Text = fact.Detail, FontSize = 12, Opacity = 0.45, TextWrapping = TextWrapping.Wrap });
            grid.Children.Add(new Border { Background = (Brush)Application.Current.Resources["PanelBrush"], CornerRadius = new CornerRadius(12), Margin = new Thickness(0, 0, 10, 10), Child = card });
        }
        var limits = new StackPanel { Spacing = 10, Padding = new Thickness(14) };
        foreach (var limit in new[]
        {
            "A weak password. The strength check refuses guessable ones.",
            "Malware with administrator rights on this PC, or any software running as you while the vault is open.",
            "Copies other apps keep of files opened in them, and names they remember.",
            "Someone able to change the vault's folder putting back an older copy of it.",
        })
        {
            limits.Children.Add(new TextBlock { Text = "◦  " + limit, FontSize = 12, Opacity = 0.7, TextWrapping = TextWrapping.Wrap });
        }
        var page = new StackPanel { Spacing = 12 };
        page.Children.Add(grid);
        page.Children.Add(GroupLabel("What Stillroom can't protect against"));
        page.Children.Add(new Border { Background = (Brush)Application.Current.Resources["PanelBrush"], CornerRadius = new CornerRadius(12), Child = limits });
        return page;
    }

    // MARK: Data

    private UIElement Data()
    {
        var page = new StackPanel { Spacing = 16 };
        page.Children.Add(Section("This vault",
            Row("Check vault", "Reads every item and earlier version back, to find any a disk fault or crash has damaged.", Button("Check…", CheckVault)),
            Row("Move to Stillroom in Explorer",
                "Adds it to the Send to menu when you right-click files. They go into the vault, and once each is checked against its encrypted copy, the original is deleted (or goes to the Recycle Bin if BitLocker is off).",
                Switch("Move to Stillroom in Explorer", SendTo.IsOn, true, on => { SendTo.Set(on); return Task.CompletedTask; })),
            Row("Where it lives", state.StoreRoot, Button("Show in Explorer", () =>
            {
                Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{state.StoreRoot}\"") { UseShellExecute = false });
                return Task.CompletedTask;
            }))));
        page.Children.Add(Section("Backups",
            Row("Back up", "One file holding the whole vault, still encrypted. Keep it on a disk you plug in, not in the cloud.", Button("Back Up…", BackUp)),
            Row("Restore", "Put the vault back from a backup file. The vault here now is kept aside, never deleted, until you delete the vault.", Button("Restore…", Restore)),
            Row("Export everything", "Every file, note and secret back out as ordinary files in folders, with their own dates. For leaving Stillroom, or a copy anything can read.", Button("Export…", ExportAll))));
        var delete = new Button
        {
            Content = "Delete Vault…",
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0xFF, 0xC4, 0x2B, 0x1C)),
            Foreground = new SolidColorBrush(Microsoft.UI.Colors.White),
        };
        delete.Click += async (_, _) => await Wipe();
        page.Children.Add(Panel(Row("Delete the vault", "Every file in it, and the keys, for good.", delete)));
        return page;
    }

    private Task CheckVault() => Work(async vault =>
    {
        var items = state.Contents().GetProperty("files").EnumerateArray().Select(VaultItem.From).ToList();
        await CheckDialog.ShowAsync(XamlRoot, vault, items);
        changed();
    });

    private Task BackUp() => Work(async vault =>
    {
        var picker = new FileSavePicker { SuggestedFileName = $"Stillroom Backup {DateTime.Now:yyyy-MM-dd}", CommitButtonText = "Back Up" };
        WinRT.Interop.InitializeWithWindow.Initialize(picker, window.Handle);
        picker.FileTypeChoices.Add("Stillroom backup", [".stillroombackup"]);
        if (await picker.PickSaveFileAsync() is not StorageFile file) return;
        Say("Backing up…", InfoBarSeverity.Informational);
        await Task.Run(() => vault.Backup(file.Path));
        Say($"Backed up to {file.Path}. Pick a disk you can unplug and keep somewhere safe.", InfoBarSeverity.Success);
    });

    private async Task Restore()
    {
        var picker = new FileOpenPicker();
        WinRT.Interop.InitializeWithWindow.Initialize(picker, window.Handle);
        picker.FileTypeFilter.Add(".stillroombackup");
        if (await picker.PickSingleFileAsync() is not StorageFile file) return;
        try { await Task.Run(() => Store.CheckBackup(file.Path)); }
        catch (StillroomException failure) { Say(failure.Message, InfoBarSeverity.Error); return; }
        if (await Ask.Choose(XamlRoot, "Restore from this backup?",
                "The vault closes and the backup's vault takes its place; it opens with the password it had then. The vault here now is kept aside.",
                "Restore") != ContentDialogResult.Primary) return;
        // Shut first: nothing still holding the old keys may write into the restored vault once it's in place.
        state.Lock("restore");
        var store = state.Store;
        try { await Task.Run(() => store.Restore(file.Path)); }
        catch (StillroomException failure) { state.LockNotice = failure.Message; }
        state.Reloaded();
    }

    private async Task ExportAll()
    {
        if (await Ask.Choose(XamlRoot, "Export everything, unencrypted?",
                "Everything comes out as normal files anyone with access to this PC can open, secrets' hidden values included. Pick a disk you control, and delete the copy when you're done with it.",
                "Choose Where…") != ContentDialogResult.Primary) return;
        await Work(async vault =>
        {
            var picker = new FolderPicker { CommitButtonText = "Export Here" };
            WinRT.Interop.InitializeWithWindow.Initialize(picker, window.Handle);
            picker.FileTypeFilter.Add("*");
            if (await picker.PickSingleFolderAsync() is not StorageFolder parent) return;
            Say("Exporting…", InfoBarSeverity.Informational);
            var result = await Task.Run(() => vault.ExportAll(parent.Path));
            var folder = result.GetProperty("folder").GetString() ?? parent.Path;
            var failed = result.GetProperty("failed").GetArrayLength();
            Say(failed == 0 ? $"Everything is out, in {folder}." : $"Out, in {folder}, except {failed} that couldn't be taken out.", failed == 0 ? InfoBarSeverity.Success : InfoBarSeverity.Warning);
            Process.Start(new ProcessStartInfo("explorer.exe", $"\"{folder}\"") { UseShellExecute = false });
        });
    }

    private async Task Wipe()
    {
        if (await Ask.Choose(XamlRoot, "Delete the vault and everything in it?", "Nothing in it can be opened again, by anyone.", "Delete Everything", destructive: true) != ContentDialogResult.Primary) return;
        if (Vault is not { } vault) return;
        var helloMine = Has("helloIsMine");
        try { await Task.Run(vault.Wipe); }
        catch (StillroomException failure) { Say(failure.Message, InfoBarSeverity.Error); return; }
        if (helloMine) await WindowsHello.ForgetAsync();
        state.Lock("vault deleted");
    }

    // MARK: Pieces

    /// <summary>Runs something on the open vault, one at a time; a refusal is said at the top. Redraws after.</summary>
    private async Task Work(Func<Vault, Task> work)
    {
        if (busy || Vault is not { } vault) return;
        busy = true;
        try { await work(vault); }
        catch (StillroomException failure) { Say(failure.Message, InfoBarSeverity.Error); }
        catch (ObjectDisposedException) { return; }
        finally { busy = false; }
        Draw();
        changed();
    }

    private void Say(string message, InfoBarSeverity severity)
    {
        problem.Message = message;
        problem.Severity = severity;
        problem.IsOpen = true;
    }

    private void Save()
    {
        try { Settings.Save(); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Say($"The setting couldn't be saved. {e.Message}", InfoBarSeverity.Error); }
    }

    private static string Ago(DateTimeOffset when)
    {
        var days = (DateTimeOffset.Now - when).TotalDays;
        return days < 1 ? "today" : days < 2 ? "yesterday" : days < 60 ? $"{(int)days} days ago" : days < 730 ? $"{(int)(days / 30)} months ago" : $"{(int)(days / 365)} years ago";
    }

    private static TextBlock Eyebrow(string text) => new()
    {
        Text = text.ToUpperInvariant(),
        FontSize = 10.5,
        FontWeight = FontWeights.SemiBold,
        CharacterSpacing = 80,
        Foreground = (Brush)Application.Current.Resources["QuietBrush"],
    };

    private static TextBlock GroupLabel(string text) => new()
    {
        Text = text,
        FontSize = 12,
        FontWeight = FontWeights.SemiBold,
        Foreground = (Brush)Application.Current.Resources["QuietBrush"],
        Margin = new Thickness(4, 0, 0, 0),
    };

    private static Border Panel(UIElement child) => new()
    {
        Background = (Brush)Application.Current.Resources["PanelBrush"],
        CornerRadius = new CornerRadius(12),
        Child = child,
    };

    private static StackPanel Section(string title, params UIElement[] rows)
    {
        var list = new StackPanel();
        foreach (var row in rows)
        {
            if (list.Children.Count > 0) list.Children.Add(new Border { Height = 1, Margin = new Thickness(14, 0, 0, 0), Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x0D, 0xFF, 0xFF, 0xFF)) });
            list.Children.Add(row);
        }
        var section = new StackPanel { Spacing = 6 };
        section.Children.Add(GroupLabel(title));
        section.Children.Add(Panel(list));
        return section;
    }

    private static Grid Row(string title, string detail, UIElement? control)
    {
        var row = new Grid { Padding = new Thickness(14, 12, 14, 12), ColumnSpacing = 16 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var words = new StackPanel { Spacing = 3 };
        words.Children.Add(new TextBlock { Text = title });
        words.Children.Add(new TextBlock { Text = detail, FontSize = 12, Opacity = 0.45, TextWrapping = TextWrapping.Wrap });
        row.Children.Add(words);
        if (control is FrameworkElement shown)
        {
            shown.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(shown, 1);
            row.Children.Add(shown);
        }
        return row;
    }

    private static StackPanel Buttons(params UIElement?[] buttons)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        foreach (var button in buttons) if (button is not null) row.Children.Add(button);
        return row;
    }

    /// <summary>`name` tells a screen reader which of two alike buttons this is ("Remove…" for the kit, or the decoy).</summary>
    private Button Button(string text, Func<Task> act, bool quiet = false, string? name = null)
    {
        var button = new Button { Content = text };
        if (name is not null) AutomationProperties.SetName(button, name);
        if (quiet)
        {
            button.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            button.BorderThickness = new Thickness(0);
        }
        button.Click += async (_, _) => await act();
        return button;
    }

    private ToggleSwitch Switch(string name, bool on, bool enabled, Func<bool, Task> change)
    {
        var toggle = new ToggleSwitch { IsOn = on, IsEnabled = enabled, OnContent = "", OffContent = "", MinWidth = 0 };
        AutomationProperties.SetName(toggle, name);
        toggle.Toggled += async (_, _) =>
        {
            if (drawing || switching) return;
            // Not disabled while it works: that, and the redraw after, would move the keyboard focus elsewhere in the
            // window, where keys typed meanwhile (a PIN meant for Windows Hello's prompt) would press something else.
            switching = true;
            try { await change(toggle.IsOn); }
            catch (StillroomException failure) { Say(failure.Message, InfoBarSeverity.Error); }
            catch (ObjectDisposedException) { return; }
            finally { switching = false; }
            focusAfterDraw = name;
            Draw();
        };
        // The page was drawn again after this switch was flipped: its new copy takes the keyboard focus back.
        if (name == focusAfterDraw)
        {
            toggle.Loaded += (_, _) =>
            {
                toggle.Focus(FocusState.Keyboard);
                focusAfterDraw = null;
            };
        }
        return toggle;
    }

    private bool switching;
    private string? focusAfterDraw;
}
