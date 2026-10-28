---
title: 'Recovery Key: The Way In When You Forget Your Password'
description: 'Every Stillroom vault comes with a recovery key to write on paper. What it opens, how to use it, how to make a new one, and what it can''t do.'
h1: 'Recovery key'
lead: 'A key you write on paper when you make your vault. If you forget your password or lose your Mac, it''s the other way in.'
name: 'Recovery key'
updated: '27 October 2026'
order: 30
related: ['/features/emergency-kit/', '/features/lock-to-this-mac/', '/guides/if-your-mac-is-stolen/']
faq:
  - q: 'I forgot my password and lost my recovery key. Can you open my vault?'
    a: 'No. Nobody can, including the people who make Stillroom. If you made an emergency kit, enough of its pieces will open it; otherwise the vault stays shut.'
  - q: 'Can I see my recovery key again later?'
    a: 'No. It is shown once, when it is made. If you lose the paper, make a new key in Settings while your vault is open and write that one down.'
  - q: 'Does the recovery key work on a different Mac?'
    a: 'Yes. It opens its vault on any Mac, even with Lock to this Mac turned on. That is why it should be kept as carefully as the vault itself.'
  - q: 'Does a new recovery key stop the old one working?'
    a: 'It stops the old one opening the vault as it is now. Backups made before the new key still open with the old one.'
---

## What it is

Every Stillroom vault has a recovery key. It's made with the vault, shown to you once, and never shown again. It looks like this:

`XXXXX-XXXXX-XXXXX-XXXXX-XXXXX`

That's 25 characters in five groups of five, drawn from an alphabet with no look-alikes (no 0 or O, no 1, I or L), so it's hard to copy down wrong. It holds about 124 random bits, far beyond what anyone can guess, however many tries they have.

The recovery key opens your vault without the password, on any Mac. After it opens, Stillroom asks you to choose a new password before anything else.

## When you'd use it

- **You forgot your password.** This is the main reason it exists. Stillroom can't reset a password, and there's no email link or support desk that can let you in. See [forgot your password](/support/#forgot).
- **Your Mac was lost, stolen or replaced.** Restore a backup on a new Mac and open it with the recovery key. If the vault was [locked to the old Mac](/features/lock-to-this-mac/), the recovery key is the only thing besides an emergency kit that opens it elsewhere.
- **Your Mac was repaired** and a vault locked to it no longer opens with the password.

## How to set it up

You don't need to turn it on: making a vault makes its recovery key.

1. When you make your vault, Stillroom shows the key with the instruction to write it on paper and keep it somewhere safe.
2. Click **I've Written It Down**.
3. Stillroom asks you to type two of the groups from your paper, to check you copied it correctly. If they don't match, you can see the key again.

Keep the paper somewhere you'd keep a passport. Don't store it in a photo, a note on your phone or a file on your Mac: it opens the vault on any Mac, so treat it like the vault itself.

### Making a new one

If you lose the paper, or think someone saw it, open your vault and go to **Settings**, then the **Access** tab. Next to **Recovery key**, click **New Key…** and confirm. The new key is shown once and checked the same way.

### Using it

On the lock screen, click **Use Recovery Key**, type the key (dashes and capitals don't matter), and choose a new password when asked.

## How it works underneath

Your vault has a 32-byte slot key that seals your list of items, your search index and the key that hides them. That slot key is never written down unsealed. Instead, each way in seals its own copy of it:

- your password seals one copy in `password.key`
- your recovery key seals another in `recovery.key`
- an emergency kit, if you make one, seals a third in `kit.key`

The recovery key is turned into a sealing key the same way a password is: with Argon2id, using 512 MB of memory, 3 passes and 4 lanes. Before stretching, it's put in capitals with dashes and spaces taken out, so however you write it, it matches.

[Lock to this Mac](/features/lock-to-this-mac/) adds an outer seal on the password key only. The recovery key is never locked this way, which is what lets it open the vault anywhere. The [format page](/format/) has the byte-level layout, and [stillroom-open.py](/format/) can open a vault with the recovery key without the app.

If you use a [decoy password](/features/decoy-password/), each vault has its own recovery key. The decoy's is shown when you set the decoy.

## Limits

- **Lose the password and the recovery key (and any kit), and the vault is gone.** Nobody can open it, not even Stillroom's makers. There's no master key and there never will be.
- **It's shown once.** Stillroom doesn't keep a readable copy anywhere. If you didn't write it down, make a new one while you still know your password.
- **A new key doesn't cut off old backups.** Making a new recovery key stops the old one opening the vault as it is now. Backups and Time Machine copies made before still open with the old key, and the slot key they reveal opens today's files too. A key rotation feature to fix this is planned for a later version.
- **Anyone with the key and a copy of the vault folder can open it**, on any Mac. Wrong recovery keys typed at the lock screen go in the [intruder log](/features/intruder-log/), but that's a deterrent, not a lock.

The recovery key is part of every vault, on every tier, the free one included.
