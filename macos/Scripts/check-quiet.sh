#!/bin/bash
# The runtime half of "never goes online". check-offline.sh proves the app links no networking code; this runs it and
# watches. A debug copy (its demo hooks open each screen without typing) opens a vault of every kind of file it shows,
# including an email, a web page, an SVG, an RTF and a link file that all point at real addresses. Meanwhile two
# watchers run:
#  - macOS's own log of every name lookup (mDNSResponder, with the asking pid) and every connection made through
#    Apple's network code (com.apple.network, CFNetwork). These are events, not samples: however short a connection
#    is, it leaves lines. Any line from a watched process that isn't on the short list of start-up chatter below fails.
#  - nettop's flows, for a socket opened straight at an IP address, which skips both. It samples once a second, so
#    it only vouches for connections that stay open about that long.
# Watched processes are Stillroom and every helper macOS ran for it (WebKit, Quick Look, the system tools Room check
# reads), found by responsible process every 20 ms for as long as Stillroom runs.
#
# First it proves each part works: a short curl has to show up in the log and be judged a failure, and a connection
# held open for three seconds has to show up in nettop.
# Usage: Scripts/check-quiet.sh   (about a minute; a Stillroom window opens and closes a few times)
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$PWD/build/quiet"            # one fixed folder, so the tamper seal keeps one keychain entry for it
HOME_="$WORK/home"
APP="$WORK/StillroomQuiet.app"
FLOWS="$WORK/flows.csv"
mkdir -p "$WORK"

# Which processes a given one is responsible for: itself, and the helpers launchd started on its behalf. Looks every
# 20 ms until that process ends, printing each new one once, so a helper that comes and goes quickly is still caught.
cat > "$WORK/responsible.c" <<'C'
#include <libproc.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
pid_t responsibility_get_pid_responsible_for_pid(pid_t);
int main(int argc, char **argv) {
    pid_t target = atoi(argv[1]), pids[8192];
    static char seen[1 << 22];
    while (kill(target, 0) == 0) {
        int n = proc_listallpids(pids, sizeof pids);
        for (int i = 0; i < n; i++)
            if (pids[i] > 0 && pids[i] < (1 << 22) && !seen[pids[i]] && responsibility_get_pid_responsible_for_pid(pids[i]) == target) {
                seen[pids[i]] = 1;
                printf("%d\n", pids[i]);
                fflush(stdout);
            }
        usleep(20000);
    }
}
C
cc -O -o "$WORK/responsible" "$WORK/responsible.c"

# Every network log line from the given pids (or asked for by them) that isn't start-up chatter, and any sign the log
# lost lines. Unknown lines fail: a new macOS saying something new is looked at, not let through.
LOG="$WORK/network.ndjson"
CHATTER='"eventMessage":"(networkd_settings_read_from_file_locked initialized networkd settings by reading plist directly|Initializing (CF|NS)HTTPCookieStorage singleton|Creating default cookie storage with process\\\/bundle identifier|No state found for <private>|Created default configuration [0-9,]+ <private>|Apple bundle using default state|OOM symptoms: checking process [0-9]+)"'
caught() {
    local pids
    pids=$(sort -u "$@" | paste -sd'|' -)
    [ -n "$pids" ] || return 0
    grep -E "\"processID\":($pids)[,}]|client pid: ($pids) \(|PID\[($pids)\]" "$LOG" | grep -vE "$CHATTER" || true
    grep -vE '^(\{|Filtering the log data)' "$LOG" || true
}

/usr/bin/log stream --level debug --style ndjson \
    --predicate 'subsystem BEGINSWITH "com.apple.network" OR subsystem == "com.apple.CFNetwork" OR process == "mDNSResponder"' > "$LOG" 2>&1 &
LOGGER=$!
nettop -P -L 0 -s 1 -x -J bytes_in,bytes_out > "$FLOWS" 2>/dev/null &
WATCH=$!
trap 'kill $WATCH $LOGGER 2>/dev/null || true' EXIT
sleep 3

