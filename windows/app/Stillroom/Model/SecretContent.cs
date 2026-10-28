using System.Security.Cryptography;
using System.Text.Json.Serialization;

namespace Stillroom.Model;

/// <summary>A secret's contents, as the Mac's `Secret` writes them: a template and labelled fields, some concealed.
/// The JSON is the format's, so a secret made here opens on the Mac and back.</summary>
internal sealed class SecretContent
{
    [JsonPropertyName("template")] public string Template { get; set; } = "other";
    [JsonPropertyName("fields")] public List<SecretField> Fields { get; set; } = [];

    public static SecretContent Starting(SecretTemplate template) => new()
    {
        Template = template.Name,
        Fields = template.Starting.Select(f => new SecretField { Label = f.Label, Concealed = f.Concealed }).ToList(),
    };

    public SecretTemplate Kind => SecretTemplates.All.FirstOrDefault(t => t.Name == Template) ?? SecretTemplates.All[^1];
}

internal sealed class SecretField
{
    /// <summary>A UUID, upper case as Swift writes them.</summary>
    [JsonPropertyName("id")] public string Id { get; set; } = Guid.NewGuid().ToString().ToUpperInvariant();
    [JsonPropertyName("label")] public string Label { get; set; } = "";
    [JsonPropertyName("value")] public string Value { get; set; } = "";
    [JsonPropertyName("concealed")] public bool Concealed { get; set; }
}

internal sealed record SecretTemplate(string Name, string Title, string Glyph, (string Label, bool Concealed)[] Starting);

/// <summary>The kinds of secret and the fields each starts with (the Mac's `Secret.Template`); more can be added.</summary>
internal static class SecretTemplates
{
    public static readonly SecretTemplate[] All =
    [
        new("login", "Login", "", [("Website", false), ("Username", false), ("Password", true)]),
        new("card", "Card", "", [("Name on card", false), ("Number", true), ("Expires", false), ("Security code", true), ("PIN", true)]),
        new("wifi", "Wi-Fi", "", [("Network", false), ("Password", true)]),
        new("identity", "ID", "", [("Full name", false), ("Document", false), ("Number", true), ("Expires", false)]),
        new("other", "Other", Glyphs.Secret, [("Secret", true)]),
    ];

    /// <summary>A random password: 20 characters from letters, digits and a few symbols that survive any website's
    /// rules, without look-alikes. About 115 random bits, as the Mac's `generatedPassword`.</summary>
    public static string GeneratePassword(int length = 20)
    {
        const string alphabet = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789-_.!@#%";
        return string.Create(length, 0, (chars, _) =>
        {
            for (var i = 0; i < chars.Length; i++) chars[i] = alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)];
        });
    }
}
