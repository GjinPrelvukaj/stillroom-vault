using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Stillroom.Model;
using Stillroom.Native;
using Stillroom.Platform;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Pickers;

namespace Stillroom;

/// <summary>The vault, open (the Mac's `VaultView`): the sidebar's shelves and tags, the list of the chosen one (All
/// Files browsed by folder), search, adding by picker or drop, and each item's menu. A note or a secret opens in its
/// editor, a file in a card.</summary>
public sealed partial class VaultView : UserControl
{
    private readonly AppState state;
    private readonly MainWindow window;

    private List<VaultItem> items = [];
    private List<string> folders = [];
    private List<string> tags = [];

    private Shelf? shelf = Shelf.All;
    private string? tag;
    /// <summary>The folder open in All Files; null at the top.</summary>
    private string? folder;
    private string search = "";
    /// <summary>Items whose contents match the search (the engine's word index).</summary>
    private HashSet<string> found = new(StringComparer.OrdinalIgnoreCase);
    /// <summary>Files being encrypted right now.</summary>
    private int adding;
    private bool dropping;
    /// <summary>Opened by the recovery key or the kit: a new password before anything else.</summary>
    private bool mustSetPassword;
    /// <summary>Settings or the intruder log, when one is open in place of the list.</summary>
    private string? page;
    private int intruders;

    /// <summary>The open vault's own "show in screenshots" setting.</summary>
    internal bool ShowInCapture { get; private set; }

    private Vault Vault => state.Vault ?? throw new ObjectDisposedException(nameof(Vault));

    internal VaultView(AppState state, MainWindow window)
    {
        this.state = state;
        this.window = window;
        InitializeComponent();
        ToolTipService.SetToolTip(LockButton, window.LockHotKey is { } key ? $"Lock (Ctrl+Shift+L; {key} locks and hides from any app)" : "Lock (Ctrl+Shift+L)");
        ToolTipService.SetToolTip(AddButton, "Add files or a folder (Ctrl+N)");
        if (state.Notice is { } notice) Say(notice, InfoBarSeverity.Informational);
        Load();
        RefreshSearchSoon();
        DrawEditing();
        // The desk outlives this view (a lock makes a new one): heard only while this one is up.
        Loaded += (_, _) => { window.Desk.Changed += Edited; window.Desk.Problem += DeskProblem; Inbox.Changed += TakeInbox; TakeInbox(); };
        Unloaded += (_, _) => { window.Desk.Changed -= Edited; window.Desk.Problem -= DeskProblem; Inbox.Changed -= TakeInbox; folderDrags.Clear(); };
        Loaded += async (_, _) =>
        {
            if (state.FreshRecoveryKey is not { } fresh) return;
            state.FreshRecoveryKey = null;
            await RecoveryKeyDialog.ShowAsync(XamlRoot, fresh);
        };
    }

    // MARK: Edit in Place

    private static bool CanEdit(VaultItem item) => Engine.CanEdit(item.Uti, item.Name, item.IsFile);

