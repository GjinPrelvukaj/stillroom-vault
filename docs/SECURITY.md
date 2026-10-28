# Security rules

These are the decisions Stillroom's safety rests on, with the reason for each, so a later change doesn't undo one by accident. Most of them came out of review findings. An automatic security review runs on each commit; when it flags something, fix it or explain why it doesn't apply.

## What Stillroom protects against, and what it doesn't

**It protects against:**
- a stolen or borrowed Mac
- a copied vault folder
- anyone taking the app apart: there's no secret in the binary, and the format is public
- tampering: every byte is authenticated, and every sealed item, the list, the search index and their covers are bound to what they are, so none can stand in for another (see Item keys)
- other accounts on the Mac
- screen recording
- keyloggers that use event taps

**It does not protect against:**
- a weak password: the strength check refuses guessable ones
- malware with admin rights while the vault is open
- copies another app keeps after Edit in Place: the warning says so

## Rules

**1. Plaintext never lands on the SSD.**
- Previews and Edit in Place copies go to the RAM disk (`EditDesk`).
- Quick Look copies never fall back to the on-disk overflow folder.
- Only an edit too big for the RAM disk uses `~/Library/Caches/app.gjin.stillroom/DeskOverflow`, which is protected by FileVault and deleted afterwards.
- An open or stage that waited on a mount writes nothing if the vault locked meanwhile (the `clears` counter).

**2. The decoy fools someone at the keyboard or with a copy of the folder, not someone with a password and a copy.**

How it works (format 4, October 2026): the folder holds two slots, `a` and `b`, built exactly alike. When a vault is
made, yours goes in one of them at random, and nothing anywhere records which. The other is a real vault whose
password, recovery key and kit secret are random and thrown away. Setting a decoy password replaces it with a new,
empty vault whose password you choose, made by the same code. So an unset decoy and a set, empty one are the same
thing.

What it does, by who's looking:
- **Someone at the keyboard, given the decoy password:** the decoy looks complete. Settings has the same rows in
  both vaults. It has its own recovery key (shown when it's set), its own emergency kit and the same intruder log.
  The lock screen always offers the recovery key and the kit. Unlock tries every password, recovery key and kit on
  both slots, so the time taken says nothing. A slot whose file is missing or can't be read (still locked to an old
  Mac) costs a stretch anyway.
- **Someone with one copy of the folder, no password:** the letters say nothing, both slots hold the same files, and
  both slots' items share one `Files/` folder under names only a slot can tell apart. Every key file has the same
  dates, so a decoy set a year later leaves nothing newer.
- **Someone with copies taken at different times, no password:** every save rewrites both slots' lists, and every
  index save both indexes, inside covers of one size, with one date. Added items can't be told apart by slot.
- **Someone with the real password and a copy:** an unset decoy and a set, empty one look the same.
- Nothing slot-specific goes in logs or preferences, and per-vault settings live in each slot's sealed list.
- **The licence is no tell** (see The licence below): one file beside the store, in neither slot, read the same
  whichever vault is open. The free tier's limit counts the open vault's own items and stops both at 25 with the same
  words. Adding or removing a licence writes nothing in the vault folder (`theLicenceAndTheLimitAreTheSameInEitherVault`).

What it doesn't do:
- **Someone with one password and a copy of the folder** can see sealed files and a list size their vault doesn't
  account for, and so that the other slot holds something and roughly how much, though not what. Closing this would
  need a fixed-size container filled with noise from the start (a hidden volume). That would reserve disk from day one,
  and even that fails against copies taken at different times.
- **Copies taken at different times show when ways in change.** A new password, recovery key or kit rewrites only
  that slot's file, and setting or removing a decoy rewrites the whole other slot folder. The other slot's files can't
  be resealed without its password. Everyday use (adding, editing, searching) doesn't show.
- **Touch ID opens one vault**, the one where it was last turned on, because a finger can't choose. If you rely on
  the decoy, turn Touch ID on in the decoy or not at all: a forced finger opens the vault it belongs to. In the vault
  that doesn't have it, its row reads off.
