---
title: 'Where to Store Two-Factor Backup Codes Safely'
description: 'Two-factor backup codes get you back in when your phone is gone. Where to keep them on a Mac or on paper, and what each place protects against.'
h1: 'Where to store two-factor backup codes'
lead: 'Backup codes are the spare key to an account that uses two-factor sign-in. They need to be safe from other people and still there when your phone is not. Here is how to choose a place for them.'
name: 'Store two-factor backup codes'
updated: '27 October 2026'
order: 50
related: ['/tools/recovery-code-sheet/', '/tools/qr-code-reader/', '/compare/apple-notes-locked-notes/', '/moving-from/apple-passwords/', '/features/recovery-key/', '/compare/1password/']
faq:
  - q: 'What are two-factor backup codes?'
    a: 'One-time codes a website gives you when you turn on two-factor sign-in. Each one can stand in for a code from your phone once, so you can get back in if you lose the phone or authenticator app.'
  - q: 'Should I keep backup codes in the same app as my two-factor codes?'
    a: 'Better not. Backup codes are for the day you lose that app or device, so keep them somewhere you can reach without it, such as paper or a separate encrypted place.'
  - q: 'Is it safe to screenshot a two-factor QR code?'
    a: 'Only briefly. The QR code holds the secret that makes every future code. If you keep it, keep it encrypted, and delete the screenshot from your Desktop and Trash.'
  - q: 'Can I store two-factor codes in Apple Passwords?'
    a: 'Yes. Apple Passwords on a Mac can make verification codes from a setup key: select the account, click Edit, then Set Up Code.'
sources:
  - label: 'Apple: Set up verification codes in Passwords on Mac'
    url: 'https://support.apple.com/guide/passwords/mchl873a6e72/mac'
  - label: 'Apple: Lock your notes on Mac'
    url: 'https://support.apple.com/guide/notes/not28c5f5468/mac'
  - label: 'Apple: Create a disk image using Disk Utility on Mac'
    url: 'https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac'
---

## What you are actually storing

When you turn on two-factor sign-in with an authenticator app, a website usually gives you two things:

- **A setup secret,** shown as a QR code or a "setup key". Your authenticator app turns it into a new six-digit code every 30 seconds or so. Anyone with this secret can make your codes forever.
- **Backup codes** (also called recovery codes): a short list of one-time codes, each of which works once in place of a code from your app.

Both are as sensitive as the password itself. Together with your password, either one gets someone into the account. And both exist for the bad day: a lost phone, a wiped app, a broken laptop. So the place you keep them should be:

1. **Encrypted, or physically locked away,** so finding them is not enough.
2. **Separate from the device that makes your everyday codes,** so losing one does not lose both.
3. **Something you can still open in a year,** without the phone you are using today.

## Free places that work

### On paper

Printing the codes and keeping them with your passport or other papers is a sound choice. It cannot be hacked from across the internet and does not depend on any device. The risks are the physical ones: fire, loss, and anyone in your home. Mark each code as used when you use it. The free [recovery code sheet](/tools/recovery-code-sheet/) prints a site's codes on one page, with a box to tick beside each.

### In a locked note

Apple Notes can lock a note with your Mac login password or a separate Notes password.

1. Open Notes and paste the codes into a new note, with the site's name.
2. Click the **More** button near the search field and choose **Lock Note**.
3. Enter your password, or create one if you have not yet.

Apple says that if you forget a custom Notes password and Touch ID cannot unlock the note, you cannot view it, and Apple cannot help. If you use your login password instead, anyone who knows your login password can open it.

### In an encrypted disk image

A `.dmg` made in Disk Utility with **File > New Image > Blank Image** and an option chosen from the **Encryption** menu holds a text file of codes behind its own password, and stays encrypted when you copy it to a USB drive. See [how to encrypt files on a Mac](/guides/encrypt-files-on-mac/) for every step.

### Your everyday codes in Apple Passwords

For the codes you use daily (not the backups), Apple Passwords on a Mac can be your authenticator:

1. On the website, turn on two-factor sign-in with an authenticator app and choose to enter a setup key by hand. Copy the key.
2. In Passwords, select the account, click **Edit**, then **Set Up Code**.
3. Paste the key into **Setup Key** and click **Use Setup Key**.
4. Click the verification code to copy it, and paste it into the website to finish.

If Passwords holds your everyday codes, keep the backup codes somewhere else from this list.

## Keeping them in Stillroom Vault

[Stillroom Vault](/features/) is an encrypted vault for files, notes and secrets on your Mac. It can hold both backup codes and live two-factor codes.

- **A secret is a record with fields,** so a site's password, backup codes and setup key can sit in one place, and any field can be marked concealed so it stays hidden until you reveal it.
- **Live codes show under any secret holding an `otpauth` link or setup key,** made on your Mac (RFC 6238). You can paste the setup key, or read a QR code from the clipboard or from a screenshot. Stillroom then offers to move the screenshot to the Trash and clears a copied QR picture from the clipboard.
- **Setup secrets are treated like passwords.** They are added concealed and kept out of the search index, whatever the field is called.
- **Anything you copy stays on this Mac.** It does not go to Universal Clipboard, is marked as concealed for clipboard managers, and is cleared after 30 seconds or when the vault locks.
- **It never goes online,** and has no account to lose. You can also [import from Apple Passwords](/moving-from/apple-passwords/).
- **You have ways back in that do not depend on a phone:** a [recovery key](/features/recovery-key/) made with the vault, and an optional emergency kit of printed pieces.

Honest limits:

- **One place for a password and its two-factor secret is one place to lose.** If someone gets into the vault, they get both. Many people accept that for convenience; if you would rather not, keep backup codes on paper and only the everyday setup in the vault.
- **It cannot recover a forgotten password.** Nobody can. Keep the recovery key away from the Mac.
- **It does not protect against malware with admin rights while the vault is open.**
- **It lives on one Mac.** There is no sync, so your codes are not on your phone. Make encrypted backups to a file you keep elsewhere.
- No independent security audit has been done yet. It needs Apple silicon and macOS 26 or later, and is free for 25 items, then $39 once ([pricing](/pricing/)).

## A simple plan

1. Use an authenticator you trust for daily codes: Apple Passwords, Stillroom, or another app.
2. Save every site's backup codes in a second place: paper, a locked note or an encrypted vault that does not depend on the first.
3. Delete screenshots of QR codes and any downloaded `backup-codes.txt` from Downloads, and empty the Trash.
4. When a site gives you new backup codes, replace the old ones everywhere you kept them.
