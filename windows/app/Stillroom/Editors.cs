using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Stillroom.Model;
using Stillroom.Native;
using Stillroom.Platform;

namespace Stillroom;

/// <summary>What a note's and a secret's editor share (the Mac's `EditorBar` and `EditorHeader`): back to the list,
/// when it was last saved, its versions, its kind over its name typed straight into, and saving a moment after typing
/// stops, on leaving, and just before the vault locks.</summary>
internal abstract class Editor : UserControl, IDisposable
{
    protected readonly AppState State;
    protected readonly VaultItem Item;
    protected readonly TextBox Title;
    private readonly TextBlock saved;
    private readonly DispatcherQueueTimer pause;
    private DateTimeOffset savedAt;
    protected bool Ready;

    protected Editor(AppState state, VaultItem item, string backTitle, string kind, string glyph, string hint, Action back, Action versions)
    {
        State = state;
        Item = item;
        savedAt = item.ChangedAt;

        var bar = new Grid();
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var backButton = new HyperlinkButton { Content = $"‹ {backTitle}", Style = (Style)Application.Current.Resources["QuietButton"] };
        backButton.Click += (_, _) => back();
        backButton.KeyboardAccelerators.Add(new KeyboardAccelerator { Key = Windows.System.VirtualKey.Escape });
        bar.Children.Add(backButton);
        saved = new TextBlock { FontSize = 12, Opacity = 0.4, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) };
        Grid.SetColumn(saved, 1);
        bar.Children.Add(saved);
        if (item.Versions.Count > 0)
        {
            var versionsButton = new HyperlinkButton { Content = $"⟲ {item.Versions.Count}", Style = (Style)Application.Current.Resources["QuietButton"] };
            ToolTipService.SetToolTip(versionsButton, "Earlier versions");
            AutomationProperties.SetName(versionsButton, "Earlier versions");
            versionsButton.Click += (_, _) => { Flush(); versions(); };
            Grid.SetColumn(versionsButton, 2);
            bar.Children.Add(versionsButton);
        }

        Title = new TextBox
        {
            Text = item.Name,
            PlaceholderText = hint,
            FontSize = 24,
            FontWeight = FontWeights.SemiBold,
            BorderThickness = new Thickness(0),
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            Padding = new Thickness(0),
        };
        AutomationProperties.SetName(Title, hint);
        Title.TextChanged += (_, _) => Schedule();
        var header = new Grid { ColumnSpacing = 14, Margin = new Thickness(0, 4, 0, 8) };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.Children.Add(new Border
        {
            Width = 46,
            Height = 46,
            CornerRadius = new CornerRadius(13),
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x24, 0xB0, 0x8C, 0xFF)),
            BorderBrush = new SolidColorBrush(Windows.UI.Color.FromArgb(0x38, 0xB0, 0x8C, 0xFF)),
            BorderThickness = new Thickness(1),
            Child = new FontIcon { Glyph = glyph, FontSize = 19, Foreground = (Brush)Application.Current.Resources["VaultBrush"] },
        });
        var words = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        words.Children.Add(new TextBlock { Text = kind.ToUpperInvariant(), FontSize = 10.5, FontWeight = FontWeights.SemiBold, CharacterSpacing = 80, Foreground = (Brush)Application.Current.Resources["QuietBrush"] });
        words.Children.Add(Title);
        Grid.SetColumn(words, 1);
        header.Children.Add(words);

        var page = new Grid { RowSpacing = 8 };
        page.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        page.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        page.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        page.Children.Add(bar);
        Grid.SetRow(header, 1);
        page.Children.Add(header);
        var body = Body();
        Grid.SetRow(body, 2);
        page.Children.Add(body);
        Content = page;

        pause = DispatcherQueue.GetForCurrentThread().CreateTimer();
        pause.Interval = TimeSpan.FromMilliseconds(700);
        pause.IsRepeating = false;
        pause.Tick += (_, _) => Flush();
        state.Locking += Flush;
        ShowSaved();
    }

    /// <summary>What's being edited, under the heading.</summary>
    protected abstract FrameworkElement Body();

    /// <summary>What to save now, or null when nothing changed since the last save (then nothing is written and no
    /// version is made).</summary>
    protected abstract (byte[] Data, string Name)? Changes();

    /// <summary>The changes are saved.</summary>
    protected abstract void Saved();

    protected void Schedule()
    {
        if (!Ready) return;
        pause.Stop();
        pause.Start();
    }

    public void Flush()
    {
        pause.Stop();
        if (!Ready || State.Vault is not { } vault || Changes() is not { } change) return;
        try
        {
            vault.Update(Item.Id, change.Data, change.Name);
            Saved();
            savedAt = DateTimeOffset.Now;
            ShowSaved();
        }
        catch (Exception e) when (e is StillroomException or ObjectDisposedException)
        {
            saved.Text = e is StillroomException failure ? failure.Message : "";
        }
        finally
        {
            CryptographicOperations.ZeroMemory(change.Data);
        }
    }

    private void ShowSaved()
    {
        var ago = DateTimeOffset.Now - savedAt;
        saved.Text = ago < TimeSpan.FromMinutes(1) ? "Saved just now"
            : ago < TimeSpan.FromHours(1) ? $"Saved {(int)ago.TotalMinutes} min ago"
            : ago < TimeSpan.FromDays(1) ? $"Saved {(int)ago.TotalHours} h ago"
            : $"Saved {savedAt.LocalDateTime:d MMM yyyy}";
    }

    public void Dispose()
    {
        Flush();
        State.Locking -= Flush;
    }

    protected static Border Panel(UIElement child) => new()
    {
        Background = (Brush)Application.Current.Resources["PanelBrush"],
        CornerRadius = new CornerRadius(12),
        Child = child,
    };
}

