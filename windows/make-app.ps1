# Builds windows/build/Stillroom: the app as it ships (release, self-contained), checked for networking code and,
# given a certificate, signed. The Windows counterpart of macos/Scripts/make-app.sh.
#
#   powershell -ExecutionPolicy Bypass -File windows/make-app.ps1                                   # unsigned
#   powershell -ExecutionPolicy Bypass -File windows/make-app.ps1 -Thumbprint <cert> -TimestampUrl <url>
#   powershell -ExecutionPolicy Bypass -File windows/make-app.ps1 -TestSign                         # a throwaway test signature
param(
    [string]$Thumbprint,
    [string]$TimestampUrl,
    [switch]$TestSign
)
$ErrorActionPreference = 'Stop'
$windows = $PSScriptRoot
$out = Join-Path $windows 'build\Stillroom'

Push-Location (Join-Path $windows 'engine')
try { cargo build --release; if ($LASTEXITCODE -ne 0) { throw 'The engine didn''t build.' } } finally { Pop-Location }

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
dotnet publish (Join-Path $windows 'app\Stillroom') -c Release -o $out --nologo
if ($LASTEXITCODE -ne 0) { throw 'The app didn''t build.' }

# Every build is checked for networking code; one that has any isn't kept.
dotnet run --project (Join-Path $windows 'tools\CheckOffline') -c Release -- $out
if ($LASTEXITCODE -ne 0) {
    Remove-Item $out -Recurse -Force
    throw 'The build reaches for the network, so it was deleted (see above).'
}

$sign = Join-Path $windows 'sign.ps1'
if ($TestSign) { & $sign -Folder $out -Test }
elseif ($Thumbprint) { & $sign -Folder $out -Thumbprint $Thumbprint -TimestampUrl $TimestampUrl }
else { Write-Host 'Not signed: no certificate given (-Thumbprint, or -TestSign).' }

Write-Host "Built $out"
