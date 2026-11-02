using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Data.Pdf;
using Windows.Storage.Streams;

namespace Stillroom;

/// <summary>A PDF in the card (the Mac's `PDFPreview`, PDFKit's view): its pages one under another, fitted to the
/// width, zoomed by pinching, Ctrl and the wheel, Ctrl+Plus and Ctrl+Minus (Ctrl+0 fits it again), or the buttons in
/// its corner. Drawn by Windows' own PDF renderer (Windows.Data.Pdf), which has no
/// networking, from memory: nothing decrypted touches the disk. A page is drawn only as it comes near the view and let
/// go again far from it, so a long PDF never holds every page as a picture.</summary>
internal sealed class PdfViewer : UserControl
{
    private sealed class Page(PdfPage source, Image image, Border frame, double aspect)
    {
        public PdfPage Source { get; } = source;
        public Image Image { get; } = image;
        public Border Frame { get; } = frame;
        /// <summary>Height over width.</summary>
        public double Aspect { get; } = aspect;
        /// <summary>Pixels wide it was drawn at; 0 while not drawn.</summary>
        public uint Drawn { get; set; }
    }

    private const double Gap = 12;
    private const double Edge = 16;
    /// <summary>Widest a page is ever drawn, however far it's zoomed.</summary>
    private const uint Widest = 4096;

    private readonly ScrollViewer scroller;
    private readonly StackPanel column = new() { Spacing = Gap, Padding = new Thickness(Edge) };
    private readonly List<Page> pages = [];
    private InMemoryRandomAccessStream? stream;
    private PdfDocument? document;
    private bool drawing;
    private bool again;
    private bool closed;
    private readonly TextBlock percent = new() { Text = "100%", MinWidth = 44, TextAlignment = TextAlignment.Center, VerticalAlignment = VerticalAlignment.Center, FontSize = 12 };

    /// <summary>The zoom steps the buttons and keys move between.</summary>
    private static readonly float[] Steps = [0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f, 3f, 4f];

