---
title: 'How to Hide Files on a Mac (and Actually Lock Them)'
description: 'Hide files on a Mac with chflags in Terminal, hide desktop icons and keep folders out of Spotlight, then lock what matters with encryption.'
h1: 'How to hide files on a Mac'
lead: 'To hide a file on a Mac, run chflags hidden on it in Terminal. Anyone can show it again with Command Shift period in Finder, though, so hiding is not locking. Here is how to hide files, desktop icons and search results, and how to lock the files that matter.'
name: 'Hide files on a Mac'
updated: '30 October 2026'
order: 12
points:
  - '**Hiding** keeps a file out of sight in Finder. Command Shift period shows it again.'
  - '**Spotlight''s Search Privacy list** keeps a folder out of search results.'
  - '**Locking** means encryption: an encrypted disk image, or a vault app.'
related: ['/guides/password-protect-a-folder-on-mac/', '/guides/encrypt-files-on-mac/', '/guides/hide-photos-on-mac/', '/guides/secure-a-shared-mac/', '/compare/encrypted-disk-image/']
faq:
  - q: 'How do I hide a file on a Mac without Terminal?'
    a: 'Finder has no Hide command for a single file. You can hide everything on the desktop with the Show Items setting in System Settings > Desktop & Dock, or keep a folder out of search results with Spotlight''s Search Privacy list. To hide one file or folder in Finder, use chflags hidden in Terminal.'
  - q: 'What is the keyboard shortcut to show hidden files on a Mac?'
    a: 'In a Finder window, press Command Shift period. Hidden files and folders appear dimmed. Press the same keys again to hide them.'
  - q: 'Are hidden files on a Mac secure?'
    a: 'No. A hidden file is an ordinary file with a flag that tells Finder not to show it. Anyone at your Mac can show it with one shortcut, and it is still listed in Terminal. To keep a file private, encrypt it.'
  - q: 'How do I unhide a file I hid with chflags?'
    a: 'In Terminal, type chflags nohidden, a space, then drag the file or folder into the Terminal window and press Return. If you cannot find it in Finder, press Command Shift period first so it shows.'
  - q: 'Does hiding desktop icons delete them?'
    a: 'No. Turning off Show Items On Desktop only stops them being drawn on the desktop. Apple says you can click the desktop to show them, and they are still in your Desktop folder in Finder.'
sources:
  - label: 'chflags(1) man page (ss64)'
    url: 'https://ss64.com/mac/chflags.html'
  - label: 'TidBITS: Reveal invisible files on the Mac with a keystroke'
    url: 'https://tidbits.com/2018/05/16/tipbits-reveal-invisible-files-on-the-mac-with-a-keystroke/'
  - label: 'Apple: Change Desktop & Dock settings on Mac (macOS Tahoe)'
    url: 'https://support.apple.com/guide/mac-help/mchlp1119/26/mac'
  - label: 'Apple: Prevent Spotlight searches in files on Mac (macOS Tahoe)'
    url: 'https://support.apple.com/guide/mac-help/mchl1bb43b84/26/mac'
  - label: 'Apple: Create a disk image using Disk Utility on Mac'
    url: 'https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac'
---

## Hiding is not locking

macOS can hide a file from Finder, but a hidden file is still an ordinary file. It opens for anyone who finds it, and finding it takes one shortcut. That is fine when you only want a tidier screen, or less chance of someone stumbling on a folder while they look over your shoulder.

If you want a file nobody else can open, you need encryption. The last two sections cover that.

## Hide a file or folder with Terminal

Finder has no Hide command, but every file on a Mac can carry a **hidden** flag that tells Finder not to show it. You set it with `chflags` in Terminal.

1. Open Terminal (in Applications, Utilities).
2. Type `chflags hidden` followed by a space. Don't press Return yet.
3. Drag the file or folder from Finder into the Terminal window. Its path appears after the command.
4. Press <kbd>Return</kbd>. The item disappears from Finder.

The whole command looks like this:

```
chflags hidden ~/Documents/Private
```

To show it again, use `nohidden` instead:

```
chflags nohidden ~/Documents/Private
```

If you have hidden it and can't drag it any more, type its path by hand, or show hidden files first (next section).

## Show hidden files with a keyboard shortcut

In any Finder window, press <kbd>Command</kbd> <kbd>Shift</kbd> <kbd>.</kbd> (period). Hidden files and folders appear, dimmed so you can tell them apart. Press the same keys again to hide them.

This is the reason hiding is not a lock. Anyone who uses your Mac can press it, and the shortcut is widely known. Terminal's `ls -a` lists hidden files too, and so does any app that browses the disk.

