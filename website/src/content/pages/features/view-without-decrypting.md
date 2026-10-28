---
title: 'View Files Without Decrypting Them to Disk'
description: 'How Stillroom shows PDFs, photos, email, audio and video without writing a decrypted copy to your SSD, and what Edit in Place can still leave behind.'
h1: 'View without decrypting to disk'
lead: 'Open a PDF, a photo or a video inside your vault, and the readable copy stays in memory or on a RAM disk. Here''s what that covers, and where the edges are.'
name: 'View without decrypting'
updated: '27 October 2026'
order: 70
related: ['/guides/encrypt-files-on-mac/', '/guides/hide-photos-on-mac/', '/compare/encrypted-disk-image/', '/features/hidden-from-capture/']
faq:
  - q: 'Does opening a file in Stillroom leave a decrypted copy on my Mac?'
    a: 'Not on the SSD. Built-in viewers work from memory, and Quick Look and Edit in Place copies go to a RAM disk that is ejected on lock. The one exception is an edit too big for the RAM disk, which goes to a FileVault-protected cache folder and is deleted afterwards.'
  - q: 'Can other apps keep copies when I use Edit in Place?'
    a: 'Yes. While a document is open in its own app, that app can read it, and it may keep its name in Recent Items or copies of its own outside the vault. Stillroom warns you before the first Edit in Place.'
  - q: 'Can I play a video without decrypting the whole file?'
    a: 'Yes. Audio and video are stored in chunks and play straight from the sealed file, a range at a time.'
  - q: 'Why can''t I use Edit in Place on some files?'
    a: 'Edit in Place opens only documents. Programs, scripts, installers, disk images, packages, web pages and sketches are excluded, because opening them in another app could run code or reach the network.'
---

## What it is

Many ways of encrypting files on a Mac work by unlocking a whole container: you mount an encrypted disk image, or decrypt a file to a folder, and the readable version sits on your SSD until you lock it again or delete it. Deleted data on an SSD isn't reliably gone, so those copies can linger.

Stillroom's first rule is that **plaintext never lands on the SSD**. When you look at an item, the readable copy stays in memory, or on a RAM disk that Stillroom makes and ejects. You can read, watch and listen to what's in your vault without leaving decrypted copies behind.

## What opens where

- **PDFs, images, sketches, plain text and email** (`.eml` and `.emlx`) open in Stillroom's own viewers, inside the vault window, from memory.
- **Audio and video** play straight from the sealed file. They're stored in a chunked format, and the player decrypts only the range it's playing.
- **Everything else** opens in Quick Look. The copy Quick Look needs goes to the RAM disk, and Quick Look copies never fall back to the SSD.
- **Two-factor codes** show live under any secret holding an `otpauth` link or setup key.

### Email is locked down

Email is the one viewer that uses a web view, so it's locked down three ways at once: JavaScript off and links cancelled, a Content Security Policy that allows only `data:`, and a WebKit block list that allows only `data:` and `about:`. An email is never shown without the block list. A test loads an email with every kind of remote load (images, stylesheets, fonts, frames, scripts, preconnect and more) aimed at a server on the Mac, and fails on any connection. So a stored email can't load a tracking image when you open it.

## When you'd use it

- You keep scans of IDs, contracts or medical letters and want to look at them now and then without exporting them.
- You keep private photos or recordings and want to view them without a decrypted folder sitting on disk.
- You save emails as evidence or records and want to read them without anything loading from the internet.

## Edit in Place

Sometimes you need to change a document in its own app. **Edit in Place** opens it from a copy on the RAM disk, and every save comes back encrypted into the vault.

Choose **Edit in Place** from an item's menu or its preview. The first time, Stillroom warns you about what it gives away, with an option not to ask again. That warning is worth reading, because Edit in Place is where the guarantee gets weaker:

- **The other app can read the document** while it's open, and may keep its name in Recent Items, and copies of its own (autosaves, caches, thumbnails) outside the vault. Stillroom can't control that.
- **An edit too big for the RAM disk** (1 GiB of free space by default) goes to a private folder in `~/Library/Caches/app.gjin.stillroom/DeskOverflow` instead. That's on the SSD, protected only by FileVault, and deleted afterwards. It's the one case where a decrypted copy touches the SSD.
- **Only documents are allowed.** Both the stored type and the file extension must pass an allowlist: no programs, scripts, installers, disk images, packages, web pages or sketches. Web pages are excluded because they'd open in a browser that runs their scripts and loads from the network.

If you only want to look at a file, open it in Stillroom instead.

## How it works underneath

- The RAM disk is made with macOS's own `hdiutil`, mounted hidden from Finder, and copies on it sit at random paths. Mounting and ejecting happen off the main thread. Previews keep the disk mounted until you lock, and locking ejects it.
- If the vault locks while an open is waiting for the RAM disk, nothing is written.
- Items over 8 MB, and all audio and video, use a chunked format (VLT2). Each chunk is sealed with the item's own key and bound to its position, so chunks can't be reordered, dropped, duplicated or swapped between files. [The format page](/format/) has the details.
- Anything you take out of the vault (Save a Copy, attachments, Export Everything) is quarantined, so a downloaded program that came out of the vault still gets checked by Gatekeeper before it runs.

## Limits

- **Memory isn't wiped perfectly.** Decrypted contents sit in ordinary memory while they're shown. macOS encrypts swap, but Stillroom can't keep memory pages out of it. Malware with admin rights on an open vault can see everything.
- **Other apps remember names.** Recent Items and Quick Look's thumbnail cache can keep names from Edit in Place and previews. If a name matters, avoid Edit in Place for it, or clear Recent Items afterwards.
- **FileVault still matters.** It protects the overflow folder and makes deleted data unreadable. Stillroom warns when it's off. See [encrypt files on a Mac](/guides/encrypt-files-on-mac/).
- **Exporting means plain files.** Export Everything writes normal, readable files where you choose. Pick a disk you control and delete the copy when you're done.

These viewers are in every tier of Stillroom, the free one included.
