#!/usr/bin/env python3
# SPDX-License-Identifier: MIT (see tools/LICENSE.md)
"""stillroom-open: take everything out of a Stillroom vault, without the Stillroom app.

For the day Stillroom can't run (a dead Mac, an app that no longer opens, another computer).
It needs exactly what Stillroom needs: the vault folder, and the password, the recovery key,
or enough pieces of the emergency kit. It has no way in without one of those.

    pip install cryptography argon2-cffi
    python3 stillroom-open.py STORE_FOLDER OUT_FOLDER              # asks for the password
    python3 stillroom-open.py STORE_FOLDER OUT_FOLDER --recovery   # asks for the recovery key
    python3 stillroom-open.py STORE_FOLDER OUT_FOLDER --kit        # asks for kit pieces

On a Mac the vault folder is ~/Library/Application Support/Stillroom/Store.
Everything comes out unencrypted into OUT_FOLDER. The format is described in docs/FORMAT.md.
"""

import base64
import getpass
import hashlib
import json
import os
import stat
import sys
import tempfile
import uuid
from datetime import datetime, timedelta, timezone

try:
    from argon2.low_level import Type, hash_secret_raw
    from cryptography.exceptions import InvalidTag
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:
    sys.exit("Needs two libraries first:  pip install cryptography argon2-cffi")

ARGON_MARK = b"VA2\x01"
CHUNK_MAGIC = b"VLT2"
CHUNK_OVERHEAD = 28  # 12-byte nonce + 16-byte tag
# Format 4: what each seal is bound to (authenticated data, not stored).
LIST_AAD = b"Vault list 3"
ITEM_AAD = b"Vault item 3"
COVER_AAD = b"Vault cover 4"        # + "list" or "search" + slot letter
COVER_KEY_AAD = b"Vault cover key 4"  # + slot letter
SLOTS = ("a", "b")
# The most any small file is read into memory as: a key file is under 100 bytes, a list or index far under 1 GiB.
KEY_FILE_MAX = 4 << 10
COVERED_MAX = 1 << 30
APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)  # Swift's JSON dates count seconds from here


class WrongKey(Exception):
    pass


# ---- Reading what's on disk ------------------------------------------------------------------

