#!/bin/bash
# The runtime half of "never goes online". check-offline.sh proves the app links no networking code; this runs it and
# watches. A debug copy (its demo hooks open each screen without typing) opens a vault of every kind of file it shows,
# including an email, a web page, an SVG, an RTF and a link file that all point at real addresses, and the script
# records every network flow on this Mac meanwhile (nettop). It fails if any came from Stillroom or from a helper
# macOS ran for it (WebKit, Quick Look, the system tools Room check reads), found by their responsible process.
#
# First it proves the watcher works: a curl that lives for a fraction of a second has to show up.
# Usage: Scripts/check-quiet.sh   (about a minute; a Stillroom window opens and closes a few times)
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$PWD/build/quiet"            # one fixed folder, so the tamper seal keeps one keychain entry for it
HOME_="$WORK/home"
APP="$WORK/StillroomQuiet.app"
FLOWS="$WORK/flows.csv"
mkdir -p "$WORK"

# Which processes a given one is responsible for: itself, and the helpers launchd started on its behalf.
cat > "$WORK/responsible.c" <<'C'
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
pid_t responsibility_get_pid_responsible_for_pid(pid_t);
int main(int argc, char **argv) {
    pid_t target = atoi(argv[1]), pids[8192];
    int n = proc_listallpids(pids, sizeof pids) ;
    for (int i = 0; i < n; i++) if (pids[i] && responsibility_get_pid_responsible_for_pid(pids[i]) == target) printf("%d\n", pids[i]);
}
C
cc -O -o "$WORK/responsible" "$WORK/responsible.c"

nettop -P -L 0 -s 1 -x -J bytes_in,bytes_out > "$FLOWS" 2>/dev/null &
WATCH=$!
trap 'kill $WATCH 2>/dev/null || true' EXIT
sleep 2

# The watcher must see a short connection, or a quiet result means nothing.
curl -s -m 5 -o /dev/null http://example.com/ & CURL=$!
wait $CURL || true
sleep 3
grep -q "^curl\.$CURL," "$FLOWS" || { echo "check-quiet: the watcher missed a test connection (offline?), so it can't vouch for anything." >&2; exit 1; }

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
    for _ in $(seq 1 16); do "$WORK/responsible" "$PID" >> "$PIDS"; sleep 0.5; done
    kill "$PID" 2>/dev/null || true
    while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
    echo "  opened $SCREEN"
done
sleep 2   # one more sample, for anything that closed at the end

# Any flow at all, open or closed, sending or not, from Stillroom or a helper it was responsible for.
CAUGHT=$(sort -u "$PIDS" | while read -r P; do grep -E "^[^,]+\.$P," "$FLOWS" | tail -1 || true; done)
if [ -n "$CAUGHT" ]; then
    echo "check-quiet: Stillroom made network flows (process,bytes in,bytes out):" >&2
    echo "$CAUGHT" >&2
    exit 1
fi
echo "check-quiet: $(sort -u "$PIDS" | wc -l | tr -d ' ') processes watched across 15 screens, no network connections"
