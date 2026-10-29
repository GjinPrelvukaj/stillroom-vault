---
title: 'Cryptomator Alternative for Mac, With No Cloud'
description: 'A Cryptomator alternative for Mac: Cryptomator encrypts your cloud folder, Stillroom Vault keeps files and passwords sealed on one Mac. Which fits you.'
h1: 'Stillroom Vault vs Cryptomator'
lead: 'Both encrypt your files on your own device. Cryptomator is built for the cloud folder you already sync; Stillroom Vault is built for a Mac that never sends anything anywhere.'
name: 'Cryptomator'
updated: '27 October 2026'
order: 10
related: ['/moving-from/cryptomator/', '/guides/encrypt-files-on-mac/', '/compare/proton-drive/', '/compare/veracrypt/']
faq:
  - q: 'Is Cryptomator free on the Mac?'
    a: 'Yes. Cryptomator says all functional and encryption features are free on the desktop, on Windows, macOS and Linux. The mobile apps are free to read, and writing is a one-time purchase per platform.'
  - q: 'Can I open a Cryptomator vault on my phone? Can I do that with Stillroom Vault?'
    a: 'Cryptomator has iOS and Android apps that open the same vault through your cloud. Stillroom Vault runs only on Apple silicon Macs and has no sync, so its vault stays on that Mac.'
  - q: 'Can I use both?'
    a: 'Yes. Many people keep files they need on several devices in Cryptomator, and keep passwords, two-factor setups and documents that never need to travel in Stillroom Vault.'
sources:
  - label: 'Cryptomator: home page'
    url: 'https://cryptomator.org/'
  - label: 'Cryptomator: Pricing'
    url: 'https://cryptomator.org/pricing/'
  - label: 'Cryptomator docs: Security architecture'
    url: 'https://docs.cryptomator.org/security/architecture/'
---

## What Cryptomator is, and who it suits

Cryptomator is a free, open source app that encrypts files before your cloud service sees them. You create a vault inside a folder your cloud service syncs, set a password, and unlock it as a virtual drive. Files you put in that drive are encrypted on your device, names included, with AES and 256-bit keys, and your cloud only ever stores the encrypted copies.

It suits you if you already keep your files in a cloud and want the provider not to be able to read them, or if you need the same encrypted files on a Mac, a Windows PC, a Linux machine and a phone. Cryptomator also has a paid team product, Cryptomator Hub, for sharing vaults inside an organization.

Stillroom Vault solves a narrower problem: a vault on one Mac, for files, notes, passwords and two-factor codes, that makes no network connections at all.

## Side by side

| What | Cryptomator | Stillroom Vault |
|---|---|---|
| Where data lives | In a folder you choose, usually one your cloud syncs | One folder on your Mac |
| Encryption | AES with 256-bit keys for files and names; password stretched with scrypt | AES-256-GCM with a fresh key per item; password stretched with Argon2id (512 MB) |
| Platforms | Windows, macOS, Linux, iOS, Android | Apple silicon Macs, macOS 26 or later |
| Price | Free on desktop; mobile writing is a one-time purchase per platform; Hub for teams | Free for 25 items; $39 once; Family $129 for 5 people |
| Source | Open source | Source available (FSL); the reader script is MIT |
| Cloud and sync | Made for it | None; it never goes online |
| Scope | Files | Files, notes, passwords and two-factor codes |

## Where Cryptomator is the better choice

Be honest with yourself about how you use your files. Cryptomator is the better fit when:

- **You need your files on more than one device.** Cryptomator works through the sync you already have, so the same vault opens on your Mac, your PC and your phone. Stillroom has no sync and no phone app.
- **You use Windows or Linux too.** Stillroom runs only on Apple silicon Macs.
- **You want every app to open your files directly.** An unlocked Cryptomator vault is a drive, so any app can open, edit and save files in it as usual.
- **You share a vault with a team.** Cryptomator Hub manages access for several people. Stillroom has no sharing, and each person's vault is their own.
- **Cost matters most.** The desktop app is free with no item limit.
- **You want fully open source code.** Stillroom's source is published under the Functional Source License, which lets you read, build and audit it, but isn't an open source licence.

## Where Stillroom Vault fits better

Stillroom is the better fit when the files never need to leave the Mac and you'd rather nothing about them did either:

- **Nothing goes online.** Stillroom makes no network connections, and a build check fails any version that links networking code. There's no cloud copy to think about.
- **Passwords and two-factor codes live with your documents.** Secrets are records with fields, and any secret holding a two-factor setup shows its live code. You can import from Apple Passwords, browsers, Bitwarden and 1Password exports.
- **Viewing doesn't write a decrypted copy to disk.** PDFs, images, text, sketches and email open in built-in viewers, audio and video stream from the sealed file, and other previews and Edit in Place copies go to a RAM disk. Edit in Place has one caveat: the app you edit in may keep its own copies, and Stillroom warns about this.
- **Names and folders stay inside the seal.** Someone with a copy of the vault folder sees how many items there are, their rough sizes and when they were added, but no names, folders, kinds or tags. The [security page](/security/) lists exactly what shows.
- **More ways in, and protections for the keyboard.** Besides a password there's a recovery key, a printable [emergency kit](/features/emergency-kit/), Touch ID and optional [Lock to this Mac](/features/lock-to-this-mac/). There's a [decoy password](/features/decoy-password/), an [intruder log](/features/intruder-log/), and every window is [hidden from screen capture](/features/hidden-from-capture/).

The decoy has limits. It protects against thieves and abusers, not police, and it doesn't fool someone who has one password and a copy of the vault folder. [Security rule 2](/security/#rules) says exactly what it does.

One more honest difference: Cryptomator's site points to independent security audits. Stillroom hasn't had one yet; one is planned before release.

## Using both, or moving over

The two don't compete for the same folder, so using both is simple. Keep what you need on your phone or share with others in Cryptomator. Keep what should stay on one Mac, such as ID scans, contracts, recovery codes and passwords, in Stillroom.

To move files from Cryptomator into Stillroom:

1. Unlock your Cryptomator vault so its drive appears in Finder.
2. Drag the files or folders you want into Stillroom's window. Folders keep their structure.
3. Check a few items open in Stillroom.
4. Then delete the copies from the Cryptomator vault yourself, if you no longer want them there.

Stillroom can delete originals for you after reading each copy back and checking it by SHA-256. With files inside an unlocked Cryptomator drive, deleting the original deletes it from your Cryptomator vault and, through sync, from your cloud. Only let it do that when that's what you want. The [moving from Cryptomator](/moving-from/cryptomator/) guide goes step by step.

Whichever you use, keep a backup and keep your password somewhere safe. Stillroom can't recover a forgotten password, and nobody else can either. In Stillroom, your recovery key or emergency kit is the only way back in, and [support](/support/#forgot) explains what to do.
