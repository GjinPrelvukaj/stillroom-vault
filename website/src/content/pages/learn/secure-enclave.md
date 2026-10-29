---
title: 'What Is the Secure Enclave on a Mac? Explained'
description: "What Apple's Secure Enclave is, what it protects and what it doesn't, and how Stillroom Vault uses it for Touch ID and Lock to this Mac."
h1: 'The Secure Enclave, explained'
lead: 'A small, separate computer inside your Mac that holds keys and never hands them out, and what that makes possible.'
name: 'Secure Enclave'
updated: '27 October 2026'
order: 40
theme: 'night'
related: ['/features/touch-id/', '/features/lock-to-this-mac/', '/learn/aes-256-gcm/', '/guides/if-your-mac-is-stolen/']
faq:
  - q: 'Does every Mac have a Secure Enclave?'
    a: 'Every Apple silicon Mac does, and so did Intel Macs with the Apple T2 chip. Stillroom Vault runs on Apple silicon only.'
  - q: 'Does Stillroom get my fingerprint?'
    a: 'No. Touch ID data stays inside the Secure Enclave. Stillroom only learns whether macOS accepted a finger, and then asks the Secure Enclave to use a key on its behalf.'
  - q: 'If my Mac breaks, can I still open my vault?'
    a: 'Yes, with your password, recovery key or emergency kit. Touch ID and the Lock to this Mac seal only work on the Mac that made them, which is why the other ways in never depend on them.'
  - q: 'Can Apple open my vault through the Secure Enclave?'
    a: 'The Secure Enclave key alone never opens a Stillroom vault. Touch ID also needs your enrolled finger, and Lock to this Mac still needs your password.'
sources:
  - label: 'Apple Platform Security: Secure Enclave'
    url: 'https://support.apple.com/guide/security/secure-enclave-sec59b0b31ff/web'
  - label: 'Apple Platform Security: Touch ID and Face ID security'
    url: 'https://support.apple.com/guide/security/touch-id-and-face-id-security-sec067eb0c9e/web'
  - label: 'Apple Developer: CryptoKit SecureEnclave'
    url: 'https://developer.apple.com/documentation/cryptokit/secureenclave'
---

## What the Secure Enclave is

The Secure Enclave is a separate, locked-down subsystem built into Apple's chips. Apple describes it as isolated from the main processor, with its own boot process and its own memory protection. It's in every Apple silicon Mac, as well as iPhones and iPads.

Its job is to look after secrets that even macOS shouldn't be able to read: the data behind Touch ID, and private keys that apps ask it to create. An app can ask the Secure Enclave to make a key and use it, but the raw key never leaves the chip. The app gets back an opaque handle that only that one chip can make sense of.

## The problem it solves

Normally, an encryption key is just bytes in a file or in memory. Anything that can copy those bytes can use the key anywhere, on any machine, at any time, as often as it likes.

The Secure Enclave changes that. A key made inside it:

- **can't be copied off the Mac**, so a stolen file holding its handle is useless elsewhere
- **can require a condition** before every use, such as a fingerprint matched by Touch ID
- **stays out of reach of the main processor**, so even code running as the system can only ask the Enclave to use it, not read it

## How it works, with an analogy

Think of a notary sitting in a sealed booth with a slot in the glass. You pass a document through the slot, the notary stamps it with a stamp that never leaves the booth, and passes it back. You can ask for as many stamps as you like (if you meet the booth's rules, such as showing your fingerprint), but you can never take the stamp home or make a copy of it.

Apps work with the Secure Enclave the same way. They pass data in, ask it to sign, decrypt or agree on a key, and get the result back. Touch ID fits the same pattern: the fingerprint sensor talks to the Secure Enclave, the match happens there, and macOS and apps only hear "yes" or "no".

The analogy's limit: a booth could have a corrupt notary. The Secure Enclave's rules are enforced by hardware and its own firmware, not by trust in a person.

## What it does not do

- **It doesn't encrypt your vault's files itself.** The Enclave guards a few small keys; the bulk encryption is done in ordinary software with [AES-256-GCM](/learn/aes-256-gcm/).
- **It doesn't protect data once it's out.** When a vault is open, decrypted contents are in ordinary memory, and malware with admin rights could see them.
- **It doesn't make a key portable.** That's the point, and also the cost: if the Mac dies, any key tied to its Secure Enclave is gone too.
- **It doesn't stop someone forcing your finger** onto the sensor. Touch ID proves a finger matched, not that you agreed.

## How Stillroom Vault uses it

Stillroom uses the Secure Enclave for two optional ways to lock things to one Mac. Both are described in the public [file format](/format/) and the [security rules](/security/#rules). Neither replaces your password, [recovery key](/features/recovery-key/) or [emergency kit](/features/emergency-kit/), which work without it.

### Touch ID

When you turn on [Touch ID](/features/touch-id/), Stillroom asks the Secure Enclave for a new P-256 key that can only be used after a matched fingerprint, and only on this Mac. It then combines that key with a fresh one of its own (an ECDH key agreement, followed by HKDF-SHA256) to make a wrapping key, and seals the vault's own key with it into `touchid.key`.

To unlock, macOS asks for your finger. Once it matches, the Secure Enclave performs its half of the key agreement, the wrapping key is rebuilt, and the vault key comes out. Stillroom never sees your fingerprint.

Two details from the source matter in practice:

- The key is made so that **adding a new finger to Touch ID later makes it unusable**. A finger enrolled after you turned it on can't open the vault. Stillroom then asks you to use your password and turn Touch ID on again in Settings.
- The file is **useless on any other Mac**, and on this Mac without a matching finger.

Touch ID opens one vault: the one where it was last turned on, because a finger can't choose. If you use a [decoy password](/features/decoy-password/), read [plausible deniability](/learn/plausible-deniability/) first, since a forced finger opens the vault it belongs to.

### Lock to this Mac

[Lock to this Mac](/features/lock-to-this-mac/) adds an outer seal around the password key files. Stillroom keeps a Secure Enclave P-256 key in `mac.key`, derives an AES key from it by ECDH and HKDF-SHA256, and seals both password key files a second time with it. That outer seal only opens on this Mac.

The effect: someone who copies your vault folder and also learns your password still can't open it elsewhere with the password alone. They'd need this Mac, or your recovery key, or enough kit pieces.

The recovery key and kit are never locked this way, on purpose. They're how you get back in if your Mac is lost, stolen or broken.

## When to use these

- **Touch ID** is a convenience. It saves typing a long password many times a day, while your password stays the real protection behind it.
- **Lock to this Mac** suits a vault that should only ever be opened on one machine. Before turning it on, make sure your recovery key or kit is somewhere safe and away from the Mac.
- **Neither** helps if you lose every other way in. Stillroom can't recover a forgotten password, and nobody else can either.
