---
title: 'Move Saved Passwords from Chrome to an Offline Vault'
description: 'Export your saved passwords from Google Password Manager in Chrome, import the CSV into Stillroom Vault on your Mac, then delete the export.'
h1: 'Moving from Chrome'
lead: 'Download your saved passwords from Google Password Manager, import them into Stillroom, and remove the plain-text file when you are done.'
name: 'Chrome'
updated: '27 October 2026'
order: 20
related: ['/moving-from/apple-passwords/', '/moving-from/firefox/', '/guides/store-two-factor-backup-codes/']
faq:
  - q: 'Does this work for Edge, Brave or other Chromium browsers?'
    a: 'Stillroom recognizes the column names Chrome and other browsers use in their password exports, so a CSV from a similar browser will usually import. Check a few accounts afterwards, as we have not listed every browser here.'
  - q: 'Will my passkeys come across?'
    a: 'No. Stillroom imports the passwords in the exported file, not passkeys. Keep passkeys in Google Password Manager or set up new ones.'
  - q: 'Do I have to delete my passwords from Chrome?'
    a: 'No. Importing copies them into Stillroom and leaves Chrome as it was. Whether you also remove them from Google Password Manager is up to you.'
sources:
  - label: 'Google Chrome Help: Manage passwords in Chrome'
    url: 'https://support.google.com/chrome/answer/95606'
---

## What changes when you move

Chrome saves your passwords in Google Password Manager. It fills them in as you sign in and, when you are signed in to Chrome, syncs them through your Google Account to your other devices. Those are real conveniences, and Stillroom doesn't replace them: it has no browser extension, no account and no sync, and it doesn't fill in sign-in forms.

What Stillroom offers instead is a vault on your Mac that never goes online. Each item is sealed with AES-256-GCM under its own key, and the vault opens with your password, a recovery key, an emergency kit or Touch ID. The same vault holds files, notes and two-factor codes. The [security page](/security/) sets out what it protects against and what it doesn't.

Some people move everything. Others keep Chrome for everyday sign-ins and keep an offline copy of their most important accounts in Stillroom. The steps below work for both.

## Export from Chrome

Google's help page gives these steps for Chrome on a computer:

1. Open **Chrome**.
2. At the top right, select **More** (the three dots), then **Passwords and autofill**, then **Google Password Manager**.
3. On the left, select **Settings**.
4. Next to **Export passwords**, select **Download file**.

Save it to a local folder such as your Desktop, not a folder that syncs to the cloud. The file is a CSV that lists every saved password in plain text, so treat it with care until it's deleted.

## Import the file into Stillroom

Open Stillroom and unlock your vault, then:

1. Go to **Secrets** in the sidebar.
2. Open the **New Secret** menu and choose **Import from Passwords…**. You can also right-click empty space in the list and choose it there.
3. The file chooser mentions the Passwords app, but any supported export works. Pick the file Chrome saved and click **Import**.

Stillroom reads the file in memory. For each account it makes a **Login** secret with the website, username and password, and adds a **Notes** field when Chrome's export has a note for that account. Each login is named after the name in the export, or else the site's address without "www.".

New logins go into a folder called **Imported**. Stillroom skips rows that have neither a password nor a username, and accounts already in the vault with the same site and username, so a second import doesn't make duplicates. A message tells you how many came in and how many were already there.

If you see "That file isn't a password export", you've likely picked a different file. Choose the CSV Chrome downloaded.

## Delete the export

As soon as the import finishes, Stillroom offers to delete the export file, since it lists every password unencrypted and its contents are now in the vault:

- **Delete It for Good** deletes it immediately, skipping the Trash.
- **Move to Trash** moves it to the Trash. Empty the Trash afterwards.
- **Keep It** leaves it alone. Delete it yourself once you've checked the import.

Deleting a file on a Mac's SSD doesn't overwrite it, and overwriting it first wouldn't reliably help either. FileVault, which encrypts the whole disk, is what keeps deleted data unreadable. Check that it's on in **System Settings › Privacy & Security**.

Also check the folder you saved it to (often Downloads) for any second copy, and remember that a backup disk or cloud folder may have picked up the file while it existed.

## Check what came across

Open a handful of imported logins and compare them with Google Password Manager. Check that the site, username and password match, and that any notes you rely on are there.

Two things to know about Chrome exports in particular:

- **Two-factor codes.** If you keep authenticator codes in a separate app, nothing changes. If you want Stillroom to show live codes for an account, add its setup key or `otpauth` link to the login as a field, and the code appears under it. See [storing two-factor backup codes](/guides/store-two-factor-backup-codes/).
- **Passkeys.** Stillroom imports passwords, not passkeys. Keep passkeys where they are. Payment cards can be added by hand as Card secrets.

## Living without autofill

Without a browser extension, signing in means opening Stillroom, finding the account and copying the password. The copy stays on this Mac (not Universal Clipboard), is marked as concealed and transient for clipboard managers, and is cleared after 30 seconds or when the vault locks.

If that's too slow for daily use, a reasonable setup is to keep Chrome or the free Passwords app for sign-ins and use Stillroom as the offline record you control. The free version of Stillroom holds 25 items, and each login counts as one; see [pricing](/pricing/) for more.

Stillroom can't recover a forgotten vault password, and neither can anyone else. Keep the recovery key it gives you somewhere safe before you rely on it.
