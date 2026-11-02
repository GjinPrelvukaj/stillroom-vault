# Proves the offline check catches what it's for: Stillroom's own files from a build pass, then each planted kind of
# networking fails it. Run from anywhere after `dotnet build` of the app (windows/app/Stillroom); needs the Visual
# Studio C++ tools, as the engine does.
#   powershell -ExecutionPolicy Bypass -File windows/tools/CheckOffline/test.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$app = Get-ChildItem (Join-Path $here '..\..\app\Stillroom\bin\Debug') -Recurse -Filter Stillroom.exe | Select-Object -First 1
if (-not $app) { throw 'Build the app first: dotnet build windows/app/Stillroom' }
$built = $app.DirectoryName
$work = Join-Path ([IO.Path]::GetTempPath()) "stillroom-offline-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failed = 0

dotnet build (Join-Path $here 'CheckOffline.csproj') -c Release -o (Join-Path $work 'check') --nologo -v q | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'The check itself didn''t build.' }
$check = Join-Path $work 'check\CheckOffline.dll'

# A folder holding Stillroom's own files and WinUI's (whose one allowed import is then read too).
function New-AppFolder {
    $dir = Join-Path $work ([guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory $dir | Out-Null
    foreach ($f in 'Stillroom.exe', 'Stillroom.dll', 'Stillroom.Native.dll', 'stillroom_core.dll', 'Microsoft.ui.xaml.dll') {
        Copy-Item (Join-Path $built $f) $dir
    }
    $dir
}

function Expect([string]$what, [string]$dir, [int]$code, [string[]]$says) {
    $out = (cmd /c "dotnet `"$check`" `"$dir`" 2>&1") -join "`n"
    $ok = $LASTEXITCODE -eq $code
    foreach ($s in $says) { if ($out -notlike "*$s*") { $ok = $false } }
    if ($ok) { Write-Host "PASS: $what" }
    else { Write-Host "FAIL: $what (exit $LASTEXITCODE)`n$out"; $script:failed++ }
}

# The C compiler, from the Visual Studio install that builds the engine.
$vcvars = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio", "$env:ProgramFiles\Microsoft Visual Studio" -Recurse -Filter vcvars64.bat -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $vcvars) { throw 'Needs the Visual Studio C++ tools (vcvars64.bat).' }
function Build-Dll([string]$name, [string]$source, [string]$link) {
    $dir = Join-Path $work 'c'
    New-Item -ItemType Directory $dir -Force | Out-Null
    Set-Content (Join-Path $dir "$name.c") $source -Encoding ascii
    cmd /c "`"$vcvars`" >nul 2>&1 && cd /d `"$dir`" && cl /nologo /LD $name.c /link $link >nul"
    if ($LASTEXITCODE -ne 0) { throw "Couldn't build $name.dll" }
    Join-Path $dir "$name.dll"
}

try {
    Expect 'Stillroom''s own files pass' (New-AppFolder) 0 @('no networking in Stillroom')

    $sockets = Build-Dll 'planted' '#include <winsock2.h>
__declspec(dllexport) int planted(void) { return (int)socket(AF_INET, SOCK_STREAM, 0); }' 'ws2_32.lib'
    $dir = New-AppFolder; Copy-Item $sockets $dir
    Expect 'a DLL importing sockets fails' $dir 1 @('planted.dll imports ws2_32.dll')

    $delayed = Build-Dll 'delayed' '#include <windows.h>
#include <winhttp.h>
__declspec(dllexport) void* delayed(void) { return WinHttpOpen(L"x", 0, 0, 0, 0); }' 'winhttp.lib delayimp.lib /DELAYLOAD:winhttp.dll'
    $dir = New-AppFolder; Copy-Item $delayed $dir
    Expect 'a DLL delay-loading WinHTTP fails' $dir 1 @('delayed.dll imports winhttp.dll')

    $dir = New-AppFolder; Copy-Item $sockets (Join-Path $dir 'stillroom_core.dll') -Force
    Expect 'the engine importing sockets fails' $dir 1 @('stillroom_core.dll imports ws2_32.dll')

    $dir = New-AppFolder; Copy-Item $sockets (Join-Path $dir 'WebView2Loader.dll')
    Expect 'a web view''s loader fails' $dir 1 @('WebView2Loader.dll starts a web view')

    # Stillroom's own .NET code: an assembly standing in for Stillroom.Native.dll that uses HttpClient, P/Invokes into
    # WinINet, loads Winsock by name and names a web address.
    $proj = Join-Path $work 'planted-net'
    New-Item -ItemType Directory $proj | Out-Null
    Set-Content (Join-Path $proj 'Planted.csproj') '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework><AssemblyName>Stillroom.Native</AssemblyName></PropertyGroup></Project>'
    Set-Content (Join-Path $proj 'Planted.cs') 'using System.Runtime.InteropServices;
public static class Planted {
    public static object Http() => new System.Net.Http.HttpClient();
    [DllImport("wininet.dll")] public static extern bool InternetGetConnectedState(out int flags, int reserved);
    public static nint Sockets() => NativeLibrary.Load("ws2_32");
    public static string Address() => "https://example.invalid/pixel.png";
}'
    dotnet build $proj -c Release -o (Join-Path $proj 'out') --nologo -v q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The planted assembly didn''t build.' }
    $dir = New-AppFolder; Copy-Item (Join-Path $proj 'out\Stillroom.Native.dll') $dir -Force
    Expect 'networking in Stillroom''s own .NET code fails' $dir 1 @(
        'Stillroom.Native.dll references System.Net.Http',
        'Stillroom.Native.dll uses System.Net.Http.HttpClient',
        'Stillroom.Native.dll calls into wininet.dll (P/Invoke)',
        'Stillroom.Native.dll names a networking DLL in a string: ws2_32',
        'Stillroom.Native.dll names a web address: https://example.invalid/pixel.png')

    $dir = New-AppFolder; Remove-Item (Join-Path $dir 'stillroom_core.dll')
    Expect 'a folder without the engine fails' $dir 1 @('stillroom_core.dll is missing')
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failed) { throw "$failed of the offline check's tests failed." }
Write-Host 'The offline check catches every planted kind of networking.'
