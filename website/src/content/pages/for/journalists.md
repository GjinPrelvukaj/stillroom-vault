---
title: 'An Encrypted Vault for Journalists on a Mac'
description: 'How a journalist can keep source documents, recordings and notes sealed on a Mac with Stillroom Vault, and the threats it is not built for.'
h1: 'Stillroom Vault for journalists'
lead: 'Leaked documents, interview recordings and the notes that name a source. What Stillroom protects on a reporter''s Mac, and what it leaves to a wider security plan.'
name: 'Journalists'
updated: '27 October 2026'
order: 30
quote: 'If your Mac may be compromised, no app on it is a safe place.'
related: ['/learn/plausible-deniability/', '/features/view-without-decrypting/', '/features/lock-to-this-mac/', '/guides/if-your-mac-is-stolen/']
faq:
  - q: 'Will Stillroom Vault protect my sources from a government?'
    a: 'Do not rely on it for that. Stillroom protects a locked vault on a stolen or copied Mac. It does not protect against malware on your Mac, a determined state attacker or legal compulsion, and it has not been independently audited yet.'
  - q: 'Does Stillroom connect to the internet?'
    a: 'No. It has no server, no account and no sync, and a check on every build fails if the app links networking code. The email viewer blocks every remote load.'
  - q: 'Should I use the decoy password if police or a court ask for my password?'
    a: 'No. The decoy is meant as protection against thieves and abusers, not police, and it does not fool someone who has one password and a copy of the vault folder. Follow the law and take legal advice.'
  - q: 'Can I read my files without Stillroom?'
    a: 'Yes. The format is public and stillroom-open.py, an MIT licensed Python script of about 300 lines, opens a vault with your password or recovery key.'
sources:
  - label: 'Freedom of the Press Foundation: Digital security education'
    url: 'https://freedom.press/digisec/'
  - label: 'Freedom of the Press Foundation: Guides and resources'
    url: 'https://freedom.press/digisec/guides/'
  - label: 'EFF Surveillance Self-Defense: Journalist on the move'
    url: 'https://ssd.eff.org/playlist/journalist-on-the-move'
---

## Start with your threat model

Before choosing any tool, it helps to write down who might want your material, what they can do and what happens if they get it. A reporter worried about a laptop stolen from a café needs something different from one whose sources are being sought by a government. The Freedom of the Press Foundation's digital security program and the EFF's Surveillance Self-Defense guide both start there, and both have material written for journalists. They are better places than this page to plan your wider security.

Stillroom Vault answers one part of the problem: keeping files on your Mac sealed so that a stolen, lost or copied Mac doesn't give them away. Its own threat model is published on the [security page](/security/). Read it before you trust Stillroom with anything that could put a person at risk.

## What it does on a reporter's Mac

Stillroom keeps files, notes and secrets sealed with AES-256-GCM, each item under its own key, with your password stretched by Argon2id. It has no server and no account, so there is nothing of yours held anywhere to be breached or requested from us. The app never goes online: a check on every build fails it if it links networking code.

**Documents from a source.** Drag in the PDFs, spreadsheets or a whole folder. Once each copy is read back and checked by SHA-256, Stillroom can delete the originals, including hidden files inside a dropped folder only once every one of them went in.

**Reading leaked email.** Stillroom opens `.eml` and `.emlx` files in a viewer locked down three ways: no JavaScript, a content policy and a WebKit block list that allow no remote loads. A tracking pixel in a leaked message can't tell its sender you opened it. A test loads a hostile email aimed at a server on the Mac and fails on any connection.

**Recordings and notes.** Interview audio and video play straight from the sealed file, streamed in chunks, without a decrypted copy on disk. Notes live inside the vault, and search works across names and contents from a word index that is itself sealed.

**Working in public.** Every window is hidden from screen capture, and secure keyboard input is on while Stillroom is in front, which stops keyloggers that use event taps. <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> locks and hides it from any app.

**On the road.** [Lock to this Mac](/features/lock-to-this-mac/) adds a Secure Enclave seal, so the password alone opens the vault only on this Mac. A copy of the folder taken elsewhere needs the recovery key or the emergency kit instead.

## What it does not protect against

Be clear about these before you rely on it:

- **A compromised Mac.** Malware with admin rights while the vault is open sees everything you see. Commercial spyware and forensic tools are outside what Stillroom can defend against. If your Mac may be compromised, no app on it is a safe place.
- **State-level attackers.** Stillroom is not designed or tested against well-resourced, targeted attacks, and it has **not been independently audited** yet (one is planned).
- **Legal compulsion.** If you are lawfully required to unlock it, Stillroom can't help, and you should take legal advice. The decoy password is protection against thieves and abusers, not police. It doesn't fool anyone who has one password and a copy of the vault folder: they can see that the other slot holds something, and roughly how much.
- **What shows on disk.** A copy of the folder shows how many items are stored, each one's size to within about 12% and when items were added. Names and contents don't show.
- **Other apps' memories.** Edit in Place opens a document in its own app, which can keep copies or recent file names, and Quick Look's thumbnail cache can keep names too. For a file whose name alone would identify a source, read it in Stillroom's own viewer instead.
- **A weak password.** Argon2id makes each guess slow, but a guessable password is still the weakest point. Stillroom refuses the obvious ones; choose a long passphrase.
- **Your phone, your messages and your cloud.** Stillroom is a Mac vault. It doesn't protect your conversations with sources or where else a document has been.

## Keeping the work, and keeping it findable

Stillroom can't recover a forgotten password; nobody can. Make an encrypted backup to one file and keep it somewhere you control, away from the laptop, and store the recovery key separately again.

Investigations last years. Every item keeps earlier versions, and you can export everything as plain files whenever you choose. If Stillroom stops being available, the [format is public](/format/) and `stillroom-open.py` reads a vault in about 300 lines of Python, so you're never relying on the app to reach your own archive.

Stillroom is free for up to 25 items with every feature; a licence is $39 once (see [pricing](/pricing/)). It needs an Apple silicon Mac with macOS 26 or later.
