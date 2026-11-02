---
title: 'FileVault vs an Encrypted Vault: What Each Protects'
description: 'Should you turn on FileVault? Yes, for nearly every Mac. What it does on Apple silicon, what it leaves open, and where a vault app adds a second lock.'
h1: 'FileVault vs an encrypted vault: what each protects'
lead: 'Should you turn on FileVault? Yes. It is free, it is quick to turn on, and it is what keeps a lost or stolen Mac unreadable. It just stops protecting your files the moment you log in, which is where a vault comes in.'
name: 'FileVault'
updated: '30 October 2026'
order: 8
points:
  - '**Turn FileVault on.** On Apple silicon your data is already encrypted; FileVault ties the key to your password.'
  - '**It protects a Mac that is off or logged out,** not one that is unlocked in front of someone, and not copies that leave the Mac.'
  - '**A vault app is a second lock** for particular files while you are logged in. Stillroom Vault is not FileVault, and works alongside it.'
related: ['/guides/encrypt-files-on-mac/', '/guides/if-your-mac-is-stolen/', '/guides/secure-a-shared-mac/', '/compare/encrypted-disk-image/', '/compare/best-encryption-software-mac/', '/learn/secure-enclave/']
faq:
  - q: 'Should I turn on FileVault on my Mac?'
    a: 'Yes, for nearly everyone. It costs nothing, and without it the data on a lost or stolen Mac is protected only by the hardware, not by your password. Keep the recovery key, or the iCloud account you choose, somewhere safe.'
  - q: 'Does FileVault slow down a Mac?'
    a: 'On Apple silicon the data is already encrypted by a dedicated hardware engine whether FileVault is on or off, and Apple says turning it on is quick because the data is already encrypted. Turning it on mostly changes what the key is protected by, not how much work the Mac does.'
  - q: 'What happens if I forget my password and lose the FileVault recovery key?'
    a: 'Apple says you won''t be able to log in, and your files and settings are lost for good. Choose the iCloud option or keep the recovery key somewhere other than the Mac.'
  - q: 'Is my data encrypted if FileVault is off?'
    a: 'On Macs with Apple silicon or a T2 chip, yes, but the key is protected only by the hardware. Anyone who can start up the Mac can get to the data without your password. FileVault adds your password to that lock.'
  - q: 'Does FileVault encrypt my Time Machine backups or files I copy to a USB drive?'
    a: 'No. FileVault covers the startup disk. Time Machine has its own Encrypt backups option, and files you copy to another drive, email or a cloud folder leave without FileVault''s protection.'
  - q: 'Is Stillroom Vault the same as FileVault?'
    a: 'No. FileVault is Apple''s whole-disk encryption, built into macOS. Stillroom Vault is a separate app that seals particular files, notes and passwords under their own password. They work together, and Stillroom warns you when FileVault is off.'
sources:
  - label: 'Apple: Protect data on your Mac with FileVault'
    url: 'https://support.apple.com/guide/mac-help/protect-data-on-your-mac-with-filevault-mh11785/mac'
  - label: 'Apple Platform Security: Volume encryption with FileVault in macOS'
    url: 'https://support.apple.com/guide/security/volume-encryption-with-filevault-sec4c6dc1b6e/web'
  - label: 'Apple Platform Security: Secure Enclave'
    url: 'https://support.apple.com/guide/security/secure-enclave-sec59b0b31ff/web'
  - label: 'Apple: Choose a backup disk and set encryption options on Mac'
    url: 'https://support.apple.com/guide/mac-help/choose-a-backup-disk-set-encryption-options-mh11421/mac'
  - label: 'Apple: Encrypt and protect a storage device with Disk Utility'
    url: 'https://support.apple.com/guide/disk-utility/encrypt-a-disk-dskutl35612/mac'
---

## Should you turn on FileVault?

