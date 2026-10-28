#!/bin/bash
# SPDX-License-Identifier: MIT (see tools/LICENSE.md)
# Proves tools/stillroom-open.py opens what the app writes: the app's tests make a real vault (folders, a streamed 9 MB
# file, a note, a secret, a recovery key, an emergency kit and a decoy holding a note), then the tool takes it out with the password, the
# recovery key and two kit pieces, and every file must come out byte for byte, with its date.
#   PYTHON=/path/to/python-with-cryptography-and-argon2 tools/test-stillroom-open.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHON="${PYTHON:-python3}"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
STILLROOM_FIXTURE_DIR="$DIR" swift test --package-path macos --filter writesFormatFixture >/dev/null
"$PYTHON" -I - "$DIR" tools/stillroom-open.py <<'PY'
import builtins, filecmp, getpass, io, json, os, runpy, sys
from contextlib import redirect_stdout

work, tool = sys.argv[1], os.path.abspath(sys.argv[2])
answers = json.load(open(os.path.join(work, "answers.json")))
source = os.path.join(work, "source")

def run(mode, secret, typed=()):
    out = os.path.join(work, "out-" + mode)
    typed = iter(typed)
    getpass.getpass = lambda prompt="": secret
    builtins.input = lambda prompt="": next(typed)
    sys.argv = [tool, os.path.join(work, "vault"), out] + ([f"--{mode}"] if mode != "password" else [])
    with redirect_stdout(io.StringIO()):
        runpy.run_path(tool, run_name="__main__")
    return out

def check(out):
    assert filecmp.cmp(os.path.join(source, "Taxes/2025/w2.txt"), os.path.join(out, "Taxes/2025/w2.txt"), shallow=False)
    for name in ("photo.bin", "big.bin"):
        assert filecmp.cmp(os.path.join(source, name), os.path.join(out, name), shallow=False), name
    assert abs(os.path.getmtime(os.path.join(out, "photo.bin")) - 1_560_000_000) < 1, "photo.bin lost its date"
    assert open(os.path.join(out, "Shopping.md")).read() == "milk\neggs\n"
    assert open(os.path.join(out, "Bank.txt")).read().splitlines() == answers["secretLines"]

check(run("password", answers["password"]))
check(run("recovery", answers["recovery"].lower()))
check(run("kit", None, [answers["pieces"][2], answers["pieces"][0]]))
getpass.getpass = lambda prompt="": answers["decoy"]
out = os.path.join(work, "out-decoy")
sys.argv = [tool, os.path.join(work, "vault"), out]
with redirect_stdout(io.StringIO()):
    runpy.run_path(tool, run_name="__main__")
assert sorted(os.listdir(out)) == ["Groceries.md"], os.listdir(out)
assert open(os.path.join(out, "Groceries.md")).read() == "bread\n"
try:
    run("password", "not the password")
    raise AssertionError("a wrong password opened it")
except SystemExit as e:
    assert "doesn't open" in str(e)
print("stillroom-open: password, recovery key and kit pieces open the app's vault, and the decoy password its decoy;"
      " every byte and date matches.")
PY
