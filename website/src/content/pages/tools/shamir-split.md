---
title: 'Shamir Secret Sharing Demo: Split a Secret Into Pieces'
description: 'Split a secret into pieces so any chosen number of them rebuild it and fewer show nothing. A working Shamir secret sharing demo that runs in your browser.'
h1: 'Shamir secret sharing demo'
lead: 'Split a secret into pieces, choose how many it takes to rebuild it, then put some back together and watch it come out. This is the idea behind Stillroom’s emergency kit, running in your browser.'
name: 'Shamir split demo'
updated: '29 October 2026'
order: 70
tool: 'shamir'
related: ['/learn/shamir-secret-sharing/', '/features/emergency-kit/', '/features/recovery-key/', '/tools/passphrase-generator/']
points:
  - '**Any chosen number of pieces** rebuild the secret, in any order.'
  - '**Fewer show nothing at all,** not even a hint, however much computing power someone has.'
  - '**Every split is new:** split the same secret twice and every piece changes.'
faq:
  - q: 'Can I use this for a real secret?'
    a: 'It works, and it runs only on your device, but its pieces are only readable by this page. For a vault, use the emergency kit inside Stillroom: its printed pieces say how to use them, and an open-source script can read them without the app.'
  - q: 'Why do the pieces change each time I split?'
    a: 'Each split draws new random numbers for every byte. The secret is the same, but the pieces are different, and pieces from two splits don’t fit together. The page notices and says so.'
  - q: 'How does it know when pieces don’t belong together?'
    a: 'Four bytes of a SHA-256 fingerprint of the secret are split along with it. If the joined result doesn’t match its fingerprint, the pieces came from different splits, or one was copied wrong.'
  - q: 'What do the numbers at the start of a piece mean?'
    a: 'A piece like 3-2-a4c0… needs 3 pieces to open, and is piece number 2. The rest is the piece itself, in hexadecimal.'
sources:
  - label: 'Adi Shamir, How to Share a Secret, Communications of the ACM 22(11), 1979'
    url: 'https://doi.org/10.1145/359168.359176'
  - label: 'NIST FIPS 197: Advanced Encryption Standard (the GF(2⁸) field)'
    url: 'https://csrc.nist.gov/pubs/fips/197/final'
---

## Try it

1. Type a secret, or keep the example.
2. Choose how many pieces to make and how many are needed, for example 5 and 3.
3. Click **Split it**. The pieces appear, and the right number are copied into the **Join pieces** tab for you.
4. Switch to **Join pieces** and click **Join them**. The secret comes back.

Now take one piece out and join again: with too few, the page says how many it needs. Change one character of a piece and it notices that too.

## How it works

For each byte of the secret, the page draws a random curve (a polynomial) that passes through the secret byte at zero, and reads off one point of it for each piece. A curve needing three pieces is a parabola, and three points fix a parabola exactly; two points fit every possible parabola equally well, so they say nothing about where it crosses zero.

The arithmetic runs in a field of 256 values, the same one AES uses, so each byte maps to exactly one byte per piece. Joining uses Lagrange interpolation to find where the curve crosses zero. [Shamir secret sharing, explained](/learn/shamir-secret-sharing/) goes through it step by step.

## The emergency kit

Stillroom Vault's [emergency kit](/features/emergency-kit/) uses this to split a key that opens your vault into printed pieces for people you trust. Any agreed number of them together can open it if something happens to you; one piece alone opens nothing. The pieces are never tied to one Mac, and the free `stillroom-open.py` script can read them without the app. The pieces this page makes are its own format, for learning, and don't open a vault.
