---
title: 'An Encrypted Vault for Lawyers on a Mac'
description: 'How a lawyer can keep client files, notes and passwords sealed on a Mac with Stillroom Vault, and where its part in your safeguards ends.'
h1: 'Stillroom Vault for lawyers'
lead: 'Client files on a laptop that travels to court, to clients and home again. How Stillroom fits that day, and what it leaves to you.'
name: 'Lawyers'
updated: '27 October 2026'
order: 10
related: ['/guides/if-your-mac-is-stolen/', '/features/emergency-kit/', '/features/view-without-decrypting/', '/compare/encrypted-disk-image/']
faq:
  - q: 'Does Stillroom Vault make my practice compliant with bar rules or GDPR?'
    a: 'No. No single app makes anyone compliant. Stillroom can be one part of the safeguards you choose, and you should check your own obligations with your bar, regulator or adviser.'
  - q: 'Can the firm open a lawyer''s vault if they leave or are ill?'
    a: 'Not with an admin key, because there is none. Each vault opens only with its own password, recovery key, emergency kit or Touch ID. A lawyer can choose to hand out emergency kit pieces to colleagues so that an agreed number of them can open it.'
  - q: 'Does Stillroom send client files anywhere?'
    a: 'No. Stillroom has no server, no account and no sync, and the app never goes online. Your files stay on your Mac and in the backups you make.'
  - q: 'How is Teams priced?'
    a: 'Teams is priced per seat, upon request. It is the same app with the same protection as the single licence.'
sources:
  - label: 'ABA: Model Rule 1.6, Confidentiality of Information'
    url: 'https://www.americanbar.org/groups/professional_responsibility/publications/model_rules_of_professional_conduct/rule_1_6_confidentiality_of_information/'
  - label: 'ICO: A guide to data security'
    url: 'https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/security/a-guide-to-data-security/'
---

## What a lawyer's Mac carries

A lawyer's laptop holds more than most people's. Engagement letters, draft pleadings, scanned identity documents from client intake, medical records in a personal injury file, bank statements in a divorce, settlement figures nobody else should see yet. Then the logins: the court e-filing portal, the practice management system, the client's data room, and the two-factor backup codes for each.

That laptop goes to court, to a client's office, onto a train and home at night. It gets left on a table during a break. Most professional rules don't name a tool for this. The ABA's Model Rule 1.6(c), for example, asks lawyers to make reasonable efforts to prevent unauthorized access to client information, and leaves what counts as reasonable to the lawyer. The UK's Information Commissioner's Office lists theft and loss of equipment among the common causes of security incidents and calls encryption an appropriate measure.

Stillroom Vault can be one part of that. It isn't a compliance product, it doesn't make anyone compliant with anything, and you should check your own obligations with your bar, your regulator or your adviser.

## How it fits the day

Stillroom is a Mac app that keeps files, notes and secrets (password records with fields) sealed with AES-256-GCM, each item under its own key. It has no server and no account, and it never goes online.

**Client intake.** Scan a passport or driving licence with your iPhone straight into the vault, or drag in the PDF the client emailed. Once each copy is read back and checked, Stillroom can delete the original from the Downloads folder, so the only readable copy isn't sitting where Finder can show it.

**Working on a file.** Folders and tags let you keep one folder per matter. PDFs, images, text and email (`.eml` and `.emlx`) open in Stillroom's own viewers, which don't write a decrypted copy to the disk. To edit a Word document, Edit in Place opens it in its own app from a RAM disk and seals your changes back. Every save keeps an earlier version, so you can go back to the draft from before a client's call.

**Logins and codes.** Keep the portal passwords as secrets. A secret holding an `otpauth` link or setup key shows a live two-factor code under it, and copied secrets clear from the clipboard after 30 seconds and never travel to your other devices through Universal Clipboard.

**Stepping away.** Stillroom locks itself after a few minutes idle and when the Mac sleeps. <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> locks and hides it from any app, which is the habit to build before you stand up in a meeting room. Every Stillroom window is hidden from screen capture, so it's left out of screen recordings and of a whole-screen share on a video call. Someone in the room can still read it over your shoulder.

## A small office

Stillroom is one person's vault on one person's Macs. For a firm, the **Teams** licence is priced per seat, upon request (see [pricing](/pricing/)). It is the same app with the same protection. There is no admin key and no central console: nobody, including a managing partner, can open a colleague's vault. That is deliberate, and it means you need to plan for absence.

The way to plan for it is the [emergency kit](/features/emergency-kit/). A lawyer prints a set of Shamir pieces and hands them to, say, three colleagues, chosen so that any two together can open the vault. One piece alone shows nothing. Each lawyer decides this for their own vault; Stillroom doesn't do it for them.

Stillroom also doesn't share files between people. If a matter needs to be worked on by several lawyers at once, that belongs in your document management system. Stillroom is better suited to what one person must carry: the scans, the private notes, the credentials.

## Backups and the files you can't lose

Make an encrypted backup to one file and keep it somewhere other than the laptop, such as a drive in the office safe. A restore unpacks beside the vault and swaps it in with one atomic step, so a crash midway never leaves you without one.

Stillroom can't recover a forgotten password, and neither can anyone else. Keep the recovery key somewhere apart from the Mac. If you ever need the files without the app, the [format is public](/format/), and `stillroom-open.py` reads a vault in about 300 lines of Python. You can also export everything as plain files at any time, which matters when a file has to be kept for years after a matter closes.

## Its limits, plainly

- **It protects a stolen or copied vault, not an open one.** Malware with admin rights on your Mac while the vault is open can see what you see. Keep macOS updated and turn on FileVault, which Stillroom warns you about if it's off.
- **Edit in Place hands a copy to another app.** That app can keep its own copies (autosave, recent files). Stillroom warns you when you use it.
- **Some facts show on disk.** Someone with a copy of the vault folder can see how many items it holds, each one's approximate size and when they were added. Names, contents and folders don't show. The full list is on the [security page](/security/).
- **It has not been independently audited yet.** One is planned. The rules it follows, and what it doesn't protect against, are published on the [security page](/security/).
- **It isn't a records system.** It keeps no audit trail of who opened what, and holds no retention schedule. Your practice management and document systems still do that work.

The free version holds 25 items with every feature, so you can try it on a single matter before deciding. See [download](/download/).
