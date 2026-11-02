---
title: 'How to Password Protect a PDF on a Mac'
description: 'Encrypt a PDF on a Mac with Preview: the exact steps, why only the open password protects it, and how to keep many PDFs locked.'
h1: 'How to password protect a PDF on a Mac'
lead: 'Open the PDF in Preview, choose File > Export, click Permissions and select Require Password To Open Document. That encrypts it. Here are the full steps, what the other permission settings really do, and how to keep a whole collection of PDFs locked.'
name: 'Password protect a PDF'
updated: '30 October 2026'
order: 14
points:
  - '**Preview** can add a password to any PDF, free, from File > Export.'
  - '**The open password is the one that protects it.** Permissions on printing and copying are easy to get around.'
  - '**For many PDFs you keep,** an encrypted disk image or a vault is less work than one password per file.'
related: ['/guides/encrypt-files-on-mac/', '/guides/password-protect-a-folder-on-mac/', '/guides/keep-id-scans-safe/', '/features/view-without-decrypting/', '/tools/passphrase-generator/']
faq:
  - q: 'How do I password protect a PDF on a Mac for free?'
    a: 'Open it in Preview, choose File > Export, click Permissions, select Require Password To Open Document, enter the password twice, set an owner password, then click Apply and Save. No other app is needed.'
  - q: 'Can I remove a password from a PDF in Preview?'
    a: 'Yes, if you know it. Open the PDF in Preview with the password, choose File > Edit Permissions (or export it again), clear Require Password To Open Document, then click Apply.'
  - q: 'Is a PDF password secure?'
    a: 'The password to open the document encrypts it, so it is as strong as the password you choose. A permissions (owner) password only asks apps not to allow printing or copying. Many PDF tools ignore it, so do not rely on it to protect anything.'
  - q: 'What if I forget the PDF password?'
    a: 'There is no reset. If you saved under a new name, the original unprotected copy is still where you left it. Otherwise the only way in is guessing, which is why a long password matters.'
sources:
  - label: 'Apple: Password-protect a PDF in Preview on Mac'
    url: 'https://support.apple.com/guide/preview/prvw587dd90f/mac'
  - label: 'Adobe: Remove passwords from PDFs'
    url: 'https://helpx.adobe.com/ro/acrobat/desktop/protect-documents/protect-with-passwords/remove-passwords-from-pdfs.html'
  - label: 'Apple: Create a disk image using Disk Utility on Mac'
    url: 'https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac'
---

## What a PDF password protects against

A password on a PDF is for one job: a single document that will leave your Mac. You email a tax return to your accountant, upload a contract, or put a scan of your passport on a USB stick. The file may end up in places you don't control, so it needs its own lock.

A PDF has two kinds of password, and only one of them is a lock:

- **The password to open the document** (Acrobat calls it the document open password). Without it, the PDF does not open. It encrypts the file.
- **The owner password** (Acrobat calls it the permissions password). It sets rules for people who can already open the file: whether they may print it, copy text or change it.

## Password protect a PDF in Preview (free, built in)

Preview has done this for years. Apple's steps:

1. Open the PDF in Preview.
2. Choose **File > Export**.
3. To keep the original without a password, type a new name for the protected copy.
4. Click **Permissions**.
5. Select **Require Password To Open Document**, then enter the password and retype it.
6. For each action listed, such as printing or making changes, select its checkbox to allow it without the owner password, or leave it unselected to require it.
7. In the **Owner Password** section, enter a password and retype it. It can be the same as the open password or different.
8. Click **Apply**, then click **Save**.

To check it worked, close the file and open the new copy. Preview should ask for the password.

To change the settings later on a PDF that has an owner password, open it and choose **File > Edit Permissions**, make your changes, and click **Apply**. Apple says changes take effect the next time the PDF is opened.

### Then deal with the original

If you saved a protected copy under a new name, the unprotected original is still on your Mac. Move it to the Trash and empty it once you have checked the copy opens. With FileVault on, what is left on the disk stays encrypted.

## What the password protects, and what it doesn't

**The open password does the real work.** With it set, the PDF's contents are encrypted, and someone who gets the file has to guess the password. That makes the password the whole of the protection, so use a long one: a passphrase of four or five random words is easier to type than a jumble and much harder to guess. The [passphrase generator](/tools/passphrase-generator/) makes one in your browser.

**The owner password is a request, not a lock.** Printing and copying permissions only work if the app showing the PDF chooses to respect them. Plenty of PDF tools don't. Treat "no printing" or "no copying" as a polite note to honest readers, never as protection for anything sensitive. If you set only an owner password and no open password, anyone can read the document.

Other things to know:

- **Send the password a different way from the file.** A phone call, a text, a different app. A password in the same email as the PDF protects nothing.
- **Once it is open, it is open.** Whoever opens the PDF can save, print or screenshot what they see.
- **One file, one password.** For ten PDFs you get ten passwords to choose, keep and type.
- **Other copies are not protected.** The original, earlier drafts, and the file in Downloads all stay as they were.

## If you keep many PDFs, not send one

Statements, payslips, medical letters, scans of IDs: if you are storing PDFs rather than sending one, protecting each file separately quickly becomes a chore, and the originals are easy to leave behind.

The free built-in alternative is an **encrypted disk image**: one password for a whole folder of PDFs. In Disk Utility, choose **File > New Image > Blank Image**, choose an option from the **Encryption** menu, and copy your PDFs into the image. Eject it to lock them all. The [folder guide](/guides/password-protect-a-folder-on-mac/) has every step. While it is open, it is an ordinary drive, so eject it when you are done.

See [how to encrypt files on a Mac](/guides/encrypt-files-on-mac/) for how this fits with FileVault.

## Where Stillroom Vault fits

[Stillroom Vault](/features/) is built for a collection of private documents you keep and look at, not a single file you send.

- **Every PDF is sealed on its own,** with AES-256-GCM and a fresh random key, inside one vault with one password stretched with [Argon2id](/learn/argon2id/). Names, folders and contents do not show on disk.
- **PDFs open inside the app.** Stillroom has its own PDF viewer, so reading a statement does not unpack a copy to your SSD. See [view without decrypting](/features/view-without-decrypting/).
- **Search covers names and contents,** from a word index that is itself encrypted.
- **You can scan straight in** from your iPhone with Continuity Camera, so a paper letter never sits as a PDF in your Downloads folder.
- **Originals don't get left behind.** Drag PDFs or whole folders in, and once each copy is read back and checked, Stillroom offers to delete the originals.
- **It locks itself** after a set time, when the Mac sleeps, or with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> from any app.

What it does not do:

- **It does not make a password-protected PDF to send.** To share one document, export it from Stillroom and use Preview as above.
- **It cannot recover a forgotten password.** Nobody can. Keep the recovery key it gives you.
- **It does not protect against malware with admin rights while the vault is open,** or a password someone can guess.
- **Someone with a copy of the vault folder can see how many items it holds and roughly how big each is,** but not names or contents.
- It needs Apple silicon and macOS 26 or later. It is free for 25 items, then $39 once ([pricing](/pricing/)). No independent security audit has been done yet; the [format is public](/format/).

## Which to use

- **One PDF to send:** Preview, with a password to open and a long password.
- **A folder of PDFs you open now and then:** an encrypted disk image.
- **Private documents you keep and read often:** a vault such as Stillroom, on top of FileVault.
