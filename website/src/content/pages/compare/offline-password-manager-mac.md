---
title: 'Best Offline Password Managers for Mac in 2026'
description: 'Offline password managers for Mac with no account and no vendor cloud: KeePassXC, Strongbox, MacPass, Enpass, pwSafe and Stillroom Vault, compared fairly.'
h1: 'The best offline password managers for Mac'
lead: 'Six Mac password managers that keep your vault on your own computer, with no account on someone else''s server. What "offline" really means, how each one handles sync and autofill, and how to choose.'
name: 'Offline password managers'
updated: '30 October 2026'
order: 5
related: ['/compare/keepassxc/', '/compare/password-manager-no-subscription/', '/compare/1password/', '/compare/bitwarden/', '/guides/store-two-factor-backup-codes/']
points:
  - 'Offline means no account, no vendor server, and sync only where you choose.'
  - 'KeePassXC and MacPass are free and open source; Strongbox and Enpass add phone apps and autofill.'
  - 'Stillroom Vault has no network code at all, and holds files too, but has no autofill, sync or phone app.'
faq:
  - q: 'Is there a password manager that works without internet on a Mac?'
    a: 'Yes. KeePassXC, MacPass, Strongbox, Enpass, pwSafe and Stillroom Vault all keep the vault on your Mac and open it with no connection. Sync, where they have it, is optional and goes through storage you choose.'
  - q: 'Which password manager doesn''t need an account?'
    a: 'KeePassXC and MacPass need no account at all: you download them and make a database file. Stillroom Vault needs no account either; you make a vault on your Mac and that''s it.'
  - q: 'Is an offline password manager safer than a cloud one?'
    a: 'It removes one risk, a vendor''s server holding your encrypted vault, and adds another: if your Mac and your backups are lost, so are your passwords. Good cloud managers are end-to-end encrypted. Offline suits people who would rather nothing leave their own devices.'
  - q: 'Can I use KeePass on a Mac?'
    a: 'Not the original KeePass, which is a Windows app, but several Mac apps open the same .kdbx files: KeePassXC, MacPass and Strongbox among them.'
  - q: 'Does Stillroom Vault fill in passwords?'
    a: 'No. Stillroom has no browser extension and no autofill. You copy a password, and it clears from the clipboard after 30 seconds if nothing else was copied since.'
sources:
  - label: 'KeePassXC: home page'
    url: 'https://keepassxc.org/'
  - label: 'KeePassXC: User Guide'
    url: 'https://keepassxc.org/docs/KeePassXC_UserGuide'
  - label: 'Strongbox: home page'
    url: 'https://strongboxsafe.com/'
  - label: 'Strongbox: Pricing'
    url: 'https://strongboxsafe.com/pricing/'
  - label: 'Strongbox: source code (AGPL-3.0)'
    url: 'https://github.com/strongbox-password-safe/Strongbox'
  - label: 'MacPass: README on GitHub'
    url: 'https://github.com/MacPass/MacPass'
  - label: 'MacPass: feature status'
    url: 'https://github.com/MacPass/MacPass/wiki/Status'
  - label: 'Enpass: Pricing'
    url: 'https://www.enpass.io/pricing/'
  - label: 'pwSafe on the Mac App Store'
    url: 'https://apps.apple.com/us/app/pwsafe-password-safe/id520993579'
  - label: 'Password Safe: home page'
    url: 'https://www.pwsafe.org/'
---

## What "offline" really means for a password manager

"Offline password manager" gets used for quite different things. Four questions sort them out:

1. **Do you need an account?** Some apps ask for an email address and a sign-in before they do anything. A truly local one lets you make a vault and start.
2. **Does the vendor hold your vault?** Many cloud managers are end-to-end encrypted, so the company can't read your data, but it still keeps a copy on its servers. Every app on this page keeps your vault on your own Mac instead.
3. **Where does sync go?** Most offline managers can still sync, by putting the vault in iCloud Drive, Dropbox or a server you run. That's your choice and your storage, but it does mean the vault goes online.
4. **Can the app reach the network at all?** Even a local app may fetch site icons, check for updates, or talk to a sync service. Usually you can turn these off. Very few apps have no network code at all.