- **Setting a decoy from inside the decoy deletes the real vault.** It's the same row in both, and someone in the
  decoy could delete everything from Settings anyway.
- **After moving a Mac-locked vault to a new Mac** with a recovery key, the other vault's password needs its own
  recovery key once.
- **Other apps remember names.** Recent Items or Quick Look's thumbnail cache can keep names from Edit in Place and
  previews, and a name not in the decoy points to another vault. Don't Edit in Place or preview names you'd need to
  deny, or clear Recent Items afterwards. Plaintext copies themselves are on the RAM disk, at random paths. A folder dragged out of the window carries a
  random id, never its name.
- **Forensic tools** see each file's inode change time, which no app can set. The two slots are made in a random
  order, so which one is newer says nothing on its own.
- **The intruder log can't keep what was typed.** Shared by both vaults, it would show the decoy's holder your typos
  of the real password.

Say exactly this, in the app and anywhere it's sold: protection against thieves and abusers, not police.

**3. Nothing that weakens protection goes in preferences.**
- `UserDefaults` can be changed by any program running as the user.
- The "show in screenshots" switch therefore lives in the sealed manifest (`VaultIndex.showInCapture`), is applied after unlock, and the lock screen is always hidden.
- Preferences only hold comfort settings: auto-lock time, appearance, the intruder switches, the activity log switch, "don't ask again".
- The wrong-try counter and the intruder log are deterrents for someone at the keyboard, not protection. The log keeps the date, kind and a photo, never what was typed (rule 2). Argon2id is what slows guessing.

**4. The activity log keeps no secrets.**
- It never records typed characters, nor even that typing happened: in text fields only ⌘ shortcuts are logged.
- It never records file names, sizes, counts, contents, which slot opened, or the text of error messages.
- Keys are logged only while a vault is open.
- Nothing in it may tell a decoy session from a main one:
  - no per-slot work, so password stretching isn't logged
  - main-only pages and settings appear under neutral names
  - decoy code paths are never named, in errors or in stall stacks
  - durations of steps that grow with the vault's contents are logged only when slow, in rough bands; memory is rounded to 100 MB while open
