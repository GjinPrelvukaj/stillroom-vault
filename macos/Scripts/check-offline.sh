#!/bin/bash
# Stillroom never goes online: no server, no updates, no tracking. This fails if a build of it links anything that
# could open a connection, so the claim is checked on every app build, not just promised.
# The email viewer's web view is the one exception kept: its own test (MailLockdownTests) proves it loads nothing.
set -euo pipefail
BIN="${1:?usage: check-offline.sh <path to the Stillroom binary>}"

linked=$(otool -L "$BIN" | grep -E "/(Network|CFNetwork)\.framework/" || true)
# Sockets, DNS, URL loading and Network framework calls. URLRequest alone is allowed: the email viewer reads the
# address of a clicked link to cancel it.
imported=$(nm -u "$BIN" | grep -E "^_(socket|connect|getaddrinfo|gethostbyname|sendto|bind|listen)$|NSURLSession|URLSession|NSURLConnection|NSURLDownload|_nw_|NWConnection|NWListener|NWBrowser|CFSocket|CFStreamCreatePairWith|CFHost|NSNetService|SCNetworkReachability" || true)

# Looking code up by name at run time, which the two checks above can't see: dlopen could load CFNetwork, dlsym could
# find socket() in a library that's already loaded, and the Objective-C runtime could find a networking class by name.
# None is allowed, with one exception the app doesn't write itself: the compiler's runtime adds
# __initializeAvailabilityCheck (compiler-rt's os_version_check, behind SwiftUI's OS version checks), which finds
# _availability_version_check with dlsym. dlsym passes only when every reference to it is inside that function.
byname=$(nm -u "$BIN" | grep -E "^_(dlopen|NSClassFromString|NSSelectorFromString|objc_getClass|objc_lookUpClass|objc_getRequiredClass)$" || true)
if nm -u "$BIN" | grep -qx "_dlsym"; then
    # Each instruction naming dlsym's stub, or its address, with the function it sits in.
    code=$(otool -tV "$BIN")
    stub=$(grep -m1 "symbol stub for: _dlsym" <<<"$code" | grep -oE "0x[0-9a-f]+" | head -1 || true)
    callers=$(awk -v stub="${stub:-_dlsym}" '/^[^ \t].*:$/ {fn=$0} index($0, "_dlsym") || index($0, stub) {print fn}' <<<"$code" | sort -u)
    others=$(grep -vx "__initializeAvailabilityCheck:" <<<"$callers" || true)
    if [ -z "$stub" ] || [ -n "$others" ]; then
        byname="$byname${byname:+$'\n'}_dlsym, called from: ${others:-an address the check cannot place}"
    fi
fi

if [ -n "$linked$imported$byname" ]; then
    echo "check-offline: $BIN can reach the network:" >&2
    [ -n "$linked" ] && echo "$linked" >&2
    [ -n "$imported" ] && echo "$imported" >&2
    [ -n "$byname" ] && echo "$byname (looks code up by name at run time)" >&2
    exit 1
fi
echo "check-offline: no networking code in $(basename "$BIN")"
