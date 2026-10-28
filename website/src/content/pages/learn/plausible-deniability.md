---
title: 'Plausible Deniability in Encryption, and Its Limits'
description: 'What plausible deniability means for encrypted data, where it breaks down, and exactly what Stillroom Vault’s decoy password does and doesn’t do.'
h1: 'Plausible deniability, explained'
lead: 'What a decoy can and can’t hide, who it’s meant to protect you from, and the honest limits of Stillroom’s decoy password.'
name: 'Plausible deniability'
updated: '27 October 2026'
order: 50
related: ['/features/decoy-password/', '/for/leaving-an-abusive-relationship/', '/learn/secure-enclave/', '/guides/secure-a-shared-mac/']
faq:
  - q: 'Is a decoy password the same as a hidden volume?'
    a: 'No. A hidden volume sits inside a fixed-size container filled with random data from the start. Stillroom’s decoy is a second vault built exactly like yours, which avoids reserving disk space but means someone with one password and a copy of the folder can tell the other vault holds something.'
  - q: 'Can I use a decoy password with the police or at a border?'
    a: 'No. Stillroom’s decoy is designed and sold as protection against thieves and abusers, not police. Misleading police, border officers or a court can be an offence in itself, and the decoy is not built to stand up to a forensic examination.'
  - q: 'Should I turn on Touch ID if I use a decoy?'
    a: 'Only in the decoy, or not at all. A finger can’t choose a vault, so Touch ID opens the one where it was last turned on, and a forced finger opens that one.'
  - q: 'Does Stillroom always have two vaults?'
    a: 'Yes. Every vault folder holds two slots built alike, and the one you don’t use is a real vault whose passwords nobody knows. Setting a decoy replaces it with an empty vault whose password you choose.'
sources:
  - label: 'VeraCrypt documentation: Hidden Volume'
    url: 'https://veracrypt.io/en/Hidden%20Volume.html'
  - label: 'Czeskis et al., Defeating Encrypted and Deniable File Systems (USENIX HotSec 2008)'
    url: 'https://www.usenix.org/legacy/event/hotsec08/tech/full_papers/czeskis/czeskis.pdf'
---

## What plausible deniability means

In encryption, **plausible deniability** is the idea that you can hand over a password and open something real, while what you most care about stays hidden, and nothing on the screen or on disk proves there's more.

The usual way to offer it is a **decoy**: a second password that opens a harmless set of data. Someone who forces you to unlock sees something believable and, ideally, has no way to show that a second set exists.

## The problem it tries to solve

Strong encryption protects data from someone who doesn't have the key. It doesn't help when someone stands over you and demands the key. A thief who has taken your laptop, or a partner who controls your devices, may not care about mathematics; they care whether you open it.

A decoy gives you something to open. It can end the demand quickly and safely, without exposing the things you need to keep private, such as documents you're gathering to leave an abusive relationship.

## How it works, with an analogy

Picture a house with two identical safes behind the same panel. Each has its own combination. When someone demands "the" combination, you give one, and that safe opens with a plausible set of papers inside. The other safe looks just the same from outside, and every house has two of them, so its presence alone proves nothing.

The analogy shows where the hard part is. The safes look alike from outside, but a careful visitor with time can still learn things: how heavy each one is, whether one was opened last week, or whether a receipt in the kitchen mentions a document that isn't in the safe you opened. Real-world deniability fails in exactly these ways.

## Where deniability breaks down in practice

Deniability is a property of the whole situation, not only of the encryption. Known limits include:

- **Sizes and space.** If someone can open one vault and also see how much encrypted data exists in total, a gap points to something else. Some tools, VeraCrypt for example, offer a hidden volume inside the free space of a fixed-size container to make that gap invisible, at the cost of reserving the space up front.
- **Copies over time.** Someone who copies your encrypted data at two different times can compare them and see which parts changed.
- **The rest of the computer.** Researchers showed in 2008 (Czeskis and others, on TrueCrypt hidden volumes) that the operating system and ordinary apps can leak the existence and contents of hidden data, through recent-file lists, shortcuts and caches.
- **People.** A determined adversary may simply not believe you, whatever the software shows.
- **The law.** In many countries, misleading police, border officers or a court can be an offence in its own right, and some can require you to unlock a device. A decoy offers no protection there, and Stillroom is not made or sold for that.

## How Stillroom Vault's decoy works

Stillroom has a [decoy password](/features/decoy-password/). The design is in the [security rules](/security/#rules), rule 2, and the public [file format](/format/).

Every vault folder holds **two slots**, `a` and `b`, built exactly alike. When you make a vault, yours goes in one of them at random, and nothing anywhere records which. The other slot is a real vault whose password, recovery key and kit secret are random and thrown away. Setting a decoy password replaces it with a new, empty vault whose password you choose, made by the same code. So an unset decoy and a set, empty one are the same thing on disk.

What that gives you, by who's looking:

- **Someone at the keyboard, given the decoy password**, sees a complete vault. Settings has the same rows in both. The decoy has its own recovery key and emergency kit, and the same intruder log. Unlock tries every password, recovery key and kit on both slots, so the time taken says nothing.
- **Someone with one copy of the folder and no password** sees two slots holding the same set of files, items for both in one shared folder under names only a slot can tell apart, and key files with the same dates.
- **Someone with copies taken at different times, and no password** sees both slots' lists rewritten together on every save, inside covers of one size with one date.

## What Stillroom's decoy does not do

The security rules put it this way: the decoy fools someone at the keyboard or with a copy of the folder, **not someone with a password and a copy**. Specifically:

- **Someone with one password and a copy of the folder** can see sealed files and a list size their vault doesn't account for. They can tell the other slot holds something, and roughly how much, though not what. Closing that would need a hidden-volume design, which reserves disk from day one and still fails against copies taken at different times.
- **Copies taken at different times show when ways in change.** A new password, recovery key or kit, or setting a decoy, rewrites files that a later copy can compare. Everyday adding, editing and searching don't show.
- **Touch ID opens one vault**, the one where it was last turned on. If you rely on the decoy, turn Touch ID on in the decoy or not at all.
- **Setting a decoy from inside the decoy deletes the real vault.** It's the same Settings row in both.
- **Other apps remember names.** Recent Items or Quick Look's thumbnail cache can keep file names from Edit in Place and previews. Don't edit in place or preview names you'd need to deny, or clear Recent Items afterwards.
- **Forensic tools** can see file change times that no app can set.
- **The activity log** could, over many days, hint that two vaults are in use. It's off by default; keep it off if you rely on the decoy.

## Who it's for

Stillroom says this plainly in the app and wherever it's sold: **protection against thieves and abusers, not police.** It's meant for the moment someone takes your Mac or pressures you to open it, not for a forensic examination, and never for deceiving police, border officers or courts.

If you're in an abusive relationship, a decoy is one tool among several. Think about who has seen your devices and when, keep the activity log off, and see [leaving an abusive relationship](/for/leaving-an-abusive-relationship/) for a fuller plan. If you're in danger, contact local emergency services or a domestic abuse service first.