- Even so, stalls and slow steps logged over many days could hint that two different vaults are used. Settings says so: with a decoy you rely on, keep the log off (it's off by default).

**5. The email viewer stays locked down three ways at once.**
- JavaScript off, and links cancelled.
- A Content Security Policy allowing only `data:`.
- A WebKit block list allowing only `data:` and `about:`. An email is never shown without it: WebKit once rejected the rule silently ("disjunctions are not supported") and pages went out with one lock fewer.
- `<link>` tags are disarmed before the page is shown. The page policy doesn't cover preconnect and prefetch links, which open connections on their own.

`MailLockdownTests` loads an email with every kind of remote load (images, srcset, stylesheets, @import, fonts, frames, scripts, media, forms, SVG, base, meta refresh, preconnect, prefetch) pointed at a server on this Mac, and fails on any connection. Without the block list it sees two.

**Stillroom never goes online.** `macos/Scripts/check-offline.sh` runs on every app build and fails it if the binary links the Network or CFNetwork frameworks or imports sockets, DNS or URL-loading calls. The email web view is the one exception, covered by the test above. The check catches mistakes; it isn't a proof: Foundation calls such as `Data(contentsOf:)` given a web address load through frameworks it doesn't see, so never pass one a URL that didn't come from a file.

**6. Edit in Place opens only documents.**
- It's allowed only when both the stored type and the name's extension pass an allowlist: no executables, scripts, installers, disk images or packages.
- No web pages either (HTML, XHTML, XML, SVG, web archives, internet locations): they'd open in a browser that runs their scripts and loads from the network.
- Sketches are excluded.
- Copies are quarantined, and so is every file taken out of the vault (Save a Copy, attachments, Export Everything): extended attributes aren't kept inside, so a downloaded program would otherwise come out unflagged and run without Gatekeeper checking it.

**7. Originals are deleted only after the vault copy checks out.**
- Each copy is read back and compared by SHA-256 first.
- A dropped folder is removed whole only if every file in it, hidden ones included, went in. Otherwise only the checked files go, so `.env` or `.git` are never lost.
- Don't add "secure overwrite": on APFS SSDs it does nothing. FileVault is what makes deleted data unreadable, and Stillroom warns when it's off.
- A restore locks the vault first, so nothing still holding the old keys (an Edit in Place save, a note, the search index) can write into the restored one. A backup of an open vault is packed again if anything was saved while packing, so it never names a file it doesn't hold. A restore never leaves the vault missing, even if the Mac stops midway. The backup is unpacked and checked beside the vault, then the two folders swap in one step (`renamex_np` with `RENAME_SWAP`), and the old vault stays as `Store-before-restore-…`. Don't go back to two separate moves: a crash between them left no vault at all (black-box test, 24 Oct 2026).

**8. Copied secrets stay on this Mac and don't stay long.**
- They're copied with `.currentHostOnly` (no Universal Clipboard).
- They're marked concealed and transient for clipboard managers.
- They're cleared after 30 seconds, or at once when the vault locks or Stillroom quits, if nothing else was copied since.
- Two-factor setups (otpauth links and setup keys) are as secret as passwords: added concealed, kept out of the search index whatever their field says, and a QR picture they were read from is cleared from the clipboard or offered to the Trash.

**9. Windows are hidden from capture.**
- Every window and sheet uses `.hiddenFromCapture()`.
- Secure keyboard input is on while Stillroom is in front.
- ⌃⌥⌘L locks and hides Stillroom from any app. It's a Carbon hot key (`LockKey`), so it needs no accessibility permission and sees no other keys.

**10. Every way in to a slot seals that slot's key, and the slot key seals only its list, search index and cover key.**
- Password, recovery key, emergency kit, Touch ID.
- Lock to this Mac adds an outer Secure Enclave seal on both slots' password keys only; recovery keys and kits still work on any Mac.
- Each item has its own key, kept in the sealed list (see Item keys).
- Changing the password, making a new recovery key or a new kit doesn't re-key the vault. Old backups (and Time Machine copies) still open with the old password, key or pieces, and the slot key they reveal opens today's files too. The app says so where these are changed. A "rotate keys" feature would fix it; it has been discussed but not built. Item keys make it cheap (a new slot key reseals the list, not every file), but it would mean a new recovery key and a new kit every time, since Stillroom never keeps those.

**11. Hostile files must not crash the app.**
- Email: at most 256 inline pictures, and the page is built once, off the main thread; parts nest at most 16 deep, and `.emlx` byte counts are bounds-checked. Inline pictures add at most 64 MB to a page (one picture named thousands of times would otherwise grow into gigabytes). Tags are stripped for search in one linear pass, and the Date header is cleaned with a plain search: the regular expressions they replaced took minutes on a long run of `<` or `(`.
- Password exports are read in memory and never written out.
- `ChunkedReader` rejects impossible chunk sizes, and key-file Argon2 costs are bounds-checked (at most 2 GiB and 10 passes, so a doctored key file can't hang unlock for minutes).

## Emergency kit

The Shamir splitting in `EmergencyKit.swift` (GF(2⁸), polynomial 0x11b) was reviewed in October 2026 against a separately written implementation: 5,600 joins agreed both ways, and share bytes were uniform for fixed secrets, so fewer pieces than needed show nothing. All single-character typos and adjacent swaps are caught by the 2-byte check; a rarer typo that passes gives a wrong key, refused as "wrong kit". A forged piece can't ask for more than 10 boxes.

- Pieces don't carry a kit id, so pieces from an old and a new kit with the same plan give a "wrong kit" rather than "these are from different kits".
- One print job holds every piece, so the print spool, the printer's memory or a network printer briefly holds them all, and the print panel offers Save as PDF. Print on a printer attached to this Mac.

## Item keys

Since format 3 (October 2026), and unchanged in format 4, every sealing of an item, each earlier version included, has its own random 256-bit key, made fresh each time it's sealed and kept in the sealed list beside it. A slot's key seals only its list, its search index and its cover key.

- **Nothing can stand in for anything else.** Each one-piece item is bound to the fresh id it was sealed under (`sealedAs`), and its blob is named by that id. The list and the search index are each bound to their own name, and the intruder log's private key rides inside the list. A sealed file copied over another fails to open, and so does the search index copied over the list.
- **Keys stay in one place in memory.** The list is read into `AppState.itemKeys` and the keys are taken off each `VaultFile`, which is copied into views and tasks that can outlive a lock. Locking empties the table with the slot key.
- **Nothing older is read.** A list sealed without its binding, a list naming an item without its own key, and a key file without the Argon2id mark are refused as damaged, and an unlock that fails deletes nothing. A search index sealed without its binding is ignored and rebuilt. Stillroom 1.0 shipped without the 0.x formats (they had no users), so there is no unbound path to fall back to.
- **A list holding files is wrapped** (`{"format": 4, "vault": …}`); an empty one isn't, so every empty list is one size.
- **Covers** (format 4) are bound to kind and slot (`Vault cover 4 | list or search | letter`), and each `cover.key` to its slot, so neither slot's list or index can stand in for the other's.

- **A cover can't crash the app:** its length is read unsigned and checked before use, so a doctored one (both slots share the cover key) is refused as damaged.
- **Checking a new password against the other slot is limited:** setting or changing a password checks it doesn't open the other slot, which answers a guess; each check counts as a wrong try at the lock screen (`TryLimit`).

**Still unbound, on purpose:** the password, recovery and kit key files and `touchid.key`, and the Lock to this Mac outer seal. Their one layout is shared by every slot, set or not; a wrong file in their place opens nothing.

**Rollback isn't prevented.** Someone who can write the vault folder can put back an older genuine list and its blobs from a backup. Nothing short of state kept outside the folder could notice.

## What still shows on disk

Everything inside is sealed, but someone with a copy of the folder can see:

- how many items and earlier versions both vaults hold together (one file each in `Files/`), but not which vault's
- each item's size, to within about 12% (Padmé padding)
- when files were added, and when a slot's ways in changed (see rule 2)
- whether the folder is locked to a Mac or has Touch ID (their files exist or don't), but not for which vault
- beside the folder, the licence file if there is one: the buyer's name, email and edition, unencrypted (it's signed, not sealed)

Names, folders, kinds, tags, dates inside the vault and contents never show.

## Memory

Best effort only. Swift and macOS give no promise that no copy of a secret is left in memory.

- The typed password's bytes and the stretched key (Argon2's own output buffer included) are wiped after unlocking, and the opened slot key's plain copy too, whichever way in opened it. Keys are sealed straight from their own memory, without a plain copy.
- The slot key, cover key and item keys are held as CryptoKit `SymmetricKey`s, which wipe themselves when freed, and are let go on lock.
- What can't be done: a typed password is a Swift `String` and can't be reliably wiped; nor can the list's JSON, which holds every item key in base64 while it's read or written, or the kit's secret while a kit is made; decrypted contents sit in ordinary buffers while shown; macOS encrypts swap but Stillroom can't keep pages out of it. Malware with admin rights on an open vault sees everything.

## Streamed files

The VLT2 format was reviewed in October 2026. Truncation, reordering, duplicating chunks and swapping chunks between files are all refused. Every sealing ties its chunks to a fresh id (`sealedAs`), so an older version (or its chunks) copied over the current one is refused too.

The reader refuses chunk sizes outside 1 byte to 64 MiB, and sizes past 1 PiB, before any arithmetic on them.

Chunks are sealed with the item's own key (see Item keys), and one-piece items, the list and the search index are bound as well.

## Argon2id

Passwords are stretched by the Argon2 reference implementation (P-H-C/phc-winner-argon2, release 20190702), copied unchanged into `macos/Sources/CArgon2`. Don't edit those files.

Before it, Stillroom used its own Swift implementation. A review in October 2026 found that one correct: it matched libargon2 on 434 parameter sets. The switch was for trust: buyers and auditors can see Stillroom uses the reference code. The output is byte-identical, so no vault changed.

Each guess costs the full stretch: about 280 ms on an Apple silicon Mac, and roughly 10–30 guesses a second per high-end GPU (the 2026-10-24 black-box test's estimate). That's strong but ordinary, so the password's own strength is the real boundary, which is why the strength check refuses guessable ones. Say so plainly; don't market the stretch as making weak passwords safe.

The Swift implementation stays in the tests as a second, independent implementation. The tests check the C against it on 80 parameter combinations, against the RFC 9106 vector, and against three libargon2 answers. libsodium wasn't an option: it fixes lanes at 1, and existing keys use 4.

## The licence

- **What it is:** one line, `SR1.<payload>.<signature>`. The payload is JSON (licence id, edition, seats, the buyer's
  name and email, the day issued); the signature is Ed25519 over `SR1.<payload>`. The app holds only the public key,
  compiled in (`License.publicKey`), and checks a key with a pure parser plus CryptoKit: no network, no clock, no
  expiry. 1.x keys work in 1.x forever; 2.0 will take only its own keys.
- **Where it lives:** `~/Library/Application Support/Stillroom/License`, beside `Store`, never inside a slot, so it
  applies to both vaults alike and isn't in backups (a new Mac needs the key pasted again). Deleting the vault leaves
  it: it's a purchase, not vault data. Not the keychain: a signed key needs no secrecy, and the keychain is best left
  untouched where it isn't needed.
- **What it gives away:** the file is readable by anyone with the Mac's files, and names the buyer. It says nothing about
  either vault. Stillroom never sends it anywhere; nothing about it is logged but "licence added" or "removed" (rule 4).
- **The free tier never holds files hostage:** without a licence, only adding stops past 25 items (files, notes and
  secrets; folders and earlier versions don't count). Opening, editing, moving, deleting, exporting, backing up,
  restoring a backup of any size and checking always work (`overTheLimitNothingButAddingStops`).
- **The signer** (`website/server/`, served as `stillroomvault.com/api/paddle-webhook`) reads only a request whose
  Paddle signature checks out and is at most five minutes old, remembers handled event ids so a replay does nothing,
  and signs with a private key held only as a Worker secret and in Gjin's offline backup. It stores nothing about the
  buyer. A leaked private key lets anyone make keys; the fix is a new pair and an app update, and old keys then stop
  working, so keep it offline.

## Tampering and cracking

- **No obfuscation, anti-debugging or hidden checks** (decided 2026-10-28). An offline check always ends in one branch
  someone can patch, the source builds freely under FSL for personal use anyway, and code that hides itself breaks the
  promise that Stillroom can be taken apart and audited, and looks like malware to scanners.
- **What stops a forged key:** Ed25519. Nobody without the private key can make one, so there are no key generators.
- **A key posted publicly:** its id goes in `License.blocked` and the next release refuses it. Settings says why.
- **A changed copy:** `SelfCheck` checks at launch that the app is signed with an Apple certificate for team
  WP56DL33UR (`anchor apple generic and certificate leaf[subject.OU] = "WP56DL33UR"`), and the lock screen warns if
  not, before a password is typed in. A crack has to be signed again by someone else, so it fails. This protects
  people from a doctored download; whoever changes the app can remove it too.
- **The download:** `make-dist.sh` prints the zip's SHA-256 and the download page publishes it with how to check it.

## Things decided against

- **A server, an account or cloud sync:** there's nothing to breach, subpoena or moderate if Stillroom holds nothing. Future sync would go through a folder the user chooses, carrying already-encrypted data.
- **A master key or back door, ever:** "we can't open it" must stay true.
- **Forced automatic updates:** a pushed update is how a back door would arrive.
- **Advertising the decoy as a way to fool police:** market it as protection against coercion by thieves or abusers.
