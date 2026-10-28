using Microsoft.Win32;
using Windows.Graphics.Imaging;
using Windows.Media.Capture;
using Windows.Media.MediaProperties;
using Windows.Storage.Streams;

namespace Stillroom.Platform;

/// <summary>A photo of whoever is at the PC, for the intruder log (the Mac's `IntruderCamera`). Windows lights the
/// camera's light and shows its camera-in-use mark for the second or so this takes; nothing can hide them, by design.
///
/// A desktop app gets no camera question of its own on Windows: Settings › Privacy &amp; security › Camera, "Let desktop
/// apps access your camera", decides for all of them. So nothing is ever asked at the lock screen either. The photo is
/// held in memory only, and goes straight into the intruder log, sealed.</summary>
internal static class IntruderCamera
{
    public enum Access { Allowed, Denied, NoCamera }

    private const string ConsentStore = @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam";

    /// <summary>Whether Windows lets desktop apps use the camera: the device-wide switch, this account's, and the one
    /// for desktop apps must all allow it. (Whether a camera is plugged in shows when it's tried.)</summary>
    public static Access WindowsAllows()
    {
        static bool Denied(RegistryKey root, string path) => (root.OpenSubKey(path)?.GetValue("Value") as string) == "Deny";
        return Denied(Registry.LocalMachine, ConsentStore) || Denied(Registry.CurrentUser, ConsentStore) || Denied(Registry.CurrentUser, ConsentStore + @"\NonPackaged")
            ? Access.Denied
            : Access.Allowed;
    }

    /// <summary>One JPEG, at most 1280 px on the long side, or null if there's no camera, Windows doesn't allow it, or it
    /// takes more than about 3 seconds. Never throws.</summary>
    public static async Task<byte[]?> SnapAsync()
    {
        if (WindowsAllows() != Access.Allowed) return null;
        var shot = Take();
        // Whichever comes first: a camera that hangs mustn't hold up the lock screen's log.
        return await Task.WhenAny(shot, Task.Delay(TimeSpan.FromSeconds(3))) == shot ? await shot : null;
    }

    private static async Task<byte[]?> Take()
    {
        MediaCapture? capture = null;
        try
        {
            capture = new MediaCapture();
            await capture.InitializeAsync(new MediaCaptureInitializationSettings
            {
                StreamingCaptureMode = StreamingCaptureMode.Video,
                MemoryPreference = MediaCaptureMemoryPreference.Cpu,
            });
            var photos = await capture.PrepareLowLagPhotoCaptureAsync(ImageEncodingProperties.CreateJpeg());
            // A cold camera's first frames are dark or badly exposed: give it a moment to settle.
            await Task.Delay(800);
            var photo = await photos.CaptureAsync();
            await photos.FinishAsync();
            return await SmallJpeg(photo.Frame);
        }
        catch (Exception)
        {
            // No camera, or Windows refused it: the wrong try is logged without a photo.
            return null;
        }
        finally
        {
            capture?.Dispose();
        }
    }

    /// <summary>At most 1280 px on the long side, JPEG at 0.7: a face is clear, the log stays small.</summary>
    private static async Task<byte[]> SmallJpeg(IRandomAccessStream taken)
    {
        var decoder = await BitmapDecoder.CreateAsync(taken);
        using var picture = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore);
        using var output = new InMemoryRandomAccessStream();
        // A JPEG's quality is set as its encoder is made.
        var quality = new BitmapPropertySet { { "ImageQuality", new BitmapTypedValue(0.7f, Windows.Foundation.PropertyType.Single) } };
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, output, quality);
        encoder.SetSoftwareBitmap(picture);
        var scale = Math.Min(1.0, 1280.0 / Math.Max(decoder.PixelWidth, decoder.PixelHeight));
        encoder.BitmapTransform.ScaledWidth = (uint)Math.Round(decoder.PixelWidth * scale);
        encoder.BitmapTransform.ScaledHeight = (uint)Math.Round(decoder.PixelHeight * scale);
        encoder.BitmapTransform.InterpolationMode = BitmapInterpolationMode.Fant;
        await encoder.FlushAsync();
        var bytes = new byte[output.Size];
        using var reader = new DataReader(output.GetInputStreamAt(0));
        await reader.LoadAsync((uint)output.Size);
        reader.ReadBytes(bytes);
        return bytes;
    }
}
