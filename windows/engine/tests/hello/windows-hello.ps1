# Windows Hello for real, against the engine's DLL: the test tests/hello.rs can't be, as it needs a person.
#
# Needs Windows Hello set up (Settings > Accounts > Sign-in options > PIN), and the DLL built (`cargo build` in
# windows/engine). Run it in Windows PowerShell 5.1, which can call Windows Hello directly:
#
#     powershell -ExecutionPolicy Bypass -File tests\hello\windows-hello.ps1
#
# Windows asks for your PIN, face or finger three times: to make a test credential, to turn Hello on in a test vault,
# and to open that vault with Hello. Everything it makes (the credential, the vault, a temp folder) is deleted at the
# end, whatever happens.

$ErrorActionPreference = 'Stop'
$dll = (Resolve-Path (Join-Path $PSScriptRoot '..\..\target\debug\stillroom_core.dll')).Path

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Engine {
    const string D = @"$dll";
    [StructLayout(LayoutKind.Sequential)] public struct Bytes { public IntPtr Data; public UIntPtr Length; }
    [DllImport(D)] public static extern IntPtr stillroom_last_error();
    [DllImport(D)] public static extern int stillroom_store_open(byte[] root, [MarshalAs(UnmanagedType.U1)] bool readOnly, out IntPtr store);
    [DllImport(D)] public static extern int stillroom_store_lower_cost_for_tests(IntPtr store);
    [DllImport(D)] public static extern void stillroom_store_free(IntPtr store);
    [DllImport(D)] public static extern int stillroom_store_create(IntPtr store, byte[] password, UIntPtr length, out IntPtr vault, out IntPtr recovery);
    [DllImport(D)] public static extern void stillroom_vault_lock(IntPtr vault);
    [DllImport(D)] public static extern int stillroom_vault_wipe(IntPtr vault);
    [DllImport(D)] public static extern int stillroom_hello_new_challenge(out Bytes challenge);
    [DllImport(D)] public static extern int stillroom_vault_turn_on_hello(IntPtr vault, byte[] c, UIntPtr cl, byte[] s, UIntPtr sl, byte[] k, UIntPtr kl);
    [DllImport(D)] public static extern int stillroom_store_hello_challenge(IntPtr store, out Bytes challenge);
    [DllImport(D)] public static extern int stillroom_store_unlock_with_hello(IntPtr store, byte[] s, UIntPtr sl, out IntPtr vault);
    [DllImport(D)] public static extern int stillroom_vault_new_entry(IntPtr vault, int kind, byte[] name, byte[] content, UIntPtr length, byte[] folder, out IntPtr id);
    [DllImport(D)] public static extern int stillroom_vault_state(IntPtr vault, out IntPtr json);
    [DllImport(D)] public static extern void stillroom_string_free(IntPtr value);
    [DllImport(D)] public static extern void stillroom_bytes_free(Bytes value);

    public static byte[] Z(string s) { return System.Text.Encoding.UTF8.GetBytes(s + "\0"); }
    public static void Check(int status) {
        if (status != 0) throw new Exception("engine said " + status + ": " + Marshal.PtrToStringAnsi(stillroom_last_error()));
    }
    public static byte[] Take(Bytes b) {
        var copy = new byte[(int)b.Length.ToUInt64()];
        Marshal.Copy(b.Data, copy, 0, copy.Length);
        stillroom_bytes_free(b);
        return copy;
    }
    public static string TakeString(IntPtr s) {
        if (s == IntPtr.Zero) return null;
        int n = 0; while (Marshal.ReadByte(s, n) != 0) n++;
        var bytes = new byte[n]; Marshal.Copy(s, bytes, 0, n);
        stillroom_string_free(s);
        return System.Text.Encoding.UTF8.GetString(bytes);
    }
}
"@

# Windows Hello through WinRT, which Windows PowerShell 5.1 projects itself.
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Security.Credentials.KeyCredentialManager, Windows.Security.Credentials, ContentType = WindowsRuntime]
$null = [Windows.Security.Cryptography.CryptographicBuffer, Windows.Security.Cryptography, ContentType = WindowsRuntime]
$asTaskOf = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' } | Select-Object -First 1
function Wait-For($operation, [Type] $type) {
    $task = $asTaskOf.MakeGenericMethod($type).Invoke($null, @($operation))
    $task.Wait() | Out-Null
    $task.Result
}
# Windows' own buffer helpers, called through reflection: PowerShell's binder won't take the IBuffer it was given.
$copyToBytes = [Windows.Security.Cryptography.CryptographicBuffer].GetMethod('CopyToByteArray')
function To-Bytes($buffer) {
    $arguments = @($buffer, $null)
    $null = $copyToBytes.Invoke($null, $arguments)
    , [byte[]] $arguments[1]
}
function To-Buffer([byte[]] $bytes) { [Windows.Security.Cryptography.CryptographicBuffer]::CreateFromByteArray($bytes) }
$requestSign = [Windows.Security.Credentials.KeyCredential].GetMethod('RequestSignAsync')
function Sign($credential, [byte[]] $challenge) {
    $operation = $requestSign.Invoke($credential, @(, (To-Buffer $challenge)))
    Wait-For $operation ([Windows.Security.Credentials.KeyCredentialOperationResult])
}
function Len([byte[]] $b) { [UIntPtr]::new([uint64]$b.Length) }

