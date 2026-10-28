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

if [ -n "$linked$imported" ]; then
    echo "check-offline: $BIN can reach the network:" >&2
    [ -n "$linked" ] && echo "$linked" >&2
    [ -n "$imported" ] && echo "$imported" >&2
    exit 1
fi
echo "check-offline: no networking code in $(basename "$BIN")"