/// <summary>A note, open: its title and text, saved as you type (a moment after you stop), encrypted like any file.</summary>
internal sealed class NoteEditor : Editor
{
    private TextBox text = null!;
    private string savedName = "";
    private string savedText = "";

    public NoteEditor(AppState state, VaultItem item, Action back, Action versions)
        : base(state, item, "Notes", "Note", Glyphs.Note, "Title", back, versions)
    {
        try
        {
            var data = state.Vault!.Read(item.Id);
            savedText = Encoding.UTF8.GetString(data);
            CryptographicOperations.ZeroMemory(data);
        }
        catch (Exception e) when (e is StillroomException or ObjectDisposedException or NullReferenceException) { }
        savedName = item.Name;
        text.Text = savedText;
        Ready = true;
    }

    protected override FrameworkElement Body()
    {
        text = new TextBox
        {
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            FontSize = 14,
            BorderThickness = new Thickness(0),
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            Padding = new Thickness(14),
            PlaceholderText = "Write anything. It's saved as you type, encrypted.",
        };
        ScrollViewer.SetVerticalScrollBarVisibility(text, ScrollBarVisibility.Auto);
        AutomationProperties.SetName(text, "Note");
        text.TextChanged += (_, _) => Schedule();
        return Panel(text);
    }

    private string EntryName => Title.Text.Trim().Length == 0 ? "Untitled note" : Title.Text.Trim();

    protected override (byte[] Data, string Name)? Changes() =>
        EntryName == savedName && text.Text == savedText ? null : (Encoding.UTF8.GetBytes(text.Text), EntryName);

    protected override void Saved() => (savedName, savedText) = (EntryName, text.Text);
}

/// <summary>A secret, open: its fields, each labelled. Concealed values show as dots until the eye is pressed, and copy
/// to a clipboard that Windows' clipboard history skips and that empties itself after 30 seconds.</summary>
internal sealed class SecretEditor : Editor
{
    private SecretContent secret = new();
    private string savedJson = "";
    private string savedName = "";
    private readonly HashSet<string> shown = [];
    private StackPanel rows = null!;
    private TextBlock line = null!;
    private readonly DispatcherQueueTimer clock;
    private readonly List<Action> ticking = [];

    public SecretEditor(AppState state, VaultItem item, Action back, Action versions)
        : base(state, item, "Secrets", "Secret", Glyphs.Secret, "Name", back, versions)
    {
        try
        {
            var data = state.Vault!.Read(item.Id);
            secret = JsonSerializer.Deserialize<SecretContent>(data) ?? new SecretContent();
            CryptographicOperations.ZeroMemory(data);
        }
        catch (Exception e) when (e is StillroomException or ObjectDisposedException or JsonException or NullReferenceException) { }
        savedJson = JsonSerializer.Serialize(secret);
        savedName = item.Name;
        // The codes under two-factor fields change every 30 seconds: their rows follow the clock.
        clock = DispatcherQueue.GetForCurrentThread().CreateTimer();
        clock.Interval = TimeSpan.FromSeconds(1);
        clock.Tick += (_, _) => ticking.ForEach(t => t());
        clock.Start();
        Unloaded += (_, _) => clock.Stop();
        DrawRows();
        Ready = true;
    }