None of these is right or wrong. An app that syncs through your own iCloud is still far more private than most, and an app that can never go online is less convenient. It's worth knowing which kind you're choosing.

## Is there a password manager that works without internet?

Yes, all six below. Each keeps an encrypted vault on your Mac and opens it with no connection. They differ in price, in how they sync, whether they fill in passwords for you, and whether they run on anything other than a Mac. Prices were checked on 30 October 2026, in US dollars.

## KeePassXC

KeePassXC is a free, open source password manager for Windows, macOS and Linux, under the GPLv3. Its site says no data is stored on remote servers, with no ads and no subscriptions. Your passwords live in a `.kdbx` file you can keep anywhere.

It has a browser extension for Firefox, Chrome, Chromium and Vivaldi, Auto-Type for other apps, two-factor (TOTP) codes, passkeys, and an SSH agent. You can require a key file or a YubiKey as well as your password. There's no built-in sync and no official phone app, so if you want your passwords on several devices you put the file in a cloud folder and open it with another KeePass app on your phone.

It suits you if you want something free and fully open, on any desktop. We compare it with Stillroom in detail in [Stillroom Vault vs KeePassXC](/compare/keepassxc/).

## Strongbox

Strongbox is a KeePass and Password Safe app for iPhone, iPad and Mac, with an Apple Watch companion. It fills passwords in Safari, Chrome and Firefox. It can add two-factor codes by QR code, and unlocks with Touch ID or Face ID.

Your database can stay offline on one device, or sync through your own cloud storage, WebDAV, SFTP or Strongbox's Wi-Fi Sync between your devices. Because it uses the KeePass format, the same file opens in KeePassXC or MacPass too.

There's a free version for non-commercial use with fewer convenience features. Strongbox Pro costs $2.99 a month, $24.99 a year, or $124.99 once for a lifetime licence. The source code is on GitHub under the AGPL-3.0. Its site says Strongbox has joined a company called Applause.

It suits you if you want one KeePass vault on your Mac and iPhone, with autofill, and don't mind paying for the full version.

## MacPass

MacPass is a free, open source KeePass app made only for macOS, under the GPLv3. Its developer describes it as the only fully open source native macOS KeePass client. It opens and saves `.kdbx` files, including KDBX 4, with key files, attachments, entry history, two-factor codes and Auto-Type, which types your username and password into the app or web page in front.

There's no built-in sync, though it can merge two copies of a database. Development was quiet for a few years before version 0.8.2 in September 2026. One practical note: its old web address lapsed, and the developer says to download MacPass only from [its GitHub releases page](https://github.com/MacPass/MacPass/releases), not from the old domain.

It suits you if you want a native, free, open source KeePass app on your Mac and don't need a phone app from the same developer. See also [MacPass compared](/compare/macpass/).

## Enpass

Enpass is offline-first rather than strictly offline. Its pricing page says every plan keeps your vault in your own iCloud, Google Drive, OneDrive, Dropbox, Box or other personal cloud, never on Enpass's servers. You can also keep it on one device with no sync at all.

It's the most complete of the six as an everyday password manager: apps for Windows, macOS, Linux, iOS and Android, browser extensions for Chrome, Edge, Firefox, Safari, Brave, Vivaldi and Opera, autofill, passkeys, a built-in authenticator for two-factor codes, and breach monitoring. It isn't open source; its encryption uses the open source SQLCipher engine.

The free plan holds up to 25 items in one vault. Premium is $1.99 a month billed yearly, or $49.99 for three years, and a Family plan covers six people. More on it in [Enpass compared](/compare/enpass/).

It suits you if you want 1Password-style convenience on every device while keeping the vault in storage you control.

## pwSafe

pwSafe is a Mac App Store app from Huvisoft B.V. that opens the Password Safe format, an older open source format best known from the free Password Safe app for Windows. The Mac app itself isn't open source. It costs $14.99 once, and needs macOS 14 or later.

It syncs with its iPhone and iPad app through iCloud, or through Dropbox, autofills in Safari, and supports Touch ID and printing a paper copy of your data.

