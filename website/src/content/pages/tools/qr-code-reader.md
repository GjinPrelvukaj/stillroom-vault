---
title: 'Two-Factor QR Code Reader: Get the Setup Key Out'
description: 'Read a two-factor QR code or a Google Authenticator export from a screenshot and get each setup key, in your browser. The image never leaves your device.'
h1: 'Two-factor QR code reader'
lead: 'Drop in a screenshot of a two-factor QR code and get the setup key inside it, so you can keep it as a backup or move it to another app. Google Authenticator’s “Export accounts” codes work too.'
name: 'QR code reader'
updated: '29 October 2026'
order: 40
tool: 'qr'
related: ['/tools/two-factor-codes/', '/guides/store-two-factor-backup-codes/', '/guides/two-factor-codes-on-mac/', '/moving-from/apple-passwords/']
points:
  - '**Turns a QR code back into text:** the setup key, the site, the account and the code settings.'
  - '**Reads Google Authenticator exports,** which pack several accounts into one QR code.'
  - '**The picture stays on your device.** It’s read in your browser and never uploaded.'
faq:
  - q: 'Is my screenshot uploaded?'
    a: 'No. The image is read by your browser, on your device, with a QR library bundled into this page. Nothing is sent, and the page forgets it when you close the tab.'
  - q: 'How do I export accounts from Google Authenticator?'
    a: 'In the app, open the menu, choose Transfer accounts, then Export accounts, and pick the ones you want. It shows one or more QR codes. Take a screenshot of each and drop them here one at a time.'
  - q: 'Why does it say no QR code was found?'
    a: 'The code may be too small, blurred or cut off. Take a screenshot of just the code, as large as you can, with nothing over it. Photos of a screen work less well than screenshots.'
  - q: 'What should I do with the screenshot afterwards?'
    a: 'Delete it, and empty the Trash. The QR code holds the secret that makes every future code, so a copy left in Downloads or on the Desktop is a copy of that secret.'
sources:
  - label: 'Google Authenticator: Key Uri Format'
    url: 'https://github.com/google/google-authenticator/wiki/Key-Uri-Format'
  - label: 'Google: Get verification codes with Google Authenticator'
    url: 'https://support.google.com/accounts/answer/1066447'
  - label: 'jsQR, the QR decoding library this page uses (Apache 2.0)'
    url: 'https://github.com/cozmo/jsQR'
---

## What's inside a two-factor QR code

A two-factor QR code is just text: a link that starts with `otpauth://totp/`. It names the site and your account and carries the **setup key**, the secret your authenticator app turns into a new code every 30 seconds. Once you have the link or the key, you no longer need the picture.

Google Authenticator's export is different. Its QR codes start with `otpauth-migration://` and pack several accounts at once, encoded so that other apps can't easily read them. This page unpacks them into one entry per account, each with its own key and link.

## What you can do with the key

- **Keep a backup.** If your phone is lost, the key lets you set up codes again without going through every site's recovery process. Keep it encrypted, or on paper somewhere safe.
- **Move to another app.** Most authenticator apps and password managers accept a setup key or an `otpauth` link by hand. Copy it from here and paste it there.
- **Check it works.** The live code shown under each account should match your current app. If it does, the key is right.

## Doing it inside Stillroom

[Stillroom Vault](/features/) reads two-factor QR codes too, from a screenshot or from the clipboard, and the codes start showing under the secret. It then offers to move the screenshot to the Trash and clears the picture from the clipboard, because the screenshot is the weak spot. The key is kept concealed, out of the search index, and on your Mac only. The [two-factor code generator](/tools/two-factor-codes/) and the guide to [storing backup codes](/guides/store-two-factor-backup-codes/) cover the rest.
