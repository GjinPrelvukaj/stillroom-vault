// Stillroom never goes online: no server, no updates, no tracking. This fails if a build of it could open a connection,
// so the claim is checked on every build, not just promised: the Windows counterpart of macos/Scripts/check-offline.sh.
//
//   dotnet run --project windows/tools/CheckOffline -- <app folder> [--list]
//
// It reads every program file in the folder, Microsoft's included, and fails on any of these:
//   1. A native import (direct or delay-loaded) of a networking DLL (`Networking` below), unless `Allowed` names that
//      file and DLL with the reason.
//   2. A file that starts Edge's Chromium (WebView2), which carries its own networking. The build deletes them.
//   3. In Stillroom's own .NET code: a reference to a networking assembly or namespace (.NET's System.Net, WinRT's
//      Windows.Networking and Windows.Web, Cast, push notifications…), a P/Invoke into a networking DLL, a networking
//      DLL's name in a string (for NativeLibrary.Load), or a web address other than the release notes', which open in
//      the browser.
// It catches mistakes; it isn't a proof. Microsoft's own code (.NET, WinUI) holds networking that runs only when asked
// to load a web address, which Stillroom's code never names; code could still build an address at run time, or reach
// the network through COM by a class id. windows/SECURITY.md says what's allowed and why.

using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
using System.Text;
using System.Text.RegularExpressions;

var folder = args.FirstOrDefault(a => !a.StartsWith("--"));
var list = args.Contains("--list");
if (folder is null || !Directory.Exists(folder))
{
    Console.Error.WriteLine("usage: CheckOffline <built or published app folder> [--list]");
    return 2;
}

// DLLs that open connections, resolve names, or read the network's state.
var networking = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
{
    "ws2_32.dll", "wsock32.dll", "mswsock.dll",              // sockets
    "winhttp.dll", "wininet.dll", "webio.dll", "urlmon.dll", // HTTP and URL loading
    "websocket.dll", "httpapi.dll",                          // WebSockets, HTTP server
    "dnsapi.dll", "iphlpapi.dll", "nsi.dll", "winnsi.dll",   // names, addresses, interfaces
    "netapi32.dll", "mpr.dll",                               // shares and network drives
    "rasapi32.dll", "wlanapi.dll", "wcmapi.dll", "fwpuclnt.dll", "ondemandconnroutehelper.dll",
    "icmp.dll", "qmgr.dll", "bitsproxy.dll",                 // ping, background transfers
    "msedgewebview2.exe", "embeddedbrowserwebview.dll", "webview2loader.dll",
};
// API sets that stand for the same DLLs (api-ms-win-…/ext-ms-win-…).
var networkingApiSet = new Regex(@"^(api|ext)-ms-win-.*(winhttp|wininet|winsock|ws2|dnsapi|iphlp|webio|websocket|networking|net-|wlan|rasapi|http)", RegexOptions.IgnoreCase);

// Files that start a web view: Chromium and its networking. Deleted from every build (Stillroom.csproj).
var webView = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
{
    "WebView2Loader.dll", "Microsoft.Web.WebView2.Core.dll", "EmbeddedBrowserWebView.dll", "msedgewebview2.exe",
};

// Microsoft's files that import a networking DLL, each with why it's allowed. Anything new fails until it's looked at.
var allowed = new Dictionary<(string File, string Dll), string>(new PairComparer())
{
    [("Microsoft.ui.xaml.dll", "urlmon.dll")] =
        "WinUI loads a picture or resource given a web address (CreateURLMonikerEx). Stillroom gives it pictures from " +
        "memory only, and its code names no web address (check 3).",
};

// Stillroom's own files: they must all be there, so the check never passes on the wrong folder.
string[] ownNative = ["Stillroom.exe", "stillroom_core.dll"];
string[] ownManaged = ["Stillroom.dll", "Stillroom.Native.dll"];

