---
title: 'If Your Mac Is Stolen: What to Do and Set Up Now'
description: 'What to do if your Mac is lost or stolen, with Apple’s steps, and the settings that decide whether your files are safe before it happens.'
h1: 'If your Mac is stolen'
lead: 'What protects your files is mostly decided before the theft: FileVault, a lock screen and Find My. Here are Apple’s steps for afterwards, and what to set up today.'
name: 'If your Mac is stolen'
updated: '27 October 2026'
order: 60
related: ['/features/lock-to-this-mac/', '/features/intruder-log/', '/features/recovery-key/', '/for/travellers/']
faq:
  - q: 'Can a thief read my files if my Mac was locked?'
    a: 'With FileVault on and a strong login password, the disk cannot be decrypted without that password. If the Mac was unlocked and awake when it was taken, your files are as open as they were to you.'
  - q: 'Should I erase my stolen Mac remotely?'
    a: 'Apple suggests erasing it if you do not think you will get it back. Once it is erased, Find My can no longer locate it, so try to locate it first.'
  - q: 'Does Find My work if the Mac is offline?'
    a: 'Apple says the Mac must be turned on and connected to the internet to be locked or erased. You may still see its location in Find My while it is offline.'
  - q: 'Can I open my Stillroom vault on a new Mac?'
    a: 'Yes, from an encrypted backup. Restore it on the new Mac and open it with your password. If the vault was locked to the old Mac, use your recovery key or emergency kit, which work on any Mac.'
sources:
  - label: 'Apple: If your Mac has been lost or stolen'
    url: 'https://support.apple.com/en-us/102481'
  - label: 'Apple: Set up Find My on Mac'
    url: 'https://support.apple.com/guide/mac-help/mh36811/mac'
  - label: 'Apple: Protect data on your Mac with FileVault'
    url: 'https://support.apple.com/guide/mac-help/protect-data-on-your-mac-with-filevault-mh11785/mac'
  - label: 'Apple: Change Lock Screen settings on Mac'
    url: 'https://support.apple.com/guide/mac-help/change-lock-screen-settings-mh11784/mac'
---

## If it has already happened

These are Apple's steps, in Apple's order.

1. **Locate it.** Sign in at icloud.com/find, or open Find My on another Apple device, and select your Mac. You will see its approximate location. If it is nearby, you can play a sound.
2. **Lock it.** Turn on Lost Mode in Find My, or choose **Lost Mac** on iCloud.com. Apple says a Mac with Apple silicon is locked with your Apple Account password.
3. **Erase it, if you do not expect it back.** Erasing removes your data and stops anyone else reaching it. After that, Find My can no longer locate the Mac, so do this last.
4. **Report it to the police.** They may ask for the serial number, which is on the original box or receipt.
5. **Change your Apple Account password,** so the Mac can no longer reach your iCloud data or services like iMessage.
6. **Remove the Mac from your trusted devices** for your Apple Account.
7. **Change the passwords of other accounts** you used on the Mac: email, banking, shopping, social media.

Apple notes that to lock or erase, the Mac has to be on and connected to the internet. A thief who keeps it offline delays both, which is why the settings below matter more than anything you can do after.

Do not go to the location yourself to get it back. Give it to the police.

## Set these up today

### FileVault

FileVault is what stops a thief reading the disk. On Apple silicon your data is already encrypted, and FileVault makes it impossible to decrypt without your login password.

1. Choose **Apple menu > System Settings**, then **Privacy & Security**.
2. Click **FileVault** and turn it on.
3. Choose your iCloud account or a recovery key as the way back in. Keep a recovery key off the Mac and not in the same bag.
4. Click **Continue**.

### A lock screen that comes on quickly

FileVault only helps if the Mac is locked when it is taken. In **System Settings > Lock Screen**, set **Require password after screen saver begins or display is turned off** to a short time. Press <kbd>Control</kbd> <kbd>Command</kbd> <kbd>Q</kbd> to lock it whenever you step away. Use a login password that is not easy to guess or to watch you type.

### Find My Mac

1. In **System Settings**, click your name at the top of the sidebar, then **iCloud**.
2. Click **See All**, then **Find My Mac**, and click **Turn On**. Click **Allow** if asked to let it use your Mac's location, and enter an administrator's name and password.
3. Make sure **Location Services** is on in **Privacy & Security**. Find My Mac needs it.

If the Mac has several user accounts, Apple says Find My Mac works for one user at a time.

### A backup somewhere else

A stolen Mac is also a lost one. Keep a current backup (Time Machine to a drive at home, or iCloud for what you keep there) so a theft costs you a computer, not your files.

## What a thief sees in Stillroom Vault

[Stillroom Vault](/features/) is a second lock for the files that matter most, on top of FileVault.

- **It is locked when the Mac sleeps,** after a time you choose, or with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd>. So a laptop grabbed from a café table, then closed, has a locked vault even if the thief somehow gets past the login.
- **Every guess costs the full stretch.** The vault password is stretched with [Argon2id](/learn/argon2id/) (512 MB, 3 passes, 4 lanes), about 280 ms per try on an Apple silicon Mac. That slows guessing; a strong password is still what stops it, and the strength check refuses guessable ones.
- **[Lock to this Mac](/features/lock-to-this-mac/)** adds a seal held by this Mac's Secure Enclave, so the password alone opens the vault only on this Mac. A copy of the vault folder taken elsewhere cannot be opened with the password alone.
- **The [intruder log](/features/intruder-log/)** records wrong tries, and optionally a photo, sealed so only your open vault can read them. It is useful if you get the Mac back; it does not stop anyone by itself.
- **You can carry on without the old Mac.** Restore an encrypted backup on a new Mac. Your [recovery key](/features/recovery-key/) and emergency kit work on any Mac, even when the vault was locked to the old one.

What it does not do:

- **It cannot help if the vault was open and the Mac awake** when it was taken, until it auto-locks.
- **It does not find, lock or erase the Mac.** Use Find My for that.
- **Changing your vault password later does not cut off a copy already taken.** Old copies still open with the old password, recovery key or kit. If you think someone knows any of those, assume what they copied is readable.
- **Without a backup, a stolen vault is gone.** Stillroom keeps nothing on a server, by design.
- It has not had an independent security audit yet. It needs Apple silicon and macOS 26 or later ([pricing](/pricing/)).

## Afterwards

Once the urgent steps are done, think about what was on the Mac that still matters: saved passwords in browsers, two-factor codes, ID scans. Change the passwords for anything that was stored or signed in there, starting with email, since it can reset the rest. See [where to store two-factor backup codes](/guides/store-two-factor-backup-codes/) and [how to keep ID scans safe](/guides/keep-id-scans-safe/) for setting up the next Mac better.
