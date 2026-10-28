---
title: 'Hidden From Screen Capture, Screenshots and Sharing'
description: 'Stillroom''s windows show blank to screenshots, recordings and screen sharing, and other apps can''t read your typing. How it works, and its limits.'
h1: 'Hidden from screen capture'
lead: 'Screenshots, screen recordings and screen sharing see Stillroom''s windows blank. While it''s in front, other apps can''t read what you type.'
name: 'Hidden from capture'
updated: '27 October 2026'
order: 80
related: ['/features/view-without-decrypting/', '/guides/secure-a-shared-mac/', '/for/journalists/']
faq:
  - q: 'Why is Stillroom blank in my screenshot or video call?'
    a: 'Its windows are hidden from capture by default. To show someone your vault, open it and turn on Show in screenshots and screen sharing in Settings, Protection. The lock screen stays hidden either way.'
  - q: 'Can someone still photograph my screen with a phone?'
    a: 'Yes. Hiding from capture works on what software on your Mac can record. It can''t stop a camera pointed at the screen.'
  - q: 'What does the keyboard shield do?'
    a: 'While Stillroom is the app in front, macOS''s secure keyboard entry is on, so other apps, keyloggers that use event taps among them, receive none of what you type. It goes off when you switch to another app.'
  - q: 'How do I hide Stillroom quickly?'
    a: 'Press Control, Option, Command and L in any app. Stillroom locks and hides at once. The menu bar icon can do the same.'
---

## What it is

Every Stillroom window and sheet is marked as hidden from capture. When something on your Mac takes a screenshot, records the screen or shares it in a video call, Stillroom's windows come out blank. You see your vault on your own display; the picture that leaves your Mac doesn't.

Three more things go with it:

- **The keyboard shield.** While Stillroom is the app in front, macOS's secure keyboard entry is on, so other apps (keyloggers that use event taps among them) can't read what you type in any field.
- **Lock and hide from anywhere.** <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> locks Stillroom and hides it at once, from any app. The menu bar icon does the same.
- **Copied secrets don't travel.** When you copy a password, it stays on this Mac (no Universal Clipboard), is marked as concealed for clipboard managers, and is cleared after 30 seconds, or at once when the vault locks or Stillroom quits, if nothing else was copied since.

## When you'd use it

- You share your screen in meetings and don't want a vault window to appear by accident.
- You use screen recording or remote support tools and want your vault left out of them.
- Someone else uses your Mac, or there's software on it you don't fully trust, and you want what you type into Stillroom kept from other apps.
- You need to put Stillroom away fast when someone walks up, without hunting for the window.

If you never share or record your screen, you lose nothing by leaving it on: your own display shows Stillroom normally.

## How to set it up

It's on from the start. You don't need to do anything.

To show your vault to someone on purpose (for example, to walk them through it in a call), open your vault, go to **Settings**, then the **Protection** tab, and turn on **Show in screenshots & screen sharing**. Turn it off again when you're done. The lock screen always stays hidden, whatever the switch says.

The keyboard shield has no switch: it's always on while Stillroom is in front, and the Protection tab lists it so you know.

The lock-and-hide shortcut needs no setting up either. If you want the menu bar icon, turn on **Menu bar icon** in the same tab.

## How it works underneath

- **Hiding windows.** macOS lets an app mark a window so it isn't shared with screen capture. Stillroom marks every window and every sheet this way, and applies the setting again to all windows when you change it.
- **Where the switch lives.** The **Show in screenshots** setting is stored inside your vault's sealed list, not in macOS preferences. Preferences can be changed by any program running as you, so a setting that weakens protection must not live there. It's applied after you unlock, which is why the lock screen is always hidden. If you use a [decoy password](/features/decoy-password/), each vault remembers its own setting.
- **The keyboard shield** turns on macOS's secure keyboard entry when Stillroom comes to the front and turns it off when it goes to the back.
- **The shortcut** is a Carbon hot key. It needs no accessibility permission and sees no keys other than its own.

## Limits

- **It can't stop a camera.** A phone pointed at your screen, or someone looking over your shoulder, sees what you see.
- **It relies on macOS.** Hiding windows and secure keyboard entry are macOS features. They block apps that capture or listen through the normal routes. They don't protect against malware with admin rights while the vault is open, which can see everything.
- **Turning on Show in screenshots really shows it.** While that switch is on, recordings and shared screens include your vault. It's remembered with the vault, so check it after you've used it.
- **The keyboard shield only works while Stillroom is in front.** It goes off when you switch apps, as it has to, so other apps can use the keyboard normally.
- **The clipboard is cleared only if nothing else was copied since.** If you copy something else within 30 seconds, Stillroom leaves the clipboard alone.

Hiding from capture is in every tier of Stillroom, the free one included.