Yes. For nearly every Mac, FileVault should be on. It's free, it's built into macOS, and on Apple silicon it takes very little time to turn on. It's the thing that keeps your files unreadable if the Mac is lost, stolen or sent off for repair while it's switched off.

The few people who might leave it off are those whose Mac is managed by an employer (who sets it for them) or who keep nothing on the Mac at all. Everyone else should turn it on, then read on for what it doesn't do.

## What FileVault actually does on Apple silicon

There's a common belief that FileVault "encrypts your disk" and that, without it, your files sit in the clear. On a Mac with Apple silicon or a T2 chip, that isn't quite right.

- **Your data is already encrypted.** Apple says these Macs encrypt the internal storage automatically. A dedicated AES engine does the work as data is written and read, with the keys kept in the [Secure Enclave](/learn/secure-enclave/), away from the main processor.
- **Without FileVault, the key is protected only by the hardware.** Apple's security guide says that with FileVault off, the volume key is protected "only by the hardware UID". The Mac can unlock it by itself, so the encryption doesn't depend on anyone knowing your password.
- **With FileVault on, your password joins the hardware.** The key that unlocks the disk is then protected by your login password together with the hardware. Nobody can decrypt the disk without a valid password or the recovery key, and the Mac asks for it before macOS starts.
- **Turning it on is quick.** Because the data is already encrypted, Apple says nothing has to be re-encrypted from scratch. Changing your password later doesn't re-encrypt the disk either.

So FileVault isn't a heavy layer on top of your disk. It's the step that makes the encryption depend on you.

### Performance

On Apple silicon, encryption happens in the hardware engine whether FileVault is on or off, so turning it on doesn't add a new job for the processor. Apple doesn't publish speed figures, and we won't invent any. In practice, the reason most people hesitated about FileVault years ago (slow encryption on older Macs) doesn't apply here.

## How to turn it on, and the recovery choice

You need to be an administrator.

1. Choose **Apple menu > System Settings**, then **Privacy & Security**.
2. Click **FileVault** (you may need to scroll), and turn it on. You may be asked for your password.
3. Choose how you'll get back in if you forget your password.
4. Click **Continue**. If you see **Enable Users**, enter each person's password so they can unlock the disk too.

The choice in step 3 matters more than anything else on this page:

- **Allow your iCloud account to unlock the disk.** Apple suggests this if you use iCloud. You don't need to keep track of a separate key, but your Apple Account becomes a way into the disk, so protect it with a strong password and two-factor authentication.
- **Create a recovery key.** The Mac shows a string of letters and numbers. Keep a copy somewhere other than the Mac: on paper, in a safe place, or in a password manager that lives elsewhere. Don't store it only on the disk it unlocks.

Apple is blunt about the risk. If you forget your login password and also lose the recovery key, you can't log in, and your files and settings are gone for good. There's no back door. Our [recovery code sheet](/tools/recovery-code-sheet/) can help you print a key neatly.

## What FileVault doesn't cover

FileVault protects a Mac that is **off, or at the login screen**. Once you log in, the disk is unlocked, and it stays unlocked until you shut down or log out. That leaves three gaps worth knowing about.

### Anyone at your unlocked Mac

While you're logged in, every file in your account is readable by whoever is at the keyboard and by every app you run. If you step away and the screen isn't locked, FileVault does nothing for you. Set **System Settings > Lock Screen** to ask for your password soon after the screen turns off, and press <kbd>Control</kbd> <kbd>Command</kbd> <kbd>Q</kbd> when you walk away.

The same applies if someone knows or watches you type your login password, or if your Mac is taken while it's awake and unlocked. FileVault can't tell you from them.

### Copies that leave the Mac

FileVault covers the startup disk, nothing else. A file you attach to an email, copy to a USB stick, drop in a cloud folder or send by AirDrop leaves as an ordinary, readable file.