    /// <summary>`data` is copied into memory the renderer reads; the caller wipes its own copy.</summary>
    public PdfViewer(byte[] data, Func<UIElement> unreadable)
    {
        scroller = new ScrollViewer
        {
            Content = column,
            ZoomMode = ZoomMode.Enabled,
            MinZoomFactor = 0.5f,
            MaxZoomFactor = 4,
            HorizontalScrollMode = ScrollMode.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            IsTabStop = true,
        };
        var zoomOut = ZoomButton("\uE71F", "Zoom out", () => ZoomBy(-1));
        var fit = new Button { Content = percent, Padding = new Thickness(4, 4, 4, 4), Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), BorderThickness = new Thickness(0) };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(fit, "Fit to width");
        fit.Click += (_, _) => ZoomTo(1);
        var zoomIn = ZoomButton("\uE8A3", "Zoom in", () => ZoomBy(1));
        var bar = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(0, 0, 20, 14),
            Padding = new Thickness(4),
            CornerRadius = new CornerRadius(8),
            Background = Theme.Brush("GlassBrush"),
            Children = { zoomOut, fit, zoomIn },
        };
        var layers = new Grid { Children = { scroller, bar } };
        Content = layers;
        Key(Windows.System.VirtualKey.Add, () => ZoomBy(1));
        Key((Windows.System.VirtualKey)187, () => ZoomBy(1));
        Key(Windows.System.VirtualKey.Subtract, () => ZoomBy(-1));
        Key((Windows.System.VirtualKey)189, () => ZoomBy(-1));
        Key(Windows.System.VirtualKey.Number0, () => ZoomTo(1));

        stream = new InMemoryRandomAccessStream();
        var writer = new DataWriter(stream);
        writer.WriteBytes(data);
        Loaded += async (_, _) =>
        {
            if (document is not null || stream is null) return;
            try
            {
                await writer.StoreAsync();
                writer.DetachStream();
                stream.Seek(0);
                document = await PdfDocument.LoadFromStreamAsync(stream);
            }
            catch (Exception)
            {
                // Damaged, not a PDF, or locked with a password (Windows asks for none here).
                Content = unreadable();
                Close();
                return;
            }
            if (closed) return;
            for (uint i = 0; i < document.PageCount; i++)
            {
                var source = document.GetPage(i);
                var size = source.Size;
                var image = new Image { Stretch = Stretch.Uniform };
                // White until drawn, as paper: a page's own background is white, in either appearance.
                var frame = new Border { Child = image, Background = new SolidColorBrush(Microsoft.UI.Colors.White), CornerRadius = new CornerRadius(3) };
                pages.Add(new Page(source, image, frame, size.Width > 0 ? size.Height / size.Width : 1.414));
                column.Children.Add(frame);
            }
            Fit();
            Draw();
            // The keys and Ctrl and the wheel zoom only with the keyboard focus inside: it starts here, as a PDF opens.
            scroller.Focus(FocusState.Programmatic);
        };
        scroller.SizeChanged += (_, _) => { Fit(); Draw(); };
        scroller.ViewChanged += (_, e) =>
        {
            percent.Text = $"{Math.Round(scroller.ZoomFactor * 100)}%";
            if (!e.IsIntermediate) Draw();
        };
        Unloaded += (_, _) => Close();
    }

    /// <summary>Every page as wide as the view (unzoomed), each as tall as its own shape.</summary>
    private void Fit()
    {
        var width = Math.Max(120, scroller.ViewportWidth - 2 * Edge);
        foreach (var page in pages)
        {
            page.Frame.Width = width;
            page.Frame.Height = width * page.Aspect;
        }
    }

    private void ZoomBy(int steps)
    {
        var now = scroller.ZoomFactor;
        var next = steps > 0 ? Steps.FirstOrDefault(z => z > now + 0.01f, Steps[^1]) : Steps.LastOrDefault(z => z < now - 0.01f, Steps[0]);
        ZoomTo(next);
    }

    /// <summary>Zoomed about the middle of what's in view, so the page being read stays put.</summary>
    private void ZoomTo(float zoom)
    {
        var now = scroller.ZoomFactor;
        var middleX = (scroller.HorizontalOffset + scroller.ViewportWidth / 2) / now;
        var middleY = (scroller.VerticalOffset + scroller.ViewportHeight / 2) / now;
        scroller.ChangeView(Math.Max(0, middleX * zoom - scroller.ViewportWidth / 2), Math.Max(0, middleY * zoom - scroller.ViewportHeight / 2), zoom);
    }

    private static Button ZoomButton(string glyph, string name, Action act)
    {
        var button = new Button
        {
            Content = new FontIcon { Glyph = glyph, FontSize = 13 },
            Padding = new Thickness(8, 6, 8, 6),
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
        };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, name);
        ToolTipService.SetToolTip(button, name);
        button.Click += (_, _) => act();
        return button;
    }

    private void Key(Windows.System.VirtualKey key, Action act)
    {
        var accelerator = new Microsoft.UI.Xaml.Input.KeyboardAccelerator { Key = key, Modifiers = Windows.System.VirtualKeyModifiers.Control };
        accelerator.Invoked += (_, e) => { act(); e.Handled = true; };
        KeyboardAccelerators.Add(accelerator);
    }

    /// <summary>Draws the pages near the view at its zoom, one at a time, and lets go of those far from it.</summary>
    private async void Draw()
    {
        if (drawing) { again = true; return; }
        drawing = true;
        try
        {
            do
            {
                again = false;
                if (closed || pages.Count == 0 || XamlRoot is null) return;
                var zoom = scroller.ZoomFactor;
                var top = scroller.VerticalOffset / zoom;
                var tall = scroller.ViewportHeight / zoom;
                var wanted = (uint)Math.Min(Widest, pages[0].Frame.Width * zoom * XamlRoot.RasterizationScale);
                var y = Edge;
                foreach (var page in pages)
                {
                    var bottom = y + page.Frame.Height;
                    var near = bottom > top - tall && y < top + 2 * tall;
                    var far = bottom < top - 4 * tall || y > top + 5 * tall;
                    y = bottom + Gap;
                    if (far && page.Drawn > 0)
                    {
                        page.Image.Source = null;
                        page.Drawn = 0;
                    }
                    // Drawn again only when zoomed well past what it was drawn for, or drawn much bigger than needed.
                    if (!near || (page.Drawn >= wanted * 0.8 && page.Drawn <= wanted * 2)) continue;
                    await DrawPage(page, wanted);
                    if (closed || again) break;
                }
            } while (again && !closed);
        }
        finally
        {
            drawing = false;
        }
    }

    private static async Task DrawPage(Page page, uint width)
    {
        try
        {
            using var picture = new InMemoryRandomAccessStream();
            await page.Source.RenderToStreamAsync(picture, new PdfPageRenderOptions { DestinationWidth = width });
            picture.Seek(0);
            var bitmap = new BitmapImage();
            await bitmap.SetSourceAsync(picture);
            page.Image.Source = bitmap;
            page.Drawn = width;
        }
        catch (Exception)
        {
            // A page the renderer can't draw stays blank; the rest still show.
            page.Drawn = width;
        }
    }

    /// <summary>The pages and the PDF's bytes let go of as the card closes.</summary>
    private void Close()
    {
        if (closed) return;
        closed = true;
        foreach (var page in pages)
        {
            page.Image.Source = null;
            page.Source.Dispose();
        }
        pages.Clear();
        document = null;
        stream?.Dispose();
        stream = null;
    }
}
