# Stillroom's file format

Everything Stillroom keeps is in one folder. On a Mac that's `~/Library/Application Support/Stillroom/Store`. This page describes every file in it, exactly enough to read a vault without the app. `tools/stillroom-open.py` does that in about 300 lines of Python, and `tools/test-stillroom-open.sh` checks it against a vault the app writes.

This is **format 4**, the format of Stillroom 1.0; nothing older is read.

Nothing here is secret. A vault opens with its password, its recovery key, or enough pieces of its emergency kit, and with nothing else. Publishing the format gives no one a way in.

## The pieces

All sealing is **AES-256-GCM** in Apple CryptoKit's combined form:

```
nonce (12 bytes) | ciphertext | tag (16 bytes)
```

Changing any byte makes it fail to open. Big-endian is used for every number.

Most seals also carry *authenticated data*: a few bytes naming what was sealed, which aren't stored but must be given
again to open it. A sealed file copied into another's place then fails to open. Each is listed where it's used below.

### Two slots

The folder holds two **slots**, `a/` and `b/`, built exactly alike. When a vault is made, yours goes in one of them at
random, and nothing records which. The other is a real slot sealed with a random password, recovery key and kit secret
nobody knows. Setting a decoy password replaces it with a new, empty slot whose password you chose. Every way in is
tried on both slots.

```
Store/
  a/  b/          password.key, recovery.key, kit.key, cover.key, list, search
  intruder.pub    both slots' intruder public keys
  intruder/       the intruder log
  touchid.key     when Touch ID is on (it opens one slot)
  mac.key         when Lock to this Mac is on
  Files/          both slots' items
```

### The slot key

Each slot's **slot key** is 32 random bytes made with the slot. It's never written down unsealed. Each way in is the
slot key, sealed by a key made from something you know:

| File in `a/` or `b/` | Sealed with |
|---|---|
| `password.key` | the slot's password |
| `recovery.key` | its recovery key, in capitals with dashes and spaces taken out |
| `kit.key` | its emergency kit's 16-byte secret, written as 32 lowercase hex characters (a slot with no kit: a random secret) |

`touchid.key`, at the top, seals one slot's key with a key in this Mac's Secure Enclave, released by your fingerprint.
It isn't readable off this Mac. Try the key it gives on both slots' `cover.key`.

A key file is laid out like this:

```
"VA2" 0x01 | memory KiB (u32) | passes (u32) | lanes (u32) | salt (16) | sealed slot key
```

The sealing key is **Argon2id** (version 0x13, RFC 9106). It's made from the UTF-8 password with that salt, memory, passes and lanes, and is 32 bytes long. New vaults use 524288 KiB (512 MB), 3 passes and 4 lanes. Readers refuse costs outside 1–16 lanes, 1–10 passes and 8 × lanes KiB to 2 GiB, as a damaged or doctored file. A key file without the `VA2` mark is damaged.

### The cover key

The **cover key** is 32 random bytes, made once with the vault and the same in both slots. Each slot's `cover.key` is
the cover key sealed with that slot's key, authenticated data `Vault cover key 4` followed by the slot's letter (`a` or
`b`).

Each slot's `list` and `search` sit inside a **cover**, sealed with the cover key:

```
sealed with the cover key, authenticated data "Vault cover 4" | "list" or "search" | letter:
    length of what's inside (u64) | the slot's sealed list or index | zero bytes
```

Stillroom writes both slots' covers of a kind together, the same size and with the same date, so a copy of the folder
can't tell which slot changed. To read a slot: open `cover.key` with the slot key, the cover with the cover key, and
the list inside with the slot key.

### Lock to this Mac

With **Lock to this Mac** on, `mac.key` holds a Secure Enclave P-256 key. Both slots' `password.key` are then sealed a second time, outside the layout above, with an AES key derived from it by ECDH and HKDF-SHA256. That outer seal only opens on this Mac. `recovery.key` and `kit.key` are never locked this way, so they open their slot anywhere.

### The list of files

Inside each slot's `list` cover: UTF-8 JSON sealed with the slot key, with authenticated data `Vault list 3` (UTF-8),
padded at the end with spaces. A list holding any files is wrapped as `{"format": 4, "vault": { … }}`. A list with no
files is written bare, as below, so every empty list is the same size. Readers should refuse a `format` they don't
know.

