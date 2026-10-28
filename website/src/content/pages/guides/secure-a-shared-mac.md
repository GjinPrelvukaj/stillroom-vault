---
title: 'How to Keep Your Files Private on a Shared Mac'
description: 'Sharing a Mac with family or housemates? Set up separate user accounts, FileVault and the lock screen, then add a vault for what others must not see.'
h1: 'How to keep your files private on a shared Mac'
lead: 'The best privacy tool on a shared Mac is one macOS already has: a separate user account for each person. Here is how to set that up properly, where it stops, and what a vault adds.'
name: 'Secure a shared Mac'
updated: '27 October 2026'
order: 70
related: ['/features/decoy-password/', '/features/hidden-from-capture/', '/guides/hide-photos-on-mac/', '/for/leaving-an-abusive-relationship/']
faq:
  - q: 'Can other users on my Mac see my files?'
    a: 'Each account has its own files and settings. Files you put in your Public folder, or in the Shared folder, can be read by every user of the Mac. Administrators can also change settings and manage other users, so give admin rights only to people you trust.'
  - q: 'Should I just share one account and use a guest account for visitors?'
    a: 'For visitors, the Guest User account is a good fit: Apple says guests get no access to other users’ files or settings. For people who use the Mac every day, separate accounts are better than sharing one.'
  - q: 'Does FileVault protect me from other people on the same Mac?'
    a: 'Not on its own. FileVault protects the disk while nobody is logged in. Separation between people on the Mac comes from user accounts and their login passwords.'
sources:
  - label: 'Apple: Set up users, guests and groups on Mac'
    url: 'https://support.apple.com/guide/mac-help/set-up-users-guests-and-groups-mtusr001/mac'
  - label: 'Apple: Share files with others who use your Mac'
    url: 'https://support.apple.com/guide/mac-help/mchlp1122/mac'
  - label: 'Apple: Protect data on your Mac with FileVault'
    url: 'https://support.apple.com/guide/mac-help/protect-data-on-your-mac-with-filevault-mh11785/mac'
  - label: 'Apple: Change Lock Screen settings on Mac'
    url: 'https://support.apple.com/guide/mac-help/change-lock-screen-settings-mh11784/mac'
  - label: 'Apple: Mac keyboard shortcuts'
    url: 'https://support.apple.com/102650'
---

## Give each person their own account

If everyone uses one login, everyone sees everything: files, browser history, saved passwords, open mail. The fix is free and built in.

1. Choose **Apple menu > System Settings**, then click **Users & Groups** in the sidebar.
2. Click **Add User**. You may need to enter your password.
3. Choose the account type, enter the person's name and a password, and create the account.
4. Repeat for each person who uses the Mac.

Choose the account type with care. Apple describes three:

- **Administrator:** can add and manage other users, install apps and change settings. Keep this to the people who look after the Mac, ideally one.
- **Standard:** can install apps and change their own settings, but cannot add users or change other users' settings. Use this for everyone else.
- **Sharing Only:** can reach shared files over the network but cannot log in to the Mac.

For visitors who just need a browser for an hour, turn on the **Guest User** in Users & Groups. Apple says guests can log in without access to other users' files or settings.

## Close the gaps around the accounts

Separate accounts only help if each one is locked when its owner is away.

**Lock your session when you step away.** Press <kbd>Control</kbd> <kbd>Command</kbd> <kbd>Q</kbd>. In **System Settings > Lock Screen**, set **Require password after screen saver begins or display is turned off** to a short time. A logged-in account left open is open to whoever sits down next.

**Use a password others will not guess.** On a shared Mac, the people around you know your birthday, your pet's name and how you type. Use something they would not guess, and do not type it while someone is watching.

**Turn on FileVault.** It protects every account if the Mac is stolen. In **System Settings > Privacy & Security > FileVault**, turn it on and click **Enable Users** to let each person unlock the disk with their own password. Each user's information is encrypted, too.

**Mind the shared folders.** Apple says files in your Public folder, or in the Shared folder in Users, can be read by every user of the Mac. Do not keep anything private there.

**Know who the administrator is.** An administrator manages the other accounts and the Mac's settings. If you are not the administrator, you are trusting whoever is.

## Where accounts stop

Accounts separate people. They do not protect a file from someone who:

- uses your account while you are logged in and away from the desk,
- knows or can guess your login password,
- is the Mac's administrator,
- or watches your screen, in person or with screen recording.

For files that must stay private from people who share your home, you need a second lock that does not open with your login.

## Adding Stillroom Vault

[Stillroom Vault](/features/) keeps files, notes and passwords in an encrypted vault with its own password, separate from your Mac login.

- **The vault has its own password,** stretched with Argon2id, and every item is sealed on its own with AES-256-GCM. Knowing your login password does not open it.
- **Other accounts cannot read the vault folder,** and if they copied it they would find only sealed files. Stillroom guards against other accounts on the same Mac by design ([security](/security/)).
- **It locks itself** after a time you choose and when the Mac sleeps. <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> locks and hides it from any app, and so does the menu bar icon, so you can close it fast if someone walks in.
- **Its windows are hidden from screen capture,** and secure keyboard input is on while it is in front, which blocks keyloggers that use event taps. See [hidden from capture](/features/hidden-from-capture/).
- **The intruder log** keeps wrong tries, and optionally a photo, sealed so only an open vault can read them. It never keeps what was typed.
- **A [decoy password](/features/decoy-password/)** can open a second, harmless vault, for when someone demands you open it. On disk the two are built alike.

What it does not do, plainly:

- **It does not protect against an administrator who installs monitoring software,** or any malware with admin rights while the vault is open.
- **The decoy fools someone at the keyboard, not someone who has one password and a copy of the vault folder.** That person can tell the folder holds more than their vault accounts for, though not what. Touch ID opens only one of the two vaults, so if you rely on the decoy, turn Touch ID on in the decoy or not at all. The decoy is protection against thieves and abusers, not police. Read [rule 2](/security/#rules) before relying on it.
- **Opening a file in another app with Edit in Place, or previewing it,** can leave its name in Recent Items or Quick Look's cache.
- **If you forget the vault password and have no recovery key or kit, nobody can open it.**
- It needs Apple silicon and macOS 26 or later, and has not had an independent audit yet. It is free for 25 items, $39 once, or $129 for a Family licence covering 5 people ([pricing](/pricing/)).

If you are keeping things private from someone you live with because you are not safe, see [Stillroom for leaving an abusive relationship](/for/leaving-an-abusive-relationship/), and think about whether that person can reach your Mac's administrator account or install software on it.
