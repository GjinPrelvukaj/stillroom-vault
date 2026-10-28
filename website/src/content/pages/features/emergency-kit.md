---
title: 'Emergency Kit: Let Trusted People Open Your Vault'
description: 'Stillroom''s emergency kit splits a key into printed pieces, so any agreed number of trusted people can open your vault if something happens to you.'
h1: 'Emergency kit'
lead: 'Printed pieces for people you trust. Any agreed number of them together open your vault; one piece alone opens nothing.'
name: 'Emergency kit'
updated: '27 October 2026'
order: 20
related: ['/learn/shamir-secret-sharing/', '/features/recovery-key/', '/guides/keep-id-scans-safe/']
faq:
  - q: 'Can one person with one piece open my vault?'
    a: 'No. A piece on its own opens nothing and shows nothing about the key. Only the number of pieces you chose, put together, rebuilds it.'
  - q: 'What if Stillroom is no longer available when my family needs the vault?'
    a: 'Each printed piece says so: the free, open-source tool stillroom-open.py opens the vault with the same pieces, without the app. It is MIT licensed and described on the format page.'
  - q: 'Does making a new kit cut off the old pieces?'
    a: 'The old pieces stop opening the vault as it is now. Backups made before the new kit still open with the old pieces, so collect and destroy them too.'
  - q: 'Is there a company or server holding a copy of the kit?'
    a: 'No. No server and no account are involved. The pieces exist only on the paper you print.'
---

## What it is

The emergency kit is a way into your vault meant for other people. Stillroom makes a secret that opens the vault, then splits it into printed pieces. You choose how many pieces there are and how many are needed:

- **2 of 2:** both pieces are needed. Losing either one makes the kit useless.
- **2 of 3:** for example your partner, your lawyer and your safe. Any two together open it.
- **3 of 5:** for a family. Five people, any three together open it. Two alone never can.

One piece alone opens nothing. No server and no account are involved, and nobody at Stillroom holds a copy.

## When you'd use it

Stillroom can't recover a forgotten password, and nobody else can either. That's what keeps the vault safe, but it also means that if you're in an accident, fall ill or die, the people who need your documents can't get to them. The kit is for that.

It fits well when:

- you keep wills, insurance papers, property deeds or account details that your family would need
- you don't want any one person, even someone you trust, to be able to open the vault alone
- you want a way in that doesn't depend on Stillroom still being sold

If you only want a backup way in for yourself, the [recovery key](/features/recovery-key/) is simpler. You can have both.

## How to set it up

1. Open your vault, go to **Settings**, then the **Access** tab.
2. Next to **Emergency kit**, click **Make Kit…**.
3. Choose a plan: 2 of 2, 2 of 3 or 3 of 5.
4. Click **Print Pieces…**. Each piece prints on its own page, with plain instructions on it.
5. Give each page to a different person, or put it in a different place.

The pieces aren't shown again after this. Print on paper. Don't save the print as a PDF and don't photograph the pages: a piece kept on a computer or phone is much easier to steal than one in a drawer. Each page suggests keeping it where you'd keep a will or a passport, such as a safe, a lockbox, or with your lawyer's papers. There's a "Given to" line at the bottom so you can note who has which piece.

### Using the kit

The printed page explains this to whoever holds it:

1. On the Mac with Stillroom, open Stillroom and click **Use Emergency Kit** on the lock screen.
2. Type in this piece and the others needed, one per box. Capitals, dashes and spaces don't matter.
3. Choose a new password for the vault when asked.

If Stillroom isn't available, [stillroom-open.py](/format/) opens the vault with the same pieces.

## How it works underneath

The kit's secret is 16 random bytes. It seals your vault's key in its own key file, the same way your password and recovery key each do, and it's stretched with Argon2id like them.

The secret is split with **Shamir's secret sharing** over GF(256), the same small number field AES uses. For each byte of the secret, Stillroom picks a random polynomial whose constant term is that byte. Each piece is one point on every polynomial. With enough points, the polynomials can be rebuilt and the secret read off; with fewer, every possible secret is equally likely. That's why one piece, or one fewer than needed, shows nothing at all. [Shamir secret sharing, explained](/learn/shamir-secret-sharing/) goes further.

Each piece is 21 bytes: a version, how many pieces are needed, the piece's number, its 16-byte share, and a 2-byte check. It's printed as `VK-` followed by groups of four letters and digits, from an alphabet that leaves out I, L, O and U so they can't be confused with 1 and 0. The check catches every single-character typo and every swap of two neighboring characters. A rarer typo that slips past gives a wrong key, and the vault refuses it as the wrong kit.

The splitting code was reviewed in October 2026 against a separately written implementation: 5,600 joins agreed both ways, and the shares were uniform for fixed secrets. That was an internal review; Stillroom hasn't had an independent audit yet.

## Limits

- **Pieces don't carry a kit id.** If you mix pieces from an old kit and a new one with the same plan, you get "wrong kit" rather than a clearer "these are from different kits".
- **Printing passes every piece through one print job.** The print spool, the printer's memory or a network printer briefly holds them all, and the print panel offers Save as PDF. Print on a printer attached to your Mac.
- **A new kit doesn't cut off old backups.** Making a new kit or removing one stops the old pieces opening the vault as it is now, but backups (and Time Machine copies) made before still open with them. Collect and destroy old pieces. A key rotation feature to fix this is planned for a later version.
- **The people holding pieces have to cooperate.** If you choose 3 of 5 and three of the people can't be reached, the kit can't help.
- **A kit belongs to one vault.** If you use a [decoy password](/features/decoy-password/), each vault has its own kit.

The kit is in every tier of Stillroom, the free one included.
