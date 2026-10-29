---
title: 'Move Your Passwords from Apple Passwords to a Vault'
description: 'Export every login from the Passwords app on your Mac, import the file into Stillroom Vault, then delete the unencrypted export safely.'
h1: 'Moving from Apple Passwords'
lead: 'Export your logins from the Passwords app, bring them into Stillroom as secrets, and get rid of the plain-text file afterwards.'
name: 'Apple Passwords'
updated: '27 October 2026'
order: 10
related: ['/tools/qr-code-reader/', '/moving-from/chrome/', '/guides/store-two-factor-backup-codes/', '/features/recovery-key/']
faq:
  - q: 'Do my verification codes come across from Apple Passwords?'
    a: 'When the export holds a two-factor setup for an account, Stillroom keeps it in a concealed field called Two-factor setup and shows the live code under it. Check one or two accounts after the import to make sure.'
  - q: 'Are passkeys and Wi-Fi passwords imported?'
    a: 'No. Apple says the Passwords app cannot export Wi-Fi passwords, and Stillroom imports only what is in the exported file, which is passwords, not passkeys.'
  - q: 'Should I keep using the Passwords app as well?'
    a: 'You can. Stillroom does not fill in passwords on websites, so many people keep Passwords for everyday sign-ins and use Stillroom for the records they want offline and separate.'
  - q: 'What if I import the same file twice?'
    a: 'Accounts already in the vault with the same site and username are skipped, and Stillroom tells you how many it skipped.'
sources:
  - label: 'Apple Support: Export passwords from your Mac to a file'
    url: 'https://support.apple.com/guide/passwords/export-passwords-mchl35b12625/mac'
---

## Before you start

The Passwords app on your Mac is free, built in, and fills in passwords for you in Safari and other apps. It syncs through iCloud Keychain to your other Apple devices. Stillroom does none of that: it has no server, no account and no sync, and it doesn't fill in sign-in forms. What it gives you is a vault that never goes online, sealed with AES-256-GCM, that also holds files and notes, with its own password, recovery key and emergency kit. See [features](/features/) and the [security model](/security/) for what that means and where its limits are.

Many people keep Passwords for daily sign-ins and keep a separate, offline copy in Stillroom. Others move everything. Either way, the steps are the same.

You'll need Stillroom open and unlocked, and a few minutes.

## Export from the Passwords app

Apple documents these steps for the Passwords app on the Mac:

1. Open the **Passwords** app.
2. Choose **File › Export All Passwords to File**.
3. Click **Export Passwords**.
4. Choose where to save the file, then click **Save**.

The result is a CSV file. Apple's own warning is worth taking literally: exported passwords are not encrypted, and anyone who can read the file can read every password in it. Save it somewhere local, such as your Desktop, not a synced folder like iCloud Drive, and don't email it.

Apple also notes what can't be exported: Wi-Fi passwords, passwords you share with a group (unless you created the group), and access to Sign in with Apple accounts. Those stay in Passwords.

If you only want to move one account, select it and choose **File › Export Selected Password to File** instead. Stillroom imports a one-account file the same way.

## Import the file into Stillroom

With your vault unlocked:

1. Go to **Secrets** in the sidebar.
2. Open the **New Secret** menu and choose **Import from Passwords…**. (You can also right-click empty space in the list and choose the same command.)
3. Pick the file you exported and click **Import**.

Stillroom reads the file in memory and writes nothing decrypted to disk while doing it. Each account becomes a **Login** secret with its website, username and password. If the export has a note for an account, that comes across as a **Notes** field. If it has a two-factor setup (an `otpauth` link), that comes across as a concealed **Two-factor setup** field, and Stillroom shows the live code under it.

All the new logins go into a folder called **Imported**, so you can see at a glance what came in and move things around later.

A few rows are left out on purpose:

- Rows with neither a password nor a username.
- Accounts already in the vault with the same site and username. If you import the same file twice, nothing is doubled.

When it's done, Stillroom tells you how many logins it imported and how many were already there.

If Stillroom says the file isn't a password export, check that you picked the CSV file the Passwords app saved, not a different file.

## Delete the export

Right after the import, Stillroom asks whether to delete the exported file, because it lists every password unencrypted and everything in it is now in the vault. You get three choices:

- **Delete It for Good** deletes the file straight away, without going through the Trash.
- **Move to Trash** puts it in the Trash. Remember to empty the Trash afterwards, or the file is still there.
- **Keep It** leaves the file where it is. If you choose this, delete it yourself as soon as you've checked the import.

On an Apple silicon Mac's SSD, overwriting a file before deleting it does not reliably erase it. What makes deleted data unreadable is FileVault, which encrypts the whole disk. If FileVault is off, turn it on in **System Settings › Privacy & Security**.

If you saved the export anywhere that syncs or backs up (iCloud Drive, Dropbox, a Time Machine disk), check there too. A Time Machine backup taken while the file existed will still hold a copy.

## Check a few accounts

Open three or four imported logins and compare them with the Passwords app: the site, the username and the password. Check one account that uses a verification code and make sure the code Stillroom shows matches the one in Passwords. If you rely on notes, check one of those as well.

Copying a password from Stillroom puts it on this Mac's clipboard only (not Universal Clipboard), and Stillroom clears it after 30 seconds.

## What doesn't move

- **Passkeys.** The export holds passwords, not passkeys. Keep passkeys in Passwords or set up new ones where you need them.
- **Autofill.** Stillroom doesn't fill in websites. You open the secret and copy what you need.
- **Sync.** A Stillroom vault lives on one Mac. To keep a copy elsewhere, make an encrypted backup to one file and store that where you like.

The free version of Stillroom holds 25 items, and each imported login is one item. See [pricing](/pricing/) if your export holds more.

## If you forget the vault password

Stillroom can't recover a forgotten password, and neither can anyone else. Before you rely on the vault for your passwords, write down the [recovery key](/features/recovery-key/) it made with the vault, and consider an emergency kit. The [support page](/support/#forgot) explains what to do if you're locked out.
