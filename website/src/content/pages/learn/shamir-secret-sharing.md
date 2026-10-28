---
title: 'Shamir Secret Sharing, Explained Simply'
description: 'How Shamir secret sharing splits a secret into pieces so any agreed number can rebuild it and fewer reveal nothing, and how Stillroom Vault uses it.'
h1: 'Shamir secret sharing, explained'
lead: 'How a secret can be split into pieces so that any agreed number of them rebuilds it, and fewer show nothing at all.'
name: 'Shamir secret sharing'
updated: '27 October 2026'
order: 30
related: ['/features/emergency-kit/', '/features/recovery-key/', '/learn/argon2id/', '/guides/if-your-mac-is-stolen/']
faq:
  - q: 'Can one piece of a Shamir split reveal part of the secret?'
    a: 'No. With fewer pieces than the threshold, every possible secret is equally likely, so the pieces show nothing about it. This holds however much computing power someone has.'
  - q: 'What happens if I lose some pieces?'
    a: 'As long as enough pieces remain to meet the threshold, the secret can still be rebuilt. With a 2 of 3 kit you can lose one piece; with 3 of 5 you can lose two. With 2 of 2, losing either piece makes the kit useless.'
  - q: 'Can the people holding my pieces open my vault without me?'
    a: 'Yes, if enough of them get together. That is what the kit is for, so choose holders you trust and a threshold that makes it hard for the wrong people to meet it.'
  - q: 'Does a Stillroom emergency kit work on a new Mac?'
    a: 'Yes. Kit pieces are never tied to one Mac, even when Lock to this Mac is on, so they still open the vault on a different Mac.'
sources:
  - label: 'Adi Shamir, How to Share a Secret, Communications of the ACM 22(11), 1979'
    url: 'https://doi.org/10.1145/359168.359176'
  - label: 'How to Share a Secret (PDF copy hosted by MIT)'
    url: 'https://web.mit.edu/6.857/OldStuff/Fall03/ref/Shamir-HowToShareASecret.pdf'
  - label: 'NIST FIPS 197: Advanced Encryption Standard (the GF(2⁸) field)'
    url: 'https://csrc.nist.gov/pubs/fips/197/final'
---

## What Shamir secret sharing is

Shamir secret sharing is a way to split a secret into several **pieces** (also called shares) and choose a **threshold**: any that many pieces together rebuild the secret, and anything fewer reveals nothing about it. It was published by Adi Shamir in 1979, in a two-page paper called "How to Share a Secret", and it's still the standard way to do this.

You'll see it written as "k of n": 3 of 5 means five pieces exist, and any three of them are enough.

## The problem it solves

A single secret has two opposite risks. If only you know it, it's lost when you forget it, lose the paper or can't be reached. If you give a copy to someone else, that person alone can use it, and so can anyone who finds their copy.

Cutting a written secret in half doesn't really help. Each half gives away part of the answer, and losing one half loses everything. Shamir's scheme removes both problems: no single piece holder can use it, nobody learns anything from fewer pieces than the threshold, and a few lost pieces don't matter.

## How it works, with an analogy

Start with a fact from school geometry: **two points fix a straight line**. If you know one point, infinitely many lines pass through it.

Now say the secret is where a line crosses the vertical axis. To make a 2 of 3 split:

1. Draw a random straight line that crosses the axis at the secret.
2. Pick three other points on that line, and give one to each person.

Any two people can put their points together, draw the line, and read off where it crosses the axis. One person alone has a single point, and a line through it could cross the axis anywhere. Their point says nothing about the secret, not "a little", but nothing.

For a higher threshold you use a curve instead of a line. Three points fix a parabola, so a 3 of 5 split uses a random parabola and hands out five points. In general a threshold of k uses a polynomial of degree k minus 1, and rebuilding it from k points is called **Lagrange interpolation**.

The analogy is accurate with one adjustment. On paper, coordinates are ordinary numbers. In practice the arithmetic is done in a **finite field**, a small number system that wraps around, so every value fits in a fixed size and no piece leaks information through how big or precise its numbers are.

## What it does not do

- **It doesn't protect against enough pieces being misused.** If the threshold number of holders agree, or someone collects that many pieces, they have the secret. Choosing who holds pieces matters as much as the math.
- **It doesn't check that a piece is genuine** by itself. Plain Shamir rebuilds a wrong secret from a mistyped or tampered piece, so real systems add a check.
- **It doesn't help once too many pieces are gone.** Below the threshold, the secret is unrecoverable, by design.
- **Pieces don't expire.** Anyone who still has old pieces can use them on whatever they open.

## How Stillroom Vault uses it

Stillroom's **emergency kit** is a Shamir split. It's one of the ways in to a vault, alongside the password, the [recovery key](/features/recovery-key/) and Touch ID. The details below come from the public [file format](/format/) and the [security rules](/security/).

**What is split.** Each vault's kit has a 16-byte random secret. That secret is split into pieces over GF(256), the same 256-value field AES uses, with one random polynomial per byte and the secret as its constant term. To unlock, the rebuilt secret is stretched with [Argon2id](/learn/argon2id/) into the key that opens the vault's `kit.key` file, just as a password opens `password.key`.

**The choices.** When you make a kit, you pick one of three plans:

- **2 of 2**: both pieces are needed. Losing either one makes the kit useless.
- **2 of 3**: for example your partner, your lawyer and your safe. Any two open it.
- **3 of 5**: for example a family of five. Any three open it; two alone never can.

**What a piece looks like.** Each piece is 21 bytes: a version, the threshold, the piece's number, its 16-byte share, and a 2-byte check taken from SHA-256 over the rest. It's printed in Crockford base32, starting `VK-`, in groups of four characters. Case, spaces and dashes don't matter, and O, I and L are read as 0, 1 and 1, so a piece read off paper is forgiving. The check catches every single-character typo and every swap of two neighbouring characters. A rarer typo that slips past it gives a wrong key, which the vault refuses as "wrong kit".

**How it was checked.** The splitting code was compared in October 2026 against a separately written implementation: 5,600 joins agreed both ways, and the share bytes were uniform for fixed secrets, so fewer pieces than needed show nothing. That was Stillroom's own testing; there hasn't been an independent security audit yet.

**Works on any Mac.** Kit pieces aren't tied to one Mac, even with [Lock to this Mac](/features/lock-to-this-mac/) on. If your Mac is lost and you've forgotten the password, enough pieces still open a copy of your vault on another Mac.

**Old kits and old backups.** Making a new kit doesn't re-key the vault. Old backups, including Time Machine copies, still open with the old kit's pieces. The app says so where you make a kit, and it's on the [security page](/security/#rules) as rule 10.

## Choosing a threshold

A lower threshold is easier to use and easier to misuse. A higher one is safer against a few people acting together, and more fragile if pieces get lost. Some plain questions help:

- Who could realistically be reached when you need the pieces?
- Could any group of that size be pressured or tempted to act together?
- Where will each piece be in five years?

Keep a note of who holds which piece number, and store each piece somewhere you'd look for important papers.
