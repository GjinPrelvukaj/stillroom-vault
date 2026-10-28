---
title: 'Move Files from a VeraCrypt Volume to Stillroom Vault'
description: 'Mount your VeraCrypt volume on a Mac, drag its files into Stillroom Vault, let Stillroom check every copy, then dismount the volume.'
h1: 'Moving from VeraCrypt'
lead: 'Mount the volume in VeraCrypt, drag your files into Stillroom, and unmount it once every copy has been checked.'
name: 'VeraCrypt'
updated: '27 October 2026'
order: 70
related: ['/compare/veracrypt/', '/moving-from/cryptomator/', '/compare/encrypted-disk-image/']
faq:
  - q: 'Can Stillroom open a VeraCrypt container without VeraCrypt?'
    a: 'No. Mount the volume in VeraCrypt first, then drag the files from the mounted volume into Stillroom.'
  - q: 'What about a hidden volume?'
    a: 'Mount it with its own password in VeraCrypt, the same as any other volume, and drag its files across. Stillroom has a decoy password of its own, but it works differently and has its own limits, set out on the security page.'
  - q: 'Should I delete the VeraCrypt container afterwards?'
    a: 'Only once you have opened your files in Stillroom and have a Stillroom backup. Until then the container is a useful second copy.'
sources:
  - label: 'VeraCrypt: Beginner''s Tutorial'
    url: 'https://veracrypt.io/en/Beginner%27s%20Tutorial.html'
  - label: 'VeraCrypt: Downloads'
    url: 'https://veracrypt.io/en/Downloads.html'
---

## When to keep VeraCrypt

VeraCrypt encrypts whole volumes: a container file that mounts as a disk, or an entire drive or partition. It runs on Windows, Linux and macOS, so a container can move between computers. On a Mac it needs a FUSE layer; VeraCrypt publishes separate builds for macFUSE and for FUSE-T, and recommends the FUSE-T build on Apple silicon. If you need a container you can open on Windows or Linux, or an encrypted external drive, VeraCrypt does that and Stillroom doesn't. The [comparison page](/compare/veracrypt/) has more.

Stillroom works differently. It doesn't mount anything. Each file is sealed separately with AES-256-GCM under its own key, and you open files in built-in viewers that don't write a decrypted copy to disk. It's for one Mac, never goes online, and holds notes, logins and two-factor codes as well as files.

You can move only part of a volume. Nothing here requires giving up VeraCrypt.

## Mount the volume

VeraCrypt's tutorial describes mounting a container like this:

1. Open **VeraCrypt** and choose a free slot in the main window.
2. Click **Select File**, find your container file, and open it.
3. Click **Mount** and enter the volume's password (and the PRF, if you chose a non-default one when you made it; otherwise leave it on autodetection).
4. Click **OK**. The volume mounts and appears in Finder.

The tutorial is written for Windows (it picks a drive letter where a Mac shows a slot), but the steps in VeraCrypt's main window are the same buttons.

## Drag the files into Stillroom

Open Stillroom and unlock your vault. Then either:

- drag files or whole folders from the mounted volume in Finder onto Stillroom's window, or
- right-click empty space in Stillroom's list, choose **Add Files or Folders…**, and pick them from the volume.

Drop them on a folder in Stillroom to put them there. Dragged folders keep their structure. Apps and other bundles are skipped, and Stillroom tells you how many.

Stillroom seals each file as it goes in. Files over 8 MB, and all audio and video, are sealed in chunks, so they open and play straight from the sealed file. A large volume takes a while; let it finish before you unmount.

## How Stillroom checks each copy

Stillroom doesn't offer to delete anything until it has read each sealed copy back and compared it with the original by SHA-256. Only files that match are offered. A dragged folder is removed whole only if every file in it, hidden files included, went in. Otherwise only the checked files are removed, so nothing that didn't make it in is lost.

Then it asks what to do with the originals:

- **Delete Originals** deletes them without using the Trash. This can't be undone.
- **Move to Trash** moves them to the Trash.
- **Keep Originals** leaves them on the volume.

For a VeraCrypt volume, **Keep Originals** is the sensible first choice. The files on the volume are already encrypted at rest, so deleting them gains you little right away, and they make a good second copy until you've checked Stillroom. When you're ready to retire the volume, delete the container file (or reformat the drive) yourself.

If Stillroom tells you FileVault is off, take that seriously: files deleted from your Mac's own disk could still be recovered without it. Turn it on in **System Settings › Privacy & Security**.

## Unmount the volume

Go back to VeraCrypt, select the volume in the list, and click **Unmount**. The files go back to being readable only with the volume's password.

## Afterwards

- **Open a few files** in Stillroom: documents, photos, a video. Make sure everything you need is there.
- **Make a backup.** Stillroom can write an encrypted backup of the vault to one file. Keep it on an external drive or somewhere other than this Mac.
- **Store your recovery key.** Stillroom can't recover a forgotten password, and neither can anyone else. Keep the [recovery key](/features/recovery-key/) safe, and consider an emergency kit.
- **Know what Edit in Place does.** Viewing doesn't write decrypted files to disk, but Edit in Place opens a file in another app, which may keep its own copies or a name in Recent items. The [security rules](/security/#rules) list exactly what still shows on disk.
- **Decoys and hidden volumes are different.** Stillroom's decoy password opens a second, harmless vault, and it doesn't fool someone who has one password and a copy of the vault folder. It's meant for thieves and abusers, not the police. See the [security page](/security/#rules) before relying on it.

The free version holds 25 items, and each file is one item; see [pricing](/pricing/).
