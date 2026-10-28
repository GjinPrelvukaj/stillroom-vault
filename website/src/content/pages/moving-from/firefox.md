---
title: 'Move Your Saved Firefox Passwords to an Offline Vault'
description: 'Export your logins from Firefox to a CSV file, import them into Stillroom Vault on your Mac, and delete the unencrypted export afterwards.'
h1: 'Moving from Firefox'
lead: 'Export your saved logins from Firefox, bring them into Stillroom as secrets, and remove the plain-text file once they are in.'
name: 'Firefox'
updated: '27 October 2026'
order: 30
related: ['/moving-from/chrome/', '/moving-from/apple-passwords/', '/features/recovery-key/']
faq:
  - q: 'Why are my imported Firefox logins named after websites?'
    a: 'Firefox exports a site address for each login but no separate name, so Stillroom names each login after the site, without "www.". You can rename them afterwards.'
  - q: 'I use a Primary Password in Firefox. Does that matter?'
    a: 'Mozilla says Firefox may ask for your Primary Password, or your Mac login, before it exports. Once the file is saved it is not protected by either.'
  - q: 'Can I import the same file again after adding more logins in Firefox?'
    a: 'Yes. Accounts already in the vault with the same site and username are skipped, so only the new ones are added.'
sources:
  - label: 'Firefox Help: Export login data from Firefox'
    url: 'https://support.mozilla.org/en-US/kb/export-login-data-firefox'
---

## Before you move

Firefox's password manager fills in logins as you browse and, with a Mozilla account, syncs them between your devices. Stillroom doesn't do either. It has no browser extension, no account and no sync, and it doesn't fill in forms. It keeps your logins, along with files, notes and two-factor codes, in a vault on your Mac that never goes online, each item sealed with AES-256-GCM under its own key.

If you value Firefox's autofill, keeping it for daily sign-ins and using Stillroom as an offline copy is a sensible arrangement. If you'd rather your passwords live in one offline place, move them over and then remove them from Firefox. The [security page](/security/) explains what Stillroom protects against, and what it doesn't.

## Export from Firefox

Mozilla's help page gives these steps for Firefox on a computer:

1. Click the menu button (three lines) to open the menu panel.
2. Click **Passwords**. The `about:logins` page opens in a new tab.
3. Click the menu icon (three dots), then click **Export Passwords…**.
4. A dialog reminds you that the passwords are saved as readable text. Click **Continue with export**.
5. If you use a Primary Password, Firefox may ask for it, or ask for your Mac's login.
6. Choose a file name and location, then click **Save**.

Mozilla's warning is plain: the exported passwords are not encrypted and anyone who can view the file can read them. Don't upload, email or share it, and delete it when you're done. Save it somewhere local, such as your Desktop, rather than a synced folder.

## Import the file into Stillroom

With your vault unlocked in Stillroom:

1. Go to **Secrets** in the sidebar.
2. Open the **New Secret** menu and choose **Import from Passwords…**. Right-clicking empty space in the list offers the same command.
3. The file chooser mentions the Passwords app, but it accepts any supported export. Pick the CSV Firefox saved and click **Import**.

Stillroom reads the file in memory. Each account becomes a **Login** secret with its website, username and password. Firefox's export doesn't include a name for each login, so Stillroom names it after the site's address, without "www." (or after the username when there's no site).

The new logins go into a folder called **Imported**. Stillroom leaves out rows with neither a password nor a username, and skips accounts already in the vault with the same site and username. A message tells you how many logins it imported and how many were already there.

If it says "That file isn't a password export", check that you picked the CSV file from Firefox.

## Delete the export

Right after the import, Stillroom asks whether to delete the file you exported, because it lists every password unencrypted and everything in it is now in the vault:

- **Delete It for Good** removes it at once, without the Trash.
- **Move to Trash** sends it to the Trash. Empty the Trash afterwards.
- **Keep It** leaves the file. If you pick this, delete it yourself once you've checked the import.

On a Mac's SSD, overwriting a file before deleting it doesn't reliably erase it. FileVault, which encrypts the whole disk, is what keeps deleted files unreadable. Make sure it's on in **System Settings › Privacy & Security**. If a Time Machine backup or a cloud folder caught the file while it existed, that copy needs deleting too.

## Check a few logins

Open several imported logins and compare them with `about:logins` in Firefox: site, username and password. Rename any whose site-based name isn't clear, and organize them into folders or tags if you like.

A few things don't come across from a Firefox export:

- **Notes and two-factor codes.** Firefox's export holds sites, usernames and passwords. To get live codes in Stillroom, add an account's setup key or `otpauth` link as a field, and the code shows under it. See [storing two-factor backup codes](/guides/store-two-factor-backup-codes/).
- **Passkeys.** Stillroom imports passwords, not passkeys.
- **Autofill.** You copy a password from Stillroom when you need it. The copy stays on this Mac (not Universal Clipboard) and is cleared after 30 seconds or when the vault locks.

## Removing logins from Firefox

Once you've checked the import, you may want to remove your passwords from Firefox, especially if they sync through a Mozilla account. That's done in Firefox, from the `about:logins` page. Take your time with this step: removing them is your choice and isn't needed for the import to work.

## Before you rely on it

Stillroom can't recover a forgotten vault password, and neither can anyone else. Keep the [recovery key](/features/recovery-key/) it made with the vault somewhere safe, and consider an emergency kit for the people you trust.

The free version holds 25 items, and each login is one item. See [pricing](/pricing/) if you have more.
