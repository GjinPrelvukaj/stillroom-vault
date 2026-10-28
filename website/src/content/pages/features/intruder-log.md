---
title: 'Intruder Log: See Who Tried to Open Your Vault'
description: 'Stillroom records wrong passwords and recovery keys at the lock screen, with an optional photo, sealed so only an open vault can read them.'
h1: 'Intruder log'
lead: 'Every wrong password or recovery key typed at the lock screen, with the date and, if you allow the camera, a photo. Sealed so only your open vault can read it.'
name: 'Intruder log'
updated: '27 October 2026'
order: 60
related: ['/features/decoy-password/', '/guides/secure-a-shared-mac/', '/for/leaving-an-abusive-relationship/']
faq:
  - q: 'Does the intruder log record what the person typed?'
    a: 'No. It keeps the date, whether it was a wrong password or a wrong recovery key, and a photo if the camera is allowed. It never keeps what was typed.'
  - q: 'Will the camera light come on when a photo is taken?'
    a: 'Yes. The camera light comes on for a second when Stillroom takes a photo of whoever typed a wrong password.'
  - q: 'Can someone delete the intruder log without opening my vault?'
    a: 'Someone who can write to the vault folder can delete files in it, including the log. They can''t read it without opening a vault. The log is a deterrent and a record, not protection.'
  - q: 'Why do my own typos show up?'
    a: 'Because a wrong try at the lock screen looks the same whoever makes it. Stillroom can''t tell your typo from someone else''s guess, so it records both.'
---

## What it is

The intruder log is a list of failed attempts to open your vault. Each entry has:

- the date and time
- what kind of try it was: **Wrong password** or **Wrong recovery key**
- a photo of whoever was at the Mac, if you allowed the camera

It shows in the sidebar as **Intruder Log**, with a count of entries you haven't seen yet. The page reads "No one has tried" when it's empty. You can delete a single entry or clear the whole log.

## When you'd use it

- You share a home or office and want to know if someone has been trying to get into your vault while you were away.
- You're concerned about a partner or family member who checks your devices.
- You left your Mac somewhere and want to see whether anyone tried.
- You want a photo of who it was, not just a count, if someone tries while you're out of the room.

It's a record and a deterrent. It doesn't stop anyone guessing; what slows guessing is Argon2id, which makes every try cost the full password stretch, and the lock screen, which makes each next try wait longer after three wrong passwords in a row.

## How to set it up

The log itself needs no setting up: wrong tries are recorded from the start.

The photo is optional. To turn it on:

1. Open your vault, go to **Settings**, then the **Protection** tab.
2. Under **Intruder log**, click **Allow Camera…** and accept macOS's camera prompt.
3. Turn on **Take a photo**.

Stillroom asks for camera access while your vault is open on purpose, so the question never appears in front of someone at the lock screen. If you said no earlier, turn the camera on for Stillroom in System Settings, Privacy & Security, Camera.

## How it works underneath

A wrong try happens while the vault is locked, so Stillroom has no key to seal anything with in the usual way. The log uses public-key encryption instead:

- Each vault (each slot) has its own X25519 key pair. The public halves sit in the open in a file called `intruder.pub`. The private halves are inside each vault's sealed list.
- When someone types a wrong password, Stillroom seals the entry (date, kind and photo) with **HPKE** (X25519, HKDF-SHA256 and ChaCha20-Poly1305) to both public keys, and writes it as one file in the `intruder/` folder.
- Only a vault that's open holds a private key, so only an open vault can read the entries.

A wrong try doesn't say which vault it was aimed at, so it belongs to both. That's also why the log is the same in your vault and in a [decoy](/features/decoy-password/): whichever one you open, you see the same entries.

## Why it never keeps what was typed

It would be useful to see what someone guessed. Stillroom deliberately doesn't keep it. The log is shared by both vaults, so if it held the typed text, whoever knows the decoy password could read your typos of the real password. A near miss is often most of a password. The log keeps the date, the kind and a photo, and nothing else.

## Limits

- **It's a deterrent for someone at the keyboard, not protection.** It doesn't stop anyone from trying, and it can't stop someone who copied the vault folder from guessing on another computer. For that, see [Lock to this Mac](/features/lock-to-this-mac/).
- **Your own typos are in it too.** Every wrong try at the lock screen is recorded, whoever made it.
- **Someone with access to the folder can delete it.** They can't read entries without opening a vault, but they can remove them. The public keys are in the open by design, so someone with the folder could also add entries of their own.
- **A photo needs the camera to be allowed.** If someone covers the camera, or the Mac has none available, you get the date and kind only. The camera light comes on for a second when a photo is taken, so the person will see it.
- **It records tries at Stillroom's lock screen only.** Someone guessing with a copy of the folder elsewhere leaves no entry.

The intruder log is in every tier of Stillroom, the free one included.
