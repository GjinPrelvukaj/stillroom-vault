---
title: 'Move from Bitwarden to an Offline Password Vault'
description: 'Which Bitwarden export to choose, how to import your logins into Stillroom Vault on a Mac, what stays behind, and how to delete the export.'
h1: 'Moving from Bitwarden'
lead: 'Export your Bitwarden vault as a .csv file, import the logins into Stillroom, and delete the unencrypted export once they are in.'
name: 'Bitwarden'
updated: '27 October 2026'
order: 40
related: ['/compare/bitwarden/', '/moving-from/1password/', '/guides/store-two-factor-backup-codes/']
faq:
  - q: 'Which Bitwarden export format should I choose?'
    a: 'Choose .csv. Stillroom reads password exports in CSV form, and not Bitwarden .json files, encrypted exports or .zip files with attachments.'
  - q: 'Do my secure notes come across?'
    a: 'No. Stillroom imports only login rows and skips notes. Copy any secure notes you want into Stillroom notes by hand.'
  - q: 'Are my Bitwarden folders kept?'
    a: 'No. Every imported login goes into one folder called Imported. You can sort them into folders in Stillroom afterwards.'
  - q: 'Are my authenticator keys imported?'
    a: 'Yes, when a login has one. Stillroom keeps it in a concealed Two-factor setup field and shows the live code under it.'
sources:
  - label: 'Bitwarden Help: Export vault data'
    url: 'https://bitwarden.com/help/export-your-data/'
  - label: 'Bitwarden Help: Condition a Bitwarden .csv or .json'
    url: 'https://bitwarden.com/help/condition-bitwarden-import/'
---

## Is moving the right choice?

Bitwarden is a password manager that syncs your vault across your devices and browsers, fills in sign-in forms, and supports sharing through organizations. If you need passwords on your phone, autofill in the browser, or shared vaults for a family or team, Bitwarden does those things and Stillroom doesn't. The [comparison page](/compare/bitwarden/) goes through the differences.

Stillroom is for a different job: a vault on one Mac that never goes online, with no server and no account. It holds files and notes as well as logins, sealed with AES-256-GCM under a fresh key per item. Some people move entirely. Others keep Bitwarden for daily sign-ins and keep an offline copy of their most important accounts in Stillroom.

## Choose the right export

Bitwarden offers several export formats. For Stillroom, choose **.csv**.

According to Bitwarden's help, a .csv export holds logins and secure notes, and leaves out:

- **Cards and identities.** Only .json exports include them.
- **Passkeys.** Only .json exports include stored passkeys.
- **SSH keys.** Only .json exports include them.
- **Attachments.** Only the .zip format with attachments includes them.
- **Trash and Sends.** No export format includes these.

Stillroom reads the .csv only. It doesn't read Bitwarden's .json, encrypted .json or .zip exports.

Export **My vault** for your own items. If you also want logins from an organization you belong to, Bitwarden lets you export an organization vault separately (only from collections you can manage); import that file the same way.

## Export from Bitwarden

In the **web app**:

1. Select **Tools**, then **Export**.
2. In **Export from**, choose **My vault**.
3. Choose **.csv** as the file format.
4. Select **Export**, then confirm with your master password or an email verification code.

In the **desktop app**:

1. Select **Export** from the navigation menu.
2. In **Export from**, choose **My vault**.
3. Choose **.csv** as the file format.
4. Select **Export vault**, confirm with your master password or an email verification code, then select **Export vault** again.

Save the file somewhere local, such as your Desktop, not a synced folder. It lists every password in plain text.

## Import the file into Stillroom

With your vault unlocked in Stillroom:

1. Go to **Secrets** in the sidebar.
2. Open the **New Secret** menu and choose **Import from Passwords…**. Right-clicking empty space in the list offers the same command.
3. The file chooser mentions the Passwords app, but any supported export works. Pick the .csv from Bitwarden and click **Import**.

Stillroom reads the file in memory and recognizes Bitwarden's column names. Each login becomes a **Login** secret named after its Bitwarden name, with the website, username and password. A login's notes come across as a **Notes** field, and its authenticator key (TOTP) as a concealed **Two-factor setup** field, with the live code shown under it.

What it leaves out:

- **Rows that aren't logins**, such as Bitwarden's secure notes. Copy any you need into Stillroom notes by hand.
- **Rows with neither a password nor a username.**
- **Accounts already in the vault** with the same site and username, so importing twice doesn't make duplicates.
- **Custom fields**, folders, favorites and the reprompt setting. Every imported login goes into one folder called **Imported**.

A message tells you how many logins came in and how many were already there.

## Delete the export

Right after the import, Stillroom asks whether to delete the export, because it lists every password unencrypted and everything in it is now in the vault:

- **Delete It for Good** deletes it straight away, skipping the Trash.
- **Move to Trash** moves it to the Trash. Empty the Trash afterwards.
- **Keep It** leaves the file. Delete it yourself once you've checked the import.

On a Mac's SSD, overwriting before deleting doesn't reliably erase anything. FileVault is what keeps deleted data unreadable, so check that it's on in **System Settings › Privacy & Security**. Delete any copy a backup or cloud folder may have picked up, too.

## Check what came across

Open a few imported logins and compare them with Bitwarden: site, username, password, and the two-factor code for an account that uses one. Then deal with what didn't come across: cards and identities can be added by hand as Card and ID secrets, attachments can be saved from Bitwarden and dragged into Stillroom as files, and secure notes can be pasted into new notes.

If you're leaving Bitwarden, keep your account until you're satisfied everything is in Stillroom and you have the vault's [recovery key](/features/recovery-key/) stored safely. Stillroom can't recover a forgotten password, and neither can anyone else.

The free version holds 25 items, and each login is one item; see [pricing](/pricing/).
