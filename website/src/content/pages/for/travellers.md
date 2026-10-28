---
title: 'Keeping Your Files Safe on a Mac While Travelling'
description: 'Passport scans, bookings and passwords on a laptop that could be stolen or lost abroad. How Stillroom Vault, backups and a recovery key kept apart help.'
h1: 'Stillroom Vault for travellers'
lead: 'A laptop on the move gets left in taxis, lifted from hostel lockers and taken from hotel rooms. How to set Stillroom up before you leave, so losing the Mac doesn''t mean losing control of what''s on it.'
name: 'Travellers'
updated: '27 October 2026'
order: 40
related: ['/guides/if-your-mac-is-stolen/', '/guides/keep-id-scans-safe/', '/features/recovery-key/', '/features/lock-to-this-mac/']
faq:
  - q: 'What happens if my Mac is stolen while I''m abroad?'
    a: 'A locked vault stays sealed: the thief needs your password, recovery key or emergency kit. To get your files back, restore your latest backup on another Mac and open it with your recovery key or kit, or with your password if the vault was not locked to the old Mac.'
  - q: 'Should I travel with my recovery key?'
    a: 'Not in the same bag as the Mac. Keep it at home, with someone you trust, or somewhere else apart from the laptop, so one theft can''t take both.'
  - q: 'Can I use the decoy password at a border?'
    a: 'No. The decoy is protection against thieves and abusers, not police or border officers. Follow the law of the country you are entering.'
  - q: 'Does Stillroom need internet access while I travel?'
    a: 'No. Stillroom never goes online, so it works the same on a plane, in a hotel with no Wi-Fi or anywhere else.'
sources:
  - label: 'U.S. Customs and Border Protection: Border Search of Electronic Devices at Ports of Entry'
    url: 'https://www.cbp.gov/travel/cbp-search-authority/border-search-electronic-devices'
---

## What travels with you

A travel laptop holds the files you'd least like to lose abroad: a scan of your passport and visa, travel insurance documents, booking confirmations, a copy of your driving licence, the banking logins you'll need if a card is stopped, and the two-factor backup codes for your email in case your phone is the thing that goes missing.

Travel is also when a Mac is most likely to be stolen or lost. It moves through airports, taxis, cafés and rooms that other people have keys to. Stillroom Vault keeps those files sealed with AES-256-GCM on the Mac, so a thief with the laptop has a locked vault rather than your documents. It has no server and no account, and it never goes online, so it works the same on a plane as at home.

## Before you leave

A few things are worth doing at home, while the Mac and your papers are in one safe place.

**Put the documents in.** Scan your passport and cards with your iPhone straight into the vault, or drag the PDFs in. Once each copy is read back and checked, Stillroom can delete the originals from Downloads and the Desktop. Keep the logins and backup codes as secrets; a secret holding an `otpauth` link shows a live two-factor code, which helps if your phone is lost.

**Make a backup and leave it behind.** An encrypted backup is one file. Copy it to a drive that stays at home, or give it to someone you trust. If the Mac is stolen, that file and your recovery key get everything back on a new one.

**Keep the recovery key apart from the Mac.** The [recovery key](/features/recovery-key/) opens the vault if you forget your password, and Stillroom can't recover a forgotten password for you; nobody can. Don't keep the recovery key in the laptop bag. If you've made an [emergency kit](/features/emergency-kit/), its pieces should be with the people you gave them to, not with you.

**Consider Lock to this Mac.** [Lock to this Mac](/features/lock-to-this-mac/) adds a Secure Enclave seal, so your password alone opens the vault only on this Mac. Someone who copied the folder can't use a password they watched you type on another machine. Your recovery key and kit still work on any Mac, which is how you get back in on a replacement.

**Turn on FileVault.** It encrypts the whole disk, and Stillroom warns you when it's off. The two work together: FileVault protects the Mac when it's off, Stillroom protects your vault while the Mac is on and the vault is locked.

## On the road

**Lock it whenever you look away.** Stillroom locks after a few minutes idle and whenever the Mac sleeps, so closing the lid locks it. <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> locks and hides it from any app, and the menu bar icon does the same.

**Touch ID for quick unlocks.** On a Mac with Touch ID you can open the vault with a finger instead of typing your password where others can see.

**Shared screens and shared spaces.** Every Stillroom window is hidden from screen capture, and copied passwords clear from the clipboard after 30 seconds. Neither stops someone beside you on a train reading the screen, so open the vault when you need it and lock it again.

**If the Mac is stolen.** The locked vault stays sealed. Our guide to [what to do if your Mac is stolen](/guides/if-your-mac-is-stolen/) covers the steps, including restoring your backup on another Mac and changing the passwords that were stored in it if you think the vault might have been open.

## Border device searches

Some countries' border authorities can inspect travellers' electronic devices. U.S. Customs and Border Protection, for example, states that its search authority extends to electronic devices, and that a device which can't be inspected because of a passcode or encryption may be detained. Rules differ by country and change over time, so check the rules of the country you're entering and follow the law.

Stillroom isn't designed for border searches, and its decoy password must not be used to mislead border officers. The decoy is protection against thieves and abusers, not police or officials, and it doesn't fool someone who has one password and a copy of the vault folder.

If you'd rather not carry certain files across a border at all, the plain choice is to leave them at home: your encrypted backup and the [public format](/format/) mean the files are still yours when you return.

## Limits to keep in mind

- **A locked vault is what's protected.** If the Mac is taken while the vault is open, whoever has it can read it until it auto-locks. Lock before you step away.
- **Malware with admin rights** on the Mac while the vault is open sees what you see. Be careful with hotel business-centre machines and unknown USB drives.
- **The backup is only as current as its date.** Make a fresh one before you leave.
- **Stillroom hasn't been independently audited yet.** One is planned. See the [security page](/security/) for the full threat model.

Stillroom is free for up to 25 items, enough for a trip's worth of documents; see [download](/download/). It needs an Apple silicon Mac with macOS 26 or later.