// What Stillroom's own .NET code may not reference.
string[] networkingAssemblies =
[
    "System.Net", "Microsoft.Web.WebView2", "Microsoft.Security.Authentication.OAuth", "Microsoft.Windows.PushNotifications",
];
string[] networkingNamespaces =
[
    "System.Net",                                   // sockets, HTTP, DNS, mail, WebSockets, QUIC, ping
    "Windows.Networking", "Windows.Web",            // WinRT sockets, HTTP, connectivity, push, background transfers
    "Microsoft.Web.WebView2",
    "Windows.Media.Casting", "Windows.Media.PlayTo", "Windows.Media.DialProtocol", "Windows.Media.Streaming.Adaptive",
    "Windows.System.RemoteSystems", "Windows.Services", "Windows.Security.Authentication.Web",
    "Windows.Devices.WiFi", "Windows.Devices.WiFiDirect",
    "Microsoft.Security.Authentication.OAuth", "Microsoft.Windows.PushNotifications",
];
// Web addresses Stillroom's code may name, and why.
string[] allowedAddresses =
[
    "https://stillroomvault.com/changelog/", // Check for Updates opens it in the browser; Stillroom loads nothing (Updates.cs)
    "http://schemas.microsoft.com/",         // XAML's namespace names, compiled into the app; never loaded
];
var webAddress = new Regex(@"\b(https?|wss?|ftp)://", RegexOptions.IgnoreCase);

var failures = new List<string>();
var notes = new List<string>();
var files = Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories)
    .Where(f => f.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) || f.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
    .OrderBy(f => f, StringComparer.OrdinalIgnoreCase)
    .ToList();

foreach (var own in ownNative.Concat(ownManaged))
    if (!File.Exists(Path.Combine(folder, own))) failures.Add($"{own} is missing: is this Stillroom's app folder?");

int native = 0, managed = 0;
var netAssembliesShipped = new List<string>();
foreach (var path in files)
{
    var name = Path.GetFileName(path);
    var rel = Path.GetRelativePath(folder, path);
    if (webView.Contains(name)) failures.Add($"{rel} starts a web view (Chromium, with its own networking): the build deletes it");

    using var stream = File.OpenRead(path);
    PEReader pe;
    try { pe = new PEReader(stream); _ = pe.PEHeaders; }
    catch (BadImageFormatException) { continue; } // not a program file (a resource-only satellite, say)
    using (pe)
    {
        if (pe.PEHeaders.CorHeader is null || (pe.PEHeaders.CorHeader.Flags & CorFlags.ILOnly) == 0)
        {
            native++;
            foreach (var dll in NativeImports(pe))
            {
                var bad = networking.Contains(dll) || networkingApiSet.IsMatch(dll);
                if (list) Console.WriteLine($"  {rel} -> {dll}{(bad ? "  (networking)" : "")}");
                if (!bad) continue;
                if (allowed.TryGetValue((name, dll), out var why) && !ownNative.Contains(name, StringComparer.OrdinalIgnoreCase))
                    notes.Add($"{rel} imports {dll}, allowed: {why}");
                else
                    failures.Add($"{rel} imports {dll}");
            }
        }
        if (pe.HasMetadata)
        {
            managed++;
            var md = pe.GetMetadataReader();
            if (md.IsAssembly && networkingAssemblies.Any(n => IsIn(md.GetString(md.GetAssemblyDefinition().Name), n)))
                netAssembliesShipped.Add(name);
            if (ownManaged.Contains(name, StringComparer.OrdinalIgnoreCase)) CheckOwnCode(rel, md);
        }
    }
}

// Check 3: Stillroom's own .NET code.
void CheckOwnCode(string rel, MetadataReader md)
{
    foreach (var h in md.AssemblyReferences)
    {
        var n = md.GetString(md.GetAssemblyReference(h).Name);
        if (networkingAssemblies.Any(a => IsIn(n, a))) failures.Add($"{rel} references {n}");
    }
    foreach (var h in md.TypeReferences)
    {
        var t = md.GetTypeReference(h);
        var ns = md.GetString(t.Namespace);
        if (networkingNamespaces.Any(a => IsIn(ns, a))) failures.Add($"{rel} uses {ns}.{md.GetString(t.Name)}");
    }
    for (var i = 1; i <= md.GetTableRowCount(TableIndex.ModuleRef); i++)
    {
        var n = md.GetString(md.GetModuleReference(MetadataTokens.ModuleReferenceHandle(i)).Name);
        if (IsNetworkingDll(n)) failures.Add($"{rel} calls into {n} (P/Invoke)");
    }
    var us = MetadataTokens.UserStringHandle(1);
    while (!us.IsNil)
    {
        var s = md.GetUserString(us);
        if (webAddress.IsMatch(s) && !allowedAddresses.Any(a => s.StartsWith(a, StringComparison.OrdinalIgnoreCase)))
            failures.Add($"{rel} names a web address: {s}");
        foreach (var word in Regex.Split(s, @"[^\w.\-]+"))
            if (word.Length > 0 && IsNetworkingDll(word)) failures.Add($"{rel} names a networking DLL in a string: {s}");
        us = md.GetNextHandle(us);
    }
}

