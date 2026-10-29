---
title: 'Passphrase Generator: Random Words, Made in Your Browser'
description: 'Make a strong, memorable passphrase from the EFF’s 7,776-word list, with fair random picks made on your device. Nothing is sent anywhere.'
h1: 'Passphrase generator'
lead: 'A few random words are easier to remember than a jumble of symbols, and harder to guess. This makes them with your browser’s own random number generator, on your device.'
name: 'Passphrase generator'
updated: '29 October 2026'
order: 10
tool: 'passphrase'
related: ['/tools/password-strength/', '/learn/argon2id/', '/features/recovery-key/', '/guides/encrypt-files-on-mac/']
points:
  - '**Six random words** from a list of 7,776 give about 78 bits: far past what anyone can guess.'
  - '**Picked fairly** by your browser’s cryptographic random generator, with no bias towards any word.'
  - '**Made on your device.** The page sends nothing, and there’s no copy anywhere but your screen.'
faq:
  - q: 'How many words should a passphrase have?'
    a: 'Five words from this list give about 65 bits and six give about 77. For a password that guards an encrypted vault or a password manager, six is a good choice; for something with limited tries, like a phone, fewer is fine.'
  - q: 'Is a passphrase better than a random password?'
    a: 'For something you type from memory, usually yes. Strength comes from how many choices were made at random, not from symbols. Six random words carry as much randomness as a 12 character password of letters, digits and symbols, and they are far easier to remember and type.'
  - q: 'Do I need capitals, digits or symbols?'
    a: 'Not for strength. They add little to a random passphrase. Some sites insist on them anyway, which is what the capital letters and digit options are for.'
  - q: 'Can I use a sentence I make up myself instead?'
    a: 'It is much weaker than it feels. People choose words that go together, and guessing programs know the patterns. The strength of a passphrase comes from the words being picked at random, not by you.'
sources:
  - label: 'EFF: Dice-generated passphrases and the long word list'
    url: 'https://www.eff.org/dice'
  - label: 'MDN: Crypto.getRandomValues()'
    url: 'https://developer.mozilla.org/en-US/docs/Web/API/Crypto/getRandomValues'
---

## How it works

The generator picks each word at random from the **EFF long word list**: 7,776 words chosen by the Electronic Frontier Foundation to be easy to spell and type, with none that is the start of another. The list was made for rolling five dice per word, and 7,776 is six to the power of five.

Each pick uses `crypto.getRandomValues`, the same random generator your browser uses for encryption. Numbers that would favour some words over others are thrown away and drawn again, so every word is exactly as likely as every other.

The strength line under the phrase is simple arithmetic. Each word adds about 12.9 bits (the number of times you could halve 7,776), so six words give about 78 bits. The time shown assumes an attacker who knows you used this list and how many words you chose, which is the honest way to count.

## How strong is strong enough

It depends on what the passphrase guards, and how fast someone can try guesses against it.

- **A website login** is guessed online, slowly, and the site locks the account. Four or five words are plenty.
- **An encrypted file or vault** can be copied and guessed offline, as fast as the attacker's hardware allows. That is where the count of words matters.

Stillroom Vault stretches your password with [Argon2id](/learn/argon2id/), using 512 MB of memory and 3 passes for every guess. A test in October 2026 estimated roughly 10 to 30 guesses a second per high-end graphics card. At that rate, even five random words would take far longer than anyone has.

## Keeping it

A passphrase you will type every day sticks after a week or so. Until then, write it on paper and keep the paper somewhere safe, then destroy it once you know the phrase.

For the vault itself, Stillroom gives you a [recovery key](/features/recovery-key/) to write down when you make it, so forgetting the passphrase doesn't lose your files. Its own password check accepts a random passphrase like these and refuses guessable ones; you can try the same check on the [password strength checker](/tools/password-strength/).
