---
title: 'Stillroom Vault vs VeraCrypt'
description: 'VeraCrypt encrypts volumes, partitions and drives on Windows, macOS and Linux. Stillroom Vault is a Mac app for files and passwords. How they differ.'
h1: 'Stillroom Vault vs VeraCrypt'
lead: 'VeraCrypt encrypts whole volumes and drives, on almost any computer. Stillroom Vault is a Mac app that seals each item on its own and opens it in built-in viewers.'
name: 'VeraCrypt'
updated: '27 October 2026'
order: 20
related: ['/moving-from/veracrypt/', '/compare/encrypted-disk-image/', '/learn/plausible-deniability/', '/features/decoy-password/']
faq:
  - q: 'Is VeraCrypt free?'
    a: 'Yes. VeraCrypt is free and open source, for Windows, macOS and Linux. On a Mac it needs macFUSE or FUSE-T, and VeraCrypt recommends the FUSE-T version on Apple silicon.'
  - q: 'Is a Stillroom decoy password the same as a VeraCrypt hidden volume?'
    a: 'No. Both open something harmless with a second password, but a hidden volume is built so its presence cannot be proven from the volume itself. Stillroom''s decoy does not fool someone who has one password and a copy of the vault folder.'
  - q: 'Can Stillroom Vault encrypt a USB drive or my whole disk?'
    a: 'No. Stillroom keeps its vault in one folder on your Mac. For a whole Mac, use FileVault; for an external drive, Disk Utility can encrypt it, or use VeraCrypt if it has to open on other systems.'
sources:
  - label: 'VeraCrypt: home page'
    url: 'https://veracrypt.io/en/Home.html'
  - label: 'VeraCrypt: Hidden volume'
    url: 'https://veracrypt.io/en/Hidden%20Volume.html'
  - label: 'VeraCrypt: Downloads'
    url: 'https://veracrypt.io/en/Downloads.html'
  - label: 'Apple: Encrypt and protect a storage device with Disk Utility'
    url: 'https://support.apple.com/guide/disk-utility/encrypt-a-disk-dskutl35612/mac'
  - label: 'Apple: Protect data on your Mac with FileVault'
    url: 'https://support.apple.com/guide/mac-help/mh11785/mac'
---

## What VeraCrypt is, and who it suits

VeraCrypt is free, open source disk encryption for Windows, macOS and Linux, based on TrueCrypt 7.1a. It does three things:

- **File containers:** an encrypted volume inside one file, which you mount as a drive.
- **Partitions and devices:** a whole partition, USB stick or external disk.
- **System encryption:** the drive Windows runs from, with a password before it starts.

Encryption is real time and transparent: once a volume is mounted, every app reads and writes it like any other disk. VeraCrypt also offers hidden volumes, a second volume tucked inside the free space of another.

It suits people who move encrypted drives between Windows, Mac and Linux machines, who need to encrypt a USB stick or an external disk, or who want an established, open source tool they can inspect. On a Mac, VeraCrypt needs a FUSE layer installed alongside it (macFUSE or FUSE-T), and its download page recommends the FUSE-T version on Apple silicon.

## Side by side

| What | VeraCrypt | Stillroom Vault |
|---|---|---|
| Where data lives | A container file, a partition or a whole drive, wherever you put it | One folder on your Mac |
| Encryption | Whole volumes, encrypted in real time | AES-256-GCM, a fresh key per item; Argon2id (512 MB) for the password |
| Platforms | Windows, macOS (with macFUSE or FUSE-T), Linux | Apple silicon Macs, macOS 26 or later |
| Price | Free | Free for 25 items; $39 once; Family $129 for 5 people |
| Source | Open source | Source available (FSL); the reader script is MIT |
| Cloud and sync | None built in; you can copy a container anywhere | None; it never goes online |
| Scope | Volumes and drives | Files, notes, passwords and two-factor codes |

## Where VeraCrypt is the better choice

- **You use more than one operating system.** A VeraCrypt volume opens on Windows, Mac and Linux. Stillroom runs only on Apple silicon Macs.
- **You need to encrypt a drive.** VeraCrypt can encrypt a USB stick, an external disk or a partition. Stillroom can't. (On a Mac, Disk Utility can also encrypt an external drive with a password, and FileVault protects the startup disk; both come with macOS.)
- **You want every app to work on the files directly.** A mounted volume is an ordinary disk, so apps open and save files in it with no extra step.
- **You need hidden volumes.** VeraCrypt's documentation describes a hidden volume's header as indistinguishable from random data, and the outer volume's free space as random from the start, so the hidden volume's presence can't be proven, provided you follow its precautions. Stillroom's decoy is a different, weaker design, described below.
- **Free and open source matter most.** VeraCrypt costs nothing, and its code is open source.

## Where Stillroom Vault fits better

Stillroom is a better fit when what you want is a place to keep things, not a drive to manage:

- **One app for files, notes and passwords.** Secrets are records with fields, two-factor codes show live under any secret holding a setup key, and there are folders, tags, earlier versions and a search index that is itself sealed.
- **No mounted volume to forget.** A mounted volume is readable by any app until you dismount it. Stillroom locks on its own after a while, when the Mac sleeps, or with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> from any app, and every window is [hidden from screen capture](/features/hidden-from-capture/).
- **Viewing doesn't write a decrypted copy to disk.** Built-in viewers handle PDFs, images, text, sketches and email, audio and video stream from the sealed file, and other previews go to a RAM disk. Edit in Place uses the RAM disk too, though the app you edit in may keep copies of its own; Stillroom warns about this.
- **More ways back in.** A recovery key, a printable [emergency kit](/features/emergency-kit/) split into pieces, Touch ID, and optional [Lock to this Mac](/features/lock-to-this-mac/). There's also an [intruder log](/features/intruder-log/).
- **No extra system software.** Stillroom doesn't install a file system extension.

### The decoy is not a hidden volume

Stillroom's [decoy password](/features/decoy-password/) opens a second, harmless vault, and on disk the two are built alike. It fools someone at the keyboard, or someone with a copy of the folder and no password. It does **not** fool someone with one password and a copy of the folder: they can see the other vault holds something, though not what. Copies taken at different times also show when a vault's ways in changed. It's protection against thieves and abusers, not police. [Security rule 2](/security/#rules) has the details, and [plausible deniability](/learn/plausible-deniability/) explains the difference.

Also worth knowing: VeraCrypt has a long public history. Stillroom hasn't had an independent security audit yet; one is planned. Its [file format is public](/format/), and a short MIT-licensed Python script opens a vault without the app.

## Using both, or moving over

They work well together. Use VeraCrypt for a drive you carry between computers, and Stillroom for what stays on your Mac. FileVault should be on either way: Stillroom warns when it's off.

To move files from a VeraCrypt volume into Stillroom:

1. Mount the volume in VeraCrypt.
2. Drag the files or folders into Stillroom's window. Folders keep their structure.
3. Open a few items in Stillroom to check them.
4. Dismount the volume, and keep or delete the container as you choose.

Stillroom can delete originals after reading each copy back and checking it by SHA-256. Inside a mounted volume, that deletes them from the volume, so only allow it when you mean to. The [moving from VeraCrypt](/moving-from/veracrypt/) guide has the details.

Stillroom can't recover a forgotten password, and nobody can. Make your recovery key and kit before you move anything important.
