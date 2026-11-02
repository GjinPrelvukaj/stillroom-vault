# Nothing Stillroom shows reaches the network: the Mac's MailLockdownTests, end to end on Windows, for the email viewer
# and the fallback preview. A server on this PC counts connections; a hostile email aimed at it (at 127.0.0.1 and at
# localhost, which may be ::1) is shown in the app's real viewer, alone in a window, and so are a font in Stillroom's
# font card and a bitmap font through Windows' previewer; nothing may connect. A connection away from this PC made meanwhile by the app or a previewer's host
# (prevhost, dllhost, or an Office app serving as one) fails it too. A Word document whose picture, field and template are on the server must not be previewed at all: Word's
# previewer fetched its linked picture when it was tried (29 October 2026), so the fallback preview leaves Office out.
#
# Needs a development build (`dotnet build Stillroom` in windows/app) and no Stillroom already running. From windows/app:
#
#     powershell -ExecutionPolicy Bypass -File tests\lockdown.ps1
#
# The app itself never listens or connects: the server is this script's, and the app is only told which file to show
# (STILLROOM_SHOW_FILE, read by development builds only). A window opens for each file for a few seconds.

$ErrorActionPreference = 'Stop'
$exe = Get-ChildItem (Join-Path $PSScriptRoot '..\Stillroom\bin\Debug') -Recurse -Filter Stillroom.exe | Select-Object -First 1
if (-not $exe) { throw 'Build the app first: dotnet build Stillroom' }
if (Get-Process Stillroom -ErrorAction SilentlyContinue) { throw 'Quit Stillroom first: a second copy would hand over to it.' }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

# Both loopbacks on one port, so "localhost" is caught whichever it resolves to.
$v4 = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$v4.Start()
$port = $v4.LocalEndpoint.Port
$v6 = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::IPv6Loopback, $port)
$v6.Start()
$script:asked = [System.Collections.Generic.List[string]]::new()

