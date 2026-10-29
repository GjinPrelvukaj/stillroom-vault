---
title: 'What Is Argon2id? Password Hashing Explained'
description: 'Argon2id turns a password into a key slowly and with lots of memory, so every guess costs an attacker. How it works, and how Stillroom Vault uses it.'
h1: 'Argon2id, explained'
lead: 'Why a vault turns your password into a key slowly on purpose, and what the memory cost buys you.'
name: 'Argon2id'
updated: '27 October 2026'
order: 20
related: ['/tools/password-strength/', '/tools/passphrase-generator/', '/learn/aes-256-gcm/', '/features/recovery-key/', '/features/emergency-kit/', '/learn/shamir-secret-sharing/']
faq:
  - q: 'Is Argon2id better than PBKDF2 or bcrypt?'
    a: 'For new designs it is generally preferred because it is memory-hard: each guess needs a large block of memory, which makes cheap parallel guessing on graphics cards and custom chips much more expensive. RFC 9106 recommends Argon2id as the default variant.'
  - q: 'Does Argon2id make a weak password safe?'
    a: 'No. It makes each guess slower and more expensive, but a password near the top of a guessing list still falls quickly. A strong password is still the real protection.'
  - q: 'Why does unlocking take a moment?'
    a: 'Stillroom stretches your password with Argon2id using 512 MB of memory and 3 passes, which takes about 280 ms on an Apple silicon Mac. Every guess an attacker makes costs the same.'
  - q: 'Can Stillroom recover my password?'
    a: 'No, and nobody else can either. Use your recovery key or emergency kit if you made one.'
sources:
  - label: 'RFC 9106: Argon2 Memory-Hard Function for Password Hashing and Proof-of-Work Applications'
    url: 'https://www.rfc-editor.org/rfc/rfc9106'
  - label: 'Password Hashing Competition'
    url: 'https://www.password-hashing.net/'
  - label: 'Argon2 reference implementation (P-H-C/phc-winner-argon2)'
    url: 'https://github.com/P-H-C/phc-winner-argon2'
---

## What Argon2id is

Argon2id is a **password hashing function**, also called a key derivation function. It takes something a person can remember, your password, and turns it into a 32-byte key that encryption can use. It does that deliberately slowly, and with a deliberately large amount of memory.

Argon2 won the Password Hashing Competition in 2015, an open contest run by cryptographers to find a successor to older schemes. In 2021 it was published by the IETF as RFC 9106. It comes in three variants, and Argon2id is the one RFC 9106 recommends as the default.

## The problem it solves

A good encryption key is 32 random bytes. Nobody can guess that. A password is different: people choose them, and people choose from a much smaller pool. An attacker with a copy of your encrypted data doesn't try keys, they try passwords, starting with the likeliest ones.

If turning a password into a key took a microsecond, they could try billions a second. Argon2id makes each attempt cost real time and, more importantly, real memory. You pay that cost once when you unlock. An attacker pays it for every single guess.

## How it works, with an analogy

Imagine a lock that only opens after you fill a huge whiteboard with numbers, where each number depends on earlier ones scattered across the board, and you go over the whole board several times. The last number you write is the key.

- You can't skip ahead, because every step needs earlier results.
- You can't use a small whiteboard and redo the missing parts, because that makes the work grow sharply.
- You can't buy a million tiny cheap whiteboards to work in parallel, because each attempt needs a full-size one.

That last point is what **memory-hard** means, and it's the main reason Argon2 exists. Graphics cards and custom chips are very good at running many small calculations side by side, but memory is expensive for them. Forcing every guess to use hundreds of megabytes takes away much of their advantage.

Argon2id has a few settings:

- **Memory**: how big the whiteboard is.
- **Passes** (also called iterations): how many times you go over it.
- **Lanes** (parallelism): how many strips the board is split into, so several processor cores can work at once.
- **Salt**: random bytes stored with the result, so the same password gives a different key in every vault and precomputed tables are useless.

The "id" is a hybrid. RFC 9106 describes it as working like Argon2i for the first half of the first pass, which resists side-channel attacks, and like Argon2d for the rest, which gives the strongest protection against guessing hardware.

## What it does not do

Argon2id slows guessing. It doesn't stop it.

- **A weak password is still weak.** If your password is near the top of a list of common ones, an attacker reaches it in a handful of guesses, however slow each one is.
- **It doesn't protect against someone watching you type**, or malware on a Mac that's already unlocked.
- **It can't help you remember.** A slow, salted key derivation has no back door, and that's the point.

## How Stillroom Vault uses it

Every way in to a Stillroom vault that you type (the password, the recovery key and the emergency kit's secret) is stretched by Argon2id into the key that seals the vault's own key. The facts below are from the public [file format](/format/) and the [security rules](/security/).

**The settings.** New vaults use Argon2id version 0x13 with **512 MB of memory, 3 passes and 4 lanes**, a 16-byte random salt and a 32-byte output. For comparison, RFC 9106 offers two general recommendations: 2 GiB with 1 pass, or 64 MiB with 3 passes, both with 4 lanes. Stillroom's setting sits between them. The settings and salt are stored in each key file's header, so a reader always knows how to repeat the work.

**What a guess costs.** Each guess costs the full stretch: about 280 ms on an Apple silicon Mac. A black-box test of Stillroom in October 2026 estimated roughly 10 to 30 guesses a second per high-end graphics card. That is strong but ordinary, so your password's own strength is the real boundary. That's why Stillroom's strength check refuses guessable passwords, rather than relying on the stretch to make them safe. You can run the same check in your browser with the [password strength checker](/tools/password-strength/).

**The reference code.** Stillroom runs the Argon2 reference implementation (P-H-C/phc-winner-argon2, release 20190702), copied unchanged into the app. Anyone checking Stillroom can see it uses the same code everyone else checks. An earlier Swift implementation stays in the tests as an independent second implementation: the tests compare the two on 80 parameter combinations, against the RFC 9106 test vector, and against three answers from libargon2.

**Guarding against doctored files.** Because the settings live in the key file, someone could edit them to make unlocking hang. Stillroom refuses costs outside 1 to 16 lanes, 1 to 10 passes, and memory up to 2 GiB, treating such a file as damaged.

**Wrong tries.** The lock screen counts wrong tries and can keep an [intruder log](/features/intruder-log/), but the security rules are clear that those deter someone at the keyboard. Against a copy of the folder, Argon2id is what slows guessing.

## If you forget your password

Nobody can recover it: not Stillroom, not its makers, not anyone with the source code. There's no master key. What you can do is open the vault another way: with your [recovery key](/features/recovery-key/), or enough pieces of your [emergency kit](/features/emergency-kit/). Both are also stretched with Argon2id. See [forgot your password](/support/#forgot) for the steps.
