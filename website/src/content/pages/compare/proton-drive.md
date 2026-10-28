---
title: 'Stillroom Vault vs Proton Drive'
description: 'Proton Drive is end-to-end encrypted cloud storage with sharing and sync. Stillroom Vault keeps files and passwords on one Mac, offline. Which fits.'
h1: 'Stillroom Vault vs Proton Drive'
lead: 'Proton Drive is encrypted cloud storage you can reach from anywhere. Stillroom Vault is an encrypted vault that never leaves your Mac. They answer different questions, and work well together.'
name: 'Proton Drive'
updated: '27 October 2026'
order: 80
related: ['/compare/cryptomator/', '/compare/boxcryptor-alternative/', '/guides/encrypt-files-on-mac/', '/guides/if-your-mac-is-stolen/']
faq:
  - q: 'Is Proton Drive end-to-end encrypted?'
    a: 'Yes. Proton says files and folder names are end-to-end encrypted, so Proton can''t see them without your permission, and that its apps and encryption libraries are open source.'
  - q: 'Can I keep a Stillroom Vault backup in Proton Drive?'
    a: 'Yes. A Stillroom backup is one encrypted file, so you can keep it in any folder, including one Proton Drive syncs. It opens with the password, recovery key or kit the vault had when the backup was made.'
  - q: 'Does Stillroom Vault have cloud storage?'
    a: 'No. Stillroom has no server, no account and no sync, and makes no network connections. Its vault stays in one folder on your Mac.'
sources:
  - label: 'Proton Drive: home page'
    url: 'https://proton.me/drive'
  - label: 'Proton Drive: Security'
    url: 'https://proton.me/drive/security'
  - label: 'Proton Drive: Pricing'
    url: 'https://proton.me/drive/pricing'
---

## What Proton Drive is, and who it suits

Proton Drive is cloud storage from Proton, a company based in Geneva, Switzerland. Files and folder names are end-to-end encrypted on your device before they're uploaded, and Proton says no one, not even Proton, can access your files or see their names without your permission. Its apps and encryption libraries are open source, and Proton publishes the reports of independent audits.

It has apps for Windows, macOS, iPhone and Android, a web app and a command-line tool. It syncs files between your computer and the cloud, backs up photos and videos from your phone, keeps earlier versions of files, and shares files with links you can protect with a password and an expiry date. Proton Docs and Sheets add editing with other people.

There's a free plan with 5 GB of storage, and paid subscriptions with more storage, some bundled with Proton's other services.

It suits you if you want your files backed up off your Mac, available on every device and shareable, without the provider being able to read them.

## Side by side

| What | Proton Drive | Stillroom Vault |
|---|---|---|
| Where data lives | Proton's servers, synced to your devices | One folder on your Mac |
| Encryption | End-to-end, files and folder names | AES-256-GCM, a fresh key per item; Argon2id (512 MB) for the password |
| Platforms | Windows, macOS, iOS, Android, web, command line | Apple silicon Macs, macOS 26 or later |
| Price | Free 5 GB; paid subscriptions for more | Free for 25 items; $39 once; Family $129 once for 5 people |
| Source | Open source apps and libraries | Source available (FSL); the reader script is MIT |
| Cloud and sync | Built in | None; it never goes online |
| Scope | Cloud storage and sharing | Files, notes, passwords and two-factor codes |

## Where Proton Drive is the better choice

- **Your files survive losing your Mac.** Proton Drive keeps a copy off the machine. Stillroom's vault lives on one Mac, so you need to make backups yourself.
- **Every device, and the web.** Open your files on your phone, another computer or in a browser. Stillroom runs only on Apple silicon Macs.
- **Sharing and collaboration.** Password-protected links with expiry dates, shared albums, and documents you can edit together. Stillroom has no sharing.
- **Photo backup.** Automatic backup from your phone.
- **Open source and audited.** Proton's apps and libraries are open source, and it publishes audit reports. Stillroom's source is published under the Functional Source License, which isn't an open source licence, and Stillroom hasn't had an independent security audit yet; one is planned.

## Where Stillroom Vault fits better

Proton Drive is a good answer to "I want my files in the cloud, privately." Stillroom answers a different question: "I want these things on my Mac only, and I want them locked even while I'm using it."

- **Nothing leaves the Mac.** Stillroom has no account and no server, and makes no network connections; a build check fails any version that links networking code. For some things, such as ID scans, medical records or recovery codes, you may prefer that no copy exists anywhere else, encrypted or not.
- **Locked while you work.** Any file that sits unsealed on your Mac can be read by apps running as you. Stillroom keeps everything sealed until you open the vault, and locks again after a while, when the Mac sleeps, or with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> from any app. Its viewers show PDFs, images, text, email, audio and video without writing a decrypted copy to disk.
- **Passwords and two-factor codes.** Secrets are records with fields, with live two-factor codes. Copied secrets stay off Universal Clipboard and clear after 30 seconds.
- **Protection at the keyboard.** A [decoy password](/features/decoy-password/), an [intruder log](/features/intruder-log/), and windows [hidden from screen capture](/features/hidden-from-capture/). The decoy protects against thieves and abusers, not police, and doesn't fool someone who has one password and a copy of the vault folder ([rule 2](/security/#rules)).
- **Ways back in that you hold.** A [recovery key](/features/recovery-key/), a printable [emergency kit](/features/emergency-kit/), [Touch ID](/features/touch-id/) and optional [Lock to this Mac](/features/lock-to-this-mac/). Nobody can recover a forgotten Stillroom password.
- **Pay once.** No subscription: $39 for one person's Macs, or $129 for a family of five.

## Using both

This pair works well, because each covers the other's gap.

- **Keep a Stillroom backup in Proton Drive.** Stillroom makes encrypted backups to one file you keep. Put that file in a Proton Drive folder and you have an off-Mac copy, encrypted by Stillroom before Proton's own encryption. If your Mac is lost, restore the backup onto a new Mac; [if your Mac is stolen](/guides/if-your-mac-is-stolen/) covers what to do.
- **Know what a backup opens with.** A backup opens with the password, recovery key or kit the vault had when the backup was made. Changing your password later doesn't lock old backups, so delete backups you no longer want.
- **Split by need.** Files you share or need on your phone go in Proton Drive. Files that should only ever be on your Mac, and your passwords and two-factor codes, go in Stillroom.

To move files from Proton Drive into Stillroom, download them to your Mac, drag them into Stillroom's window, and check they open. Stillroom can delete the local originals after checking each copy by SHA-256; deleting files in a synced folder may delete them from Proton Drive too, so remove the cloud copies only when you mean to.