    protected override FrameworkElement Body()
    {
        rows = new StackPanel();
        var adds = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 8, 0, 0) };
        adds.Children.Add(Quiet("+ Add Field", () => { secret.Fields.Add(new SecretField { Label = "New field" }); Changed(); }));
        adds.Children.Add(Quiet("+ Add Password", () => { secret.Fields.Add(new SecretField { Label = "Password", Concealed = true }); Changed(); }));
        adds.Children.Add(Quiet("+ Add Two-Factor", () =>
        {
            secret.Fields.Add(new SecretField { Label = "Two-factor setup", Concealed = true });
            Changed();
            Say("Paste the setup key or otpauth link the website shows under its QR code.");
        }));
        line = new TextBlock { FontSize = 12, Opacity = 0.5, Margin = new Thickness(0, 8, 0, 0) };
        var page = new StackPanel();
        page.Children.Add(Panel(rows));
        page.Children.Add(adds);
        page.Children.Add(line);
        return new ScrollViewer { Content = page, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden };
    }

    private static HyperlinkButton Quiet(string text, Action act)
    {
        var button = new HyperlinkButton { Content = text, Style = (Style)Application.Current.Resources["QuietButton"] };
        button.Click += (_, _) => act();
        return button;
    }

    private void Changed()
    {
        DrawRows();
        Schedule();
    }

    private void Say(string text)
    {
        line.Text = text;
        _ = Task.Delay(TimeSpan.FromSeconds(6)).ContinueWith(_ => DispatcherQueue.TryEnqueue(() => { if (line.Text == text) line.Text = ""; }), TaskScheduler.Default);
    }

    private void DrawRows()
    {
        rows.Children.Clear();
        ticking.Clear();
        foreach (var field in secret.Fields)
        {
            if (rows.Children.Count > 0) rows.Children.Add(new Border { Height = 1, Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x0D, 0xFF, 0xFF, 0xFF)) });
            rows.Children.Add(FieldRow(field));
            if (CodeRow(field) is { } code) rows.Children.Add(code);
        }
    }

    private Grid FieldRow(SecretField field)
    {
        var visible = !field.Concealed || shown.Contains(field.Id);
        var row = new Grid { Height = 42, Padding = new Thickness(14, 0, 8, 0), ColumnSpacing = 8 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(130) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var label = new TextBox { Text = field.Label, PlaceholderText = "Label", FontSize = 12, Opacity = 0.6, BorderThickness = new Thickness(0), Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), VerticalAlignment = VerticalAlignment.Center };
        AutomationProperties.SetName(label, "Label");
        label.TextChanged += (_, _) => { field.Label = label.Text; Schedule(); };
        row.Children.Add(label);

        Control value;
        if (visible)
        {
            var box = new TextBox { Text = field.Value, PlaceholderText = "Empty", FontFamily = field.Concealed ? new FontFamily("Consolas") : FontFamily, BorderThickness = new Thickness(0), Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), VerticalAlignment = VerticalAlignment.Center };
            box.TextChanged += (_, _) => { field.Value = box.Text; Schedule(); };
            box.LostFocus += (_, _) => { if (CodeChanged(field)) DrawRows(); };
            value = box;
        }
        else
        {
            var box = new PasswordBox { Password = field.Value, PlaceholderText = "Empty", BorderThickness = new Thickness(0), Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), VerticalAlignment = VerticalAlignment.Center, PasswordRevealMode = PasswordRevealMode.Hidden };
            box.PasswordChanged += (_, _) => { field.Value = box.Password; Schedule(); };
            box.LostFocus += (_, _) => { if (CodeChanged(field)) DrawRows(); };
            value = box;
        }
        AutomationProperties.SetName(value, field.Label);
        Grid.SetColumn(value, 1);
        row.Children.Add(value);

        var tools = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 2 };
        if (field.Concealed)
        {
            tools.Children.Add(Tool(visible ? "" : "", visible ? "Hide" : "Show", () =>
            {
                if (!shown.Remove(field.Id)) shown.Add(field.Id);
                DrawRows();
            }));
            tools.Children.Add(Tool("", "Make a strong random password", () =>
            {
                field.Value = SecretTemplates.GeneratePassword();
                shown.Add(field.Id);
                Changed();
            }));
        }
        var copy = Tool("", "Copy", () => Copy(field.Value));
        copy.IsEnabled = field.Value.Length > 0;
        tools.Children.Add(copy);
        var more = new MenuFlyout();
        var concealed = new ToggleMenuFlyoutItem { Text = "Concealed", IsChecked = field.Concealed };
        concealed.Click += (_, _) => { field.Concealed = concealed.IsChecked; shown.Remove(field.Id); Changed(); };
        more.Items.Add(concealed);
        var remove = new MenuFlyoutItem { Text = "Remove Field" };
        remove.Click += (_, _) => { secret.Fields.Remove(field); Changed(); };
        more.Items.Add(remove);
        var menu = Tool("", "More", () => { });
        menu.Flyout = more;
        tools.Children.Add(menu);
        Grid.SetColumn(tools, 2);
        row.Children.Add(tools);
        return row;
    }

    private Dictionary<string, bool> hadCode = [];

    /// <summary>Whether a field's value now does or doesn't hold a two-factor setup, unlike when last drawn.</summary>
    private bool CodeChanged(SecretField field) => hadCode.GetValueOrDefault(field.Id) != (Code(field) is not null);

    private static (string Code, int SecondsLeft)? Code(SecretField field) =>
        field.Value.Length == 0 ? null : Engine.OneTimeCode(field.Label, field.Value, DateTimeOffset.UtcNow);

    /// <summary>Under a two-factor setup: the code the website asks for now, the seconds it has left, and a copy button.</summary>
    private Grid? CodeRow(SecretField field)
    {
        hadCode[field.Id] = Code(field) is not null;
        if (!hadCode[field.Id]) return null;
        var row = new Grid { Height = 46, Padding = new Thickness(14, 0, 8, 0), ColumnSpacing = 8, Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x0D, 0xB0, 0x8C, 0xFF)) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(130) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(new TextBlock { Text = "Code", FontSize = 12, Opacity = 0.6, VerticalAlignment = VerticalAlignment.Center });
        var code = new TextBlock { FontFamily = new FontFamily("Consolas"), FontSize = 17, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
        var left = new TextBlock { FontSize = 11, Opacity = 0.6, VerticalAlignment = VerticalAlignment.Center };
        ToolTipService.SetToolTip(left, "Seconds until the code changes");
        Grid.SetColumn(code, 1);
        Grid.SetColumn(left, 2);
        row.Children.Add(code);
        row.Children.Add(left);
        var copy = Tool("", "Copy the code", () => { if (Code(field) is { } now) Copy(now.Code); });
        Grid.SetColumn(copy, 3);
        row.Children.Add(copy);
        void Tick()
        {
            if (Code(field) is not { } now) return;
            // Split in half, as authenticator apps show it: easier to read off and type.
            code.Text = $"{now.Code[..(now.Code.Length / 2)]} {now.Code[(now.Code.Length / 2)..]}";
            var warn = now.SecondsLeft <= 5;
            code.Foreground = warn ? new SolidColorBrush(Microsoft.UI.Colors.Orange) : (Brush)Application.Current.Resources["VaultBrush"];
            left.Text = $"{now.SecondsLeft} s";
            AutomationProperties.SetName(code, $"Code {string.Join(' ', now.Code.ToCharArray())}");
        }
        Tick();
        ticking.Add(Tick);
        return row;
    }

    private static Button Tool(string glyph, string help, Action act)
    {
        var button = new Button
        {
            Content = new FontIcon { Glyph = glyph, FontSize = 14 },
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
            Padding = new Thickness(8, 6, 8, 6),
        };
        ToolTipService.SetToolTip(button, help);
        AutomationProperties.SetName(button, help);
        button.Click += (_, _) => act();
        return button;
    }

    private void Copy(string value)
    {
        Say(SecretClipboard.Copy(value, App.Window?.Handle ?? IntPtr.Zero) ? "Copied. The clipboard empties itself in 30 seconds." : "The clipboard is busy. Try again.");
    }

    private string EntryName => Title.Text.Trim().Length == 0 ? secret.Kind.Title : Title.Text.Trim();

    protected override (byte[] Data, string Name)? Changes()
    {
        var json = JsonSerializer.Serialize(secret);
        return json == savedJson && EntryName == savedName ? null : (Encoding.UTF8.GetBytes(json), EntryName);
    }

    protected override void Saved() => (savedJson, savedName) = (JsonSerializer.Serialize(secret), EntryName);
}
