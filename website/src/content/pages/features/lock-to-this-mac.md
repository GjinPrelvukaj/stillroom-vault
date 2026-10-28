---
title: 'Lock to This Mac: A Vault That Opens on One Mac Only'
description: 'Lock to this Mac seals your password key with your Mac''s Secure Enclave, so a copied vault folder won''t open elsewhere, even with the password.'
h1: 'Lock to this Mac'
lead: 'An extra seal from your Mac''s Secure Enclave, so the password opens your vault only on this Mac. A copy of the folder is useless anywhere else without the recovery key.'
name: 'Lock to this Mac'
updated: '27 October 2026'
order: 50
related: ['/learn/secure-enclave/', '/features/recovery-key/', '/guides/if-your-mac-is-stolen/']
faq:
  - q: 'If my vault is locked to this Mac, how do I move it to a new Mac?'
    a: 'Restore a backup on the new Mac and open it with your recovery key or emergency kit. Stillroom then asks for a new password, and the lock moves to the new Mac.'
  - q: 'Does Lock to this Mac stop the recovery key working elsewhere?'
    a: 'No. Only the password is locked to the Mac. The recovery key and the emergency kit open the vault on any Mac, which is why they matter more once this is on.'
  - q: 'Do I need Touch ID for Lock to this Mac?'
    a: 'No. It uses the Secure Enclave but needs no fingerprint. You still type your password; the Mac itself is the second thing it checks.'
---

## What it is

Normally, your Stillroom password opens your vault wherever the vault folder is. If someone copies the folder off your Mac (from a backup drive, a stolen disk, or another account), they could try guessing your password on a computer of their own, as fast as their hardware allows.

**Lock to this Mac** stops that. With it on, your password opens the vault only on this Mac. A copy of the folder on any other computer won't open with the password at all, so guessing it there is pointless. Your recovery key and emergency kit still open the vault anywhere.

## When you'd use it

- You keep backups of your Mac on drives that could be lost or taken.
- You worry that someone could copy the vault folder without you knowing, and then take their time guessing.
- Your vault lives on one Mac and you don't plan to move it often.

It pairs well with a strong password. Argon2id makes each guess cost about 280 ms on an Apple silicon Mac, but someone with a copy of the folder and powerful graphics cards can still try many guesses over time. With the lock on, that copy can't be attacked with the password at all.

You might leave it off if you move your vault between Macs regularly, or if you'd rather not depend on keeping your recovery key safe.

## How to set it up

Open your vault, go to **Settings**, then the **Access** tab, and turn on **Lock to this Mac**. The row explains what it does: the vault opens only on this Mac, even with the password, and your recovery key opens it if this Mac is lost or repaired.

Before you turn it on, make sure you know where your [recovery key](/features/recovery-key/) is. With the lock on, it becomes the way in if anything happens to this Mac.

To turn it off, use the same switch.

### Moving to a new Mac

Restore your backup on the new Mac. The lock screen says the vault is locked to another Mac and switches to the recovery key. Type it, choose a new password, and the lock moves to the new Mac.

If you also use a [decoy password](/features/decoy-password/), the other vault's password needs that vault's own recovery key once on the new Mac.

## How it works underneath

Your vault's key is sealed separately by each way in: password, recovery key and emergency kit each have their own key file. Lock to this Mac adds a second, outer seal around both vaults' password key files, and only those.

1. Stillroom asks your Mac's **Secure Enclave** to make a P-256 key. The Enclave keeps the private half on the chip, and it can't be copied off. A file called `mac.key` holds the Enclave's handle for it.
2. Stillroom combines that key with a second key by ECDH and HKDF-SHA256 to get an AES key.
3. Each password key file is sealed again with that AES key.

To unlock, the Enclave has to take part, and only this Mac's Enclave can. The key needs no fingerprint, only this Mac, unlocked. You still type your password, which is then stretched with Argon2id as usual.

Recovery key and kit files are never sealed this way, which is why they keep working anywhere. [The Secure Enclave, explained](/learn/secure-enclave/) covers the chip, and [the format page](/format/) has the exact layout.

## Limits

- **It doesn't stop someone who has your Mac and your password.** It only removes the option of guessing on another computer.
- **The recovery key and kit still open the vault anywhere.** Anyone with your recovery key and a copy of the folder can open it on any Mac. Keep the paper safe.
- **A lost, replaced or repaired Mac means using the recovery key.** The password only opens the vault on the Mac it's locked to, so anywhere else you'll need your recovery key or kit.
- **A copy of the folder shows that the lock is on.** The `mac.key` file exists or it doesn't. Since the lock covers both vaults, it doesn't say anything about a decoy.
- **It doesn't make a weak password safe on this Mac.** Someone at your Mac can still try passwords, though each wrong try is logged in the [intruder log](/features/intruder-log/) and three in a row make each next try wait longer.

Lock to this Mac is in every tier of Stillroom, the free one included.
