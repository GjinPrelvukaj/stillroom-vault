---
title: 'Password Strength Checker That Never Sends Your Password'
description: 'Check how guessable a password is, and how long it would take to crack, with the same check Stillroom Vault uses. It runs in your browser only.'
h1: 'Password strength checker'
lead: 'How hard a password is to guess, counted the way a guessing program counts it. This is the same check the Stillroom app uses, run in your browser: what you type never leaves this page.'
name: 'Password strength checker'
updated: '29 October 2026'
order: 20
tool: 'strength'
related: ['/tools/passphrase-generator/', '/learn/argon2id/', '/guides/encrypt-files-on-mac/', '/guides/if-your-mac-is-stolen/']
points:
  - '**Counts what a guesser counts:** common words, look-alike letters, runs like 1234 and qwerty, and years.'
  - '**The same rules as the app,** so a password it calls strong enough is one Stillroom accepts.'
  - '**Checked as you type, on your device.** Nothing is sent, saved or logged.'
faq:
  - q: 'Is it safe to type my real password here?'
    a: 'The check runs entirely in your browser and the page makes no request with what you type; you can confirm that in your browser’s network inspector. Even so, the habit of typing real passwords into websites is a risky one, so a password close to yours works just as well for learning what makes it weak.'
  - q: 'Why does P@ssw0rd123 score so low?'
    a: 'Guessing programs undo look-alike swaps first. To them it is the word password, which is near the top of every list, followed by the run 123. Both cost a guesser almost nothing.'
  - q: 'What does bits mean?'
    a: 'Each bit doubles the number of guesses needed. 50 bits is about a million billion possibilities, so a guesser needs half that many tries on average.'
  - q: 'Why are there two different times?'
    a: 'How fast someone can guess depends on how the password was stored. A site that leaked a fast hash lets an attacker try billions a second. An Argon2id vault like Stillroom’s allows only tens a second per graphics card.'
---

## How the check counts

A guessing program doesn't try every combination in order. It starts with what people actually choose: common words, names, years, keyboard runs and the usual swaps like `@` for `a` and `0` for `o`. So this check counts the way such a program does:

- **A common word costs 7 bits,** whatever its length, because it's one pick from a short list. A capital letter in it adds 1. Look-alike digits and symbols are turned back into letters first, so `p@ssw0rd` is just `password`.
- **A run or repeat costs 4 bits:** `1234`, `abcd`, `9876`, `qwerty`, `asdf` or `aaaa`.
- **A year from 1900 to 2099 costs 6 bits,** because birthdays and anniversaries are tried early.
- **Every other character** costs what a random pick from its kind would: about 4.7 bits for a letter, 3.3 for a digit, 5 for a symbol.

The chips under the result show which of these it found. The check is deliberately rough, because no check can know everything about you. If a password is your pet's name and your street, it can't tell, but someone who knows you can.

## Why it's the same as the app

Stillroom Vault refuses a password below **50 bits**, or shorter than 12 characters, when you make a vault or change your password, and says why under the field. This page runs a line-for-line copy of that check (`PasswordStrength.swift` in the app), so the website and the app give the same answer.

The bar is 50 bits because of what a guess costs against a Stillroom vault. Each one runs [Argon2id](/learn/argon2id/) with 512 MB of memory and 3 passes. A test in October 2026 estimated roughly 10 to 30 guesses a second per high-end graphics card, so 50 bits keeps a large guessing rig busy for centuries.

## The two times

- **Against Stillroom** uses 30 guesses a second, the fast end of that estimate.
- **Against a fast hash** uses 10 billion guesses a second: a cautious figure for one modern graphics card against an old site's leaked database stored with a fast hash like MD5 or SHA-1. Real rigs often manage more.

Both are averages: half the possibilities, since a guesser is as likely to find it early as late. The same password can be fine behind Argon2id and fall in an afternoon from a leaked database, which is why reusing a password across sites is the bigger risk.

## Making a strong one

The easiest strong password is a few random words. The [passphrase generator](/tools/passphrase-generator/) makes them, and six of its words land around 78 bits, well past the app's bar.
