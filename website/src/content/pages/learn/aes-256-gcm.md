---
title: 'What Is AES-256-GCM? Authenticated Encryption Explained'
description: 'AES-256-GCM scrambles data and also proves nobody changed it. What it is, what it does not do, and exactly how Stillroom Vault uses it.'
h1: 'AES-256-GCM, explained'
lead: 'The cipher that seals every file, note and secret in Stillroom Vault, and the tamper check that comes with it.'
name: 'AES-256-GCM'
updated: '27 October 2026'
order: 10
demo: 'seal'
related: ['/learn/argon2id/', '/learn/secure-enclave/', '/guides/encrypt-files-on-mac/', '/features/view-without-decrypting/']
faq:
  - q: 'Can AES-256 be broken?'
    a: 'No practical attack on AES-256 is publicly known. In real systems the weak points are elsewhere: a guessable password, a key that leaks, or a device that is compromised while the data is open.'
  - q: 'What is the difference between AES-256 and AES-256-GCM?'
    a: 'AES-256 is the block cipher itself. GCM is a mode of operation that uses AES to encrypt data of any length and adds an authentication tag, so any change to the sealed data is detected.'
  - q: 'Does Stillroom Vault use the same key for every file?'
    a: 'No. Every sealing of every item, including each earlier version, gets its own fresh 32-byte key, which is kept inside the sealed list.'
  - q: 'Does encryption hide how big my files are?'
    a: 'Not completely. Stillroom pads each item before sealing, so a sealed file gives away its real size only to within about 12 percent.'
sources:
  - label: 'NIST FIPS 197: Advanced Encryption Standard (AES)'
    url: 'https://csrc.nist.gov/pubs/fips/197/final'
  - label: 'NIST SP 800-38D: Galois/Counter Mode (GCM) and GMAC'
    url: 'https://csrc.nist.gov/pubs/sp/800/38/d/final'
  - label: 'Apple Developer: CryptoKit AES.GCM'
    url: 'https://developer.apple.com/documentation/cryptokit/aes/gcm'
---

## What AES-256-GCM is

AES-256-GCM is a way to encrypt data so that it is both **unreadable** and **tamper-evident**. It has two parts.

**AES** (the Advanced Encryption Standard) is a block cipher published by the US National Institute of Standards and Technology (NIST) in 2001 as FIPS 197. It takes 16 bytes of data and a key, and turns them into 16 bytes that look random. With the same key you can turn them back. The "256" is the key length in bits: there are 2²⁵⁶ possible keys, a number so large that trying them all is not something any computer can do.

**GCM** (Galois/Counter Mode) is a way of using AES on data of any length, standardized by NIST in SP 800-38D. It does two jobs at once: it encrypts, and it produces a short **authentication tag** that proves the result has not been changed. Encryption that also detects changes is called *authenticated encryption*.

## The problem it solves

Encryption alone answers one question: can someone read this? It does not answer a second, equally important one: has someone changed this?

Without a tamper check, an attacker who can't read your data might still flip bits in it, cut it short, or swap one encrypted file for another, and your software would happily decrypt the result. Depending on the format, that can corrupt data quietly or even leak information. GCM closes that gap. If a single byte of the sealed data, or its tag, is different, opening it fails. There is no "mostly opened" state.

## How it works, with an analogy

Picture a box with a combination lock, sealed shut with a wax seal that carries a stamp only the key holder can make.

- The **lock** is AES. Without the key, the contents are just noise.
- The **wax seal** is the GCM tag. If anyone pries the box open, cuts a corner off or swaps the lid, the seal no longer matches and you know before you trust anything inside.
- The **nonce** is a serial number stamped on each box. GCM needs a value that is never used twice with the same key, because reusing one with the same key breaks both the secrecy and the seal. That is the one rule GCM is strict about.

GCM can also cover **authenticated data**: a label that is not encrypted or even stored with the box, but is mixed into the seal. To open the box you must state the label again, exactly. Think of it as writing "tax return, 2025" into the wax. If someone moves that box onto the shelf where "medical records" should be, the label you give no longer matches the seal, and it won't open.

The analogy has a limit. A real wax seal can be faked by a good forger. The GCM tag can't be forged without the key, short of a practically impossible guess.

## What it does not do

AES-256-GCM is very good at its job, and its job is narrow.

- **It doesn't protect a weak key.** If the key comes from a guessable password, the attacker guesses the password instead. That is why Stillroom stretches the password with [Argon2id](/learn/argon2id/) and its strength check refuses guessable ones.
- **It doesn't hide sizes or timing.** A sealed file is about as big as what's inside it, and its date shows when it was written.
- **It doesn't protect data while it's open.** Once decrypted and on screen, contents sit in ordinary memory. Malware with admin rights on a Mac with an open vault sees everything.
- **It doesn't stop rollback.** Someone who can write to your files could put back an older, genuine sealed copy. Its seal is valid, because it was real once.

## How Stillroom Vault uses it

Everything Stillroom keeps is sealed with AES-256-GCM through Apple's CryptoKit. The details below come from the public [file format](/format/) and the [security rules](/security/#rules).

**The sealed layout.** Each sealing is stored as a 12-byte nonce, the ciphertext, then a 16-byte tag. Change any byte and it fails to open.

**A fresh key for every sealing.** Each item, and each earlier version of it, is sealed with its own **item key**: 32 random bytes made fresh every time it's sealed. Item keys are kept inside the vault's sealed list, never next to the file. The list is sealed with the vault's own 32-byte slot key, which is itself sealed by each way in (password, recovery key, emergency kit, Touch ID).

**Labels that bind each piece to what it is.** Stillroom uses authenticated data throughout:

- a one-piece item is bound to `Vault item 3` and its own 16-byte id (`sealedAs`)
- the list is bound to `Vault list 3`, and the search index to `Vault search 3`
- each slot's covers are bound to their kind (list or search) and slot letter

So a sealed file copied into another's place, an older version passed off as the current one, or one slot's list swapped for the other's all fail to open. The security rules call this "every sealed item, the list, the search index and their covers are bound to what they are".

**Big files in chunks.** Items over 8 MB, and all audio and video, are sealed in 1 MiB chunks. Each chunk is bound to that sealing's id, its position, and whether it's the last one. Cutting a file short, reordering chunks, duplicating them or swapping chunks between files are all refused. This is also what lets audio and video play straight from the sealed file, a range at a time.

**Padding to blur sizes.** Before sealing, each item is padded (a scheme called Padmé), so its sealed size gives away its real size only to within about 12%. Names, folders, tags and contents never show.

**What still shows.** Someone with a copy of the folder can see how many items and versions there are, roughly how big each is, and when files were added. The [security page](/security/) lists exactly what's visible.

## Reading it without Stillroom

Because AES-256-GCM is a public standard and Stillroom's [format](/format/) is published, you don't need Stillroom to open your own vault. `tools/stillroom-open.py`, about 300 lines of Python under the MIT licence, reads a vault with its password, recovery key or kit pieces. Publishing the format gives nobody else a way in: the security comes from the keys, not from keeping the method secret.
