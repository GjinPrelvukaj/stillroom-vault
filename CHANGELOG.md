# Changelog

All notable changes to Stillroom. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-28

The first release. Format 4, the 1.0 format. Vaults from 0.1.0 and format 3 don't open in this version: export from the old version and add the files again.

### Added
- The decoy redesign (format 4): two slots, `a` and `b`, built alike, with yours in either at random. A slot nobody set is a real vault whose passwords nobody knows. Each slot has its own recovery key, kit and intruder log, and Settings shows the same rows in both. Every save rewrites both slots' lists inside covers of one size and date, and both slots' items share one `Files/` folder under names only a slot can tell apart.
- Item keys: every sealing of every item, earlier versions included, gets its own random 256-bit key, kept in the sealed list.
- Every seal (items, list, search index, covers) is bound to what it is, so no sealed file can stand in for another.
- Settings in five tabs (Access, Protection, Security, Data, Licence), the same in both vaults. The Security tab shows plain facts, with a protection that's switched off shown in orange.
- Licences: paste a key in Settings › Licence, a fifth tab, the same in both vaults. Checked offline (Ed25519 against a public key built in), kept beside the store in neither vault, never expiring.
- A light appearance, and Settings › Protection › Appearance (System, Light, Dark). Before this, a Mac set to Light showed dark text on the black window.
- Blocked licence ids: a key posted publicly can be turned off in the next release, and Settings says why.
- Stillroom checks its own signature at launch and warns on the lock screen if this copy isn't signed by its maker.
- `make-dist.sh` prints the download's SHA-256, and the download page explains how to check it.
- The free tier: without a licence a vault holds 25 items (files, notes and secrets). Only adding stops; opening, editing, exporting, backing up and restoring never do. The same in either vault.
- The licence signer on the website: Paddle's webhook signs a key and emails it (`website/functions/api/paddle-webhook.ts`), plus scripts to make the key pair once and to issue a key by hand.
- Check for Updates (app menu, and Settings › Data): opens the release notes in the browser, which say whether a newer version is out; the app itself still never connects. Settings says when a copy is over six months old.
- On the website: a releases feed (`/changelog.xml`), and an email to every buyer when a new version is out (`website/scripts/send-update-email.mjs`).
- `README.md`, `LICENSE`, this changelog.

### Changed
- Renamed to Stillroom throughout: bundle id `app.gjin.stillroom`, executable, package, folders, item files (`.stillroom`), backups (`.stillroombackup`), `tools/stillroom-open.py`.
- The intruder log is sealed to both vaults and no longer keeps what was typed.
- Touch ID opens one vault, whichever last turned it on; Lock to this Mac covers both.
- Restore unpacks the backup beside the vault and swaps it in with one atomic rename, so a crash midway never leaves no vault.

### Fixed (code review, 2026-10-26)
- Files taken out of the vault (Save a Copy, email attachments, Export Everything) are marked as downloaded, so Gatekeeper checks a program before it runs.
- Web pages (HTML, XML, SVG, web archives) no longer open with Edit in Place, where a browser would run their scripts and load from the network.
- A restore locks the vault first, so an Edit in Place save or a note can't write the old list into the restored vault; a backup of an open vault is packed again if anything was saved meanwhile.
- A doctored cover length is refused instead of crashing every unlock.
- Unlock costs the same whether or not a slot's key file can be read; the two slots are made in a random order.
- A copied secret is cleared when the vault locks or Stillroom quits, not only after 30 seconds.
- An email with thousands of inline pictures no longer freezes the app (at most 256, page built off the main thread).
- A folder dragged out of the window no longer carries its name; a Quick Look copy closed while mounting is deleted; the RAM disk is checked again before a copy is written.
- Checking a new password against the other slot counts as a wrong try. More key buffers are wiped.
- `tools/stillroom-open.py`: names can't climb out of the export folder on Windows, one bad item no longer stops the export, sizes are checked before reading. The Windows engine redacts keys from debug output and boxes item keys.

### Changed (license)
- The source is under the Functional Source License 1.1 (FSL-1.1-ALv2, `LICENSE.md`): readable and buildable by anyone, not for sale by others, Apache 2.0 two years after each release. `tools/` is MIT, so anyone may use `stillroom-open.py`.

### Changed (pricing)
- Stillroom is $39 one-time (was $79, $59 at launch).

### Removed
- Reading format 3, and anything older: PBKDF2 key files, unbound seals, items without their own key, and the background upgrade.

## [0.1.0] - 2026-10-24

The first complete build, notarized and used daily by its author.

### Added
- Files, notes and secrets, with folders, tags, versions and sealed full-text search.
- Viewers for PDF, images, sketches, text and email, Quick Look for the rest, and audio and video streamed from the sealed file.
- Edit in Place from a RAM disk; verified deletion of originals after a SHA-256 read-back.
- Ways in: password (Argon2id, reference C), recovery key, emergency kit (Shamir pieces), Touch ID (Secure Enclave), and Lock to this Mac.
- A decoy vault whose unset files are shaped exactly like a set, empty one.
- Intruder log of wrong tries and photos, sealed with HPKE.
- Auto-lock, locking on sleep, the ⌃⌥⌘L lock-and-hide hot key, and a menu bar lock.
- Windows hidden from screen capture; secure keyboard input while in front.
- Encrypted backups and restore; export everything; import from Apple Passwords; iPhone scanning.
- Live two-factor codes (RFC 6238); a first-run tour; Check Vault.
- A local activity log with stall and freeze detection that records nothing private.
- Locked-down email viewer: no JavaScript, a data-only content policy and a WebKit block list, proven by a hostile-email test.
- `Scripts/check-offline.sh`, which fails any build that links networking code.
- Public file format (`docs/FORMAT.md`) and an independent Python reader.
- Developer ID signing, notarization and stapling (`Scripts/make-dist.sh`).

[Unreleased]: https://github.com/GjinPrelvukaj/Stillroom/compare/v1.0.0...main
[1.0.0]: https://github.com/GjinPrelvukaj/Stillroom/releases/tag/v1.0.0
[0.1.0]: https://github.com/GjinPrelvukaj/Stillroom/releases/tag/v0.1.0
