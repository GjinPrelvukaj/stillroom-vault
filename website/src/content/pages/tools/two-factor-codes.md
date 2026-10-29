---
title: 'Two-Factor Code Generator From a Setup Key (TOTP)'
description: 'Paste a two-factor setup key or otpauth link and get the live six-digit code, made in your browser. Check a backup key works before you need it.'
h1: 'Two-factor code generator'
lead: 'Paste the setup key a site gave you, or an otpauth link, and see the six-digit code it makes right now. Useful for checking a saved key still works, before the day you need it.'
name: 'Two-factor code generator'
updated: '29 October 2026'
order: 30
tool: 'totp'
related: ['/tools/qr-code-reader/', '/tools/recovery-code-sheet/', '/guides/store-two-factor-backup-codes/', '/guides/two-factor-codes-on-mac/']
points:
  - '**The same codes as your authenticator app,** from the same key, by the open standard (RFC 6238).'
  - '**Check a backup works:** if the code here matches your app, the key you saved is the right one.'
  - '**Made on your device.** The key stays on this page; nothing is sent.'
faq:
  - q: 'Is it safe to paste a setup key into a website?'
    a: 'Only into one that never sends it anywhere, and this one doesn’t: the code is made in your browser and the page makes no request with it. Still, a setup key is as sensitive as a password, so close the tab when you’re done and don’t leave the key on your clipboard.'
  - q: 'Why doesn’t my code match the app?'
    a: 'Most often the clock: codes depend on the time, so a Mac or phone more than half a minute off makes different ones. Otherwise check the settings: a few services use 8 digits, 60 seconds or SHA-256, which an otpauth link sets for you.'
  - q: 'Can I use this page as my authenticator?'
    a: 'It isn’t meant for that. It keeps nothing, so you’d paste your key every time, and keys belong somewhere encrypted. Use an authenticator app, or a vault that shows codes under each login.'
  - q: 'What is an otpauth link?'
    a: 'The text inside a two-factor QR code. It starts with otpauth://totp/ and holds the setup key, the site’s name, your account name and the code settings. The QR code reader turns a screenshot of one back into this link.'
sources:
  - label: 'RFC 6238: TOTP, Time-Based One-Time Password Algorithm'
    url: 'https://www.rfc-editor.org/rfc/rfc6238'
  - label: 'RFC 4226: HOTP, an HMAC-Based One-Time Password Algorithm'
    url: 'https://www.rfc-editor.org/rfc/rfc4226'
  - label: 'Google Authenticator: Key Uri Format'
    url: 'https://github.com/google/google-authenticator/wiki/Key-Uri-Format'
---

## What a setup key is

When you turn on two-factor sign-in with an authenticator app, the site shows a QR code and, usually under a link like "Can't scan it?", the same thing as text: the **setup key**. It's a string of letters A to Z and digits 2 to 7, such as `JBSW Y3DP EHPK 3PXP`.

That key is a shared secret. The site keeps a copy, your app keeps a copy, and both turn it into the same six digits every 30 seconds. Anyone with the key can make your codes forever, so it's as sensitive as the password.

## How the code is made

The method is an open standard, TOTP (RFC 6238), which every authenticator app follows:

1. Count the 30-second steps since 1 January 1970.
2. Run that number and the key through HMAC with SHA-1.
3. Take four bytes from a place the result itself points to, and keep the last six digits.

This page does exactly that with your browser's built-in cryptography, and passes the test values published in the standard. Because the time is part of it, your device's clock has to be right to within about half a minute.

## When it's useful

- **Checking a saved key.** If you kept a setup key as a backup, paste it here and compare the code with your app. A match means the backup really works.
- **Moving to a new app.** Before you delete the old authenticator, make sure the key you're carrying over gives the same codes.
- **Reading an export.** If you have a QR code rather than a key, the [QR code reader](/tools/qr-code-reader/) gets the key out of a screenshot.

## Codes inside Stillroom

[Stillroom Vault](/features/) shows live codes the same way, under any secret that holds an `otpauth` link or setup key, so a site's password, backup codes and two-factor key can sit in one encrypted record. It can read the QR code from a screenshot or the clipboard, then offers to move the screenshot to the Trash. Setup keys are kept concealed and out of the search index, and anything you copy is cleared after 30 seconds. [How to store backup codes](/guides/store-two-factor-backup-codes/) covers the other places worth considering.
