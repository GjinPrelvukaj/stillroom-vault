# Draws Stillroom\Assets\Stillroom.ico (the window, taskbar and tray icon) from the Mac's macos/Resources/AppIcon.png,
# so both apps carry the same picture. Run it in Windows PowerShell 5.1 after the Mac icon changes:
#
#     powershell -ExecutionPolicy Bypass -File make-icon.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$source = [System.Drawing.Image]::FromFile((Resolve-Path (Join-Path $PSScriptRoot '..\..\macos\Resources\AppIcon.png')).Path)
$out = Join-Path $PSScriptRoot 'Stillroom\Assets\Stillroom.ico'
$sizes = 16, 20, 24, 32, 40, 48, 64, 256

# Each size as a PNG, drawn down from the big one in high quality.
$images = foreach ($size in $sizes) {
    $bitmap = New-Object System.Drawing.Bitmap $size, $size
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.InterpolationMode = 'HighQualityBicubic'
    $graphics.PixelOffsetMode = 'HighQuality'
    $graphics.SmoothingMode = 'HighQuality'
    $graphics.DrawImage($source, 0, 0, $size, $size)
    $graphics.Dispose()
    $stream = New-Object System.IO.MemoryStream
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    , $stream.ToArray()
}
$source.Dispose()

# An .ico: a header, a directory entry per image, then the PNGs.
$file = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter $file
$writer.Write([uint16] 0); $writer.Write([uint16] 1); $writer.Write([uint16] $sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $side = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $writer.Write([byte] $side); $writer.Write([byte] $side); $writer.Write([byte] 0); $writer.Write([byte] 0)
    $writer.Write([uint16] 1); $writer.Write([uint16] 32)
    $writer.Write([uint32] $images[$i].Length); $writer.Write([uint32] $offset)
    $offset += $images[$i].Length
}
foreach ($image in $images) { $writer.Write([byte[]] $image) }
$writer.Flush()
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
[IO.File]::WriteAllBytes($out, $file.ToArray())
"Wrote $out ($($file.Length) bytes, $($sizes.Count) sizes)"