## Hide everything on your desktop

If you want a clean desktop for a screen share or a presentation, you don't need to hide files one by one. macOS has a setting for it:

1. Choose **Apple menu > System Settings**, then click **Desktop & Dock** in the sidebar.
2. Scroll to **Desktop & Stage Manager**.
3. Next to **Show Items**, turn off **On Desktop**. (**In Stage Manager** does the same while Stage Manager is on.)

Apple says that with this off, desktop items are hidden, and clicking the desktop shows them. They are still in your Desktop folder in Finder, and nothing is deleted. Turn **On Desktop** back on to see them again.

## Keep a folder out of Spotlight

A file you hid from Finder can still turn up when someone searches. Spotlight has its own list of places to leave out:

1. Open **System Settings** and click **Spotlight** in the sidebar (you may need to scroll down).
2. Click **Search Privacy** in the lower right.
3. Click the **Add** button and choose the folder or disk, or drag it into the list.

To bring it back into search, select it in the list and click **Remove**. Apple notes that excluding some folders may stop you being told about some app updates, so leave out only what you need to.

Like the hidden flag, this hides; it does not lock. The folder still opens for anyone who goes to it in Finder.

## What hiding does well, and what it doesn't

**Good for:**

- Keeping clutter, or a surprise, out of sight on a Mac you share with people you trust.
- A clean screen for meetings and screen recordings.
- Keeping a folder from appearing in Spotlight while someone types a search on your Mac.

**Not good for:**

- **Keeping anyone out.** <kbd>Command</kbd> <kbd>Shift</kbd> <kbd>.</kbd> shows everything.
- **Copies.** A hidden file copied to a USB drive, a cloud folder or an email is just a file.
- **A stolen Mac.** Without FileVault, someone with the disk can read every file, hidden or not.

Ticking **Locked** in a file's Get Info window does not help either. It only stops the file being changed or deleted by accident; anyone can still open it.

## Actually lock files: an encrypted disk image

The free, built-in way to lock files on a Mac is an encrypted disk image. Disk Utility makes a `.dmg` file that opens only with its password. While it is open it shows in Finder like a drive; when you eject it, everything inside is locked again.

1. Open Disk Utility and choose **File > New Image > Blank Image**.
2. Name it, choose where to save it, and set a **Size** with room to grow.
3. Set **Format** to **APFS**, choose an option from the **Encryption** menu, and enter a password twice.
4. Set **Image Format** to **read/write disk image**, then click **Save**.
5. Move your private files into the open image, then eject it.

The [folder guide](/guides/password-protect-a-folder-on-mac/) has every step and what to watch for. In short: while the image is mounted it is open to anyone at your keyboard, and if you forget the password, Apple says you will not be able to open it.

Turn on FileVault too (**System Settings > Privacy & Security > FileVault**), so the rest of the disk is protected if the Mac is lost. See [how to encrypt files on a Mac](/guides/encrypt-files-on-mac/) for how the built-in tools fit together.

## Where Stillroom Vault fits

[Stillroom Vault](/features/) is for the files you would otherwise hide: things you look at often and want locked every time you walk away, not just out of sight.

- **Everything is encrypted, not hidden.** Each item is sealed on its own with AES-256-GCM and a fresh key, under a password stretched with [Argon2id](/learn/argon2id/). Names, folders and contents do not show on disk.
- **It locks itself** after a time you choose, when the Mac sleeps, and when you press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd>, which locks and hides it from any app. There is no drive left mounted.
- **You view files inside the app.** PDFs, images, text, email, audio and video open in Stillroom's own viewers; Quick Look previews go to a RAM disk, not your SSD.
- **Its windows are hidden from screen capture,** so a screenshot or screen share does not pick them up.
- **You can drag whole folders in.** Stillroom reads each copy back and checks it before it offers to delete the original.
- **It never goes online.** No account, no server, no sync.

What it does not do:

- **It cannot open the vault if you lose every way in.** Keep the recovery key it makes.
- **It does not protect against malware with admin rights while the vault is open,** or a password someone can guess.
- **Someone with a copy of the vault folder can see how many items it holds and their rough sizes,** but not names or contents.
- It needs Apple silicon and macOS 26 or later. It is free for 25 items, then $39 once ([pricing](/pricing/)). No independent security audit has been done yet; the [format is public](/format/).

If you only want a tidy desktop, hiding is enough. If you want files no one else can open, encrypt them: with a disk image if you open them now and then, or with Stillroom if you open them often.
