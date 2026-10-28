# Reporting a security problem

Stillroom keeps people's most private files, so a security problem is the most important kind of report it can get.
Thank you for looking.

(How Stillroom is built to be safe, and what it does and doesn't protect against, is in
[`docs/SECURITY.md`](../docs/SECURITY.md). This page is about telling us when it falls short.)

## How to report

Email **security@stillroomvault.com**. Please include:

- what you found, and what someone could do with it
- the steps to reproduce it, or a proof of concept
- the version of Stillroom (or the commit) and the macOS or Windows version
- how you'd like to be credited (name, handle and link), or that you'd rather not be

Please don't open a public issue for a security problem, and don't post it anywhere until it's fixed or 90 days
have passed (see below).

## What happens next

Stillroom is made by two people, so these times are honest rather than fast:

- **Within 7 days:** we reply, confirming we received the report.
- **Within 30 days:** we tell you whether we agree it's a problem, and how serious we think it is.
- **Within 90 days:** we release a fix, or explain why it isn't one. If we need longer, we'll say why and agree a
  date with you.
- **When the fix ships:** we publish an advisory describing the problem, request a CVE for it, and credit you in the
  advisory and in the list below, unless you asked us not to.

There is no bug bounty: Stillroom has no budget for one. What we can offer is a CVE with your name on it, public credit, and
our thanks.

## In scope

- The Stillroom app for Mac, and the Windows engine in `windows/`
- The vault format (`docs/FORMAT.md`): anything that lets someone read, change, swap or replay sealed data without
  a password, recovery key or kit
- `tools/stillroom-open.py`
- Backups, export, Edit in Place, the email viewer, the license check
- Anything that makes the app go online, or leaves plaintext on disk outside the RAM disk
- Anything that tells the two slots apart in a way `docs/SECURITY.md` (rule 2) says it shouldn't

## Out of scope

These are documented limits, not bugs (`docs/SECURITY.md` explains each):

- Malware with admin rights while the vault is open
- A weak or guessed password
- Someone with one slot's password and a copy of the folder seeing that the other slot holds data
- Copies taken at different times showing when a slot's ways in changed
- Inode change times, Recent Items and other traces macOS keeps outside Stillroom
- Copies another app keeps after Edit in Place
- Old backups still opening with an old password (key rotation is planned for 1.x)
- Physical access to an unlocked Mac with the vault open
- Reports from automated scanners with no demonstrated impact

If you're unsure whether something counts, send it anyway.

## Safe harbor

If you act in good faith, we won't take legal action against you or report you to anyone for your research. Good
faith means:

- you test only on your own Mac or PC, with your own vaults and data
- you don't access, change or destroy anyone else's data, and stop as soon as you've shown the problem
- you don't disrupt anyone else's use of Stillroom or its website
- you give us the time above to fix it before telling anyone else

This is written in the spirit of the [disclose.io](https://disclose.io) core terms. If something here is unclear,
ask before you act, at the address above.

## Thanks

People who reported a real problem, with their CVE:

- *No reports yet. This could be you.*
