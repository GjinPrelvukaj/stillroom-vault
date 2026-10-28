---
title: 'How to Password Protect a Folder on a Mac'
description: 'macOS has no lock button for folders. Here are the free ways that work (an encrypted disk image, FileVault, your login) and what each one protects.'
h1: 'How to password protect a folder on a Mac'
lead: 'Finder has no "lock this folder with a password" button. macOS can still do it, with an encrypted disk image. Here is how, what it covers, and when a vault app fits better.'
name: 'Password protect a folder'
updated: '27 October 2026'
order: 10
related: ['/guides/encrypt-files-on-mac/', '/compare/encrypted-disk-image/', '/guides/secure-a-shared-mac/', '/learn/argon2id/']
faq:
  - q: 'Can I put a password on a folder in Finder?'
    a: 'No. Finder can change who may read a folder, but it has no password lock. The built-in way to put a password on a folder is to turn it into an encrypted disk image with Disk Utility.'
  - q: 'Is FileVault enough to protect a folder?'
    a: 'FileVault protects everything on the disk while the Mac is off or no one is logged in. Once you log in, every file in your account is readable by anyone at your keyboard, so it does not protect one folder from someone using your Mac.'
  - q: 'What happens if I forget the disk image password?'
    a: 'Apple says you will not be able to open the disk image. There is no reset, so keep the password somewhere safe.'
  - q: 'Does deleting the original folder after making the image remove it for good?'
    a: 'Emptying the Trash removes it from view. With FileVault on, what is left on the disk stays encrypted, so turn FileVault on before you rely on deleting originals.'
sources:
  - label: 'Apple: Create a disk image using Disk Utility on Mac'
    url: 'https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac'
  - label: 'Apple: Protect data on your Mac with FileVault'
    url: 'https://support.apple.com/guide/mac-help/protect-data-on-your-mac-with-filevault-mh11785/mac'
  - label: 'Apple: Change Lock Screen settings on Mac'
    url: 'https://support.apple.com/guide/mac-help/change-lock-screen-settings-mh11784/mac'
  - label: 'Apple: Mac keyboard shortcuts'
    url: 'https://support.apple.com/102650'
---

## First, what you want to protect against

"Password protect a folder" can mean two different things, and macOS answers them differently.

- **Someone who gets the Mac while it is off, or takes the disk out.** FileVault covers this for the whole disk.
- **Someone who sits down at your Mac while you are logged in,** or opens a copy of the folder somewhere else. FileVault does not help here, because once you log in your files are open. For this you need the folder itself to be encrypted under its own password.

Most people asking this question mean the second one. The free answer is an encrypted disk image.

## Put the folder in an encrypted disk image (free, built in)

Disk Utility can turn a folder into a single `.dmg` file that only opens with a password. When you open it, it appears in Finder like a drive; when you eject it, its contents are locked again.

Apple documents two ways to do it. The one that suits a folder you keep adding to is a blank, encrypted, read/write image:

1. Open Disk Utility (in Applications, Utilities).
2. Choose **File > New Image > Blank Image**.
3. Type a file name and choose where to save the image.
4. Type a name in the **Name** field (this is what Finder shows when it is open), and a size in the **Size** field. Leave room to grow.
5. From the **Format** menu, choose **APFS**.
6. From the **Encryption** menu, choose an encryption option.
7. Enter the password twice, then click **Choose**.
8. Set **Partitions** to **Single partition - GUID Partition Map** and **Image Format** to **read/write disk image**.
9. Click **Save**, then **Done**. Disk Utility opens the new image.
10. In Finder, copy your folder's contents into the open image.
11. When you are sure everything copied, move the original folder to the Trash and empty it.

To lock it again, eject the image in Finder. To open it, double-click the `.dmg` and type the password.

There is also **File > New Image > Image from Folder**, which makes an image straight from an existing folder. Its read-only formats cannot be changed after they are made, so use it for an archive rather than a folder you still work in.

### What an encrypted disk image does well

- It is free and already on your Mac.
- The `.dmg` is one file, so it is easy to back up or move, and it stays encrypted wherever you copy it.
- It holds any kind of file, and apps open the files normally while it is mounted.

### What it does not do

- **While it is open, it is just a drive.** Anyone at your keyboard, and any app you run, can read it until you eject it.
- **If you forget the password, the image is gone.** Apple says plainly that you will not be able to open it.
- **You pick its size up front,** so choose one with room to grow.

## Turn on FileVault and lock your screen as well

Whatever you do with the folder, two settings carry most of the weight.

**FileVault** encrypts the whole startup disk so nothing can be read without your login password. On Macs with Apple silicon your data is already encrypted, and FileVault adds the requirement for your password before it can be decrypted. To turn it on:

1. Choose **Apple menu > System Settings**, then click **Privacy & Security**.
2. Click **FileVault** (you may need to scroll), and turn it on.
3. Choose to let your iCloud account unlock the disk, or create a recovery key and keep it somewhere other than the Mac.
4. Click **Continue**.

**Your lock screen** decides how quickly the Mac asks for a password when you walk away. In **System Settings > Lock Screen**, set **Require password after screen saver begins or display is turned off** to a short time. Press <kbd>Control</kbd> <kbd>Command</kbd> <kbd>Q</kbd> to lock the screen at once.

## Where Stillroom Vault fits

[Stillroom Vault](/features/) is an app for the case a disk image handles awkwardly: a private folder you open often, on a Mac that is often unlocked.

- **It locks itself.** It locks after a time you choose, when the Mac sleeps, and when you press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> from any app, so there is no drive left mounted.
- **You can view without unpacking to disk.** PDFs, images, text, email, audio and video open inside the app. Anything shown through Quick Look or opened with Edit in Place goes to a RAM disk, not your SSD (the [security page](/security/#rules) has the exact rule and its limits).
- **Every item is sealed on its own,** with AES-256-GCM and a fresh key, under a password stretched with [Argon2id](/learn/argon2id/). Names, folders and contents do not show on disk.
- **You can drag a whole folder in.** Stillroom reads each copy back and checks it before it offers to delete the original. If FileVault is off, the originals go to the Trash instead, and Stillroom tells you.
- **There are more ways back in than one password:** a recovery key, and optionally an emergency kit and Touch ID.

What it does not change:

- **It cannot open the vault if you lose every way in.** Nobody can. Keep the recovery key somewhere safe.
- **It does not protect against malware with admin rights while the vault is open,** or against a weak password. The strength check refuses guessable ones.
- **Someone with a copy of the vault folder can see how many items it holds and their rough sizes,** though not names or contents.
- It needs a Mac with Apple silicon and macOS 26 or later. It is free for 25 items and $39 once for more ([pricing](/pricing/)). No independent security audit has been done yet; the [format is public](/format/) so anyone can check it.

If you only need to lock a folder now and then and are happy to eject it yourself, the encrypted disk image is a good, free answer. If you would rather it locked itself and did not leave copies around when you look inside, try Stillroom with your first 25 items.
