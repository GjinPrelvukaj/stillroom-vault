---
title: 'How to Encrypt Files on a Mac: Free and Paid Ways'
description: 'Encrypt files on a Mac with FileVault, an encrypted disk image or a password-protected PDF, and see what each one protects before you choose.'
h1: 'How to encrypt files on a Mac'
lead: 'Your Mac already has three ways to encrypt files, each for a different job. Here is how to use them, where each stops, and what a vault app adds.'
name: 'Encrypt files on a Mac'
updated: '27 October 2026'
order: 20
related: ['/guides/password-protect-a-folder-on-mac/', '/compare/encrypted-disk-image/', '/learn/aes-256-gcm/', '/compare/cryptomator/']
faq:
  - q: 'Are files on a Mac encrypted by default?'
    a: 'On Macs with Apple silicon or a T2 chip, Apple says data on the disk is already encrypted. FileVault adds the requirement for your login password before it can be decrypted, which is what protects it if the Mac is stolen.'
  - q: 'Can I encrypt a single file in Finder?'
    a: 'No. Finder has no encrypt command. Use an encrypted disk image for any kind of file, or Preview to put an open password on a PDF.'
  - q: 'Do encrypted files stay encrypted when I email or copy them?'
    a: 'An encrypted disk image and a password-protected PDF stay encrypted wherever you copy them. Files protected only by FileVault are decrypted as soon as they leave the Mac, for example as an attachment or on a USB drive.'
  - q: 'Can Stillroom Vault recover a file if I forget my password?'
    a: 'No. Without your password, recovery key or emergency kit, nobody can open the vault, including us.'
sources:
  - label: 'Apple: Protect data on your Mac with FileVault'
    url: 'https://support.apple.com/guide/mac-help/protect-data-on-your-mac-with-filevault-mh11785/mac'
  - label: 'Apple: Create a disk image using Disk Utility on Mac'
    url: 'https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac'
  - label: 'Apple: Password-protect a PDF in Preview on Mac'
    url: 'https://support.apple.com/guide/preview/prvw587dd90f/mac'
---

## Three jobs, three tools

"Encrypt my files" usually means one of these:

| You want to | Built-in tool | Protects |
| --- | --- | --- |
| Keep everything safe if the Mac is lost | FileVault | The whole disk, while you are logged out |
| Lock a set of files behind their own password | Encrypted disk image | Those files, until you open the image |
| Send one document that only the recipient can open | Password-protected PDF | That PDF, wherever it goes |

They work well together. Start with FileVault, then add one of the others for the files that need a second lock.

## FileVault: the whole disk

On a Mac with Apple silicon or a T2 chip, Apple says your data is already encrypted. FileVault adds the part that matters if someone takes the Mac: the data cannot be decrypted without your login password.

1. Choose **Apple menu > System Settings**, then click **Privacy & Security**.
2. Click **FileVault** (you may need to scroll down), and turn it on. You may be asked for your password.
3. Choose how you will get back in if you forget your password: let your iCloud account unlock the disk, or create a recovery key.
4. If you chose a recovery key, write it down and keep it somewhere other than the Mac.
5. Click **Continue**. If you see **Enable Users**, enable each person who uses the Mac.

**What it does not do:** once you log in, your files are open to anyone at the keyboard and to every app you run. And files you copy off the Mac (to a USB drive, an email, a cloud folder) leave unencrypted. Apple also warns that if you lose both your login password and your recovery key, your files are lost for good.

## An encrypted disk image: a locked container

Disk Utility makes a `.dmg` file that opens only with a password. It holds any kind of file, and it stays encrypted when you copy it elsewhere.

1. Open Disk Utility and choose **File > New Image > Blank Image**.
2. Name the file, choose where to save it, and type a **Name** and a **Size**.
3. Set **Format** to **APFS** and choose an option from the **Encryption** menu.
4. Enter a password twice, then click **Choose**.
5. Set **Image Format** to **read/write disk image**, then click **Save** and **Done**.
6. Copy your files into the image that opens in Finder, then eject it to lock it.

To turn an existing folder into an image instead, use **File > New Image > Image from Folder** and choose an option from the Encryption menu there. Its read-only formats cannot be changed later. The [folder guide](/guides/password-protect-a-folder-on-mac/) has every step.

**What it does not do:** while the image is mounted, it is an ordinary drive, open to anything on the Mac. If you forget its password, Apple says you will not be able to open it. Files you open from it can also leave traces elsewhere, such as an app's recent files list.

## A password-protected PDF: one document to share

For a single document you need to send, Preview can add an open password.

1. Open the PDF in Preview and choose **File > Export**.
2. Click **Permissions**, then select **Require Password To Open Document**.
3. Enter the password and retype it.
4. Click **Apply**, then **Save**.

Send the password a different way from the file (a phone call, a different app). This suits sharing, not storage: you get one password per file, and nothing locks again on its own once it is open.

## When a vault app makes more sense

If you have many files that need their own lock, and you look at them often, the built-in tools start to ask a lot of you: remember to eject, keep the image big enough, watch where opened copies go. [Stillroom Vault](/features/) is built for that.

- **Each item is encrypted on its own,** with [AES-256-GCM](/learn/aes-256-gcm/) and a fresh random key, inside one vault on your Mac. Your password is stretched with [Argon2id](/learn/argon2id/) (512 MB, 3 passes, 4 lanes), so each guess costs an attacker real time.
- **It locks on its own:** after a set time, when the Mac sleeps, or with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> from any app.
- **Viewing does not unpack files to your SSD.** Built-in viewers show PDFs, images, text and email, and play audio and video straight from the sealed file. Quick Look previews and Edit in Place copies go to a RAM disk.
- **It keeps notes, passwords and two-factor codes** next to files, and earlier versions of each item.
- **It never goes online.** There is no account, server or sync, and the build fails if the app links networking code.
- **You are not locked in.** Export everything as plain files at any time, and the [format is public](/format/), with a short Python script that reads a vault without the app.

Its limits, stated plainly:

- **Edit in Place opens a document in its own app,** and that app may keep its own copy or remember the name. Stillroom warns you when you use it.
- **It does not protect against malware with admin rights while the vault is open,** or against a password someone can guess.
- **Someone with a copy of the vault folder can see how many items it holds and roughly how big each is,** but not names, folders or contents. See [what still shows on disk](/security/).
- **It cannot recover a forgotten password.** Nobody can. Keep the recovery key it gives you.
- It has not had an independent security audit yet. It needs Apple silicon and macOS 26 or later, and is free for 25 items, then $39 once ([pricing](/pricing/)).

## Which to use

- **Everyone:** turn on FileVault.
- **A few files you open now and then:** an encrypted disk image is free and solid.
- **One document to send:** a password-protected PDF.
- **Many private files you use often:** a vault app such as Stillroom, on top of FileVault, not instead of it.
