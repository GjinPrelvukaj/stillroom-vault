# Changelog

All notable changes to Stillroom. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-11-02

Room check, the tamper seal, cool-down items, proof of what this copy is, and a polish of every screen.

### Added
- The tamper seal: after every save, Stillroom seals a fingerprint of the vault's folder with a key only this Mac's Secure Enclave holds. If a file was removed or added, or the folder was put back from an older copy, while Stillroom wasn't looking, the next unlock says so, once. It's one seal for the whole folder, so using one vault never trips the other's, and it never says which files changed. It checks on this Mac only, and it never blocks.
- Cool-down items: right-click an item › Cool-Down to make it wait 1 hour, 24 hours or 3 days after you ask to open it; it then stays open for an hour. The wait runs on the Mac's uptime, so changing the clock doesn't shorten it, and a restart starts it again. Previews, editing, Save a Copy and Edit in Place all wait; Export Everything leaves such items in the vault and says so; search never shows their words. Changing or turning off a cool-down waits too. It's a rule the app keeps, not encryption: with your password, a copy of the folder and the open reader, the item can still be read.
- Room check: each time the lock screen shows, Stillroom takes a quick look round this Mac before you unlock, entirely offline. While it looks, the lock ring breathes, every dot glowing in and out together; then the ring settles with "The room is clear", or lists what it found. Serious findings (a screen sharing or SSH session open, a camera or microphone in use by another app, named) turn Unlock into Open Anyway and hold Touch ID until you click. Minor ones (a remote-control app such as Parsec or TeamViewer running, a clipboard manager that keeps history, FileVault, System Integrity Protection or Gatekeeper off) can be put away with Got It. It never blocks, and it looks again whenever you come back to Stillroom. These are hints: macOS doesn't let apps see everything.
- Settings › Security starts with a card about this copy of Stillroom: its version, whether it's signed by Stillroom's maker, whether Apple notarized it, and the day it passed the offline check when it was built. Copy as Text puts the same lines on the clipboard. Both signature checks run with the network off, so even checking never goes online.
- A copy someone built from the source themselves gets a short welcome in Settings › Licence, beside the Buy a Licence button.