# Takes every waiting connection: counts it, keeps its request's first line, answers 404.
function Serve {
    foreach ($listener in $v4, $v6) {
        while ($listener.Pending()) {
            $client = $listener.AcceptTcpClient()
            $stream = $client.GetStream()
            $stream.ReadTimeout = 500
            $line = '?'
            try {
                $buffer = New-Object byte[] 4096
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -gt 0) { $line = ([System.Text.Encoding]::ASCII.GetString($buffer, 0, $read) -split "`r`n")[0] }
            } catch { }
            $script:asked.Add($line)
            $reply = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 404 Not Found`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
            try { $stream.Write($reply, 0, $reply.Length) } catch { }
            $client.Close()
        }
    }
}

function Wait-Serving([double]$seconds, [scriptblock]$until) {
    $end = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $end) {
        Serve
        if ($until -and (& $until)) { return $true }
        Start-Sleep -Milliseconds 50
    }
    return $false
}

$hosts = "http://127.0.0.1:$port", "http://localhost:$port"

# Every way HTML and CSS can load something (the Mac test's list, a table's background and a link).
function Write-Email([string]$path) {
    $loads = foreach ($h in $hosts) {
        @'
<img src="H/img"><img srcset="H/srcset 2x"><picture><source srcset="H/picture"></picture>
<link rel="stylesheet" href="H/css"><link rel="prefetch" href="H/prefetch">
<link rel="preconnect" href="H"><link rel="dns-prefetch" href="H"><link rel="icon" href="H/icon">
<style>@import url(H/import); body { background: url(H/background) }
@font-face { font-family: remote; src: url(H/font) } p { font-family: remote }</style>
<p style="background-image: url(H/inline)">text</p>
<iframe src="H/frame"></iframe><script src="H/script"></script>
<video poster="H/poster" src="H/video" autoplay></video><audio src="H/audio" autoplay></audio>
<object data="H/object"></object><embed src="H/embed">
<form action="H/form"><input type="image" src="H/input"></form>
<svg><image href="H/svg" width="10" height="10"/></svg>
<table background="H/table"><tr><td background="H/cell">cell</td></tr></table>
<a href="H/link">a link</a>
'@.Replace('H', $h)
    }
    $html = "<html><head><title>lockdown</title><meta http-equiv=`"refresh`" content=`"0;url=$($hosts[0])/refresh`">" +
        "<base href=`"$($hosts[0])/base/`"></head><body><img src=`"relative.png`">$($loads -join '')</body></html>"
    $mail = "From: someone@example.com`r`nTo: you@example.com`r`nSubject: Lockdown`r`nContent-Type: text/html; charset=utf-8`r`n`r`n$html"
    [System.IO.File]::WriteAllText($path, $mail)
}

# A Word document whose picture is linked, not inside it, with an INCLUDEPICTURE field and an attached template, all
# on the server: the ways a document is known to call home when opened.
function Write-Word([string]$path) {
    $h = $hosts[0]
    $parts = [ordered]@{
        '[Content_Types].xml' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
        '_rels/.rels' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
        'word/_rels/document.xml.rels' = "<?xml version=`"1.0`" encoding=`"UTF-8`" standalone=`"yes`"?><Relationships xmlns=`"http://schemas.openxmlformats.org/package/2006/relationships`"><Relationship Id=`"rId1`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings`" Target=`"settings.xml`"/><Relationship Id=`"rId2`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image`" Target=`"$h/word-image.png`" TargetMode=`"External`"/><Relationship Id=`"rId3`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink`" Target=`"$h/word-link`" TargetMode=`"External`"/></Relationships>"
        'word/_rels/settings.xml.rels' = "<?xml version=`"1.0`" encoding=`"UTF-8`" standalone=`"yes`"?><Relationships xmlns=`"http://schemas.openxmlformats.org/package/2006/relationships`"><Relationship Id=`"rId1`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/attachedTemplate`" Target=`"$h/word-template.dotx`" TargetMode=`"External`"/></Relationships>"
        'word/settings.xml' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:attachedTemplate r:id="rId1"/></w:settings>'
        'word/document.xml' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>' +
            '<w:p><w:r><w:t>Word lockdown</w:t></w:r></w:p>' +
            '<w:p><w:r><w:drawing><wp:inline><wp:extent cx="952500" cy="952500"/><wp:docPr id="1" name="Picture 1"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="1" name="remote.png"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:link="rId2"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="952500" cy="952500"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>' +
            "<w:p><w:r><w:fldChar w:fldCharType=`"begin`"/></w:r><w:r><w:instrText xml:space=`"preserve`"> INCLUDEPICTURE `"$h/word-field.png`" \d </w:instrText></w:r><w:r><w:fldChar w:fldCharType=`"end`"/></w:r></w:p>" +
            '<w:p><w:hyperlink r:id="rId3"><w:r><w:t>a link</w:t></w:r></w:hyperlink></w:p></w:body></w:document>'
    }
    $zip = [System.IO.Compression.ZipFile]::Open($path, 'Create')
    try {
        foreach ($name in $parts.Keys) {
            $writer = [System.IO.StreamWriter]::new($zip.CreateEntry($name).Open())
            $writer.Write($parts[$name])
            $writer.Close()
        }
    } finally { $zip.Dispose() }
}

# Shows one file in the app, expecting the window to say `expect` ('shown', or 'failed' for a kind that mustn't be
# previewed); gives the requests that reached the server and the far connections made meanwhile.
function Show-File([string]$file, [string]$expect) {
    $started = Get-Date
    $env:STILLROOM_SHOW_FILE = $file
    $app = Start-Process $exe.FullName -PassThru
    $far = @()
    try {
        Wait-Serving 60 { $app.Refresh(); $app.MainWindowTitle -like 'Stillroom look: *' } | Out-Null
        if ($app.MainWindowTitle -notlike "Stillroom look: $expect*") { throw "$(Split-Path $file -Leaf): expected $expect, got '$($app.MainWindowTitle)'." }
        # Then time for anything it pulls in, watching what the processes started since connect to.
        $end = (Get-Date).AddSeconds(5)
        while ((Get-Date) -lt $end) {
            Serve
            $new = Get-Process Stillroom, prevhost, dllhost, WINWORD, EXCEL, POWERPNT, VISIO -ErrorAction SilentlyContinue |
                Where-Object { try { $_.StartTime -ge $started -or $_.Id -eq $app.Id } catch { $false } } | Select-Object -ExpandProperty Id
            $far += Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object {
                $new -contains $_.OwningProcess -and $_.RemoteAddress -notin '0.0.0.0', '::', '127.0.0.1', '::1'
            } | ForEach-Object { "$((Get-Process -Id $_.OwningProcess).ProcessName) -> $($_.RemoteAddress):$($_.RemotePort)" }
            Start-Sleep -Milliseconds 200
        }
    } finally {
        # Closed as a person would, so the viewer lets go of its copy and wipes it.
        if (-not $app.HasExited) { $app.CloseMainWindow() | Out-Null; $app.WaitForExit(10000) | Out-Null }
        if (-not $app.HasExited) { $app.Kill(); $app.WaitForExit(5000) | Out-Null }
        Remove-Item Env:STILLROOM_SHOW_FILE -ErrorAction SilentlyContinue
    }
    return , @($far | Select-Object -Unique)
}

$folder = Join-Path ([System.IO.Path]::GetTempPath()) ("stillroom-lockdown-" + [guid]::NewGuid())
New-Item -ItemType Directory $folder | Out-Null
$failed = $false
try {
    # The server answers, so a count that stays at one below means blocked, not unreachable.
    $control = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $port)
    $hello = [System.Text.Encoding]::ASCII.GetBytes("GET /control HTTP/1.1`r`n`r`n")
    $control.GetStream().Write($hello, 0, $hello.Length)
    Wait-Serving 2 { $script:asked.Count -ge 1 } | Out-Null
    $control.Close()
    if ($script:asked.Count -ne 1) { throw "The control connection didn't arrive ($($script:asked.Count))." }
    $env:STILLROOM_STORE_DIR = Join-Path $folder 'Store'

    $email = Join-Path $folder 'lockdown.eml'
    Write-Email $email
    $word = Join-Path $folder 'lockdown.docx'
    Write-Word $word
    $font = Join-Path $folder 'lockdown.ttf'
    Copy-Item (Join-Path $env:WINDIR 'Fonts/arial.ttf') $font
    # A bitmap font goes to Windows' own previewer (TrueType and OpenType get Stillroom's font card).
    $bitmap = Join-Path $folder 'lockdown.fon'
    Copy-Item (Join-Path $env:WINDIR 'Fonts/vgasys.fon') $bitmap
    foreach ($case in @($email, 'shown'), @($font, 'shown'), @($bitmap, 'shown'), @($word, 'failed')) {
        $file = $case[0]
        $before = $script:asked.Count
        $far = Show-File $file $case[1]
        $reached = $script:asked | Select-Object -Skip $before
        $name = Split-Path $file -Leaf
        if ($reached.Count -gt 0 -or $far.Count -gt 0) {
            $failed = $true
            Write-Host "FAIL: $name reached out:" -ForegroundColor Red
            $reached + $far | ForEach-Object { Write-Host "  $_" }
        } else {
            $how = if ($case[1] -eq 'shown') { 'was shown' } else { "wasn't previewed" }
            Write-Host "PASS: $name $how and nothing connected (port $port, 127.0.0.1 and ::1)." -ForegroundColor Green
        }
    }
} finally {
    Remove-Item Env:STILLROOM_STORE_DIR -ErrorAction SilentlyContinue
    $v4.Stop()
    $v6.Stop()
    Remove-Item -Recurse -Force $folder -ErrorAction SilentlyContinue
}
if ($failed) { exit 1 }
