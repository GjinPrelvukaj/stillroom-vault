---
title: 'Touch ID: Open Your Vault With a Fingerprint'
description: 'How Stillroom opens with Touch ID through a key in your Mac''s Secure Enclave, how to turn it on, and what to know before using it with a decoy.'
h1: 'Touch ID'
lead: 'Your finger opens the vault with a key that never leaves your Mac''s Secure Enclave. Your password still works whenever you need it.'
name: 'Touch ID'
updated: '27 October 2026'
order: 40
related: ['/learn/secure-enclave/', '/features/lock-to-this-mac/', '/features/decoy-password/']
faq:
  - q: 'Does Touch ID replace my password?'
    a: 'No. The password is the way in that always works, and Stillroom always offers it at the lock screen. Touch ID is a quicker way in on this one Mac.'
  - q: 'What happens if I add a new fingerprint to my Mac?'
    a: 'The Touch ID key stops working, so a newly added finger can''t open the vault. Open it with your password, then turn Touch ID on again in Settings.'
  - q: 'Does Touch ID work if someone copies my vault to another Mac?'
    a: 'No. The key Touch ID uses lives in this Mac''s Secure Enclave and can''t be read off it, so the Touch ID file is useless anywhere else.'
  - q: 'Can Touch ID open both my real vault and my decoy?'
    a: 'No. It opens one vault, whichever one last turned it on. If you rely on a decoy, turn Touch ID on in the decoy or not at all.'
---

## What it is

With Touch ID on, Stillroom asks for your fingerprint as soon as the lock screen appears. Touch the sensor and your vault opens, without typing your password.

The password never stops working. It's always there on the lock screen, and so are the recovery key and the emergency kit. Touch ID is a quicker way in on this one Mac, not a replacement for anything.

## When you'd use it

- You open Stillroom many times a day and want it to lock quickly (on sleep, after a few idle minutes, or with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd>) without making every unlock slow.
- You work in places where someone might watch you type a password.
- Your Mac has Touch ID set up.

Stillroom locks itself when your Mac sleeps, when its screen locks, when Stillroom quits, or after the idle time you choose in Settings. Touch ID makes that habit cheap: a short auto-lock costs you a touch rather than a long password.

You might leave it off if anyone could force your finger onto the sensor, or if you rely on a [decoy password](/features/decoy-password/) (see the limits below).

## How to set it up

There are two places to turn it on:

- **When you make your vault:** the lock screen offers **Open it with Touch ID too** below the password fields. It's on by default when your Mac has Touch ID set up.
- **Later:** open your vault, go to **Settings**, then the **Access** tab, and turn on **Open with Touch ID**.

If your Mac has no Touch ID set up, the row says so and the switch is greyed out. Set up a fingerprint in System Settings first.

To turn it off, use the same switch. The Touch ID file is removed and only the other ways in remain.

## How it works underneath

Your vault has a 32-byte slot key, which seals your item list and search index. Every way in (password, recovery key, emergency kit) holds its own sealed copy of that key. Touch ID adds one more copy, in a file called `touchid.key` at the top of the vault folder.

That copy is sealed by a key made inside your Mac's **Secure Enclave**, the separate security chip in Apple silicon Macs. The Enclave key can't be copied off the chip, and Stillroom asks macOS to make it usable only:

- on this Mac, while it's unlocked
- after a fingerprint check
- with the fingerprints enrolled when the key was made

That last point matters. If anyone adds a fingerprint to your Mac later, the key stops working, so a newly added finger can't open your vault. You'll see "Touch ID couldn't open it" at the lock screen. Open with your password, then turn Touch ID on again in Settings.

When your finger is accepted, the Enclave releases the sealing key, Stillroom opens `touchid.key`, and tries the slot key it finds against both vaults to see which one it belongs to. [The Secure Enclave, explained](/learn/secure-enclave/) has more on the chip.

## Limits

- **Touch ID opens one vault.** A finger can't choose between your real vault and a decoy, so it opens the one where it was last turned on. Turning it on in one vault moves it from the other. If you rely on a decoy, turn Touch ID on in the decoy or not at all: a forced finger opens the vault it belongs to. In the vault that doesn't have it, the row reads off.
- **A copy of the folder shows that Touch ID is on.** The `touchid.key` file exists or it doesn't. It doesn't show which vault it belongs to.
- **It works on one Mac only.** On a new Mac, open your vault with the password or recovery key and turn Touch ID on again.
- **Someone who can force your finger can open the vault.** Touch ID protects against someone who sees your screen, not against someone who controls your hand. Locking the vault and using the password is safer in that situation.
- **It's only as strong as your Mac's own Touch ID.** Stillroom relies on Apple's sensor and Secure Enclave for the fingerprint check.

Touch ID is in every tier, the free one included, on any Apple silicon Mac with Touch ID set up.
