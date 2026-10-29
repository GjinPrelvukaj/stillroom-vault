---
title: 'How to Hide Photos on a Mac (and Lock Them)'
description: 'Hide photos on a Mac with the Photos Hidden album and its lock, what that lock really keeps out, and how to keep private photos encrypted instead.'
h1: 'How to hide photos on a Mac'
lead: 'Photos has a Hidden album that locks with Touch ID or your password. It is quick and free. Here is how to use it, what it keeps out, and when to put photos in an encrypted vault instead.'
name: 'Hide photos on a Mac'
updated: '27 October 2026'
order: 30
related: ['/guides/secure-a-shared-mac/', '/features/view-without-decrypting/', '/features/hidden-from-capture/', '/guides/encrypt-files-on-mac/']
faq:
  - q: 'Where is the Hidden album on a Mac?'
    a: 'In Photos, click Library in the sidebar and choose View > Show Hidden Photo Album. Hidden then appears in the sidebar under Utilities. By default the album is hidden and locked.'
  - q: 'How do I hide other files on a Mac, not just photos?'
    a: 'Finder can hide a file, but anyone can show hidden files again with Command Shift period, so hiding is not locking. To keep files private, put them in an encrypted disk image, or in a vault app such as Stillroom Vault.'
  - q: 'Are hidden photos deleted?'
    a: 'No. Apple says hidden photos disappear from view but stay in your library. You can unhide them at any time.'
  - q: 'If I hide a photo on my Mac, is it hidden on my iPhone too?'
    a: 'If you use iCloud Photos, yes. Apple says photos you hide on one device are hidden on your other devices too.'
  - q: 'Can someone else on my Mac open my Hidden album?'
    a: 'The lock asks for Touch ID or your password. Anyone who knows your Mac login password, or is at your Mac while it is unlocked, can get past it.'
sources:
  - label: 'Apple: Hide photos from view in Photos on Mac'
    url: 'https://support.apple.com/guide/photos/phtf86b69c24/mac'
  - label: 'Apple: Hide photos with the Hidden album'
    url: 'https://support.apple.com/en-us/104987'
  - label: 'Apple: Set up users, guests and groups on Mac'
    url: 'https://support.apple.com/guide/mac-help/set-up-users-guests-and-groups-mtusr001/mac'
---

## Hide photos with the Photos Hidden album

The Photos app can move photos out of your library view and into a Hidden album. Apple says that in macOS Ventura and later the Hidden album is locked by default and needs Touch ID or your password to open.

To hide photos:

1. Open Photos and click **Library** in the sidebar.
2. Select the photos you want to hide.
3. Choose **Image > Hide [number] Photos**, then click **Hide**. You can also Control-click a photo and choose **Hide Photo**, or press <kbd>Command</kbd> <kbd>L</kbd>.

Apple says the photos disappear from view but are not deleted.

To see them again:

1. Click **Library**, then choose **View > Show Hidden Photo Album**.
2. Click **Hidden** under Utilities in the sidebar. If you do not see it, hold the pointer over Utilities and click the arrow.
3. If the album is locked, click **View Album** and unlock it with Touch ID or your password.
4. To unhide a photo, Control-click it and choose **Unhide [number] Photos**.

To take the album out of the sidebar again, choose **View > Hide Hidden Photo Album**. Apple notes you can turn the lock requirement off in Photos settings, so check it is still on if someone else set up the Mac.

## What the Hidden album protects, and what it doesn't

The Hidden album is a privacy screen. It is good at one thing: stopping a photo from popping up while you scroll your library in front of someone, or while someone browses Photos on your Mac without your password.

It is not a separate lock:

- **It opens with your Mac login password or Touch ID.** Anyone who knows your login password, or uses your Mac while you are logged in and walk away, can open it.
- **The photos are still in your Photos library,** in your account, protected by the same things as the rest of your files (your login and FileVault). Hiding is not extra encryption that Apple documents.
- **With iCloud Photos, hiding syncs.** Apple says a photo hidden on one device is hidden on your others. That also means the photos are in iCloud like the rest of your library.
- **A photo you exported, emailed or saved elsewhere is not hidden.** Only the copy inside Photos is.

For most people, the Hidden album plus a strong login password, FileVault and a lock screen that comes on quickly is enough. If you share the Mac, give each person their [own user account](/guides/secure-a-shared-mac/), so each person has their own files and settings.

## Keep private photos in an encrypted vault instead

If you want photos behind a password nobody else on the Mac knows, or kept out of iCloud entirely, you need them outside Photos and encrypted. A free way is an encrypted disk image (see [how to encrypt files on a Mac](/guides/encrypt-files-on-mac/)). It works, but while it is open the photos are ordinary files, and the image stays open until you eject it.

[Stillroom Vault](/features/) is made for private files you still want to look at.

- **Photos are sealed one by one** with AES-256-GCM and their own key, in a vault on your Mac with its own password (not your login password). Nothing is uploaded: Stillroom has no server, no account and no sync, and never goes online.
- **You view them inside the app.** Images, PDFs and videos open in Stillroom's own viewers, and video plays straight from the sealed file. Anything shown through Quick Look goes to a RAM disk, not your SSD. See [view without decrypting](/features/view-without-decrypting/).
- **Its windows are hidden from screen capture,** so a screen recording or screenshot tool does not pick them up. See [hidden from capture](/features/hidden-from-capture/).
- **It locks itself** after a set time, when the Mac sleeps, or with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd>, which locks and hides it from any app.
- **You can add photos straight from your iPhone.** File > Import from iPhone or iPad uses Continuity Camera to take a photo or scan a document directly into the vault.
- **You can drag photos in from Finder,** and once each copy is read back and checked, Stillroom can delete the originals.

What it does not do:

- **Photos already in your Photos library stay there** until you delete them from Photos (and from Recently Deleted). Stillroom does not reach into Photos.
- **Previewing a file can leave its name in other places,** such as Quick Look's thumbnail cache or Recent Items, though not its contents. The [security page](/security/#rules) has the details.
- **Someone with a copy of the vault folder can see how many items it holds and their rough sizes,** but not names or contents.
- **A forgotten password cannot be recovered** by anyone. Keep the recovery key Stillroom makes with the vault.
- It needs Apple silicon and macOS 26 or later. It is free for 25 items, then $39 once ([pricing](/pricing/)).

## Which to choose

- **You just don't want certain photos showing up while you scroll:** the Hidden album is built for that.
- **Other people know your Mac password, or you want photos off iCloud:** keep them in an encrypted disk image or a vault with its own password.
- **You look at them often and want them to lock themselves:** a vault app such as Stillroom, on top of FileVault.
