using Stillroom.Native;
using Windows.Data.Pdf;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;
using Windows.UI;

namespace Stillroom.Platform;

/// <summary>The words in pictures and PDFs, for search (the Mac's `SearchIndex.recognized` and PDFKit's text): Windows'
/// own text recognition, which works on this PC alone from the languages installed, never online. Windows has no way to
/// take a PDF's text out, so each page is drawn in memory (`Windows.Data.Pdf`, as the viewer draws it) and read the
/// same way: that finds the words in scanned PDFs too, but is slow, so only the first `MostPages` are read. Everything
/// stays in memory. Called off the UI thread, with the vault free (`Vault.SearchWanting`).</summary>
internal static class Recognition
{
    /// <summary>The most pages of a PDF read.</summary>
    public const int MostPages = 50;

    /// <summary>How wide a PDF page is drawn to be read: small print stays legible.</summary>
    private const uint PageWidth = 1800;

    private static readonly Lazy<OcrEngine?> ocr = new(OcrEngine.TryCreateFromUserProfileLanguages);

    /// <summary>Whether Windows can read text at all here: it needs a language with text recognition installed.
    /// Without one nothing is read, and nothing recorded, so it's read once one is.</summary>
    public static bool Available => ocr.Value is not null;

    /// <summary>The words in a picture or PDF, or "" when there are none or it can't be read (damaged, locked with a
    /// password, a kind Windows can't draw); null for any other kind.</summary>
    public static string? Read(string uti, byte[] data)
    {
        if (ocr.Value is not { } engine) return null;
        var look = Engine.LookOf(uti);
        try
        {
            if (look == Look.Pdf) return Pdf(data, engine).GetAwaiter().GetResult();
            if (look == Look.Picture && uti != "public.svg-image") return Picture(data, engine).GetAwaiter().GetResult();
            return null;
        }
        catch (Exception)
        {
            return "";
        }
    }

    private static async Task<string> Picture(byte[] data, OcrEngine engine)
    {
        using var stream = await Memory(data);
        return await Recognize(await BitmapDecoder.CreateAsync(stream), engine);
    }

    private static async Task<string> Pdf(byte[] data, OcrEngine engine)
    {
        using var stream = await Memory(data);
        var document = await PdfDocument.LoadFromStreamAsync(stream);
        var pages = new List<string>();
        for (uint i = 0; i < Math.Min(document.PageCount, (uint)MostPages); i++)
        {
            using var page = document.GetPage(i);
            using var drawn = new InMemoryRandomAccessStream();
            var width = (uint)Math.Min(PageWidth, Math.Max(1, page.Size.Width * 3));
            await page.RenderToStreamAsync(drawn, new PdfPageRenderOptions { DestinationWidth = width, BackgroundColor = Color.FromArgb(255, 255, 255, 255) });
            pages.Add(await Recognize(await BitmapDecoder.CreateAsync(drawn), engine));
        }
        return string.Join("\n", pages.Where(p => p.Length > 0));
    }

    /// <summary>A picture's lines of text, read at no more than the size Windows' recognition takes.</summary>
    private static async Task<string> Recognize(BitmapDecoder decoder, OcrEngine engine)
    {
        double longest = Math.Max(decoder.OrientedPixelWidth, decoder.OrientedPixelHeight);
        var scale = Math.Min(1, OcrEngine.MaxImageDimension / Math.Max(1, longest));
        var transform = new BitmapTransform
        {
            ScaledWidth = (uint)Math.Max(1, decoder.PixelWidth * scale),
            ScaledHeight = (uint)Math.Max(1, decoder.PixelHeight * scale),
            InterpolationMode = BitmapInterpolationMode.Fant,
        };
        using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, transform,
            ExifOrientationMode.RespectExifOrientation, ColorManagementMode.DoNotColorManage);
        var result = await engine.RecognizeAsync(bitmap);
        return string.Join("\n", result.Lines.Select(l => l.Text));
    }

    private static async Task<InMemoryRandomAccessStream> Memory(byte[] data)
    {
        var stream = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(stream))
        {
            writer.WriteBytes(data);
            await writer.StoreAsync();
            writer.DetachStream();
        }
        stream.Seek(0);
        return stream;
    }
}