# Each watcher must see its test connection, and the judge must call it a failure, or a quiet result means nothing.
curl -s -m 5 -o /dev/null http://example.com/ & CURL=$!
wait $CURL || true
(sleep 3 | nc -w 4 example.com 80 >/dev/null 2>&1) & HELD=$!
wait $HELD || true
sleep 3
NC=$(grep -oE '^nc\.[0-9]+,' "$FLOWS" | tail -1 | tr -dc 0-9)
echo "$CURL" > "$WORK/proof"
[ -n "$(caught "$WORK/proof")" ] || { echo "check-quiet: the network log missed a test connection (offline?), so it can't vouch for anything." >&2; exit 1; }
[ -n "$NC" ] || { echo "check-quiet: nettop missed a test connection held open for 3 s, so it can't vouch for anything." >&2; exit 1; }

# A debug build under its own name and preferences, and the vault it opens.
Scripts/make-app.sh debug >/dev/null
rm -rf "$APP" && cp -R build/Stillroom.app "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.gjin.stillroom.quiet" -c "Delete :NSServices" "$APP/Contents/Info.plist" 2>/dev/null || true
IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
codesign --force --deep --options runtime --entitlements build/Stillroom.entitlements --sign "${IDENTITY:--}" "$APP" 2>/dev/null
mkdir -p "$HOME_/Library/Application Support/Stillroom"
STILLROOM_QUIET_DIR="$HOME_/Library/Application Support/Stillroom" swift test --filter writesQuietCheckVault >/dev/null

PIDS="$WORK/pids"
: > "$PIDS"
# The lock screen first (Room check runs), then each screen, a few seconds apiece.
for SCREEN in lock vault "preview:Hostile email.eml" "preview:Web page.html" "preview:Picture.svg" "preview:Letter.rtf" \
              "preview:Link.webloc" "preview:Shortcut.url" "preview:Sound.wav" "preview:Report.pdf" "preview:Photo.jpg" "preview:Table.csv" \
              "note:Note" "secret:Login" "settings:security"; do
    # Through Launch Services, as a Finder launch would be, so Stillroom is responsible for itself and its helpers
    # (started from a shell, the shell would be).
    ENV=(--env CFFIXED_USER_HOME="$HOME_")
    [ "$SCREEN" = lock ] || ENV+=(--env STILLROOM_DEMO_PASSWORD=quiet-check-only --env STILLROOM_DEMO_SCREEN="$SCREEN")
    open -n -g "${ENV[@]}" "$APP"
    PID=""
    for _ in $(seq 1 20); do PID=$(pgrep -nf "$APP/Contents/MacOS/Stillroom" || true); [ -n "$PID" ] && break; sleep 0.25; done
    [ -n "$PID" ] || { echo "check-quiet: Stillroom didn't start for $SCREEN." >&2; exit 1; }
    "$WORK/responsible" "$PID" >> "$PIDS" & FINDER=$!
    sleep 8
    kill "$PID" 2>/dev/null || true
    while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
    wait $FINDER || true
    echo "  opened $SCREEN"
done
sleep 2   # one more sample, for anything that closed at the end

# Any lookup or connection in the log, and any flow at all in nettop, from Stillroom or a helper it was responsible for.
CAUGHT=$(caught "$PIDS")
if [ -n "$CAUGHT" ]; then
    echo "check-quiet: Stillroom or a helper of its touched the network (log lines, full copy in $LOG):" >&2
    # Each line as "process: message" (every log line has exactly one of each).
    paste -d' ' <(echo "$CAUGHT" | grep -oE '"processImagePath":"[^"]*"' | sed -E 's/.*\\\/([^"]*)"$/\1:/') \
                <(echo "$CAUGHT" | grep -oE '"eventMessage":"[^"]*' | cut -c17-) | sort | uniq -c | sort -rn | head -20 | cut -c1-300 >&2
    exit 1
fi
CAUGHT=$(sort -u "$PIDS" | while read -r P; do grep -E "^[^,]+\.$P," "$FLOWS" | tail -1 || true; done)
if [ -n "$CAUGHT" ]; then
    echo "check-quiet: Stillroom made network flows (process,bytes in,bytes out):" >&2
    echo "$CAUGHT" >&2
    exit 1
fi
echo "check-quiet: $(sort -u "$PIDS" | wc -l | tr -d ' ') processes watched across 15 screens, no network connections"
