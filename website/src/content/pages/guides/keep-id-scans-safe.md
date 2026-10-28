---
title: 'How to Keep Passport and ID Scans Safe on a Mac'
description: 'Where to keep passport, ID, contract and tax scans on a Mac: locked notes, encrypted disk images, FileVault, or a vault, and what each protects.'
h1: 'How to keep ID scans safe on your Mac'
lead: 'Scans of passports, ID cards, contracts and tax returns are what an identity thief wants most. They often end up in Downloads or an old email. Here is how to keep them somewhere better, with what your Mac already has and what a vault adds.'
name: 'Keep ID scans safe'
updated: '27 October 2026'
order: 40
related: ['/guides/encrypt-files-on-mac/', '/compare/apple-notes-locked-notes/', '/features/emergency-kit/', '/for/travellers/']
faq:
  - q: 'Is it safe to keep a passport scan in Apple Notes?'
    a: 'A locked note can hold scanned documents and images, and only opens with its password or Touch ID. Apple says a note with a PDF or other document attached cannot be locked, so a passport PDF from email has to go somewhere else.'
  - q: 'Should I delete ID scans from my email?'
    a: 'If you have a safe copy elsewhere, yes. A scan left in sent mail or downloads is protected only by that account and that folder, and is easy to forget about.'
  - q: 'What if I lose access to the place I keep my ID scans?'
    a: 'Plan for it before you need it. FileVault, Notes, disk images and Stillroom all lose your data if you forget the password and have no recovery key, so keep the recovery key or kit somewhere separate.'
sources:
  - label: 'Apple: Lock your notes on Mac'
    url: 'https://support.apple.com/guide/notes/not28c5f5468/mac'
  - label: 'Apple: Create a disk image using Disk Utility on Mac'
    url: 'https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac'
  - label: 'Apple: Password-protect a PDF in Preview on Mac'
    url: 'https://support.apple.com/guide/preview/prvw587dd90f/mac'
  - label: 'Apple: Protect data on your Mac with FileVault'
    url: 'https://support.apple.com/guide/mac-help/protect-data-on-your-mac-with-filevault-mh11785/mac'
---

## Start by finding the copies you already have

Before choosing where to keep these documents, find where they are now. Scans of IDs and paperwork tend to collect in a few places:

- **Downloads,** from every time you got one by email or from a website.
- **Desktop and Documents,** from scanning or exporting.
- **Mail attachments** you sent to a landlord, employer or accountant.
- **Photos,** if you took a picture of a card with your phone.
- **Messages** threads where you sent a picture of your passport.

Search Finder for "passport", "ID", "tax" and the names of your bank or accountant. Gather what you find in one folder. Once each document is safely in its new home, delete the scattered copies, and empty the Trash.

## Turn on FileVault first

[FileVault](/guides/encrypt-files-on-mac/) encrypts your whole disk so nothing can be read without your login password if the Mac is stolen. It is the base everything else sits on.

1. Choose **Apple menu > System Settings**, then **Privacy & Security**.
2. Click **FileVault** and turn it on.
3. Choose your iCloud account or a recovery key as the way back in, and keep any recovery key off the Mac.
4. Click **Continue**.

FileVault does not protect these files from someone using your Mac while you are logged in. For documents like these, add a second lock.

## Free ways to add a second lock

### Locked notes

Notes can lock a note behind your Mac login password or a separate Notes password, with Touch ID as a shortcut.

1. Open Notes and make a note for the document.
2. Add the scan or the photo of the card.
3. Click the **More** button near the search field, choose **Lock Note**, and enter your password.

Apple lists what a locked note can hold: tables, images, drawings, scanned documents, maps and web attachments. A note with a PDF, document, audio or video attached cannot be locked. So locked notes suit photos and scans made in Notes, but not the PDF contract your lawyer emailed you. Apple also says that if you forget a custom Notes password and Touch ID cannot unlock the note, the note cannot be opened, and Apple cannot help.

### An encrypted disk image

For any kind of file, put them in an encrypted disk image.

1. Open Disk Utility and choose **File > New Image > Blank Image**.
2. Give it a name, a size with room to grow, **APFS** as the format, and an option from the **Encryption** menu.
3. Enter a password twice, click **Choose**, and set **Image Format** to **read/write disk image**.
4. Click **Save**, then copy your documents into the image that opens, and eject it when you are done.

It holds anything and stays encrypted wherever you copy it, which makes it a reasonable thing to keep a backup of. While it is open, it is an ordinary drive.

### A password on one PDF

To send a scan to someone, add an open password in Preview: **File > Export**, then **Permissions**, then **Require Password To Open Document**. Send the password another way. This is for sharing one file, not for storing many.

## Keeping them in Stillroom Vault

[Stillroom Vault](/features/) was made for exactly these papers: the scans, contracts and records you would otherwise lock in a drawer.

- **Any file goes in,** PDFs included, sealed one by one with AES-256-GCM and its own key, under a password stretched with Argon2id.
- **You can scan straight in.** File > Import from iPhone or iPad uses Continuity Camera to scan documents or take a photo with your iPhone directly into the vault, so the scan never sits in Downloads.
- **You can read them without unpacking them.** PDFs and images open in Stillroom's own viewers. Quick Look previews go to a RAM disk, not your SSD.
- **Search covers names and contents,** from a word index that is itself encrypted. Tags, folders and earlier versions help you keep a passport and its renewal together.
- **Notes and secrets sit next to files,** so a passport number, a tax reference or a policy number can live beside the scan.
- **Someone you trust can help you get back in.** An [emergency kit](/features/emergency-kit/) splits a way in into printed pieces you hand out, so that an agreed number of them opens the vault. That suits family documents that someone else may one day need.
- **Encrypted backups** go to one file you keep, and you can export everything as plain files whenever you like.

What it does not do:

- **It cannot open the vault without your password, recovery key or kit.** Nobody can. Keep the recovery key away from the Mac.
- **Edit in Place opens a document in its own app,** which may keep a copy or remember the name. Use the built-in viewers for documents you only need to read.
- **It does not protect against malware with admin rights while the vault is open,** or a password someone can guess.
- **Its decoy password is not meant to mislead police, border officers or courts.** It is protection against thieves and abusers ([security rules](/security/#rules)).
- It has not had an independent audit yet, needs Apple silicon and macOS 26 or later, and is free for 25 items, then $39 once ([pricing](/pricing/)).

## Keep one copy somewhere else

Whatever you choose, a single copy on one Mac is lost if that Mac fails. Keep a second, still encrypted, copy: a disk image on an external drive, or a Stillroom backup file on a drive you keep elsewhere. Write down how you will get back in, and keep that note somewhere other than with the Mac.
