---
title: 'How to Password Protect a Zip File on a Mac'
description: 'Make an encrypted zip on a Mac with zip -e in Terminal, why its old encryption is weak, and the safer AES-256 options for files that matter.'
h1: 'How to password protect a zip file on a Mac'
lead: 'In Terminal, run zip -er archive.zip folder and type a password. That makes a password-protected zip with no extra app. Its encryption is old and weak, though. Here is how to do it, why it falls short, and what to use instead.'
name: 'Password protect a zip file'
updated: '30 October 2026'
order: 15
points:
  - '**`zip -e`** in Terminal adds a password, but uses legacy ZipCrypto, which has been broken since 1994.'
  - '**For real protection,** use an encrypted disk image, or a 7z archive with AES-256.'
  - '**Finder''s Compress** makes a zip with no password at all.'
related: ['/guides/encrypt-files-on-mac/', '/guides/password-protect-a-folder-on-mac/', '/compare/encrypted-disk-image/', '/learn/aes-256-gcm/', '/tools/passphrase-generator/']
faq:
  - q: 'Can I password protect a zip file on a Mac without an app?'
    a: 'Yes. In Terminal, type zip -er followed by a name for the archive and the folder to put in it, press Return, and enter the password twice. Finder''s Compress command cannot add a password.'
  - q: 'Is zip -e on a Mac secure?'
    a: 'Not very. It uses the original zip encryption, known as ZipCrypto, which the zip manual itself calls relatively weak. A known-plaintext attack against it was published in 1994. Use it to keep out a casual look, not to protect anything sensitive.'
  - q: 'How do I open a password-protected zip on a Mac?'
    a: 'Double-click it in Finder and type the password when asked, or run unzip archive.zip in Terminal. Zips made with zip -e open in almost any app on any system.'
  - q: 'What is the most secure way to send a folder from a Mac?'
    a: 'An archive encrypted with AES-256, such as a 7z file from 7-Zip or Keka, or an encrypted disk image if the other person has a Mac. Use a long password and send it a different way from the file.'
sources:
  - label: 'zip(1) manual page, Info-ZIP (man zip on macOS)'
    url: 'https://linux.die.net/man/1/zip'
  - label: 'Biham and Kocher: A Known Plaintext Attack on the PKZIP Stream Cipher (1994)'
    url: 'https://link.springer.com/chapter/10.1007/3-540-60590-8_12'
  - label: 'Keka: the macOS file archiver'
    url: 'https://keka.io/en'
  - label: 'Keka on GitHub: encrypting file names needs the 7z format'
    url: 'https://github.com/aonez/Keka/issues/592'
  - label: '7-Zip: Download'
    url: 'https://www.7-zip.org/download.html'
  - label: '7-Zip command line: method switches (-mhe)'
    url: 'https://7-zip.opensource.jp/chm/cmdline/switches/method.htm'
  - label: 'Apple: Create a disk image using Disk Utility on Mac'
    url: 'https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac'
---

## What a zip password is for

A password-protected zip is a way to send a few files in one package, so that only someone with the password can unpack them. Its strength is that almost everyone can open it, on any computer, without installing anything.

Its weakness is the encryption. The tool built into macOS uses the original zip scheme, which was broken decades ago. So the honest answer to "how do I encrypt a zip on a Mac" has two parts: the quick way, and the way to use when the contents matter.

## The quick way: zip -e in Terminal

Finder's **Compress** command makes a zip, but cannot add a password. Terminal's `zip` command can. The `-e` option asks for a password and encrypts the archive; `-r` includes everything inside a folder.

1. Open Terminal (in Applications, Utilities).
2. Go to the folder that holds what you want to zip. For something on your desktop, type `cd ~/Desktop` and press <kbd>Return</kbd>.
3. Type the command, with a name for the new archive first and the folder second:

   ```
   zip -er Private.zip "Tax 2026"
   ```

4. Enter a password when asked, and again to confirm. Nothing shows as you type; that is normal.
5. `Private.zip` appears in the same folder.

For a single file, leave out the `r`: `zip -e Letter.zip Letter.pdf`.

To open it, double-click it in Finder and enter the password, or run `unzip Private.zip` in Terminal.

### What zip -e does well

- It is already on your Mac and costs nothing.
- The zip opens almost anywhere: Windows, Linux and phones can all unpack it with the password.
- It keeps out someone who stumbles on the file and is not trying very hard.