bool IsNetworkingDll(string n)
{
    var dll = n.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) || n.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? n : n + ".dll";
    return networking.Contains(dll) || networkingApiSet.IsMatch(dll);
}

static bool IsIn(string name, string prefix) =>
    name.Equals(prefix, StringComparison.Ordinal) || name.StartsWith(prefix + ".", StringComparison.Ordinal);

// The DLLs a native image imports, directly and delay-loaded, lower case.
static IEnumerable<string> NativeImports(PEReader pe)
{
    var h = pe.PEHeaders;
    var image = pe.GetEntireImage().GetContent().ToArray();
    var result = new List<string>();
    int Offset(int rva)
    {
        foreach (var s in h.SectionHeaders)
        {
            var size = Math.Max(s.VirtualSize, s.SizeOfRawData);
            if (rva >= s.VirtualAddress && rva < s.VirtualAddress + size) return rva - s.VirtualAddress + s.PointerToRawData;
        }
        return -1;
    }
    string? Name(int rva)
    {
        var at = Offset(rva);
        if (at < 0 || at >= image.Length) return null;
        var end = Array.IndexOf(image, (byte)0, at);
        return end < 0 ? null : Encoding.ASCII.GetString(image, at, end - at).ToLowerInvariant();
    }
    int Int(int at) => at + 4 <= image.Length ? BitConverter.ToInt32(image, at) : 0;

    var imports = h.PEHeader!.ImportTableDirectory;
    if (imports.RelativeVirtualAddress != 0)
        for (var at = Offset(imports.RelativeVirtualAddress); at >= 0 && at + 20 <= image.Length; at += 20)
        {
            int nameRva = Int(at + 12), thunk = Int(at + 16);
            if (nameRva == 0 && thunk == 0) break;
            if (Name(nameRva) is { } n) result.Add(n);
        }
    var delayed = h.PEHeader.DelayImportTableDirectory;
    if (delayed.RelativeVirtualAddress != 0)
        for (var at = Offset(delayed.RelativeVirtualAddress); at >= 0 && at + 32 <= image.Length; at += 32)
        {
            int attributes = Int(at), nameRva = Int(at + 4);
            if (nameRva == 0) break;
            // Old-style descriptors hold addresses, not RVAs.
            if ((attributes & 1) == 0) nameRva = (int)((ulong)(uint)nameRva - h.PEHeader.ImageBase);
            if (Name(nameRva) is { } n) result.Add(n);
        }
    return result.Distinct();
}

foreach (var n in notes) Console.WriteLine($"check-offline: {n}");
if (netAssembliesShipped.Count > 0)
    Console.WriteLine($"check-offline: {netAssembliesShipped.Count} networking assemblies of .NET's and the Windows App " +
        "SDK's ship with it, referenced by none of Stillroom's code" +
        (list ? ":\n  " + string.Join("\n  ", netAssembliesShipped) : " (--list names them)"));
if (failures.Count > 0)
{
    Console.Error.WriteLine($"check-offline: {folder} can reach the network:");
    foreach (var f in failures.Distinct()) Console.Error.WriteLine($"  {f}");
    return 1;
}
Console.WriteLine($"check-offline: no networking in Stillroom ({native} native and {managed} .NET files read)");
return 0;

sealed class PairComparer : IEqualityComparer<(string File, string Dll)>
{
    public bool Equals((string File, string Dll) a, (string File, string Dll) b) =>
        string.Equals(a.File, b.File, StringComparison.OrdinalIgnoreCase) && string.Equals(a.Dll, b.Dll, StringComparison.OrdinalIgnoreCase);
    public int GetHashCode((string File, string Dll) p) =>
        HashCode.Combine(p.File.ToLowerInvariant(), p.Dll.ToLowerInvariant());
}