$name = 'Stillroom Windows Hello test'
$work = Join-Path ([IO.Path]::GetTempPath()) ("stillroom-hello-" + [Guid]::NewGuid().ToString('N'))
$store = [IntPtr]::Zero
$failed = $false
function Step($what) { Write-Host "- $what" }
function Expect($condition, $what) { if (-not $condition) { throw "expected: $what" } ; Write-Host "  ok: $what" }

try {
    Step 'Windows Hello is set up'
    $supported = Wait-For ([Windows.Security.Credentials.KeyCredentialManager]::IsSupportedAsync()) ([bool])
    Expect $supported 'apps can use Windows Hello (set up a PIN in Settings > Accounts > Sign-in options)'

    Step 'Windows Hello makes a test credential (Windows asks you now)'
    $made = Wait-For ([Windows.Security.Credentials.KeyCredentialManager]::RequestCreateAsync($name, [Windows.Security.Credentials.KeyCredentialCreationOption]::ReplaceExisting)) ([Windows.Security.Credentials.KeyCredentialRetrievalResult])
    Expect ($made.Status -eq 'Success') "credential made (status: $($made.Status))"
    $publicKey = To-Bytes $made.Credential.RetrievePublicKey()
    Expect ($publicKey.Length -gt 0) "public key ($($publicKey.Length) bytes)"

    Step 'A test vault, and Hello turned on in it (Windows asks you again)'
    [Engine]::Check([Engine]::stillroom_store_open([Engine]::Z((Join-Path $work 'Store')), $false, [ref] $store))
    [Engine]::Check([Engine]::stillroom_store_lower_cost_for_tests($store))
    $password = [Text.Encoding]::UTF8.GetBytes('a test password for hello')
    $vault = [IntPtr]::Zero; $recovery = [IntPtr]::Zero
    [Engine]::Check([Engine]::stillroom_store_create($store, $password, (Len $password), [ref] $vault, [ref] $recovery))
    $null = [Engine]::TakeString($recovery)
    $id = [IntPtr]::Zero; $text = [Text.Encoding]::UTF8.GetBytes('opened by windows hello')
    [Engine]::Check([Engine]::stillroom_vault_new_entry($vault, 0, [Engine]::Z('Hello note'), $text, (Len $text), $null, [ref] $id))
    $null = [Engine]::TakeString($id)
    $bytes = New-Object Engine+Bytes
    [Engine]::Check([Engine]::stillroom_hello_new_challenge([ref] $bytes))
    $challenge = [Engine]::Take($bytes)
    $signed = Sign $made.Credential $challenge
    Expect ($signed.Status -eq 'Success') "challenge signed (status: $($signed.Status))"
    $signature = To-Bytes $signed.Result
    [Engine]::Check([Engine]::stillroom_vault_turn_on_hello($vault, $challenge, (Len $challenge), $signature, (Len $signature), $publicKey, (Len $publicKey)))
    $json = [IntPtr]::Zero
    [Engine]::Check([Engine]::stillroom_vault_state($vault, [ref] $json))
    Expect (([Engine]::TakeString($json) | ConvertFrom-Json).helloIsMine) 'Hello is on for this vault'
    [Engine]::stillroom_vault_lock($vault); $vault = [IntPtr]::Zero

    Step 'The vault opened with Windows Hello (Windows asks you a third time)'
    [Engine]::Check([Engine]::stillroom_store_hello_challenge($store, [ref] $bytes))
    $asked = [Engine]::Take($bytes)
    Expect ([Convert]::ToBase64String($asked) -eq [Convert]::ToBase64String($challenge)) 'the vault asks for the same challenge'
    $opened = Wait-For ([Windows.Security.Credentials.KeyCredentialManager]::OpenAsync($name)) ([Windows.Security.Credentials.KeyCredentialRetrievalResult])
    $again = Sign $opened.Credential $asked
    Expect ($again.Status -eq 'Success') "signed again (status: $($again.Status))"
    $secondSignature = To-Bytes $again.Result
    Expect ([Convert]::ToBase64String($secondSignature) -eq [Convert]::ToBase64String($signature)) 'Windows Hello gives the same signature every time (the design depends on it)'
    [Engine]::Check([Engine]::stillroom_store_unlock_with_hello($store, $secondSignature, (Len $secondSignature), [ref] $vault))
    [Engine]::Check([Engine]::stillroom_vault_state($vault, [ref] $json))
    $state = [Engine]::TakeString($json) | ConvertFrom-Json
    Expect ($state.files[0].name -eq 'Hello note') 'the vault opened by Windows Hello holds its note'
    [Engine]::stillroom_vault_lock($vault); $vault = [IntPtr]::Zero

    Step 'A signature from anything else opens nothing'
    $other = [Text.Encoding]::UTF8.GetBytes('not windows hello')
    $status = [Engine]::stillroom_store_unlock_with_hello($store, $other, (Len $other), [ref] $vault)
    Expect ($status -eq 6) 'refused as "Windows Hello changed"'

    Write-Host ''
    Write-Host 'Windows Hello works with the engine.'
}
catch {
    $failed = $true
    Write-Host ''
    Write-Host "FAILED: $($_.Exception.Message)"
}
finally {
    if ($store -ne [IntPtr]::Zero) { [Engine]::stillroom_store_free($store) }
    try { $asTask.Invoke($null, @([Windows.Security.Credentials.KeyCredentialManager]::DeleteAsync($name))).Wait() | Out-Null } catch { }
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    Write-Host 'Cleaned up: the test credential, the test vault and its folder.'
}
if ($failed) { exit 1 }