    /// <summary>Edit in Place, after saying what it gives away (once, if the person says so), as the Mac does.</summary>
    private async Task EditInPlace(VaultItem item)
    {
        if (!window.Settings.EditWarningOff)
        {
            var app = EditDesk.AppFor(item.Name) ?? "its app";
            var encrypted = EditDesk.SystemDriveEncrypted();
            var text = $"It opens from a working copy in a folder only your account can read, and every save comes back encrypted. While it's open, {app} can read it, and may keep its name in Recent files and copies of its own outside the vault. To only look at it, open it here instead.";
            if (encrypted == false)
                text += "\n\nBitLocker is off on this PC, so the working copy could be recovered from the disk after it's deleted. Turn on Device encryption or BitLocker in Windows Settings › Privacy & security.";
            var dontAsk = new CheckBox { Content = "Don't ask again" };
            var body = new StackPanel { Spacing = 12, MaxWidth = 460 };
            body.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap });
            body.Children.Add(dontAsk);
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = $"Open “{item.Name}” in {app}?",
                Content = body,
                PrimaryButtonText = "Open",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
            };
            if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
            if (dontAsk.IsChecked == true)
            {
                window.Settings.EditWarningOff = true;
                try { window.Settings.Save(); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
            }
        }
        try { await window.Desk.OpenAsync(item.Id, item.Name); }
        catch (Exception e) when (e is StillroomException or IOException or System.ComponentModel.Win32Exception or ObjectDisposedException)
        {
            Say($"“{item.Name}” couldn't be opened for editing. {e.Message}", InfoBarSeverity.Error);
        }
        DrawEditing();
    }

    /// <summary>A save came in, or the set of files out changed.</summary>
    private void Edited()
    {
        DrawEditing();
        Load();
    }

    private void DeskProblem(string message) => Say(message, InfoBarSeverity.Warning);

    private void DrawEditing()
    {
        var count = window.Desk.Count;
        EditingBar.IsOpen = count > 0;
        EditingBar.Message = $"Editing {count} {(count == 1 ? "file" : "files")} in {(count == 1 ? "its app" : "their apps")}. Each save is encrypted back in.";
    }

    private void OnDoneEditing(object sender, RoutedEventArgs e)
    {
        window.Desk.ClearAll();
        DrawEditing();
        Load();
    }

    // MARK: Reading the vault

    /// <summary>The list again from the engine, and everything drawn from it.</summary>
    private void Load()
    {
        JsonElement contents;
        try { contents = state.Contents(); }
        catch (ObjectDisposedException) { return; }
        items = contents.GetProperty("files").EnumerateArray().Select(VaultItem.From).ToList();
        folders = contents.GetProperty("folders").EnumerateArray().Select(f => f.GetString() ?? "").ToList();
        tags = contents.GetProperty("tags").EnumerateArray().Select(t => t.GetString() ?? "").ToList();
        ShowInCapture = contents.GetProperty("showInCapture").GetBoolean();
        intruders = contents.GetProperty("intruders").GetInt32();
        mustSetPassword = contents.GetProperty("mustSetPassword").GetBoolean();
        AddButton.IsEnabled = !mustSetPassword;
        MustSetPassword.Visibility = mustSetPassword ? Visibility.Visible : Visibility.Collapsed;
        if (tag is not null && !tags.Contains(tag)) (shelf, tag) = (Shelf.All, null);
        if (folder is not null && !folders.Contains(folder)) folder = null;
        DrawSidebar();
        DrawPane();
    }

    /// <summary>The word index brought up to date off the UI thread (text only for now: reading pictures and PDFs
    /// comes with the viewers), then the search run again.</summary>
    private void RefreshSearchSoon()
    {
        if (state.Vault is not { } vault) return;
        _ = Task.Run(() =>
        {
            try { return vault.RefreshSearch(); }
            catch (Exception e) when (e is ObjectDisposedException or StillroomException) { return false; }
        }).ContinueWith(t =>
        {
            if (t.Result && search.Length > 0) DispatcherQueue.TryEnqueue(() => { Search(); DrawPane(); });
        }, TaskScheduler.Default);
    }

    // MARK: Sidebar

    private void DrawSidebar()
    {
        Shelves.Children.Clear();
        var list = page is null;
        foreach (var s in Model.Shelves.Library) Shelves.Children.Add(SidebarItem(s.Title(), s.Glyph(), items.Count(i => s.Holds(i)), list && shelf == s && tag is null, () => Go(s, null)));
        Shelves.Children.Add(GroupLabel("Kinds"));
        foreach (var s in Model.Shelves.Kinds) Shelves.Children.Add(SidebarItem(s.Title(), s.Glyph(), items.Count(i => s.Holds(i)), list && shelf == s && tag is null, () => Go(s, null)));
        if (tags.Count > 0)
        {
            Shelves.Children.Add(GroupLabel("Tags"));
            foreach (var t in tags)
                Shelves.Children.Add(SidebarItem(t, "", items.Count(i => i.Tags.Contains(t)), list && tag == t, () => Go(null, t), TagColors.Of(t)));
        }
        Pages.Children.Clear();
        // Unseen wrong tries in red, as the Mac does; the log is the same in either vault.
        var unseen = intruders > window.Settings.IntrudersSeen;
        Pages.Children.Add(SidebarItem("Intruder Log", Glyphs.Shield, intruders, page == "intruders", () => OpenPage("intruders"),
            unseen ? Windows.UI.Color.FromArgb(0xFF, 0xF8, 0x71, 0x71) : null, glyphTint: true));
        Pages.Children.Add(SidebarItem("Settings", Glyphs.Settings, 0, page == "settings", () => OpenPage("settings")));
        var total = items.Where(i => i.IsFile).Sum(i => i.Size);
        TotalSize.Text = Shell.Size(total);
        TotalCount.Text = $"{items.Count} {(items.Count == 1 ? "item" : "items")}, all encrypted";
    }

    private static TextBlock GroupLabel(string text) => new()
    {
        Text = text,
        FontSize = 11,
        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        Foreground = (Brush)Application.Current.Resources["QuietBrush"],
        Margin = new Thickness(10, 16, 0, 4),
    };

    /// <summary>`tint` colours a tag's dot (drawn small), or with `glyphTint` a page's symbol at full size.</summary>
    private static Button SidebarItem(string title, string glyph, int count, bool chosen, Action go, Windows.UI.Color? tint = null, bool glyphTint = false)
    {
        var row = new Grid { ColumnSpacing = 10 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(18) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(new FontIcon
        {
            Glyph = glyph,
            FontSize = tint is null || glyphTint ? 15 : 9,
            Foreground = tint is { } color ? new SolidColorBrush(color) : (Brush)Application.Current.Resources["ButtonForeground"],
        });
        var name = new TextBlock { Text = title, TextTrimming = TextTrimming.CharacterEllipsis };
        Grid.SetColumn(name, 1);
        row.Children.Add(name);
        if (count > 0)
        {
            var number = new TextBlock { Text = count.ToString(), FontSize = 12, Opacity = 0.5 };
            Grid.SetColumn(number, 2);
            row.Children.Add(number);
        }
        var button = new Button
        {
            Content = row,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Padding = new Thickness(10, 6, 10, 6),
            BorderThickness = new Thickness(0),
            Background = new SolidColorBrush(chosen ? Windows.UI.Color.FromArgb(0x1F, 0xFF, 0xFF, 0xFF) : Microsoft.UI.Colors.Transparent),
        };
        AutomationProperties.SetName(button, title);
        button.Click += (_, _) => go();
        return button;
    }

    /// <summary>Settings or the intruder log, in place of the list.</summary>
    private void OpenPage(string which)
    {
        if (Editor.Content is IDisposable leaving) leaving.Dispose();
        page = which;
        ShowEditor(which == "settings" ? new SettingsPage(state, window, Load) : new IntruderPage(state, window.Settings));
        DrawSidebar();
    }

    private void Go(Shelf? to, string? toTag)
    {
        CloseEditor();
        (shelf, tag, folder) = (to, toTag, null);
        SearchBox.Text = "";
        DrawSidebar();
        DrawPane();
    }

    // MARK: Pane

    /// <summary>Browsing All Files by folder (a search shows everything that matches instead).</summary>
    private bool Browsing => shelf == Shelf.All && tag is null && search.Length == 0;
    /// <summary>Where something made or dropped now goes.</summary>
    private string? FolderHere => Browsing ? folder : null;

    private List<VaultItem> Shown() => items
        .Where(i => tag is not null ? i.Tags.Contains(tag) : shelf!.Value.Holds(i))
        .Where(i => !Browsing || i.Folder == folder)
        .Where(i => search.Length == 0
            || i.Name.Contains(search, StringComparison.CurrentCultureIgnoreCase)
            || (i.Folder ?? "").Shown().Contains(search, StringComparison.CurrentCultureIgnoreCase)
            || i.Tags.Any(t => t.Contains(search, StringComparison.CurrentCultureIgnoreCase))
            || found.Contains(i.Id))
        .OrderByDescending(i => i.IsFile ? i.AddedAt : i.ChangedAt)
        .ToList();

    /// <summary>The folders directly inside the one open, when browsing.</summary>
    private List<string> Subfolders() => Browsing ? folders.Where(f => f.Parent() == folder).OrderBy(f => f.ShownLast(), StringComparer.CurrentCultureIgnoreCase).ToList() : [];

    private void DrawPane()
    {
        // An editor or a page is open over the list: the list is drawn again when it closes.
        if (Editor.Visibility == Visibility.Visible) return;
        var shown = Shown();
        var subfolders = Subfolders();

        Eyebrow.Text = (tag is not null ? $"Tagged “{tag}”" : shelf!.Value.Title()).ToUpperInvariant();
        Headline.Text = HeadlineFor(shown.Count);
        SearchBox.Visibility = items.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        DrawActions();
        DrawCrumbs();

        if (mustSetPassword)
        {
            Rows.Visibility = Empty.Visibility = SearchBox.Visibility = Visibility.Collapsed;
            Actions.Children.Clear();
            return;
        }
        var rows = subfolders.Select(FolderRow).Concat(shown.Select(ItemRow)).ToList();
        Rows.ItemsSource = rows;
        var empty = rows.Count == 0;
        Rows.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
        Empty.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        if (empty) DrawEmpty();
    }

    private string HeadlineFor(int n)
    {
        if (adding > 0) return $"Encrypting {adding} {(adding == 1 ? "file" : "files")}…";
        if (search.Length > 0) return n == 0 ? "Nothing called that" : $"{n} found";
        if (Browsing && folder is not null) return folder.ShownLast();
        var noun = shelf == Shelf.Notes ? "note" : shelf == Shelf.Secrets ? "secret" : tag is null ? "file" : "item";
        return n == 0 ? "Nothing here yet" : $"{n} {noun}{(n == 1 ? "" : "s")}";
    }

    private Row FolderRow(string path) => new()
    {
        Glyph = Glyphs.Folder,
        GlyphBrush = (Brush)Application.Current.Resources["VaultBrush"],
        Name = path.ShownLast(),
        Kind = items.Count(i => i.IsInside(path)) is var n && n == 1 ? "1 item" : $"{n} items",
        FolderPath = path,
    };

    private Row ItemRow(VaultItem item)
    {
        string detail = "";
        if (search.Length > 0 && found.Contains(item.Id) && !item.Name.Contains(search, StringComparison.CurrentCultureIgnoreCase))
        {
            try { detail = Vault.Snippet(item.Id, search) ?? ""; }
            catch (Exception e) when (e is StillroomException or ObjectDisposedException) { }
        }
        else if (!Browsing && item.Folder is { } where)
        {
            detail = where.ShownPath();
        }
        return new Row
        {
            Glyph = item.Glyph,
            Name = item.Name,
            Tags = item.Tags.Select(TagColors.Chip).ToList(),
            Detail = detail,
            Versions = item.Versions.Count > 0 ? item.Versions.Count.ToString() : "",
            Kind = item.KindName,
            Size = item.IsFile ? Shell.Size(item.Size) : "",
            Date = item.ShownDate.LocalDateTime.ToString("d MMM yyyy"),
            Item = item,
        };
    }

    /// <summary>What can be made here: a note, a secret, or a folder.</summary>
    private void DrawActions()
    {
        Actions.Children.Clear();
        if (shelf == Shelf.Notes && tag is null)
        {
            Actions.Children.Add(IconButton("New Note", "", (_, _) => NewNote()));
        }
        else if (shelf == Shelf.Secrets && tag is null)
        {
            var menu = new MenuFlyout { Placement = Microsoft.UI.Xaml.Controls.Primitives.FlyoutPlacementMode.BottomEdgeAlignedRight };
            AddSecretItems(menu.Items);
            var button = new DropDownButton { Content = "New Secret", Flyout = menu };
            Actions.Children.Add(button);
        }
        else if (Browsing)
        {
            var button = IconButton(null, Glyphs.NewFolder, async (_, _) => await NewFolder());
            ToolTipService.SetToolTip(button, "New Folder");
            AutomationProperties.SetName(button, "New Folder");
            Actions.Children.Add(button);
        }
    }

    private static Button IconButton(string? text, string glyph, RoutedEventHandler click)
    {
        var content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        content.Children.Add(new FontIcon { Glyph = glyph, FontSize = 14 });
        if (text is not null) content.Children.Add(new TextBlock { Text = text });
        var button = new Button { Content = content };
        if (text is not null) AutomationProperties.SetName(button, text);
        button.Click += click;
        return button;
    }

    private void AddSecretItems(IList<MenuFlyoutItemBase> menu)
    {
        foreach (var template in SecretTemplates.All)
        {
            var item = new MenuFlyoutItem { Text = template.Title, Icon = new FontIcon { Glyph = template.Glyph } };
            item.Click += (_, _) => NewSecret(template);
            menu.Add(item);
        }
        menu.Add(new MenuFlyoutSeparator());
        var import = new MenuFlyoutItem { Text = "Import Logins…", Icon = new FontIcon { Glyph = "" } };
        import.Click += async (_, _) => await ImportLogins();
        menu.Add(import);
    }

    private void DrawCrumbs()
    {
        if (!Browsing || folder is null)
        {
            Crumbs.Visibility = Visibility.Collapsed;
            return;
        }
        var parts = folder.Split('/');
        Crumbs.ItemsSource = new[] { "All Files" }.Concat(parts.Select(p => p.Shown())).ToList();
        Crumbs.Visibility = Visibility.Visible;
    }

    private void OnCrumb(BreadcrumbBar sender, BreadcrumbBarItemClickedEventArgs args)
    {
        folder = args.Index == 0 ? null : string.Join('/', folder!.Split('/').Take(args.Index));
        DrawPane();
    }

    private void DrawEmpty()
    {
        EmptyRing.Opacity = dropping ? 1 : 0.5;
        EmptyGlyph.Glyph = dropping ? "" : search.Length > 0 ? Glyphs.Search
            : tag is not null ? ""
            : shelf is { } s && s != Shelf.All ? s.Glyph()
            : folder is null ? Glyphs.Lock : Glyphs.Folder;
        (EmptyTitle.Text, EmptyLine.Text) = search.Length > 0 ? ("Nothing has that in its name", "Try another word.")
            : tag is not null ? ("Nothing tagged yet", "Add tags to anything from its menu.")
            : shelf == Shelf.Notes ? ("No notes yet", "Anything that should stay private.\nSaved as you type, encrypted.")
            : shelf == Shelf.Secrets ? ("No secrets yet", "Logins, cards, Wi-Fi, ID numbers.\nCopied to a clipboard that empties itself.")
            : (folder is null ? "Drop files here" : "This folder is empty", "Files or whole folders.\nEncrypted the moment they land.");
        EmptyAction.Content = shelf == Shelf.Notes ? "New Note" : shelf == Shelf.Secrets ? "New Login" : "Choose Files…";
        EmptyAction.Visibility = search.Length == 0 && tag is null ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void OnEmptyAction(object sender, RoutedEventArgs e)
    {
        if (shelf == Shelf.Notes) NewNote();
        else if (shelf == Shelf.Secrets) NewSecret(SecretTemplates.All[0]);
        else await PickFiles();
    }

    // MARK: Search

    private void OnSearch(object sender, TextChangedEventArgs e)
    {
        search = SearchBox.Text.Trim();
        Search();
        DrawPane();
    }

    private void Search()
    {
        found = new(StringComparer.OrdinalIgnoreCase);
        if (search.Length == 0 || state.Vault is not { } vault) return;
        try { found = vault.Search(search).ToHashSet(StringComparer.OrdinalIgnoreCase); }
        catch (Exception e) when (e is StillroomException or ObjectDisposedException) { }
    }

    // MARK: Opening

    private void OnRowClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not Row row) return;
        if (row.FolderPath is { } path)
        {
            folder = path;
            DrawPane();
        }
        else if (row.Item is { } item)
        {
            Open(item);
        }
    }

    private void Open(VaultItem item)
    {
        if (item.IsNote) ShowEditor(new NoteEditor(state, item, CloseEditor, () => _ = ShowVersions(item)));
        else if (item.IsSecret) ShowEditor(new SecretEditor(state, item, CloseEditor, () => _ = ShowVersions(item)));
        else ShowEditor(new PreviewCard(state, item, null, CloseEditor, () => _ = SaveCopy(item), CanEdit(item) ? () => { CloseEditor(); _ = EditInPlace(item); } : null));
    }

    private void ShowEditor(UIElement editor)
    {
        Editor.Content = editor;
        Editor.Visibility = Visibility.Visible;
        foreach (var part in new UIElement[] { Header, Crumbs, Rows, Empty }) part.Visibility = Visibility.Collapsed;
    }

    /// <summary>Back to the list; an editor saves as it goes.</summary>
    private void CloseEditor()
    {
        if (Editor.Content is IDisposable leaving) leaving.Dispose();
        Editor.Content = null;
        Editor.Visibility = Visibility.Collapsed;
        page = null;
        Header.Visibility = Visibility.Visible;
        Load();
        RefreshSearchSoon();
    }

    // MARK: Menus

    /// <summary>The menu for the row it was asked on: right-clicked, or the menu key or Shift+F10 on a focused row (that
    /// starts at the list item and bubbles up, so it's handled here on the list). Empty space gets what can be made.</summary>
    private void OnRowMenu(UIElement sender, ContextRequestedEventArgs args)
    {
        if (RowAt(args.OriginalSource as DependencyObject) is not Row row)
        {
            OnSpaceMenu(sender, args);
            return;
        }
        var at = (UIElement)args.OriginalSource;
        var menu = new MenuFlyout();
        void Add(string text, Action act, bool enabled = true)
        {
            var item = new MenuFlyoutItem { Text = text, IsEnabled = enabled };
            item.Click += (_, _) => act();
            menu.Items.Add(item);
        }
        if (row.FolderPath is { } path)
        {
            Add("Open", () => { folder = path; DrawPane(); });
            Add("Rename…", () => _ = RenameFolder(path));
            menu.Items.Add(new MenuFlyoutSeparator());
            Add("Delete Folder…", () => _ = DeleteFolder(path));
        }
        else if (row.Item is { } item)
        {
            Add("Open", () => Open(item));
            if (CanEdit(item)) Add("Edit in Place", () => _ = EditInPlace(item));
            Add("Rename…", () => _ = Rename(item));
            Add("Tags…", () => _ = EditTags(item));
            var move = new MenuFlyoutSubItem { Text = "Move To" };
            var top = new MenuFlyoutItem { Text = "Top Level", IsEnabled = item.Folder is not null };
            top.Click += (_, _) => Move(item, null);
            move.Items.Add(top);
            if (folders.Count > 0) move.Items.Add(new MenuFlyoutSeparator());
            foreach (var f in folders.OrderBy(f => f, StringComparer.CurrentCultureIgnoreCase))
            {
                var to = new MenuFlyoutItem { Text = f.ShownPath(), IsEnabled = item.Folder != f };
                to.Click += (_, _) => Move(item, f);
                move.Items.Add(to);
            }
            menu.Items.Add(move);
            if (item.Versions.Count > 0) Add("Versions…", () => _ = ShowVersions(item));
            if (item.IsFile) Add("Save a Copy…", () => _ = SaveCopy(item));
            menu.Items.Add(new MenuFlyoutSeparator());
            Add("Delete…", () => _ = Delete(item));
        }
        ShowMenu(menu, at, args);
    }

    /// <summary>The row an element belongs to: up to its list item, then which row the list put there.</summary>
    private Row? RowAt(DependencyObject? element)
    {
        for (var at = element; at is not null; at = VisualTreeHelper.GetParent(at))
        {
            if (at is ListViewItem container) return Rows.ItemFromContainer(container) as Row;
            if (at == Rows) return null;
        }
        return null;
    }

    /// <summary>Right-click on empty space: what can be made.</summary>
    private void OnSpaceMenu(UIElement sender, ContextRequestedEventArgs args)
    {
        var menu = new MenuFlyout();
        if (Browsing)
        {
            var newFolder = new MenuFlyoutItem { Text = "New Folder…" };
            newFolder.Click += async (_, _) => await NewFolder();
            menu.Items.Add(newFolder);
        }
        var files = new MenuFlyoutItem { Text = "Add Files…" };
        files.Click += async (_, _) => await PickFiles();
        menu.Items.Add(files);
        var aFolder = new MenuFlyoutItem { Text = "Add a Folder…" };
        aFolder.Click += async (_, _) => await PickFolder();
        menu.Items.Add(aFolder);
        menu.Items.Add(new MenuFlyoutSeparator());
        var note = new MenuFlyoutItem { Text = "New Note" };
        note.Click += (_, _) => NewNote();
        menu.Items.Add(note);
        var secret = new MenuFlyoutSubItem { Text = "New Secret" };
        AddSecretItems(secret.Items);
        menu.Items.Add(secret);
        ShowMenu(menu, sender, args);
    }

    private static void ShowMenu(MenuFlyout menu, UIElement at, ContextRequestedEventArgs args)
    {
        if (args.TryGetPosition(at, out var point)) menu.ShowAt(at, point);
        else menu.ShowAt((FrameworkElement)at);
        args.Handled = true;
    }

    // MARK: Changing things

    /// <summary>Runs a change on the vault, then shows the list again; a refusal is said in the notice bar.</summary>
    private bool Change(Action<Vault> change)
    {
        try
        {
            change(Vault);
            return true;
        }
        catch (StillroomException failure)
        {
            Say(failure.Message, InfoBarSeverity.Error);
            return false;
        }
        catch (ObjectDisposedException)
        {
            return false;
        }
        finally
        {
            Load();
        }
    }

    private void Say(string message, InfoBarSeverity severity)
    {
        Notice.Message = message;
        Notice.Severity = severity;
        Notice.IsOpen = true;
    }

    private async Task Rename(VaultItem item)
    {
        if (await Ask.Name(XamlRoot, "Rename", "Rename", item.Name) is { } name && name != item.Name) Change(v => v.Rename(item.Id, name));
    }

    private async Task EditTags(VaultItem item)
    {
        var typed = await Ask.Name(XamlRoot, "Tags", "Save", string.Join(", ", item.Tags), "Tags, separated by commas");
        if (typed is null) return;
        var chosen = typed.Split(',').Select(t => t.Trim()).Where(t => t.Length > 0).Distinct().ToList();
        Change(v => v.SetTags(item.Id, chosen));
        RefreshSearchSoon();
    }

    private void Move(VaultItem item, string? to) => Change(v => v.MoveItems([item.Id], to));

    private async Task Delete(VaultItem item)
    {
        var answer = await Ask.Choose(XamlRoot, $"Delete “{item.Name}” from the vault?", "It and its earlier versions can't be brought back.", "Delete", destructive: true);
        if (answer == ContentDialogResult.Primary) Change(v => v.Delete(item.Id));
    }

    private async Task NewFolder()
    {
        if (await Ask.Name(XamlRoot, "New folder", "Make Folder") is { } name) Change(v => v.MakeFolder(name, FolderHere));
    }

    private async Task RenameFolder(string path)
    {
        if (await Ask.Name(XamlRoot, "Rename folder", "Rename", path.ShownLast()) is not { } name) return;
        string? renamed = null;
        // Stay where you are; inside the renamed folder, follow it to its new name.
        if (Change(v => renamed = v.RenameFolder(path, name)) && renamed is not null && folder is { } here && (here == path || here.StartsWith(path + "/", StringComparison.Ordinal)))
        {
            folder = renamed + here[path.Length..];
            DrawPane();
        }
    }

    private async Task DeleteFolder(string path)
    {
        var answer = await Ask.Choose(XamlRoot, $"Delete the folder “{path.ShownLast()}” and everything in it?",
            "Every file, note and secret inside it goes too, and can't be brought back.", "Delete Folder", destructive: true);
        if (answer != ContentDialogResult.Primary) return;
        if (Change(v => v.DeleteFolder(path)) && folder is { } here && (here == path || here.StartsWith(path + "/", StringComparison.Ordinal)))
        {
            folder = path.Parent();
            DrawPane();
        }
    }

    // MARK: Making

    private void NewNote()
    {
        string? id = null;
        if (!Change(v => id = v.NewNote("Untitled note", "", FolderHere)) || items.FirstOrDefault(i => string.Equals(i.Id, id, StringComparison.OrdinalIgnoreCase)) is not { } note) return;
        (shelf, tag) = (Shelf.Notes, null);
        DrawSidebar();
        Open(note);
    }

    private void NewSecret(SecretTemplate template)
    {
        string? id = null;
        var json = JsonSerializer.SerializeToUtf8Bytes(SecretContent.Starting(template));
        if (!Change(v => id = v.NewSecret(template.Title, json, FolderHere)) || items.FirstOrDefault(i => string.Equals(i.Id, id, StringComparison.OrdinalIgnoreCase)) is not { } secret) return;
        (shelf, tag) = (Shelf.Secrets, null);
        DrawSidebar();
        Open(secret);
    }

    // MARK: Adding

    private void OnAddFiles(object sender, RoutedEventArgs e) => _ = PickFiles();
    private void OnAddFolder(object sender, RoutedEventArgs e) => _ = PickFolder();

    private async Task PickFiles()
    {
        var picker = new FileOpenPicker();
        WinRT.Interop.InitializeWithWindow.Initialize(picker, window.Handle);
        picker.FileTypeFilter.Add("*");
        if (await Picking(picker.PickMultipleFilesAsync()) is { Count: > 0 } picked) await Add(picked.Select(f => f.Path).ToList());
    }

    private async Task PickFolder()
    {
        var picker = new FolderPicker();
        WinRT.Interop.InitializeWithWindow.Initialize(picker, window.Handle);
        picker.FileTypeFilter.Add("*");
        if (await Picking(picker.PickSingleFolderAsync()) is { } picked) await Add([picked.Path]);
    }

    /// <summary>A picker's answer, or null when it was closed or couldn't open (which is said).</summary>
    private async Task<T?> Picking<T>(Windows.Foundation.IAsyncOperation<T> picking) where T : class
    {
        try { return await picking; }
        catch (Exception failure)
        {
            Say($"The file picker didn't work. {failure.Message} (0x{failure.HResult:X8})", InfoBarSeverity.Error);
            return null;
        }
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        if (!e.DataView.Contains(StandardDataFormats.StorageItems) || Editor.Visibility == Visibility.Visible) return;
        e.AcceptedOperation = DataPackageOperation.Copy;
        e.DragUIOverride.Caption = "Put in the vault";
        if (!dropping)
        {
            dropping = true;
            if (Empty.Visibility == Visibility.Visible) DrawEmpty();
        }
    }

    private void OnDragLeave(object sender, DragEventArgs e)
    {
        dropping = false;
        if (Empty.Visibility == Visibility.Visible) DrawEmpty();
    }

    private async void OnDrop(object sender, DragEventArgs e)
    {
        dropping = false;
        if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;
        var dropped = await e.DataView.GetStorageItemsAsync();
        var paths = dropped.Select(i => i.Path).Where(p => p.Length > 0).ToList();
        if (paths.Count > 0) await Add(paths);
        else DrawPane();
    }

    /// <summary>Files and folders in, each checked against its original; then what to do with the originals.</summary>
    // MARK: Dragging within the window

    /// <summary>Which folder each drag token stands for, held in memory only: a drag carries the token, never the
    /// folder's name, so dropped anywhere else it says nothing about what's in the vault (the Mac's `FolderDrag`).</summary>
    private static readonly Dictionary<string, string> folderDrags = new();
    private const string ItemFormat = "Stillroom.Item";
    private const string FolderFormat = "Stillroom.Folder";

    /// <summary>The row under a drag: hit-tested at its position (a drag's source element isn't the row under it).</summary>
    private Row? RowUnder(DragEventArgs e)
    {
        var at = e.GetPosition(null);
        foreach (var element in VisualTreeHelper.FindElementsInHostCoordinates(at, Rows))
            if (element is ListViewItem container) return Rows.ItemFromContainer(container) as Row;
        return null;
    }

    private void OnRowsDragStarting(object sender, DragItemsStartingEventArgs e)
    {
        if (e.Items.FirstOrDefault() is not Row row) { e.Cancel = true; return; }
        if (row.Item is { } item)
        {
            e.Data.SetData(ItemFormat, item.Id);
        }
        else if (row.FolderPath is { } path)
        {
            var token = Guid.NewGuid().ToString("N");
            folderDrags[token] = path;
            e.Data.SetData(FolderFormat, token);
        }
        e.Data.RequestedOperation = DataPackageOperation.Move;
    }

    /// <summary>Over a folder's row: an item or folder dragged from the list moves into it, files from Explorer go
    /// into it.</summary>
    private void OnRowsDragOver(object sender, DragEventArgs e)
    {
        var target = RowUnder(e)?.FolderPath;
        e.Handled = true;
        if (target is null)
        {
            // Not over a folder: files from Explorer still go where the window is (the window's own handler).
            e.Handled = false;
            return;
        }
        if (e.DataView.Contains(ItemFormat) || e.DataView.Contains(FolderFormat))
        {
            e.AcceptedOperation = DataPackageOperation.Move;
            e.DragUIOverride.Caption = $"Move into {target.ShownLast()}";
        }
        else if (e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            e.AcceptedOperation = DataPackageOperation.Copy;
            e.DragUIOverride.Caption = $"Put in the vault, in {target.ShownLast()}";
        }
    }

    private async void OnRowsDrop(object sender, DragEventArgs e)
    {
        var target = RowUnder(e)?.FolderPath;
        if (target is null) return;
        e.Handled = true;
        dropping = false;
        if (e.DataView.Contains(ItemFormat) && await e.DataView.GetDataAsync(ItemFormat) is string id)
        {
            Change(v => v.MoveItems([id], target));
        }
        else if (e.DataView.Contains(FolderFormat) && await e.DataView.GetDataAsync(FolderFormat) is string token && folderDrags.Remove(token, out var path))
        {
            // Not into itself or where it already is.
            if (path != target && !target.StartsWith(path + "/", StringComparison.Ordinal) && path.Parent() != target)
                Change(v => v.MoveFolder(path, target));
        }
        else if (e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            var dropped = await e.DataView.GetStorageItemsAsync();
            var paths = dropped.Select(i => i.Path).Where(p => p.Length > 0).ToList();
            if (paths.Count > 0) await Add(paths, target);
        }
    }

    private Task Add(IReadOnlyList<string> paths) => Add(paths, FolderHere);

    /// <summary>Files sent from Explorer go in now, into the folder that's open. Sent with "Move to Stillroom", their
    /// originals go once checked: deleted for good, or to the Recycle Bin if BitLocker is off (deleting wouldn't be for
    /// good then), as the Mac does with FileVault.</summary>
    private async void TakeInbox()
    {
        if (Inbox.Count == 0 || state.Vault is null || mustSetPassword) return;
        var (paths, moving) = Inbox.Take();
        await Add(paths, FolderHere, moving);
    }

    /// <summary>Files and folders in, into `into` (a folder, or the top), each checked against its original; then what
    /// to do with the originals.</summary>
    private async Task Add(IReadOnlyList<string> paths, string? into, bool moving = false)
    {
        if (state.Vault is not { } vault) return;
        adding = paths.Count;
        DrawPane();
        JsonElement report;
        try
        {
            report = await Task.Run(() => vault.Add(paths, into));
        }
        catch (StillroomException failure)
        {
            Say(failure.Message, InfoBarSeverity.Error);
            return;
        }
        catch (ObjectDisposedException)
        {
            return;
        }
        finally
        {
            adding = 0;
            Load();
        }
        RefreshSearchSoon();

        var failed = report.GetProperty("failed").EnumerateArray().ToList();
        var unchecked_ = report.GetProperty("unchecked").GetArrayLength();
        if (failed.Count > 0)
        {
            var first = failed[0];
            var name = Path.GetFileName(first.GetProperty("path").GetString());
            Say(failed.Count == 1 ? $"“{name}” couldn't be added. {first.GetProperty("message").GetString()}"
                : $"{failed.Count} couldn't be added, “{name}” among them. {first.GetProperty("message").GetString()}", InfoBarSeverity.Error);
        }
        else if (unchecked_ > 0)
        {
            Say($"{unchecked_} added, but their copies couldn't be checked against the originals, so the originals stay where they are.", InfoBarSeverity.Warning);
        }
        if (moving) await MoveOriginals(report.GetProperty("originals"));
        else await OfferOriginals(report.GetProperty("originals"));
    }

    /// <summary>"Move to Stillroom": the originals that checked out go without asking.</summary>
    private async Task MoveOriginals(JsonElement originals)
    {
        if (originals.GetProperty("files").GetArrayLength() == 0) return;
        if (EditDesk.SystemDriveEncrypted() == true)
        {
            var left = await Task.Run(() => Vault.DeleteOriginals(originals));
            if (left.GetArrayLength() > 0) Say($"Couldn't delete {string.Join(", ", left.EnumerateArray().Select(n => n.GetString()))}. They're still where they were.", InfoBarSeverity.Warning);
            return;
        }
        try
        {
            await Task.Run(() => Array.ForEach(Vault.OriginalsRemovals(originals), Shell.Recycle));
            Say("BitLocker is off, so the originals went to the Recycle Bin rather than being deleted for good.", InfoBarSeverity.Informational);
        }
        catch (Exception failure) when (failure is IOException or UnauthorizedAccessException or OperationCanceledException)
        {
            Say($"The originals couldn't be moved to the Recycle Bin. {failure.Message}", InfoBarSeverity.Warning);
        }
    }

    /// <summary>Asks what to do with the originals of what just went in (only those whose copies checked out).</summary>
    private async Task OfferOriginals(JsonElement originals)
    {
        var files = originals.GetProperty("files").EnumerateArray().Select(p => p.GetString() ?? "").Where(p => p.Length > 0).ToList();
        if (files.Count == 0) return;
        var question = files.Count == 1 ? $"Delete “{Path.GetFileName(files[0])}” now that it's in the vault?" : $"Delete the {files.Count} originals now that they're in the vault?";
        var answer = await Ask.Choose(XamlRoot, question,
            "Each was checked against its encrypted copy first. Deleting skips the Recycle Bin and can't be undone.",
            "Delete Originals", "Move to Recycle Bin", "Keep Originals");
        if (answer == ContentDialogResult.Primary)
        {
            var left = await Task.Run(() => Vault.DeleteOriginals(originals));
            if (left.GetArrayLength() > 0)
                Say($"Couldn't delete {string.Join(", ", left.EnumerateArray().Select(n => n.GetString()))}. They're still where they were.", InfoBarSeverity.Warning);
        }
        else if (answer == ContentDialogResult.Secondary)
        {
            // By the same rule as deleting: a folder whole only when everything in it went in.
            try { await Task.Run(() => Array.ForEach(Vault.OriginalsRemovals(originals), Shell.Recycle)); }
            catch (Exception failure) when (failure is IOException or UnauthorizedAccessException or OperationCanceledException)
            {
                Say($"The originals couldn't be moved to the Recycle Bin. {failure.Message}", InfoBarSeverity.Warning);
            }
        }
    }

    /// <summary>Logins out of a password manager's or browser's export, into Secrets; then the export itself, which
    /// lists every password unencrypted, offered for deleting.</summary>
    private async Task ImportLogins()
    {
        var picker = new FileOpenPicker();
        WinRT.Interop.InitializeWithWindow.Initialize(picker, window.Handle);
        picker.FileTypeFilter.Add(".csv");
        if (await picker.PickSingleFileAsync() is not { } file) return;
        var csv = await File.ReadAllBytesAsync(file.Path);
        (int Added, int Skipped) result = default;
        try
        {
            if (!Change(v => result = v.ImportLogins(csv))) return;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(csv);
        }
        (shelf, tag) = (Shelf.Secrets, null);
        DrawSidebar();
        DrawPane();
        var title = result.Added == 0
            ? result.Skipped == 0 ? "No accounts in that file." : $"Nothing new: all {result.Skipped} were already here."
            : $"Imported {result.Added} {(result.Added == 1 ? "login" : "logins")}{(result.Skipped > 0 ? $"; {result.Skipped} were already here." : ".")}";
        var answer = await Ask.Choose(XamlRoot, title,
            "The file you exported lists every password unencrypted, and everything in it is now in the vault. Delete it now?",
            "Delete It for Good", "Move to Recycle Bin", "Keep It");
        try
        {
            if (answer == ContentDialogResult.Primary) File.Delete(file.Path);
            else if (answer == ContentDialogResult.Secondary) Shell.Recycle(file.Path);
        }
        catch (Exception failure) when (failure is IOException or UnauthorizedAccessException or OperationCanceledException)
        {
            Say($"The file couldn't be removed. {failure.Message}", InfoBarSeverity.Warning);
        }
    }

    // MARK: Out of the vault

    /// <summary>A copy outside the vault, where the person picks. It isn't encrypted, and the save button says so.</summary>
    private async Task SaveCopy(VaultItem item)
    {
        var picker = new FileSavePicker { SuggestedFileName = Path.GetFileNameWithoutExtension(item.Name), CommitButtonText = "Save Unencrypted Copy" };
        WinRT.Interop.InitializeWithWindow.Initialize(picker, window.Handle);
        var extension = Path.GetExtension(item.Name);
        picker.FileTypeChoices.Add(extension.Length > 1 ? item.KindName : "File", [extension.Length > 1 ? extension : ".data"]);
        if (await picker.PickSaveFileAsync() is not StorageFile target) return;
        var vault = state.Vault;
        if (vault is null) return;
        try { await Task.Run(() => vault.ExportItem(item.Id, target.Path)); }
        catch (StillroomException failure) { Say(failure.Message, InfoBarSeverity.Error); }
        catch (ObjectDisposedException) { }
    }

    private async Task ShowVersions(VaultItem item)
    {
        var current = items.FirstOrDefault(i => string.Equals(i.Id, item.Id, StringComparison.OrdinalIgnoreCase)) ?? item;
        var chosen = await VersionsDialog.ShowAsync(XamlRoot, current);
        if (chosen is null) return;
        var (version, putBack) = chosen.Value;
        if (putBack)
        {
            CloseEditor();
            Change(v => v.RestoreVersion(item.Id, version.Id));
        }
        else
        {
            ShowEditor(new PreviewCard(state, current, version, CloseEditor, () => _ = SaveCopy(current)));
        }
    }

    // MARK: Keys

    private void OnLock(object sender, RoutedEventArgs e) => state.Lock("lock button");

    private async void OnSetPassword(object sender, RoutedEventArgs e)
    {
        if (state.Vault is not { } vault) return;
        var button = (Button)sender;
        button.IsEnabled = false;
        PasswordLine.Text = "";
        try
        {
            var problem = await Task.Run(() =>
            {
                var password = Secrets.AskNewPassword($"Choose a new password for your vault: {Secrets.Shortest} characters or more.", out var weak);
                if (password is null) return weak ?? "";
                try { vault.SetPasswordAfterRecovery(password); return null; }
                finally { CryptographicOperations.ZeroMemory(password); }
            });
            // "" was a cancel: nothing to say.
            if (problem is not null) PasswordLine.Text = problem;
            else Load();
        }
        catch (StillroomException failure)
        {
            PasswordLine.Text = failure.Message;
        }
        catch (ObjectDisposedException)
        {
        }
        finally
        {
            button.IsEnabled = true;
        }
    }
}
