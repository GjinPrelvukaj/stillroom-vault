---
title: 'Random PIN Generator That Skips the Guessable Ones'
description: 'Make random PINs of 4 to 12 digits with your browser’s cryptographic generator, leaving out 1234, birth years, dates and other PINs people guess first.'
h1: 'Random PIN generator'
lead: 'Random PINs from 4 to 12 digits, with the ones people guess first left out: 1234, 0000, repeats, runs, years and dates. Made on your device, and never sent.'
name: 'PIN generator'
updated: '29 October 2026'
order: 80
tool: 'pin'
related: ['/tools/passphrase-generator/', '/tools/password-strength/', '/guides/secure-a-shared-mac/', '/guides/if-your-mac-is-stolen/']
points:
  - '**Truly random digits** from your browser’s cryptographic generator, each one equally likely.'
  - '**Skips the PINs tried first:** the most common ones, repeats, runs, repeated pairs, years and dates.'
  - '**For limited tries only.** A PIN is fine on a phone or card that locks after a few wrong guesses.'
faq:
  - q: 'Which PINs do people guess first?'
    a: 'An analysis of 3.4 million leaked four-digit PINs found 1234 alone made up about 11% of them, with 1111 and 0000 next. Birth years, dates and patterns like 1212 and 2580 follow. This generator leaves those out.'
  - q: 'Does leaving PINs out make it weaker?'
    a: 'Very slightly, in theory: 882 of the 10,000 four-digit PINs are skipped, most of them dates. In practice it is much stronger, because those are the ones a guesser tries first and the rest are all equally unlikely.'
  - q: 'How long should a PIN be?'
    a: 'Six digits where you can. A four-digit PIN has 10,000 possibilities and a six-digit one has a million. Either is fine only where wrong tries are limited, like a phone that locks after a few attempts.'
  - q: 'Should a PIN protect a file or a vault?'
    a: 'No. Anything that can be copied and guessed offline needs a passphrase, not a PIN. A million possibilities is nothing to a computer with no limit on tries.'
sources:
  - label: 'DataGenetics: PIN analysis of 3.4 million four-digit PINs'
    url: 'http://www.datagenetics.com/blog/september32012/'
---

## Which PINs it leaves out

With **Leave out PINs people guess first** on, the generator skips:

- **The most common PINs,** such as 1234, 1111, 0000, 1212, 7777, 2000, 6969 and 2580 (straight down the keypad) for four digits, and 123456, 111111, 121212 and 112233 for six.
- **One digit over and over,** like 5555.
- **Runs up or down,** like 3456 or 8765, including ones that wrap around, like 8901.
- **Repeated pairs or triples,** like 4747 or 252525.
- **Years from 1900 to 2099,** and four-digit **dates** as day and month or month and day, because birthdays are guessed early.

Everything left is picked fairly. Each digit comes from `crypto.getRandomValues`, with any value that would favour some digits thrown away and drawn again.

## Where a PIN is enough

A PIN is strong only because the thing it guards stops guessing. A phone makes you wait longer after each wrong try and can lock you out altogether; a bank card is kept after three. Behind limits like those, six random digits are plenty.

Anything that can be copied and attacked offline, like an encrypted file, a backup or a password vault, needs a passphrase. The [passphrase generator](/tools/passphrase-generator/) makes one, and the [password strength checker](/tools/password-strength/) shows how a password holds up when nothing limits the guessing.

## Keeping PINs

PINs for cards, doors, alarms and safes are the sort of thing people write on a sticky note. [Stillroom Vault](/features/) keeps them in secrets with fields, concealed until you reveal them, encrypted on your Mac and never online.