def read_small(path, limit):
    """A whole file, only when it's a plain file (not a device, pipe or folder) of at most `limit` bytes."""
    with open(path, "rb") as f:
        info = os.fstat(f.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise WrongKey("damaged: not a file of the size it should be")
        data = f.read(limit + 1)
    if len(data) > limit:
        raise WrongKey("damaged: not a file of the size it should be")
    return data


# ---- Opening the vault key -------------------------------------------------------------------

def gcm_open(key, sealed, aad=None):
    """AES-256-GCM, Apple CryptoKit's combined form: nonce (12) | ciphertext | tag (16)."""
    return AESGCM(key).decrypt(sealed[:12], sealed[12:], aad)


def open_with_password(sealed, password):
    """A key file: "VA2"+1, Argon2id memory KiB / passes / lanes (big-endian u32 each), salt (16), sealed vault key."""
    if sealed[:4] != ARGON_MARK or len(sealed) <= 32:
        raise WrongKey("damaged key file")
    memory, passes, lanes = (int.from_bytes(sealed[i:i + 4], "big") for i in (4, 8, 12))
    if not (1 <= lanes <= 16 and 1 <= passes <= 10 and 8 * lanes <= memory <= 2 * 1024 * 1024):
        raise WrongKey("damaged key file")
    key = hash_secret_raw(password.encode(), sealed[16:32], time_cost=passes, memory_cost=memory,
                          parallelism=lanes, hash_len=32, type=Type.ID, version=19)
    body = sealed[32:]
    try:
        return gcm_open(key, body)
    except Exception:
        raise WrongKey("that doesn't open this vault")


def recovery_password(typed):
    """Recovery keys are stretched as typed but in capitals, without dashes or spaces."""
    return "".join(c for c in typed.upper() if c.isalnum())


# ---- Emergency kit pieces (Shamir's secret sharing over GF(256)) -----------------------------

CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


def read_piece(typed):
    """VK-xxxx-...: version 1, threshold, index, 16-byte share, 2 check bytes (start of SHA-256), in Crockford base32."""
    text = "".join(c for c in typed.upper() if not c.isspace() and c != "-")
    if text.startswith("VK"):
        text = text[2:]
    value = bits = 0
    out = bytearray()
    for c in text:
        c = {"O": "0", "I": "1", "L": "1"}.get(c, c)
        if c not in CROCKFORD:
            raise WrongKey("a piece has a character that can't be in one: check it against the paper")
        value = (value << 5) | CROCKFORD.index(c)
        bits += 5
        if bits >= 8:
            out.append((value >> (bits - 8)) & 0xFF)
            bits -= 8
        value &= (1 << bits) - 1
    # As Stillroom's own reader: a kit needs 2 to 10 pieces, and pieces are numbered from 1.
    if (len(out) != 21 or out[0] != 1 or hashlib.sha256(out[:19]).digest()[:2] != out[19:]
            or not 2 <= out[1] <= 10 or out[2] < 1):
        raise WrongKey("a piece doesn't read right: check it letter by letter against the paper")
    return out[1], out[2], bytes(out[3:19])  # threshold, index, share


def gf_mul(a, b):
    p = 0
    while b:
        if b & 1:
            p ^= a
        a = ((a << 1) ^ (0x1B if a & 0x80 else 0)) & 0xFF
        b >>= 1
    return p


def gf_div(a, b):
    inverse = 1
    for _ in range(254):
        inverse = gf_mul(inverse, b)
    return gf_mul(a, inverse)


def join_pieces(pieces):
    threshold = pieces[0][0]
    if any(p[0] != threshold for p in pieces):
        raise WrongKey("those pieces come from different kits")
    used = list({p[1]: p for p in pieces}.values())[:threshold]
    if len(used) < threshold:
        raise WrongKey(f"this kit needs {threshold} different pieces")
    secret = bytearray()
    for b in range(16):
        total = 0
        for _, xi, share in used:
            weight = 1
            for _, xj, _ in used:
                if xj != xi:
                    weight = gf_mul(weight, gf_div(xj, xj ^ xi))
            total ^= gf_mul(share[b], weight)
        secret.append(total)
    return bytes(secret)


# ---- Reading files ---------------------------------------------------------------------------

def padded_length(n):
    """Padmé: how long a file was padded to before sealing."""
    if n <= 1:
        return n
    e = n.bit_length() - 1
    s = e.bit_length()
    mask = (1 << (e - s)) - 1
    return (n + mask) & ~mask


def read_blob(blob, key, file_id, size, chunked, out, one_aad):
    """One piece (nonce|ciphertext|tag of the padded bytes), or "VLT2" chunks bound to the file, place and end.
    Which it is comes from the list's `chunked`, never from the blob. Either way the blob must be a plain file exactly
    as long as `size` seals to, checked before anything is read."""
    if type(size) is not int or not 0 <= size <= 1 << 50:
        raise WrongKey("damaged: impossible size in the list")
    info = os.fstat(blob.fileno())
    if not stat.S_ISREG(info.st_mode):
        raise WrongKey("damaged: not a file")
    padded = padded_length(size)
    if not chunked:
        if info.st_size != padded + CHUNK_OVERHEAD:
            raise WrongKey("damaged: wrong length")
        plain = gcm_open(key, blob.read(padded + CHUNK_OVERHEAD), one_aad)
        if len(plain) < size:
            raise WrongKey("damaged: shorter than the list says")
        out.write(plain[:size])
        return
    head = blob.read(8)
    if head[:4] != CHUNK_MAGIC:
        raise WrongKey("damaged: not in chunks as the list says")
    chunk_size = int.from_bytes(head[4:8], "big")
    # The same limits as Stillroom's own reader: a chunk of 1 byte to 64 MiB, and exactly as many bytes as the chunks need.
    if not 1 <= chunk_size <= 64 << 20:
        raise WrongKey("damaged: impossible chunk size")
    count = max(1, -(-padded // chunk_size))
    if info.st_size != 8 + padded + count * CHUNK_OVERHEAD:
        raise WrongKey("damaged: wrong length")
    for i in range(count):
        length = min(chunk_size, padded - i * chunk_size) + CHUNK_OVERHEAD
        aad = uuid.UUID(file_id).bytes + i.to_bytes(8, "big") + bytes([1 if i == count - 1 else 0])
        chunk = gcm_open(key, blob.read(length), aad)
        out.write(chunk[:max(0, min(len(chunk), size - i * chunk_size))])


UNSAFE = set('\\<>"|?*')
DEVICES = {"CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"}
DEVICES |= {p + n for p in ("COM", "LPT") for n in "0123456789\u00b9\u00b2\u00b3"}


def safe(name):
    """A name from the list as one file name, on any system: as windows/engine/src/export.rs `safe`. It can't hold a
    path separator, so it can't climb out of the folder it's put in."""
    name = name.replace("\u2215", "/").replace(":", "-")
    # On a Mac ":" is what Finder shows as "/"; elsewhere a slash can't be in a name at all.
    name = name.replace("/", ":" if sys.platform == "darwin" else "-")
    # Nor, on Windows, a backslash, any of < > " | ? * or a control character.
    name = "".join("-" if c in UNSAFE or ord(c) < 0x20 or 0x7F <= ord(c) <= 0x9F else c for c in name)
    name = name.rstrip(". ")
    if not name:
        return "Untitled"
    # A device name, even with an extension ("nul.txt"), is no file on Windows.
    if name.split(".")[0].rstrip().upper() in DEVICES:
        name = "_" + name
    return name


def inside(out, path):
    """Refuses any path that would land outside the out folder (a link planted in it, say)."""
    real_out, real = os.path.realpath(out), os.path.realpath(path)
    if os.path.commonpath([real_out, real]) != real_out:
        raise WrongKey(f"refused: {path} would land outside {out}")
    return path


def place(out, folder):
    path = out
    for part in (folder or "").split("/"):
        if part:
            path = os.path.join(path, safe(part))
    os.makedirs(inside(out, path), exist_ok=True)
    return inside(out, path)


def unused(path):
    base, ext = os.path.splitext(path)
    n = 2
    while os.path.exists(path):
        path = f"{base} {n}{ext}"
        n += 1
    return path


def apple_date(seconds):
    return (APPLE_EPOCH + timedelta(seconds=seconds)).timestamp()


def read_list(root, slot, key):
    """The slot key opens the cover key; the cover key opens the list's cover; the slot key opens the list inside."""
    folder_of = os.path.join(root, slot)
    cover = gcm_open(key, read_small(os.path.join(folder_of, "cover.key"), KEY_FILE_MAX), COVER_KEY_AAD + slot.encode())
    covered = gcm_open(cover, read_small(os.path.join(folder_of, "list"), COVERED_MAX),
                       COVER_AAD + b"list" + slot.encode())
    if len(covered) < 8:
        raise WrongKey("damaged list")
    inner = covered[8:8 + int.from_bytes(covered[:8], "big")]
    return json.loads(gcm_open(key, inner, LIST_AAD).rstrip(b" "))


def take_one(root, item, target):
    """One item into `target`, by way of a temporary file beside it: an item that fails partway leaves nothing behind."""
    if not item.get("key") or not item.get("sealedAs"):
        raise WrongKey("no key of its own in the list")
    # Sealed with its own key, named by and bound to its sealedAs.
    item_key, sealed_as = base64.b64decode(item["key"], validate=True), str(uuid.UUID(item["sealedAs"])).upper()
    blob = os.path.join(root, "Files", sealed_as + ".stillroom")
    one_aad = ITEM_AAD + uuid.UUID(sealed_as).bytes
    folder = os.path.dirname(target)
    handle, partial = tempfile.mkstemp(prefix=".stillroom-", suffix=".partial", dir=folder)
    try:
        with os.fdopen(handle, "wb") as out, open(blob, "rb") as sealed:
            read_blob(sealed, item_key, sealed_as, item["size"], item.get("chunked") is True, out, one_aad)
        if item.get("entry") == "secret":
            with open(partial, "rb") as f:
                secret = json.load(f)
            with open(partial, "w", encoding="utf-8") as f:
                f.write("".join(f"{field['label']}: {field.get('value', '')}\n" for field in secret["fields"]))
        changed = item.get("modifiedAt") or item.get("contentModified") or item.get("addedAt")
        if changed is not None:
            stamp = apple_date(changed)
            os.utime(partial, (stamp, stamp))
        os.replace(partial, inside(folder, target))
    finally:
        if os.path.exists(partial):
            os.remove(partial)


def take_out(root, slot, key, out):
    try:
        listing = read_list(root, slot, key)
        # One holding files is wrapped as {"format": 4, "vault": {...}}; only an empty one is written bare.
        if "format" in listing:
            if listing["format"] != 4:
                sys.exit(f"This vault is in format {listing['format']}, which this tool doesn't read.")
            listing = listing["vault"]
        elif listing.get("files"):
            raise WrongKey("an unwrapped list holding files")
        entries = listing["files"]
        folders = listing["folders"]
        if not isinstance(entries, list) or not isinstance(folders, list):
            raise WrongKey("damaged list")
    except (WrongKey, InvalidTag, ValueError, OSError, KeyError, TypeError, AttributeError):
        sys.exit("The list of files is damaged, or was changed outside Stillroom.")
    for folder in folders:
        try:
            place(out, folder)
        except Exception as e:
            print(f"  folder not made: {folder!r} ({e})")
    damaged = []
    for i, item in enumerate(entries, 1):
        shown = f"item {i}"
        try:
            folder = place(out, item.get("folder"))
            name = safe(item["name"]) + {"note": ".md", "secret": ".txt"}.get(item.get("entry"), "")
            target = inside(out, unused(os.path.join(folder, name)))
            shown = os.path.relpath(target, out)
            take_one(root, item, target)
        except Exception as e:
            # One damaged item doesn't stop the rest coming out.
            damaged.append(shown)
            print(f"  {i}/{len(entries)}  DAMAGED, skipped: {shown} ({type(e).__name__}: {e})")
            continue
        print(f"  {i}/{len(entries)}  {shown}")
    if damaged:
        print(f"{len(damaged)} damaged and not taken out: " + ", ".join(damaged))
    return len(entries) - len(damaged)


# ---- Main ------------------------------------------------------------------------------------

def self_test():
    """python3 stillroom-open.py --self-test: quick checks that need no vault."""
    climbing = safe("..\\..\\x.bat")
    assert "\\" not in climbing and "/" not in climbing and climbing not in (".", ".."), climbing
    assert safe("..") == safe(".") == safe("") == safe(" . ") == "Untitled"
    assert safe("NUL") == "_NUL" and safe("nul.txt") == "_nul.txt" and safe("com\u00b9") == "_com\u00b9"
    assert safe("CONOUT$") == "_CONOUT$" and safe("COM10") == "COM10" and safe("console") == "console"
    assert safe("a/b") in ("a-b", "a:b") and safe("tab\there") == "tab-here" and safe("dots...") == "dots"
    out = tempfile.mkdtemp()
    try:
        assert inside(out, os.path.join(out, "a", "b"))
        try:
            inside(out, os.path.join(out, "..", "x"))
            raise AssertionError("a path outside the out folder was allowed")
        except WrongKey:
            pass
    finally:
        os.rmdir(out)
    assert [padded_length(n) for n in (0, 1, 100)] == [0, 1, 104]
    print("stillroom-open: self-test passed")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    if "--self-test" in flags:
        return self_test()
    if len(args) != 2:
        sys.exit(__doc__)
    root, out = (os.path.expanduser(a) for a in args)
    if not all(os.path.exists(os.path.join(root, slot, "password.key")) for slot in SLOTS):
        sys.exit(f"No vault in {root}: it should hold a/ and b/, each with password.key.")
    os.makedirs(out, exist_ok=True)

    def try_each(name, secret):
        """Like Stillroom, every way in is tried on both slots; whichever it opens is the one taken out."""
        found = None
        for slot in SLOTS:
            # Both slots every time; a missing or doctored file is just "doesn't open", as in Stillroom.
            try:
                opened = open_with_password(read_small(os.path.join(root, slot, name), KEY_FILE_MAX), secret)
            except Exception:
                continue
            found = found or (slot, opened)
        if not found:
            raise WrongKey("that doesn't open this vault")
        return found

    try:
        if "--recovery" in flags:
            found = try_each("recovery.key", recovery_password(getpass.getpass("Recovery key: ")))
        elif "--kit" in flags:
            pieces = [read_piece(input("Piece 1: "))]
            while len(pieces) < pieces[0][0]:
                pieces.append(read_piece(input(f"Piece {len(pieces) + 1}: ")))
            found = try_each("kit.key", join_pieces(pieces).hex())
        else:
            if os.path.exists(os.path.join(root, "mac.key")):
                sys.exit("This vault is locked to the Mac that made it, so its password only works there.\n"
                         "Use --recovery or --kit instead.")
            found = try_each("password.key", getpass.getpass("Password: "))
    except WrongKey as e:
        sys.exit(f"Can't open it: {e}.")

    count = take_out(root, found[0], found[1], out)
    print(f"Done: {count} items, unencrypted, in {out}")


if __name__ == "__main__":
    main()
