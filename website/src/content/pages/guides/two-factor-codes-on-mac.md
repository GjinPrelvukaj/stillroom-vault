---
title: 'Authenticator App for Mac: 2FA Codes Without a Phone'
description: 'Get two-factor codes on your Mac with Apple Passwords, a password manager or an offline vault. How to set each up, and the trade-off to know first.'
h1: 'Two-factor codes on your Mac, without your phone'
lead: 'You don''t need your phone in your hand to sign in with two-factor codes. Your Mac can make the same six-digit codes. Here are the ways to do it, and the one trade-off to think about first.'
name: 'Two-factor codes on a Mac'
updated: '28 October 2026'
order: 55
points:
  - 'Any app holding a site''s setup key makes the same codes as your phone, so your Mac can make them.'
  - '**Apple Passwords** does it for free; 1Password and Bitwarden do it inside your password manager.'
  - 'Keep each site''s **backup codes** somewhere other than the device that makes your codes.'
related: ['/tools/two-factor-codes/', '/tools/qr-code-reader/', '/guides/store-two-factor-backup-codes/', '/moving-from/apple-passwords/', '/compare/1password-vs-bitwarden/', '/guides/if-your-mac-is-stolen/']
faq:
  - q: 'Is there a free authenticator app for Mac?'
    a: 'Yes. Apple Passwords, which comes with macOS, can make two-factor codes from a setup key. Select the account, click Edit, then Set Up Code.'
  - q: 'Can I move my codes from Google Authenticator or Authy to my Mac?'
    a: 'Not in one step for every site. The safe way is to turn two-factor sign-in off and on again for each site, or choose to set up a new authenticator, and scan the new setup key on your Mac. Keep the old app working until every account is moved.'
  - q: 'Is it safe to keep passwords and two-factor codes on the same Mac?'
    a: 'It is convenient, and still far safer than no two-factor at all. But if one place holds both your password and your code, someone who gets into that place has both. Keep the backup codes somewhere separate.'
  - q: 'What if I lose the Mac that makes my codes?'
    a: 'Use a backup code from the site, or a second device you set up with the same key. That is why backup codes should never live only on the device that makes your codes.'
sources:
  - label: 'Apple: Set up verification codes in Passwords on Mac'
    url: 'https://support.apple.com/guide/passwords/mchl873a6e72/mac'
  - label: '1Password: Use 1Password as an authenticator'
    url: 'https://support.1password.com/one-time-passwords/'
  - label: 'Bitwarden: Pricing'
    url: 'https://bitwarden.com/pricing/'
  - label: 'RFC 6238: TOTP, the time-based one-time password algorithm'
    url: 'https://datatracker.ietf.org/doc/html/rfc6238'
---

## How two-factor codes work

When you turn on two-factor sign-in with an authenticator app, the website gives you a **setup secret**, shown as a QR code or a "setup key". Any authenticator turns that secret into a new six-digit code every 30 seconds, using the same public method (RFC 6238). Nothing is sent between the app and the site: both work the code out from the secret and the time.

That means any app holding the secret makes the same codes as your phone. Your Mac can be that app.

## The trade-off to know first

Two-factor sign-in is strong because the code comes from somewhere other than your password. If the same app on the same Mac holds both your password and your code, someone who gets into that app has both.

For most accounts that is a fine trade: it still stops anyone who only has your password, which is how most accounts are broken into. For the accounts that matter most (your email, your Apple Account, your bank), you may prefer to keep codes in one place and passwords in another.

Whatever you choose, keep each site's **backup codes** somewhere you can reach without the device that makes your codes. [Where to store two-factor backup codes](/guides/store-two-factor-backup-codes/) covers the options. If you saved a setup key as a backup, the free [two-factor code generator](/tools/two-factor-codes/) checks it still makes the same codes as your app.

## Apple Passwords (free, built in)

The Passwords app that comes with macOS can make codes and fill them in Safari.

1. On the website, turn on two-factor sign-in with an authenticator app, and choose to enter a setup key by hand. Copy the key.
2. In Passwords, select the account, click **Edit**, then **Set Up Code**.
3. Paste the key into **Setup Key** and click **Use Setup Key**.
4. Click the verification code to copy it, and paste it into the website to finish.

If you use iCloud Keychain, your codes follow you to your iPhone and iPad as well. This is the easiest choice if every device you use is an Apple one.

## Your password manager

If you already use a password manager, it may make codes too. 1Password includes them on every plan. Bitwarden includes them on Premium and Families. Both fill the code for you after the password, and both sync it to every device.

Choosing between them? See [1Password vs Bitwarden](/compare/1password-vs-bitwarden/).

## An offline vault: Stillroom Vault

[Stillroom Vault](/features/) is an encrypted vault for files, notes and secrets on your Mac that never goes online. It isn't a password manager and doesn't fill anything, but it shows live two-factor codes:

- **Codes show under any secret holding an `otpauth` link or setup key,** made on your Mac. Paste the key, or read a QR code from the clipboard or from a screenshot. Stillroom then offers to move the screenshot to the Trash and clears a copied QR picture from the clipboard.
- **Setup secrets are treated like passwords.** They are added concealed and kept out of the search index.
- **Copies stay on this Mac.** A copied code doesn't go to Universal Clipboard, and is cleared after 30 seconds or when the vault locks.
- **No account, no sync, no server.** That keeps your codes off the cloud, and it also means they live only on this Mac, so keep backup codes elsewhere.

It suits the setup above: everyday logins in your password manager, and the codes and backup codes for your most important accounts kept apart, on one Mac. It's free for 25 items.

## Which to choose

- **Every device is an Apple one, and you want it easy:** Apple Passwords.
- **You already pay for a password manager:** use its codes for everyday accounts.
- **You want your most important codes kept apart from your passwords, and off the cloud:** an offline vault such as Stillroom, with backup codes on paper as well.
