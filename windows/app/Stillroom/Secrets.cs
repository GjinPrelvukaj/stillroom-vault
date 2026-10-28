using System.Security.Cryptography;
using System.Text;
using Stillroom.Native;

namespace Stillroom;

/// <summary>Secrets typed on the secure desktop (the engine's prompt, on a desktop of its own where other programs'
/// keyboard hooks can't see), never in the window. What's typed comes back as bytes the caller wipes, never as a
/// .NET string. Each of these blocks while the prompt is up: call them off the UI thread.</summary>
internal static class Secrets
{
    public const string PromptTitle = "Stillroom";

    /// <summary>The shortest password a vault takes: stretching slows each guess, length makes there be too many.</summary>
    public const int Shortest = 12;

    public const string WeakAdvice = "Too easy to guess. Skip common words, years and runs like 1234; a few random words work well.";

    /// <summary>What was typed, in a pinned array (so the GC never copies it) to wipe with CryptographicOperations.
    /// ZeroMemory; null when cancelled or left empty.</summary>
    public static byte[]? Ask(string message, bool multiline = false) =>
        Engine.SecurePrompt(PromptTitle, message, multiline, typed =>
        {
            if (typed.IsEmpty) return null;
            var copy = GC.AllocateUninitializedArray<byte>(typed.Length, pinned: true);
            typed.CopyTo(copy);
            return copy;
        });

    /// <summary>A new password, asked twice and checked: long and strong enough, and the same both times. Null with
    /// `problem` set when it isn't, null with no problem when cancelled.</summary>
    public static byte[]? AskNewPassword(string message, out string? problem)
    {
        problem = null;
        var first = Ask(message);
        if (first is null) return null;
        problem = Problem(first);
        if (problem is not null)
        {
            CryptographicOperations.ZeroMemory(first);
            return null;
        }
        var again = Ask("Type the same password again.");
        if (again is null)
        {
            CryptographicOperations.ZeroMemory(first);
            return null;
        }
        var same = CryptographicOperations.FixedTimeEquals(first, again);
        CryptographicOperations.ZeroMemory(again);
        if (same) return first;
        CryptographicOperations.ZeroMemory(first);
        problem = "The two didn't match. Try again.";
        return null;
    }

    /// <summary>What's wrong with a new password, or null when it will do.</summary>
    public static string? Problem(ReadOnlySpan<byte> password)
    {
        if (Encoding.UTF8.GetCharCount(password) < Shortest) return $"At least {Shortest} characters. Longer is stronger.";
        return Engine.PasswordStrength(password).Enough ? null : WeakAdvice;
    }
}
