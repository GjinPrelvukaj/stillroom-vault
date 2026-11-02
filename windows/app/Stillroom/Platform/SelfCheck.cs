using Stillroom.Native;

namespace Stillroom.Platform;

/// <summary>The Mac's `SelfCheck`: whether this copy is still signed by Stillroom's maker. A copy someone changed, a
/// crack among them, has to be signed again by someone else, or not at all, and fails. It protects people who
/// downloaded a doctored Stillroom, not the licence: whoever changes the app can take this out too. The check itself is
/// the engine's (`selfcheck.rs`): Authenticode, offline, against the publisher it pins.</summary>
internal static class SelfCheck
{
    /// <summary>Stillroom's own files: the program, its code, the bindings and the engine. Microsoft's beside them are
    /// Microsoft's to sign.</summary>
    private static IEnumerable<string> OwnFiles =>
    [
        Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "Stillroom.exe"),
        Path.Combine(AppContext.BaseDirectory, "Stillroom.dll"),
        Path.Combine(AppContext.BaseDirectory, "Stillroom.Native.dll"),
        Path.Combine(AppContext.BaseDirectory, "stillroom_core.dll"),
    ];

    /// <summary>False when any of them isn't signed by Stillroom's maker, or was changed since. True while there's
    /// nothing to check against (no certificate yet). Checked once, the first time it's asked.</summary>
    public static bool SignedByUs => signedByUs.Value;

    private static readonly Lazy<bool> signedByUs = new(() =>
    {
        foreach (var file in OwnFiles)
        {
            Engine.Signature found;
            try { found = Engine.CheckSignature(file); }
            catch (StillroomException) { return false; }
            if (found == Engine.Signature.NotSetUp) return true;
            if (found != Engine.Signature.ByUs) return false;
        }
        return true;
    });
}