### Changed
- In the light appearance, secondary text, tags, warnings and errors are darker, so they all read at WCAG AA contrast on paper; quiet buttons, field hints and the switch's off track are easier to see too. Tags, orange and red each have a shade for dark and one for light.
- Every font size comes from the kit's own scale, so like things are the same size everywhere.
- Hovers, changes and arrivals settle without overshooting, and a button now answers the press by shrinking slightly instead of only fading.
- Buttons, switches, tabs and the sidebar show a violet ring when they have keyboard focus.
- The switch is a little larger, to sit level with the buttons beside it.
- Every sheet has the same surface (the window's ground with a faint light along its bottom) and one of two widths.
- The top of a folder list counts its folders too ("7 folders, 2 files"), instead of saying "Nothing here yet" over them.
- Notes, secrets and Settings start at the same left edge as the lists, so opening one no longer moves the page sideways. The sidebar's tint runs up under the window's buttons.
- Settings keeps its title and tabs still while a tab's rows scroll, and its section labels line up with the rows' text and no longer repeat the tab's name.
- The lock screen keeps its place when Room check finishes, and making a vault or changing a password no longer leaves an empty band under the fields before anything is typed.
- A PDF's card shows the page only once it's laid out, inset from the card's edges with a shadow, instead of popping in grey.
- Empty pages share one look: the intruder log's empty state is the same ring and symbol as an empty list, saying "No one has tried" once instead of twice.
- Versions with nothing to show says so, and when one will be kept, instead of an empty box.
- Check vault fills a ring as it reads each item, ending full with a check mark, or with the damaged share in orange.
- The free tier's wording: the sidebar says "Free limit reached" with "Adding is paused" under it and a real Buy a Licence button, and Settings › Licence says "45 items, 20 over the free 25" instead of "45 of 25 items".
- Sheet titles are in title case, and their buttons name what they do ("Change Password", "Set Decoy Password", "Make My Vault", matching the tour) instead of "Save".
- Setting a decoy password puts "Everything in the other vault is deleted" on a line of its own in orange, where it can't be missed.
- The tamper warning has a title, reads in ink rather than all red, and ends with a next step: check the vault in Settings › Data.
- A minor Room check note (a clipboard manager, say) is one quiet line under the lock screen's subtitle instead of a panel; serious findings keep theirs.
- Password advice that runs to two lines no longer pushes the buttons down a second time.
- A hidden secret shows the same ten dots whatever its length, so its length can't be read over a shoulder; click it to type a new one. A two-factor setup reads "Two-factor setup key" instead of a row-long run of dots, with its code below as the thing to read.
- The dice that makes a random password shows only on password fields, not on card numbers, security codes or PINs.
- The eye, dice, copy and ⋯ buttons beside a secret's fields have a round plate on hover and press, and the ⋯ menu matches them.
- A two-factor code stays violet to the end (orange means a protection is off) and only dims in its last three seconds; its ring sweeps smoothly instead of stepping each second.
- The sidebar's "Kinds" and "Tags" labels are a size larger and easier to read.
- Notes and Secrets no longer say "Note" or "Secret" on every row, and dates in the last week read as Finder's do ("Today, 11:29", "Yesterday", "Tuesday").
- A tag looks the same everywhere: its colour's dot and its word on a capsule of that colour, in the sidebar, in rows and in the Tags sheet, where chosen tags are filled with a check mark.
- Fields and the buttons beside them are one height (32 points), on the lock screen and in a list's header alike.
- A card dims the window behind it less muddily in the light appearance, and Edit in Place is no longer its lit button, since it hands the file to another app.
- A card and the Cool-down sheet show the item's symbol in the same violet tile as its editor.
- Settings rows show one line each; the rest of a long description (the decoy and Touch ID caveats among them) is under an info button beside the row's name, word for word.
- The Security tab leads with no network connections, AES-256-GCM and keys forgotten, larger, then lists the other facts with the figure on the left, instead of nine identical cards.
- The auto-lock menu has the up-down chevron of a pop-up, and Remove… comes after New Kit… and Set… instead of before.
- A note's text has more room round it and between lines, in a column no wider than reads easily.
- The lock ring's unlit dots and the two-factor timer's track show on paper too.
- Unlock and other lit buttons waiting for input keep their shape, with dimmed words, instead of fading to a smudge.
- The tour's Skip sits in the top-right corner, so the pages stay centred and it goes on the last one.
- Unlocking reads as one movement: the ring's dots all light, the lock opens, and the lock screen grows a little as it fades before the vault comes in, instead of the two showing through each other. The same with Touch ID.
- Opening a note or secret from a list carries its name up into the editor's heading.
- A licence's welcome is ready to press in about half a second instead of two and a half.
- After copying a secret or a two-factor code, its copy button shows a check inside a ring that drains over the 30 seconds until the clipboard empties itself.
- A file that has just come in arrives with one soft pulse of violet light along its row.
- Locking with ⌃⌥⌘L or from the menu bar lets the window's light go grey before it hides, and a Force Touch trackpad gives one tap on locking and on opening.
- ⌘F goes to Search, typing a letter on a list starts a search with it, ⌘1, ⌘2 and ⌘3 go to All Files, Notes and Secrets, and ⌘[ goes back out of an editor or a folder.
- Unlocking again returns to the shelf, tag or folder you locked from, for as long as Stillroom stays open. It's held in memory only, never written anywhere, and used only if the vault that opens has that place.
- "The room is clear" fades a few seconds after you start typing, so the lock screen settles to the ring and the field. Findings never fade.

### Fixed
- A folder's item count in All Files no longer includes notes and secrets filed there, which that list doesn't show.
- The first unlock of a vault with no tamper seal yet could freeze Stillroom for about ten seconds and then say the folder had changed. A second copy of Stillroom on the same Mac shared one keychain entry with the first, so macOS stopped to ask for access and the check read the other vault's seal. Each vault folder now keeps its own, the check runs off the main thread, and the warning is shorter and says what to do next.

## [1.0.1] - 2026-11-02

A heads-up before the free limit, a way to buy from inside the app, and a stricter offline check.

### Added
- From five free items left, the sidebar says how many remain ("3 of 25 free items left", then "Free limit reached, adding is paused") with a Buy a Licence button, so the limit is never a surprise. Settings › Licence has the same button. Both open the pricing page in your browser; the app itself still makes no connection.

### Changed
- The offline build check also fails a build that looks code up by name at run time (`dlopen`, `dlsym`, `NSClassFromString` and the Objective-C class lookups), so nothing can reach a networking function that way. The app's one `dlsym`, used to make crash stacks readable, is now a direct link instead. Thanks to a reader of the dev.to article for pointing out the gap.

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

[Unreleased]: https://github.com/GjinPrelvukaj/stillroom-vault/compare/v1.1.0...main
[1.1.0]: https://github.com/GjinPrelvukaj/stillroom-vault/releases/tag/v1.1.0
[1.0.1]: https://github.com/GjinPrelvukaj/stillroom-vault/releases/tag/v1.0.1
[1.0.0]: https://github.com/GjinPrelvukaj/stillroom-vault/releases/tag/v1.0.0
[0.1.0]: https://www.stillroomvault.com/changelog/#010---2026-10-24
