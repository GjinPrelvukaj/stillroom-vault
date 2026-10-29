---
title: 'File Checksum Checker: SHA-256 Without Uploading'
description: 'Get a file’s SHA-256, SHA-1 and SHA-512 checksums in your browser and compare them with the published one. The file is read on your device, never uploaded.'
h1: 'File checksum checker'
lead: 'Drop in a file to get its SHA-256 checksum, and paste the one the publisher gave you to compare. A match means the file you have is exactly the one they published, byte for byte.'
name: 'File checksum checker'
updated: '29 October 2026'
order: 50
tool: 'checksum'
related: ['/tools/password-strength/', '/learn/aes-256-gcm/', '/guides/encrypt-files-on-mac/', '/compare/veracrypt/']
points:
  - '**A file’s fingerprint:** change one byte anywhere and the SHA-256 changes completely.'
  - '**Compare at a glance:** paste the published checksum and the matching line turns green.'
  - '**Read on your device.** The file is never uploaded, so it works for private files too.'
faq:
  - q: 'What is a checksum for?'
    a: 'To check a download arrived exactly as published. A changed or damaged file gives a different checksum, so if yours matches the one on the publisher’s site, the file is the same one, byte for byte.'
  - q: 'Is the file uploaded?'
    a: 'No. Your browser reads it and works out the checksum on your device, with its built-in cryptography. Nothing is sent, which you can confirm in your browser’s network inspector.'
  - q: 'Which checksum should I use?'
    a: 'Whichever the publisher gives. SHA-256 is the usual one today. SHA-1 is shown because older sites still publish it, but it is no longer safe against someone deliberately making two files with the same checksum.'
  - q: 'Is there a size limit?'
    a: 'Browsers read the whole file into memory to do this, so very large files, around 2 GB and up, may be refused. For those, run shasum -a 256 followed by the file’s path in Terminal on a Mac.'
  - q: 'Does a matching checksum mean the file is safe?'
    a: 'It means the file is the one the publisher published, unchanged. Whether that file is safe depends on the publisher, and on getting the checksum from their own site rather than from wherever the file came from.'
sources:
  - label: 'NIST FIPS 180-4: Secure Hash Standard (SHA-1, SHA-256, SHA-512)'
    url: 'https://csrc.nist.gov/pubs/fips/180-4/upd1/final'
  - label: 'MDN: SubtleCrypto.digest()'
    url: 'https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/digest'
---

## Why check a checksum

A download can be changed on the way: a damaged transfer, a tampered mirror, or a look-alike site offering a modified copy. A checksum catches all of these. It's a short fingerprint worked out from every byte of the file, and changing even one byte gives a completely different one.

So when a publisher lists a checksum beside a download, comparing it with yours tells you the file is the one they meant you to have. The comparison only means something if the checksum comes from the publisher's own page, so get it there, not from the place you downloaded the file.

## How to use it

1. Drop the file on the box above, or choose it.
2. Copy the checksum from the publisher's site and paste it into the field.
3. The line that matches turns green, and the note says so. If nothing matches, don't open the file: download it again from the original site.

Spaces and capital letters in the pasted checksum don't matter.

## Checking Stillroom

The [download page](/download/) lists the SHA-256 of the current Stillroom zip. Drop the zip here and this page recognises it and says so. The Terminal way works as well: `shasum -a 256 ~/Downloads/` followed by the zip's name.

Beyond the checksum, Stillroom is signed with a Developer ID and notarized by Apple, and it checks its own signature each time it opens, saying so on the lock screen if the copy has been changed.

## The other kind of fingerprint

Encryption uses the same idea. Every item Stillroom seals with [AES-256-GCM](/learn/aes-256-gcm/) carries a 16-byte tag worked out from the sealed bytes and the key, so a single changed byte makes the item refuse to open instead of opening wrong.