- **Time Machine** has its own **Encrypt backups** option, with its own password. Turn it on when you choose a backup disk; FileVault doesn't do it for you.
- **External drives** can be encrypted in Disk Utility, though Apple says the drive has to be erased first.
- **Single files you need to send** can go in an encrypted disk image or a password-protected PDF (see [how to encrypt files on a Mac](/guides/encrypt-files-on-mac/) and [encrypt a PDF](/guides/encrypt-pdf-on-mac/)).

### Other people who use your login

FileVault keeps out people without a password. It doesn't separate things within your account. If a partner, child or colleague knows your login password, or uses the Mac while you're logged in, they can open everything you can. Separate user accounts help (each person unlocks with their own password), and the [shared Mac guide](/guides/secure-a-shared-mac/) goes through them.

## Where a vault adds to FileVault

A vault app doesn't replace FileVault. It adds a second lock, with its own password, around particular things, so they stay sealed while the Mac itself is unlocked. Free options exist: an [encrypted disk image](/compare/encrypted-disk-image/) is built into macOS. The [roundup of encryption software for Mac](/compare/best-encryption-software-mac/) covers the rest.

### A word about the name

Stillroom Vault is not FileVault, and isn't made by Apple. The names are confusingly close. FileVault is a macOS setting for the whole disk. Stillroom Vault is a separate app that keeps files, notes, passwords and two-factor codes sealed inside one folder on your Mac. You want FileVault on whether or not you use Stillroom, and Stillroom warns you when it's off.

### What Stillroom Vault adds on top

- **A second lock while you're logged in.** Each item is sealed on its own with [AES-256-GCM](/learn/aes-256-gcm/) and a fresh key, under a password stretched with [Argon2id](/learn/argon2id/) (512 MB). Someone at your unlocked Mac sees a locked window, not your files.
- **It locks itself.** After a time you choose, when the Mac sleeps, and with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> from any app. Every window is [hidden from screen capture](/features/hidden-from-capture/).
- **Viewing doesn't write a decrypted copy to disk.** PDFs, images, text, sketches and email open in built-in viewers, audio and video stream from the sealed file, and other previews go to a RAM disk. Edit in Place uses the RAM disk too, though the app you edit in may keep copies of its own; Stillroom warns about this. See [view without decrypting](/features/view-without-decrypting/).
- **Names stay hidden on disk.** Someone with a copy of the vault folder sees how many items there are, their rough sizes and when they were added, but no names, folders or contents. The [security page](/security/) lists exactly what shows.
- **More ways back in.** A [recovery key](/features/recovery-key/), a printable [emergency kit](/features/emergency-kit/), [Touch ID](/features/touch-id/), and optional [Lock to this Mac](/features/lock-to-this-mac/).
- **It never goes online.** No account, server or sync.

### And what it doesn't

- **It relies on FileVault for deleted data.** Stillroom never "secure-erases": on an SSD that does nothing. FileVault is what keeps deleted originals unreadable, which is one more reason to turn it on.
- **It doesn't protect against malware with admin rights while the vault is open,** or against a password someone can guess. Your password's strength is the real boundary, which is why Stillroom refuses guessable ones.
- **It can't recover a forgotten password.** Nobody can. Keep your recovery key safe.
- **It hasn't had an independent security audit yet,** though its [format is public](/format/). It's source available under the FSL, which isn't an open source licence.
- **It needs a Mac with Apple silicon and macOS 26 or later.** It's free for 25 items, then $39 once, or $79 for a family of five ([pricing](/pricing/)).

## In short

| Situation | FileVault | A vault app (with FileVault on) |
|---|---|---|
| Mac lost or stolen while off | Protected | Protected |
| Someone at your unlocked Mac | Open | Vault items stay sealed while it's locked |
| Files copied off the Mac | Unprotected | The vault folder stays sealed; exported files don't |
| Deleted files on the SSD | Unreadable | Relies on FileVault |
| Forgotten password | iCloud or recovery key | Recovery key or emergency kit |

Turn FileVault on today. Then decide whether anything on the Mac needs a lock of its own.