```json
{ "files": [ { "id": "UUID", "name": "w2.pdf", "uti": "com.adobe.pdf", "size": 52011,
               "addedAt": 783000000.0, "folder": "Taxes/2025", "modifiedAt": null,
               "created": 561000000.0, "contentModified": 561000000.0,
               "tags": ["tax"], "entry": null, "chunked": null, "sealedAs": "UUID", "key": "base64 (32 bytes)",
               "versions": [ { "id": "UUID", "date": 782000000.0, "size": 50002, "chunked": null,
                               "sealedAs": "UUID", "key": "base64 (32 bytes)" } ] } ],
  "folders": ["Taxes", "Taxes/2025"],
  "showInCapture": false, "intruder": "base64 (32 bytes)", "touchID": "base64 (64 bytes, zeros when none)",
  "kitMade": "000000000000", "kitReminded": "000000000000" }
```

- **Dates** are seconds since 1 January 2001, UTC (Apple's reference date).
- **`size`** is the real size in bytes.
- **`entry`** is `"note"` for a note (Markdown text) or `"secret"` for a secret (JSON: `{"template": …, "fields": [{"id", "label", "value", "concealed"}]}`). It's null for a file.
- **`key`** is this sealing's own **item key**, 32 random bytes made fresh every time the item (or that version) is
  sealed. Every item and version has one; a list naming one without is damaged.
- **`sealedAs`** is a fresh 16-byte id made with each sealing: 8 random bytes, then the first 8 bytes of
  HMAC-SHA256 over them, keyed with HKDF-SHA256 of the cover key (no salt, info `Vault names 4` and the slot's
  letter, 32 bytes). It's always set, and it names the blob. The tag lets a slot tell its own files from the
  other's in the shared `Files/`.
- **`intruder`** is the slot's intruder private key (see below). **`touchID`** is the public key in the
  `touchid.key` this slot made. **`kitMade`** and **`kitReminded`** are whole seconds since 2001, 12 digits, zeros
  for none. All are always written, at fixed lengths.

### Each file's contents

Each sealing (an item's current contents, or one earlier version), of either slot, is a file of its own in `Files/`:

`Files/<sealedAs>.stillroom`, sealed with the item key. The name never changes: making a version current only changes
the list.

Every item is padded to its **Padmé** length before sealing, so sealed sizes give away at most about 12%:

```
padded(n) = n                                  if n <= 1
            e = floor(log2 n); s = floor(log2 e) + 1
            mask = 2^(e - s) - 1; (n + mask) & ~mask   otherwise
```

A file is in one of two forms:

- **One piece**: the padded bytes, sealed once with the item key and authenticated data
  `Vault item 3 (UTF-8) | sealedAs (16 raw UUID bytes)`. Keep the first `size` bytes.
- **Chunks**, when `chunked` is true (big files, all audio and video). The blob starts with `"VLT2"`:

  ```
  "VLT2" | chunk size (u32, 1 MiB) | chunk 0 | chunk 1 | … | last chunk
  ```

  - There are `max(1, ceil(padded(size) / chunk size))` chunks. Each holds a full chunk of plaintext except the last, which holds the rest of the padded length.
  - Each chunk is sealed with the item key and authenticated data `sealedAs (16 raw UUID bytes) | chunk index (u64) | 1 if last else 0`.
  - Keep the first `size` bytes across the chunks.

### The emergency kit

The kit's secret is 16 random bytes, split by **Shamir's secret sharing** over GF(256). It's the AES field, reduced by x⁸ + x⁴ + x³ + x + 1, with one random polynomial per byte and the secret as its constant term. Any `threshold` pieces rebuild it by Lagrange interpolation at x = 0.

A piece is 21 bytes:

```
version (1) | threshold | index (1-255) | share (16) | first 2 bytes of SHA-256 over the 19 bytes before
```

It's written in Crockford base32 (`0-9 A-Z` without `I L O U`) as `VK-` followed by groups of four. Readers should accept any case, spaces or dashes anywhere, O for 0, and I or L for 1.

### Other files

| File | What it holds |
|---|---|
| `a/search`, `b/search` | each slot's words, for searching inside files, in a cover like the list's: JSON sealed with the slot key, authenticated data `Vault search 3`. The JSON is a flat array, not an object, alternating item id and entry: `["UUID", {"changed": seconds since 2001-01-01, "size": bytes, "text": "…"}, …]` (how Swift encodes `[UUID: Entry]`) |
| `intruder.pub`, `intruder/` | the intruder log. `intruder.pub` is both slots' X25519 public keys, `a`'s then `b`'s (32 bytes each); each slot's private key is in its list. Each entry is sealed with HPKE (X25519, HKDF-SHA256, ChaCha20-Poly1305, info `Vault intruder log`) to both: for `a` then `b`, `length (u32) \| encapsulated key (32) \| sealed JSON` |

Stillroom doesn't need either to read files.
