using System.Security.Cryptography;
using Stillroom.Native;
using Windows.Security.Credentials;
using Windows.Security.Cryptography;

namespace Stillroom.Platform;

/// <summary>Windows Hello's way in (the Mac's `TouchIDKey`): Hello keeps a key pair in the TPM and signs the vault's
/// challenge after a face, a finger or the Windows Hello PIN; the engine turns the signature into the key that opens
/// the slot. One credential, belonging to whichever vault last turned Hello on, as Touch ID does; its name says
/// nothing about which. Proven against real Hello by windows/engine/tests/hello/windows-hello.ps1.</summary>
internal static class WindowsHello
{
    private const string CredentialName = "Stillroom";

    /// <summary>Whether this PC and account can use Windows Hello (a PIN at least is set up).</summary>
    public static async Task<bool> IsAvailableAsync()
    {
        try { return await KeyCredentialManager.IsSupportedAsync(); }
        catch (Exception) { return false; }
    }

    /// <summary>Hello opens `vault` from now on: a new credential (any older one goes, and with it the way in of
    /// the vault that had it), its signature of a fresh challenge given to the engine. Windows asks for a face, a
    /// finger or the PIN. Throws HelloCancelled when it was cancelled.</summary>
    public static async Task TurnOnAsync(Vault vault)
    {
        var made = await KeyCredentialManager.RequestCreateAsync(CredentialName, KeyCredentialCreationOption.ReplaceExisting);
        Check(made.Status);
        CryptographicBuffer.CopyToByteArray(made.Credential.RetrievePublicKey(), out byte[] publicKey);
        var challenge = Engine.HelloNewChallenge();
        var signature = await SignAsync(made.Credential, challenge);
        try { await Task.Run(() => vault.TurnOnHello(challenge, signature, publicKey)); }
        finally { CryptographicOperations.ZeroMemory(signature); }
    }

    /// <summary>The vault that turned Hello on, opened by Hello's signature of its challenge.</summary>
    public static async Task<Vault> UnlockAsync(Store store, byte[] challenge)
    {
        var opened = await KeyCredentialManager.OpenAsync(CredentialName);
        if (opened.Status == KeyCredentialStatus.NotFound)
            throw new StillroomException(Status.HelloChanged, "Windows Hello was set up again since it was turned on. Use your password, then turn Windows Hello on again.");
        Check(opened.Status);
        var signature = await SignAsync(opened.Credential, challenge);
        try { return await Task.Run(() => store.UnlockWithHello(signature)); }
        finally { CryptographicOperations.ZeroMemory(signature); }
    }

    /// <summary>Removes the credential, when Hello is turned off for the vault that had it.</summary>
    public static async Task ForgetAsync()
    {
        try { await KeyCredentialManager.DeleteAsync(CredentialName); }
        catch (Exception) { /* Already gone. */ }
    }

    // The signature also passes through a WinRT buffer, which .NET can't wipe; the copy here is wiped after use.
    private static async Task<byte[]> SignAsync(KeyCredential credential, byte[] challenge)
    {
        var signed = await credential.RequestSignAsync(CryptographicBuffer.CreateFromByteArray(challenge));
        Check(signed.Status);
        CryptographicBuffer.CopyToByteArray(signed.Result, out byte[] signature);
        return signature;
    }

    private static void Check(KeyCredentialStatus status)
    {
        switch (status)
        {
            case KeyCredentialStatus.Success: return;
            case KeyCredentialStatus.UserCanceled: throw new HelloCancelled();
            case KeyCredentialStatus.NotFound or KeyCredentialStatus.SecurityDeviceLocked:
                throw new StillroomException(Status.HelloUnavailable, "Windows Hello isn't available right now. Use your password.");
            default:
                throw new StillroomException(Status.HelloUnavailable, $"Windows Hello didn't work ({status}). Use your password.");
        }
    }
}

/// <summary>Windows Hello's prompt was cancelled: not a failure, and not a wrong try.</summary>
internal sealed class HelloCancelled : Exception;
