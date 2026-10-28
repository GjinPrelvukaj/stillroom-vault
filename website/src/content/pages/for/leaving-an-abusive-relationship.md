---
title: 'Keeping Files Private When Leaving an Abusive Relationship'
description: 'Safety comes first. What specialist services advise about monitored devices, and what Stillroom Vault can and cannot do if you need to keep files private.'
h1: 'If you are leaving an abusive relationship'
lead: 'Your safety matters more than any app. This page starts with what specialist services advise, then says plainly what Stillroom Vault can and cannot do, so you can decide with an advocate whether it has a place in your plan.'
name: 'Leaving an abusive relationship'
updated: '27 October 2026'
order: 50
related: ['/features/decoy-password/', '/features/intruder-log/', '/features/hidden-from-capture/', '/guides/secure-a-shared-mac/']
faq:
  - q: 'Could installing Stillroom Vault make things more dangerous?'
    a: 'It could. A new app can be noticed, and specialist services warn that changes to your devices can alert an abuser and that some abusers then escalate. Talk to a domestic abuse service about your situation before making changes.'
  - q: 'Can Stillroom Vault protect me if my Mac has spyware on it?'
    a: 'No. Software with admin rights on the Mac sees what you see while the vault is open. If your Mac may be monitored, use a safer device that the other person has never had access to.'
  - q: 'Will the decoy password keep my real files hidden?'
    a: 'It can help against someone at the keyboard who demands a password. It is not a guarantee: someone with one password and a copy of the vault folder can tell that the other vault holds something, and Touch ID opens whichever vault it was last turned on in.'
  - q: 'Where can I get help?'
    a: 'In the US, the National Domestic Violence Hotline. In the UK, Refuge and the National Domestic Abuse Helpline. Elsewhere, a local domestic abuse service. If you are in immediate danger, call your local emergency number.'
sources:
  - label: 'National Domestic Violence Hotline (US): Get help'
    url: 'https://www.thehotline.org/get-help/'
  - label: 'National Domestic Violence Hotline (US): Plan for safety'
    url: 'https://www.thehotline.org/plan-for-safety/'
  - label: 'National Domestic Violence Hotline (US): Tech safety tips'
    url: 'https://www.thehotline.org/resources/how-to-clear-search-history-and-other-tech-safety-tips/'
  - label: 'Refuge (UK): I need help now'
    url: 'https://refuge.org.uk/i-need-help-now/'
  - label: 'National Domestic Abuse Helpline (UK), run by Refuge'
    url: 'https://www.nationaldahelpline.org.uk/'
  - label: 'Refuge Tech Safety: Secure your tech'
    url: 'https://refugetechsafety.org/secure-your-tech/'
  - label: 'NNEDV Safety Net: Spyware and stalkerware on computers'
    url: 'https://techsafety.org/spyware-and-stalkerware-computers'
---

## Safety first, and help that knows your situation

If you are in immediate danger, call your local emergency number.

Leaving is often the most dangerous time, and the people best placed to help you plan for it are specialist domestic abuse services. They can help you make a safety plan that fits your situation, including your phone and computer. In the US, the [National Domestic Violence Hotline](https://www.thehotline.org/get-help/) offers phone, text and chat with advocates. In the UK, [Refuge](https://refuge.org.uk/i-need-help-now/) runs the [National Domestic Abuse Helpline](https://www.nationaldahelpline.org.uk/). Elsewhere, look for a local domestic abuse service.

If someone might check this browser's history, the Hotline's [tech safety tips](https://www.thehotline.org/resources/how-to-clear-search-history-and-other-tech-safety-tips/) cover that. It warns that internet use can be monitored and is impossible to erase completely.

## What tech safety advice says about devices

Specialist services that work on technology and abuse make a few points that matter before you install anything:

- **Your devices may be monitored.** Abusers can use stalkerware, shared accounts, location tracking and access to a device to watch what you do. NNEDV's Safety Net project says spyware often leaves no obvious sign, and that the clearest clue can be someone knowing things you only did on your device.
- **Changes can be noticed.** Refuge's tech safety team warns that some steps you take to increase your privacy might alert an abuser, who may then escalate. Safety Net recommends safety planning before removing monitoring.
- **A safer device can be the better choice.** Safety Net suggests using a computer or phone the other person has never had physical or remote access to, such as one at a library or a friend's.
- **Evidence first.** Refuge suggests saving evidence before taking actions like deleting messages.

[Refuge Tech Safety](https://refugetechsafety.org/secure-your-tech/) and [Safety Net](https://techsafety.org/spyware-and-stalkerware-computers) have step-by-step guides for phones, accounts and computers. Please read them, or talk to an advocate, before deciding whether any new app is right for you.

## What Stillroom Vault is

Stillroom Vault is a Mac app that keeps files, notes and passwords sealed on your Mac with AES-256-GCM. It has no account and no server, and it never goes online, so nothing is sent anywhere and there's no online login someone could reset. It could be a place for things you want to keep private on a Mac that is yours: copies of identity documents, photos or screenshots you're keeping as evidence, a note of dates and events, and new passwords for accounts you're taking back.

But an app on a shared or monitored Mac can itself be noticed. Stillroom shows up in Applications, its download can show in the browser's history, and buying a licence leaves a receipt in your email. The free version holds up to 25 items with every feature, so no purchase is needed. There's a menu bar icon, which you can turn off in Settings. None of this makes the app invisible to someone who uses or checks the Mac.

## The protections, and their limits

**The decoy password.** Stillroom can have a second password that opens a separate, harmless vault, with its own recovery key and kit. On disk the two are built alike, and nothing marks which one is yours. If someone at the keyboard demands your password, you can choose to give the decoy. Its limits:

- Someone who has one password and a copy of the vault folder can see that the other vault holds something, and roughly how much, though not what.
- Touch ID opens only the vault where it was last turned on. If a finger could be forced, turn Touch ID on in the decoy or not at all.
- Names of files you preview or Edit in Place can be remembered by macOS (Recent Items, Quick Look's thumbnail cache). A name that isn't in the decoy points to another vault.
- Someone inside the decoy can delete everything from Settings, including the real vault. Keep copies of anything you can't lose somewhere else (see below).

**The intruder log.** Stillroom records wrong password tries and can take a photo with the Mac's camera (a setting you can turn off). It never records what was typed. The log is sealed so only an open vault can read it, and both vaults share it, so whoever opens the decoy sees it too, photos included. Photos need camera permission, which macOS asks you for, and the camera's light comes on when one is taken. It's a record, not a protection: it doesn't stop anyone.

**Hidden from capture.** Every Stillroom window is left out of screenshots and screen recordings, which helps against software that records the screen. It doesn't stop someone looking at the screen, and it doesn't stop spyware with admin rights, which can see everything while the vault is open.

**Locking.** Stillroom locks after a few minutes idle, when the Mac sleeps, and with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd>, which also hides it.

Stillroom has not been independently audited yet. Its full threat model, including what it does not protect against, is on the [security page](/security/).

## Keeping evidence and keeping access

- **Don't rely on one copy.** An encrypted backup is a single file. Keep one with someone you trust, or ask a support service how they suggest storing evidence. A vault on a Mac someone else can reach can be deleted.
- **Keep the recovery key away from the home.** Stillroom can't recover a forgotten password, and nobody can. The recovery key, or emergency kit pieces given to people you trust, are the only other ways in.
- **Use a strong passphrase** the other person couldn't guess, not a date or name they know.

There is no app that can make you safe on its own. If Stillroom does fit your plan, use it alongside the advice of people who know your situation, and put your safety first.
