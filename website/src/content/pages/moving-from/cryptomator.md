---
title: 'Move Files from a Cryptomator Vault to Stillroom Vault'
description: 'How to unlock a Cryptomator vault, drag its files into Stillroom Vault on your Mac, check the copies, and lock the Cryptomator vault again.'
h1: 'Moving from Cryptomator'
lead: 'Unlock your Cryptomator vault, drag what you want into Stillroom, and decide what to do with the old vault once every copy has been checked.'
name: 'Cryptomator'
updated: '27 October 2026'
order: 60
related: ['/compare/cryptomator/', '/moving-from/veracrypt/', '/features/view-without-decrypting/']
faq:
  - q: 'Can Stillroom open a Cryptomator vault directly?'
    a: 'No. Unlock the vault in Cryptomator first, then drag the files from its drive into Stillroom.'
  - q: 'Will moving files out of Cryptomator remove them from my cloud?'
    a: 'Only if you delete them. If you let Stillroom delete the originals from an unlocked Cryptomator vault that sits in a synced folder, the deletion reaches your cloud copy too. Choosing Keep Originals leaves everything as it was.'
  - q: 'Is anything decrypted onto my disk during the move?'
    a: 'Cryptomator decrypts files on the fly through its drive, and Stillroom reads them and seals each one as it goes in. Stillroom does not write a decrypted copy of its own to disk.'
sources:
  - label: 'Cryptomator: Home page'
    url: 'https://cryptomator.org/'
  - label: 'Cryptomator Docs: Accessing vaults'
    url: 'https://docs.cryptomator.org/desktop/accessing-vaults/'
  - label: 'Cryptomator Docs: Volume type'
    url: 'https://docs.cryptomator.org/desktop/volume-type/'
  - label: 'Cryptomator Docs: Security architecture'
    url: 'https://docs.cryptomator.org/security/architecture/'
---

## When Cryptomator is still the better fit

Cryptomator is open-source software for encrypting files you keep in a cloud service. It encrypts files and file names before they reach the cloud provider, and you open the vault from your devices through a virtual drive. If you need your encrypted files on a phone, a Windows PC or in Dropbox, Cryptomator is built for that and Stillroom isn't. The [comparison page](/compare/cryptomator/) covers this in more detail.

Stillroom keeps everything on one Mac and never goes online: no server, no account, no sync. Each item is sealed with AES-256-GCM under its own key, and you open it through built-in viewers rather than a mounted drive. It also holds notes, logins and two-factor codes. If that's what you want for some or all of your files, here's how to move them.

You can move a single folder and leave the rest in Cryptomator. Nothing here requires closing your Cryptomator vault for good.

## Unlock the Cryptomator vault

Cryptomator's documentation describes these steps:

1. Open **Cryptomator** and select the vault in the vault list.
2. Click **Unlock**, enter the vault's password, and click **Unlock** again.
3. When it's unlocked, click **Reveal Drive** (or **Reveal Vault** in the dialog that appears). The decrypted drive opens in Finder.

On a Mac, Cryptomator offers several volume types (such as macFUSE, FUSE-T and WebDAV), set in its preferences under **Virtual Drive**. Any of them works for this: Stillroom only needs to read the files in Finder.

If your vault lives in a cloud folder, make sure everything has finished downloading before you start. A file that's still only in the cloud may be slow to read or fail to copy.

## Drag the files into Stillroom

Open Stillroom and unlock your vault. Then either:

- drag files or whole folders from the Cryptomator drive in Finder onto Stillroom's window, or
- right-click empty space in Stillroom's list, choose **Add Files or Folders…**, and pick them from the Cryptomator drive.

To put them in a particular folder, drop them on that folder in Stillroom. Folders you drag in keep their structure. Apps and other bundles are skipped, and Stillroom tells you how many.

Stillroom seals each file as it goes in. Large files (over 8 MB) and all audio and video are sealed in chunks, so they play and open straight from the sealed file later, without a decrypted copy on disk. Big folders take a while; the time depends on how fast Cryptomator's drive can be read.

## How Stillroom checks each copy

Before Stillroom offers to delete anything, it reads each sealed copy back and compares it with the original by SHA-256. Only files whose copies match are offered for deletion. A dragged folder is removed whole only if every file in it, hidden ones included, went in; otherwise only the checked files are removed, so nothing that didn't make it in is lost.

Then Stillroom asks whether to delete the originals:

- **Delete Originals** deletes them without using the Trash. This can't be undone.
- **Move to Trash** moves them to the Trash.
- **Keep Originals** leaves them where they are.

For a Cryptomator vault, **Keep Originals** is usually the right choice at first. Deleting from the unlocked drive deletes those files from your Cryptomator vault, and if the vault is in a synced folder, from the cloud copy too. Keep them until you've opened a few files in Stillroom and you're satisfied, then delete them from Cryptomator yourself, or keep the Cryptomator vault as a second copy.

## Lock Cryptomator again

When the copy is done, go back to Cryptomator and click **Lock**. The drive disappears, and the files stay encrypted in the vault's folder.

## Afterwards

- **Check a few files.** Open some documents, photos and videos in Stillroom to make sure they're all there.
- **Make a backup.** Stillroom can make an encrypted backup of the whole vault to one file. Keep that somewhere other than your Mac, such as an external drive.
- **Keep your recovery key safe.** Stillroom can't recover a forgotten password, and neither can anyone else. Store the [recovery key](/features/recovery-key/) it gave you, and consider an emergency kit.
- **Know the limits.** Viewing in Stillroom doesn't write decrypted files to disk, but Edit in Place opens a file in another app, which may keep its own copies or a name in Recent items. The [view without decrypting](/features/view-without-decrypting/) page and the [security rules](/security/#rules) explain what stays where.

The free version holds 25 items, and each file is one item, so a large folder needs a licence. See [pricing](/pricing/).
