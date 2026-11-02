# Signs Stillroom's own files in a built app folder with Authenticode (SHA-256, timestamped), so Windows and the app's
# own tamper check (engine/src/selfcheck.rs) can tell they're unchanged and Stillroom's. Microsoft's files in the
# folder (.NET, the Windows App SDK) are already signed by Microsoft and are left as they are.
#
#   powershell -ExecutionPolicy Bypass -File windows/sign.ps1 -Folder <app folder> -Thumbprint <cert> -TimestampUrl <url>
#   powershell -ExecutionPolicy Bypass -File windows/sign.ps1 -Folder <app folder> -Test
#
# -Thumbprint: Stillroom's code-signing certificate, in the current user's or this PC's certificate store (a certificate
#   on a hardware token shows up there too). Its subject name must be engine/src/selfcheck.rs's PUBLISHER.
# -TimestampUrl: the certificate authority's RFC 3161 timestamp server. Required for a real certificate: a timestamped
#   signature stays good after the certificate expires. (Signing contacts it; the app never does.)
# -Test: a throwaway self-signed certificate named "Stillroom Test Signing", made for this run and taken out of the
#   store again before signing. Windows doesn't trust it; a development build accepts it when STILLROOM_SIGNER_TEST
#   names it.
# -Files: other files to sign instead of the four of Stillroom's own (for tests).
param(
    [string]$Folder,
    [string]$Thumbprint,
    [string]$TimestampUrl,
    [switch]$Test,
    [string[]]$Files
)
$ErrorActionPreference = 'Stop'
$testName = 'Stillroom Test Signing'

if (-not $Files) {
    if (-not $Folder) { throw 'Say which folder: -Folder <built app folder>.' }
    $Files = 'Stillroom.exe', 'Stillroom.dll', 'Stillroom.Native.dll', 'stillroom_core.dll' | ForEach-Object { Join-Path $Folder $_ }
}
foreach ($f in $Files) { if (-not (Test-Path $f)) { throw "$f isn't there." } }

$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
    Sort-Object { [version]$_.Directory.Parent.Name } | Select-Object -Last 1 -ExpandProperty FullName
if (-not $signtool) { throw 'signtool.exe not found: it comes with the Windows SDK.' }

if ($Test) {
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=$testName" -CertStoreLocation Cert:\CurrentUser\My `
        -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 -NotAfter (Get-Date).AddDays(1)
    $pfx = Join-Path ([IO.Path]::GetTempPath()) "stillroom-test-$([guid]::NewGuid().ToString('N')).pfx"
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $secret = [Convert]::ToBase64String($bytes)
    try {
        Export-PfxCertificate -Cert $cert -FilePath $pfx -Password (ConvertTo-SecureString $secret -AsPlainText -Force) | Out-Null
        # Out of the store before anything is signed: nothing of it stays on this PC but the signatures.
        Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -DeleteKey
        & $signtool sign /q /fd SHA256 /f $pfx /p $secret $Files
        if ($LASTEXITCODE -ne 0) { throw 'signtool failed.' }
    } finally {
        Remove-Item $pfx -ErrorAction SilentlyContinue
        Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -DeleteKey -ErrorAction SilentlyContinue
    }
    $Thumbprint = $cert.Thumbprint
} else {
    if (-not $Thumbprint) { throw 'Say which certificate: -Thumbprint, or -Test for a throwaway one.' }
    if (-not $TimestampUrl) { throw 'A real certificate needs -TimestampUrl, or its signatures die when it expires.' }
    & $signtool sign /q /fd SHA256 /sha1 $Thumbprint /tr $TimestampUrl /td SHA256 $Files
    if ($LASTEXITCODE -ne 0) { throw 'signtool failed.' }
}

# Each file read back: signed, by that certificate.
foreach ($f in $Files) {
    $s = Get-AuthenticodeSignature $f
    if (-not $s.SignerCertificate -or $s.SignerCertificate.Thumbprint -ne $Thumbprint) { throw "$f didn't come out signed by $Thumbprint." }
    Write-Host "Signed $(Split-Path $f -Leaf) ($($s.SignerCertificate.GetNameInfo('SimpleName', $false)))"
}
if ($Test) { Write-Host "Test signature: Windows doesn't trust it. A development build checks it with STILLROOM_SIGNER_TEST=$testName." }