### What it does not do

- **Its encryption is weak.** `zip -e` uses the original zip encryption, often called ZipCrypto or PKZIP encryption. The `zip` manual on your Mac calls it "relatively weak". In 1994 Eli Biham and Paul Kocher published a known-plaintext attack: if an attacker knows a small part of one file in the archive, they can recover the keys and unpack everything, whatever the password. Free tools do this today.
- **File names show without the password.** Anyone can list what is inside the zip, with names and sizes, before typing anything.
- **The originals stay where they were,** unprotected, until you delete them.

Use `zip -e` for things that would be a nuisance, not a disaster, if someone else read them.

## Safer: an encrypted disk image (free, built in)

If the person receiving the files has a Mac, or the files are staying with you, an encrypted disk image is the better built-in choice. Disk Utility makes a `.dmg` that opens only with its password.

1. Open Disk Utility and choose **File > New Image > Image from Folder**.
2. Select the folder and click **Open**.
3. Type a file name and choose where to save the image.
4. Choose an option from the **Encryption** menu and enter a password twice.
5. From the **Image Format** menu, choose a compressed, read-only format for the smallest file, then click **Save** and **Done**.

The [folder guide](/guides/password-protect-a-folder-on-mac/) has every step, and how to make one you can keep adding to. A read-only image can't be changed after it is made, which suits a package you send. A `.dmg` is a Mac format, so it is not much use for sending to someone on Windows.

## Safer and cross-platform: a 7z archive with AES-256

If the other person might not have a Mac, use an archive that supports AES-256 encryption. The 7z format does.

- **Keka** is a free macOS archiver (from [keka.io](https://keka.io/en), or for a small price on the Mac App Store to support its developer). It says it uses AES-256 for 7z files. For zip files it uses the old legacy encryption, so choose **7z**, not zip, when you set a password. Tick **Encrypt filenames** as well, so the list of contents is hidden too (this only works for 7z).
- **7-Zip** offers a console (Terminal) version for macOS, for Apple silicon and Intel. Once installed, `7zz a -p -mhe=on Private.7z "Tax 2026"` makes an encrypted 7z, asks for the password, and (with `-mhe=on`) hides the file names.

The person receiving it needs an app that opens 7z files. On Windows, 7-Zip itself is free; on a Mac, Keka or 7-Zip.

Whichever you use, the password is the whole of the protection. Make it long: four or five random words is easy to type and hard to guess (try the [passphrase generator](/tools/passphrase-generator/)). And send it a different way from the archive.

## Where Stillroom Vault fits

A zip is a way to move files. If what you really want is to keep private files locked on your own Mac, [Stillroom Vault](/features/) does that job, and you don't need to re-zip anything each time you change it.

- **Each item is sealed on its own,** with [AES-256-GCM](/learn/aes-256-gcm/) and a fresh random key, under a password stretched with [Argon2id](/learn/argon2id/). Names, folders and contents do not show on disk, unlike a zip.
- **You can drag folders in,** and once each copy is read back and checked, Stillroom offers to delete the originals, so nothing is left lying around.
- **You view files inside the app** (PDFs, images, text, email, audio and video) without unpacking them to your SSD.
- **It keeps earlier versions** of each item, and locks itself after a set time, when the Mac sleeps, or with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd>.
- **Backups are one encrypted file** you keep wherever you like.
- **It never goes online.** No account, no server, no sync.

What it does not do:

- **It is not a way to send files.** It has no sharing. To send something, export it and use a 7z archive as above.
- **It cannot recover a forgotten password.** Keep the recovery key it gives you.
- **It does not protect against malware with admin rights while the vault is open,** or a password someone can guess.
- **Someone with a copy of the vault folder can see how many items it holds and their rough sizes,** but not names or contents.
- It needs Apple silicon and macOS 26 or later. It is free for 25 items, then $39 once ([pricing](/pricing/)). No independent security audit has been done yet; the [format is public](/format/).

## Which to use

- **Low-stakes files to someone on any computer:** `zip -e` is fine.
- **Anything sensitive to someone on any computer:** a 7z with AES-256 from Keka or 7-Zip.
- **Sensitive files to another Mac:** an encrypted disk image.
- **Private files that stay on your Mac:** an encrypted disk image, or a vault such as Stillroom. See [how to encrypt files on a Mac](/guides/encrypt-files-on-mac/) for the full picture.