It suits you if you already use Password Safe on Windows, or want a simple paid Mac app with a one-off price.

## Stillroom Vault

Stillroom Vault is our app, so read this entry with that in mind. It's an encrypted vault for Apple silicon Macs running macOS 26 or later. It holds passwords, two-factor codes and notes, but it was built around files: scans, contracts, photos, recordings and documents of any size, with folders, tags and earlier versions.

It's the strictest answer to question 4 above. Stillroom has no account, no server and no sync, makes no network connections, and a build check fails any version that links networking code. Each item is sealed with AES-256-GCM under its own key, and your password is stretched with Argon2id using 512 MB of memory. You get back in with a [recovery key](/features/recovery-key/), a printable [emergency kit](/features/emergency-kit/) split among people you trust, or [Touch ID](/features/touch-id/). Live two-factor codes show under any secret that holds a setup key.

The limits are real. There's no autofill: you copy a password, and the clipboard clears after 30 seconds if nothing else was copied since. There's no sync and no phone app. The source is published under the Functional Source License, which is source available, not open source, and Stillroom hasn't had an independent security audit yet; one is planned. It's free for 25 items, or $39 once for all of one person's Macs.

It suits you if you want one place on your Mac for documents and the passwords that matter most, that never goes online.

## Side by side

| App | Price (30 October 2026) | Sync | Platforms | Open source | Autofill |
|---|---|---|---|---|---|
| KeePassXC | Free | None built in; put the file in a folder you choose | Windows, macOS, Linux | Yes (GPLv3) | Browser extension and Auto-Type |
| Strongbox | Free version; Pro $2.99/month, $24.99/year or $124.99 once | Your own cloud, WebDAV, SFTP, Wi-Fi Sync | iPhone, iPad, Mac | Yes (AGPL-3.0) | Yes, in browsers |
| MacPass | Free | None built in; can merge databases | macOS | Yes (GPLv3) | Auto-Type |
| Enpass | Free for 25 items; Premium $1.99/month billed yearly, or $49.99 for 3 years | Your own iCloud, Google Drive, OneDrive, Dropbox, Box or Nextcloud | Windows, macOS, Linux, iOS, Android | No | Yes, browser extensions |
| pwSafe | $14.99 once | iCloud or Dropbox | Mac, plus an iPhone and iPad app | Format yes; the Mac app no | Safari |
| Stillroom Vault | Free for 25 items; $39 once | None; it never goes online | Apple silicon Macs, macOS 26 or later | Source available (FSL) | None |

## How to choose

- **You want free and open source:** KeePassXC, or MacPass if you'd rather a Mac-only app. Both use the same file format, so you can switch between them.
- **You want your passwords on your iPhone too:** Strongbox, or Enpass. Both sync through storage you pick, not their own servers.
- **You want everyday autofill on every device:** Enpass is closest to a cloud password manager without the vendor cloud. If you're happy with a vendor cloud, [1Password](/compare/1password/) and [Bitwarden](/compare/bitwarden/) are also good choices.
- **You already use Password Safe:** pwSafe opens the same files.
- **You want nothing to go online at all, and you keep files as well as passwords:** Stillroom Vault. Many people pair it with one of the others: everyday logins in a password manager with autofill, and the things that must never leave the Mac (ID scans, [two-factor backup codes](/guides/store-two-factor-backup-codes/), the password manager's own master password) in Stillroom.

If price matters most, [password managers without a subscription](/compare/password-manager-no-subscription/) looks at which of these are genuinely one-time, and what lifetime deals carry with them.

## A few things to do whichever you pick

- **Back up the vault.** Offline means nobody else has a copy. Keep an encrypted backup somewhere other than your Mac, and test that it opens.
- **Use a strong master password.** Every app here stretches it to slow down guessing, but the password is still the real boundary. A [passphrase generator](/tools/passphrase-generator/) helps.
- **Delete exports promptly.** Moving between apps usually means a CSV file, and that file isn't encrypted. Import it, check a few entries, then delete it and empty the Trash.
- **Download from the real source.** Get each app from its own site, its GitHub page or the App Store, not from a mirror.
