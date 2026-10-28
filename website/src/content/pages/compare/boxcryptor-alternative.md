---
title: 'Boxcryptor Alternatives for Mac'
description: 'Boxcryptor has been discontinued. The replacements worth looking at, from encrypted cloud folders to an offline Mac vault, and how to choose.'
h1: 'Looking for a Boxcryptor replacement'
lead: 'Boxcryptor has shut down. Which replacement fits depends on what you used it for: encrypting a cloud folder, sharing with a team, or simply keeping private files locked.'
name: 'Boxcryptor alternative'
updated: '27 October 2026'
order: 90
related: ['/compare/cryptomator/', '/compare/proton-drive/', '/moving-from/cryptomator/', '/guides/encrypt-files-on-mac/']
faq:
  - q: 'Is Boxcryptor still available?'
    a: 'No. Boxcryptor''s website says that as of 31 December 2025 its maker, Secomba GmbH, has ceased all operational activities, and that Boxcryptor has been discontinued.'
  - q: 'What is the closest replacement for Boxcryptor?'
    a: 'For encrypting files inside a cloud folder you already use, Cryptomator works the same way: files are encrypted on your device before your cloud syncs them. For teams on Dropbox, Dropbox offers end-to-end encrypted team folders on some business plans.'
  - q: 'Is Stillroom Vault a Boxcryptor replacement?'
    a: 'Only partly. Stillroom Vault encrypts files on your Mac but has no cloud sync, no sharing and no apps for other systems. It suits files that should stay on one Mac.'
sources:
  - label: 'Boxcryptor: Goodbye notice'
    url: 'https://boxcryptor.com/'
  - label: 'Cryptomator: home page'
    url: 'https://cryptomator.org/'
  - label: 'Cryptomator: Pricing'
    url: 'https://cryptomator.org/pricing/'
  - label: 'Proton Drive: Security'
    url: 'https://proton.me/drive/security'
  - label: 'Proton Drive: Pricing'
    url: 'https://proton.me/drive/pricing'
  - label: 'Dropbox Help: Encrypted team folders'
    url: 'https://help.dropbox.com/security/dropbox-vault'
---

## Boxcryptor has been discontinued

Boxcryptor's website now shows a short goodbye: as of 31 December 2025, Secomba GmbH, the company behind it, has ceased all operational activities, and Boxcryptor has been discontinued as a result. The notice gives a support address for urgent cases, and says replies can no longer be guaranteed.

If you still have files encrypted with Boxcryptor, getting them out is the first job, before any choice of replacement. If a Boxcryptor app you still have opens them, save plain copies of everything you need somewhere safe for now, such as a Mac with FileVault on, then encrypt them again with whatever you choose below. If it doesn't, the support address on Boxcryptor's site is the only official route left.

Most people used Boxcryptor for one of three things. Each has a different best replacement.

## Pick by what you used it for

### Encrypting files in a cloud folder

If you used Boxcryptor so that your cloud provider couldn't read your files, **Cryptomator** is the closest match. You make a vault inside a folder your cloud syncs, unlock it as a drive, and files and their names are encrypted with AES and 256-bit keys before your cloud sees them. It's open source, free on Windows, macOS and Linux, and its iOS and Android apps unlock writing with a one-time purchase per platform. Our [Stillroom Vault vs Cryptomator](/compare/cryptomator/) page compares it in detail.

### Encrypted storage without a separate tool

If you'd rather the storage did the encryption itself, **Proton Drive** encrypts files and folder names end to end, with apps for Windows, macOS, iPhone, Android and the web. Its apps and encryption libraries are open source, and it has a free 5 GB plan and paid subscriptions. See [Stillroom Vault vs Proton Drive](/compare/proton-drive/).

### Encrypted folders for a team on Dropbox

If your company used Boxcryptor with Dropbox, Dropbox now offers end-to-end encrypted team folders on its Business Plus, Advanced and Enterprise plans. Dropbox says only folder members have the encryption key, excluding anyone else, Dropbox included, and admins can create recovery keys. Check Dropbox's help page for the current terms.

### Keeping private files locked on your Mac

If your files never really needed to be in the cloud, and you used Boxcryptor mainly to keep them private, a local vault may suit you better. That's where Stillroom Vault fits.

## How the options compare

| What | Cryptomator | Proton Drive | Stillroom Vault |
|---|---|---|---|
| Where data lives | A folder your cloud syncs | Proton's servers, synced to your devices | One folder on your Mac |
| Platforms | Windows, macOS, Linux, iOS, Android | Windows, macOS, iOS, Android, web | Apple silicon Macs, macOS 26 or later |
| Price | Free on desktop; mobile writing paid once per platform | Free 5 GB; subscriptions for more | Free for 25 items; $39 once; Family $129 for 5 |
| Source | Open source | Open source apps and libraries | Source available (FSL); reader script MIT |
| Cloud and sync | Through your cloud | Built in | None; it never goes online |
| Sharing | Teams through Cryptomator Hub | Links with password and expiry | None |

## Where Stillroom Vault fits, and where it doesn't

Be clear about what Stillroom isn't. It has no sync, no sharing, and runs only on Apple silicon Macs. If you relied on Boxcryptor to reach your files from a phone or a Windows PC, or to share them with colleagues, choose Cryptomator, Proton Drive or Dropbox's encrypted folders instead.

Stillroom fits when the files should stay on one Mac:

- **Nothing goes online.** No server, no account, no sync; Stillroom makes no network connections at all.
- **Files, passwords and two-factor codes together.** Documents of any kind, notes, and secrets with live two-factor codes, with folders, tags, earlier versions and a sealed search index.
- **Viewing without leaving copies.** PDFs, images, text, sketches and email open in built-in viewers, and audio and video play from the sealed file, without writing a decrypted copy to disk.
- **Ways back in that you hold.** A [recovery key](/features/recovery-key/), a printable [emergency kit](/features/emergency-kit/) split among people you trust, Touch ID, and optional Lock to this Mac. Nobody, us included, can recover a forgotten password.
- **A format that outlives us.** One lesson from Boxcryptor's closure is that encrypted files depend on the software that opens them. Stillroom's [file format is public](/format/), and a short MIT-licensed Python script, `stillroom-open.py`, reads a vault without the app. You can also export everything as plain files at any time, and the free tier never blocks opening, exporting or backing up.

Stillroom hasn't had an independent security audit yet; one is planned. Its decoy password protects against thieves and abusers, not police, and doesn't fool someone with one password and a copy of the vault folder ([rule 2](/security/#rules)).

## Moving your files

Whichever replacement you choose, the steps are the same:

1. Save plain copies of your Boxcryptor files, if you can still open them, on a Mac with FileVault on.
2. Set up the new tool and move the files in. In Stillroom, drag files or whole folders into the window; folders keep their structure.
3. Check that a few files open in the new tool.
4. Delete the plain copies. Stillroom can do this for you once it has read each copy back and checked it by SHA-256.

You can use more than one. A common split is Cryptomator or Proton Drive for files you need everywhere, and Stillroom for ID scans, contracts, recovery codes and passwords that should stay on your Mac.
