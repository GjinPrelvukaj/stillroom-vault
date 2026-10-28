---
title: 'Decoy Password: A Second Vault for When You Are Forced'
description: 'How the decoy password opens a second, harmless vault, how to set one up, how it works on disk, and exactly what it cannot hide.'
h1: 'Decoy password'
lead: 'A second password that opens a separate, harmless vault, for when someone makes you open Stillroom in front of them. Read the limits before you rely on it.'
name: 'Decoy password'
updated: '27 October 2026'
order: 10
related: ['/learn/plausible-deniability/', '/for/leaving-an-abusive-relationship/', '/features/touch-id/', '/features/intruder-log/']
faq:
  - q: 'Can I use the decoy password at a border crossing or with the police?'
    a: 'No. Stillroom is built as protection against thieves and abusers, not police. Someone with one password and a copy of the vault folder can see that the other vault holds something, and misleading officials can carry legal consequences of its own.'
  - q: 'Does setting a decoy password delete anything?'
    a: 'Yes. Setting a decoy replaces the other vault with a new, empty one, so whatever it held is deleted. Setting one from inside the decoy deletes the real vault, because it is the same Settings row in both.'
  - q: 'Does Touch ID open the decoy or the real vault?'
    a: 'Touch ID opens one vault: the one where it was last turned on. If you rely on the decoy, turn Touch ID on in the decoy or not at all, since a forced finger opens the vault it belongs to.'
  - q: 'Is there a decoy even if I never set one?'
    a: 'Yes. Every Stillroom folder holds two slots built alike. Until you set a decoy, the second slot is a real vault whose password nobody knows, so an unset decoy and a set, empty one look the same.'
---

## What it is

Stillroom keeps two vaults in one folder. They're called slots `a` and `b`, and they're built exactly alike. Your vault goes into one of them at random when you make it, and nothing anywhere records which.

The decoy password is a password for the other slot. Type it at the lock screen and a complete, ordinary looking vault opens: its own files, its own recovery key, its own emergency kit, the same Settings rows and the same intruder log. Type your real password and your real vault opens. The lock screen is the same either way.

It's meant for one situation: someone standing over you, making you open Stillroom in front of them. You give them the decoy password, and they see a vault with a few harmless things in it.

## Read this first: what it doesn't do

The decoy is protection against thieves and abusers, not police. Don't use it to mislead police, border officers or a court. Beyond the legal risk, it is not built to stand up to that kind of examination, for these reasons (from [rule 2 of the security rules](/security/#rules)):

- **Someone with one password and a copy of the folder can tell another vault holds something.** They can see sealed files and a list size their vault doesn't account for, so they learn that the other slot holds something and roughly how much, though not what. Hiding that would take a fixed-size container filled with noise from the start, which reserves disk space from day one and still fails against copies taken at different times.
- **Copies taken at different times show when ways in changed.** A new password, recovery key or kit rewrites only that slot's file, and setting or removing a decoy rewrites the whole other slot folder. Everyday use (adding, editing, searching) doesn't show.
- **Touch ID opens one vault**, the one where it was last turned on, because a finger can't choose. If you rely on the decoy, turn Touch ID on in the decoy or not at all.
- **Setting a decoy from inside the decoy deletes the real vault.** It's the same row in both vaults.
- **Other apps remember names.** Recent Items or Quick Look's thumbnail cache can keep names from Edit in Place and previews, and a name not in the decoy points to another vault. Don't Edit in Place or preview names you'd need to deny, or clear Recent Items afterwards.
- **Forensic tools** can see each file's inode change time, which no app can set. The two slots are made in a random order, so which one is newer says nothing on its own.
- **After moving a Mac-locked vault to a new Mac** with a recovery key, the other vault's password needs its own recovery key once.
- **The activity log**, if you turn it on, could over many days hint through its timings that two vaults are used. It's off by default; keep it off if you rely on a decoy.

## When you'd use it

- You live with someone who checks your Mac and might demand you open Stillroom.
- You're worried about a robbery or a mugging where someone forces you to unlock your laptop.
- You want the vault on your Mac to look like something you'd be comfortable showing.

If your worry is a court order, a police search or a border inspection, the decoy is the wrong tool. Talk to a lawyer about your rights instead.

## How to set it up

The decoy is set from inside your real vault:

1. Open your vault and go to **Settings**, then the **Access** tab.
2. Next to **Decoy password**, click **Set…**.
3. Choose a password for the decoy (at least 12 characters).
4. Stillroom shows the decoy's own recovery key. Write it down like you did for your real one.
5. Lock Stillroom, open it with the decoy password, and add a few harmless files so it looks used.

Setting a decoy deletes whatever the other vault held and starts it empty. To take a decoy away, click **Remove…** on the same row: the decoy password stops opening anything and everything in that vault is deleted.

A password you set or change is checked so that it doesn't open the other slot. That check answers a guess, so each one counts as a wrong try at the lock screen.

## How it works underneath

Each slot has its own 32-byte slot key, sealed separately by its own password, recovery key and kit, all stretched with Argon2id. When you make a vault, the other slot is made by the same code with a random password, recovery key and kit secret that are thrown away. Setting a decoy replaces that slot with a new, empty vault whose password you choose. That's why an unset decoy and a set, empty one are the same thing on disk.

To keep the two slots from standing out:

- **At the keyboard:** unlock tries every password, recovery key and kit on both slots, so the time it takes says nothing about which one opened.
- **In one copy of the folder:** both slots hold the same files, the folder letters say nothing, and items from both share one `Files/` folder under names only a slot can tell apart. Every key file has the same dates, so a decoy set a year later leaves nothing newer.
- **Across copies taken at different times:** every save rewrites both slots' lists and both search indexes, inside covers of one size with one date. Added items can't be told apart by slot.
- **In logs and preferences:** nothing slot-specific is written. Per-vault settings live inside each slot's sealed list.
- **In the intruder log:** it's shared by both vaults and never keeps what was typed, since that would show the decoy's holder your typos of the real password.

The full on-disk layout is in [the format](/format/).

## Limits, plainly

The decoy holds up against someone at the keyboard, and against someone with a copy of the folder but no password. It does not hold up against someone with one password and a copy of the folder. It's a deterrent against coercion by a person in the room, not a way to make a vault vanish. Every tier of Stillroom, the free one included, has it.
