---
title: 'An Encrypted Vault for Medical Practices on a Mac'
description: 'How clinicians and small practices can keep patient documents and practice logins sealed on a Mac with Stillroom Vault, and what it does not do.'
h1: 'Stillroom Vault for medical practices'
lead: 'The files that end up on a clinician''s laptop rather than in the records system. Where Stillroom helps, and where your other safeguards still have to do the work.'
name: 'Medical practices'
updated: '27 October 2026'
order: 20
related: ['/guides/keep-id-scans-safe/', '/guides/if-your-mac-is-stolen/', '/features/hidden-from-capture/', '/features/emergency-kit/']
faq:
  - q: 'Is Stillroom Vault HIPAA compliant?'
    a: 'No app makes a practice compliant with HIPAA, GDPR or any other regulation on its own. Stillroom can be one of your safeguards; check your own obligations with your compliance adviser or regulator.'
  - q: 'Does Stillroom ever receive our patients'' data?'
    a: 'No. Stillroom has no server, no account and no sync, and the app never goes online. Everything stays on your Mac and in backups you make.'
  - q: 'Can a practice manager open a clinician''s vault?'
    a: 'No. There is no admin key. Each vault opens only with its own password, recovery key, emergency kit or Touch ID.'
  - q: 'Should patient records live in Stillroom?'
    a: 'Your records system should stay the place where care is documented. Stillroom suits the working copies, scans, letters and logins that otherwise sit loose on a laptop.'
sources:
  - label: 'HHS: Is the use of encryption mandatory in the Security Rule?'
    url: 'https://www.hhs.gov/hipaa/for-professionals/faq/2001/is-the-use-of-encryption-mandatory-in-the-security-rule'
  - label: 'ICO: A guide to data security'
    url: 'https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/security/a-guide-to-data-security/'
---

## The files that live outside the records system

A practice's records system is built to hold patient notes. But plenty of sensitive material ends up on a clinician's Mac anyway: a referral letter being drafted at home, a scanned consent form waiting to be uploaded, an export pulled for an audit, photos for a case presentation, a therapist's private process notes, the login for the lab portal and its two-factor backup codes. Small practices often have no IT department to decide where these should go, so they go to the Desktop.

A laptop with those files on it is then carried between the clinic, home and a conference. If it's lost or stolen, that becomes a reportable problem in many places.

Regulators generally describe outcomes rather than products. HHS says encryption under the HIPAA Security Rule is an "addressable" specification, to be put in place where a practice's risk assessment finds it reasonable and appropriate. The UK's ICO calls encryption an appropriate measure for stored personal data. Stillroom Vault can be one of the measures you choose. It doesn't make a practice compliant with HIPAA, GDPR or any other rule, and you should check your own obligations with your adviser or regulator.

## How it fits a clinician's week

Stillroom keeps files, notes and secrets sealed with AES-256-GCM, a fresh key for every item, on your Mac. It has no server and no account, so there is no copy of your patients' documents anywhere but your Mac and your backups.

**Paperwork that arrives loose.** Drag a referral PDF or a scanned form into the vault, or scan a paper document with your iPhone straight in. Once each copy is read back and checked by SHA-256, Stillroom can delete the original from Downloads.

**Reading without leaving copies.** PDFs, images and text open in Stillroom's own viewers, which don't write a decrypted copy to the disk. Audio and video, such as a recorded dictation, play straight from the sealed file. When you need to edit a letter in Word or Pages, Edit in Place opens it from a RAM disk and seals the changes back; each save keeps an earlier version.

**Logins.** Keep portal and prescribing logins as secrets, with the live two-factor code shown under any that holds an `otpauth` link. Copied passwords clear from the clipboard after 30 seconds and stay on this Mac.

**Screens other people can see.** Every Stillroom window is hidden from screen capture, which helps during a telehealth call where you share your screen. It locks after a few minutes idle, on sleep, and with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> from any app. It doesn't stop someone standing behind you from reading the screen, so lock it before you leave the room.

## A practice with several people

Each person has their own vault. For a practice, the **Teams** licence is priced per seat, upon request (see [pricing](/pricing/)), with the same app and the same protection as the single licence. There is no admin key: a practice manager cannot open a clinician's vault, and neither can we.

That means continuity is something each person sets up. The [emergency kit](/features/emergency-kit/) splits a vault's key into printed pieces; a clinician can give pieces to colleagues so that, say, any two of three can open the vault if they're away. Stillroom doesn't share files between people or keep a log of who opened what, so anything several staff work on together belongs in your shared systems.

## Backups and recovery

Make an encrypted backup to one file and keep it off the laptop, for example on a drive kept at the practice. Restores unpack beside the vault and swap in with one atomic step.

Stillroom can't recover a forgotten password; no one can. Keep the recovery key apart from the Mac. Export everything as plain files at any time, and if Stillroom ever isn't available, the [public format](/format/) and `stillroom-open.py` read a vault without the app. That matters for files you're required to keep for years.

## What it doesn't do

- **It isn't a medical records system.** No audit trail, no access roles, no retention schedule, no sharing.
- **It protects a locked vault.** Malware with admin rights on the Mac while the vault is open can see what you see. Keep macOS updated and FileVault on.
- **Edit in Place hands a copy to another app,** which may keep its own (autosave, recent files). Stillroom warns you when you use it.
- **A copy of the vault folder shows some facts:** how many items, each one's rough size and when items were added. Never names or contents. See the [security page](/security/).
- **No independent audit yet.** One is planned. The threat model and rules are published on the [security page](/security/) so you, or your adviser, can judge them.

You can try it free with up to 25 items and every feature; see [download](/download/). It runs on Apple silicon Macs with macOS 26 or later.
