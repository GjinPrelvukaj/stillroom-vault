---
title: 'Move from 1Password to an Offline Vault on Your Mac'
description: 'Export your 1Password logins as CSV, import them into Stillroom Vault, see what the CSV leaves behind, and delete the unencrypted file.'
h1: 'Moving from 1Password'
lead: 'Export your logins from 1Password as a CSV file, bring them into Stillroom, and delete the plain-text export once they are in.'
name: '1Password'
updated: '27 October 2026'
order: 50
related: ['/tools/qr-code-reader/', '/compare/1password/', '/moving-from/bitwarden/', '/guides/store-two-factor-backup-codes/']
faq:
  - q: 'Should I choose CSV or 1PUX when exporting from 1Password?'
    a: 'Choose CSV. Stillroom reads CSV password exports and does not read 1PUX files.'
  - q: 'Do my one-time passwords come across?'
    a: 'Yes. 1Password includes them in its CSV export, and Stillroom keeps each one in a concealed Two-factor setup field with the live code shown under it.'
  - q: 'What about my passkeys?'
    a: '1Password says passkeys can only be exported from its iOS and Android apps, and Stillroom imports passwords, not passkeys. 1Password suggests recreating passkeys on each website.'
  - q: 'Are my vaults and tags kept?'
    a: 'No. Every imported login goes into one folder called Imported. You can sort them into folders and add tags in Stillroom afterwards.'
sources:
  - label: '1Password Support: Export your data from 1Password'
    url: 'https://support.1password.com/export/'
---

## Should you move?

1Password syncs across your devices, fills in passwords and passkeys in the browser, and lets families and teams share vaults. If you depend on any of that, keep it. Stillroom has no sync, no account, no browser extension and no autofill. The [comparison page](/compare/1password/) goes through the differences honestly.

Stillroom is built for something narrower: a vault on one Mac that never goes online, holding files and notes alongside logins, each item sealed with AES-256-GCM under its own key. Some people move everything. Others keep 1Password for daily sign-ins and keep an offline copy of the accounts that matter most in Stillroom.

## Choose the CSV export

1Password exports in two formats:

- **CSV**, which contains only Login and Password items, with these fields: title, website, username, password, one-time password, favorite status, archived status, tags and notes.
- **1PUX**, 1Password's own unencrypted export, which keeps fields the CSV leaves out.

Stillroom reads the **CSV**. It doesn't read 1PUX files.

According to 1Password, the CSV leaves out security questions, linked items, linked apps and custom fields (which, 1Password notes, include things like two-factor backup codes). Other item types, such as credit cards, secure notes and identities, aren't in the CSV either, since it holds Login and Password items only. 1Password also says passkeys can only be exported from its iOS and Android apps. Make a note of anything you rely on in those places so you can move it by hand.

## Export from 1Password

1Password's steps for 1Password 8 on a Mac:

1. Open and unlock **1Password**.
2. In the menu bar, choose **File › Export** and choose your account.
3. Enter your account password (or sign in with your identity provider if you use SSO).
4. Choose **CSV** as the format, then select **Export Data**.
5. Choose where to save the file and confirm.

1Password's warning applies: exported files are not encrypted. Save it locally, such as on your Desktop, and don't email it or put it in a cloud folder.

## Import the file into Stillroom

With your vault unlocked in Stillroom:

1. Go to **Secrets** in the sidebar.
2. Open the **New Secret** menu and choose **Import from Passwords…**. Right-clicking empty space in the list offers the same command.
3. The file chooser mentions the Passwords app, but any supported export works. Pick the CSV from 1Password and click **Import**.

Stillroom reads the file in memory and recognizes 1Password's column names. Each row becomes a **Login** secret named after its 1Password title, with the website, username and password. Notes come across as a **Notes** field, and a one-time password as a concealed **Two-factor setup** field, with the live code shown under it.

All the new logins go into a folder called **Imported**. Stillroom leaves out rows with neither a password nor a username, and skips accounts already in the vault with the same site and username. Favorites, archived status and tags aren't carried over. A message tells you how many came in and how many were already there.

## Delete the export

Straight after the import, Stillroom asks whether to delete the export, because it lists every password unencrypted and everything in it is now in the vault:

- **Delete It for Good** deletes it at once, skipping the Trash.
- **Move to Trash** moves it to the Trash. Empty the Trash afterwards.
- **Keep It** leaves the file. Delete it yourself once you've checked the import.

Overwriting a file before deleting it doesn't reliably erase it on a Mac's SSD. FileVault, which encrypts the whole disk, is what keeps deleted data unreadable; check it's on in **System Settings › Privacy & Security**. If a backup disk or cloud folder picked up the export while it existed, delete that copy too.

## Check and fill the gaps

Open several imported logins and compare them with 1Password, including one with a one-time password: the code Stillroom shows should match 1Password's.

Then bring across what the CSV left behind:

- **Two-factor backup codes and security questions** kept in custom fields: add them as fields on the matching login, or see [storing two-factor backup codes](/guides/store-two-factor-backup-codes/).
- **Cards and identities:** add them by hand as Card and ID secrets.
- **Secure notes:** paste them into Stillroom notes.
- **Documents and attachments:** save them from 1Password and drag them into Stillroom as files.

Keep your 1Password account until you're sure everything is in Stillroom and you've stored the vault's [recovery key](/features/recovery-key/). Stillroom can't recover a forgotten password, and neither can anyone else.

The free version holds 25 items, and each login is one item; see [pricing](/pricing/).
