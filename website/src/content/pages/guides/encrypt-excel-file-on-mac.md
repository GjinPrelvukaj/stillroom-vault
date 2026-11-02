---
title: 'How to Password Protect an Excel File on a Mac'
description: 'Encrypt an Excel or Numbers file on a Mac with a password to open, why sheet protection is not encryption, and how to keep spreadsheets locked.'
h1: 'How to password protect an Excel file on a Mac'
lead: 'In Excel for Mac, set a password to open the file (Review > Protect Workbook, or File > Passwords), then save. That encrypts it. Protect Sheet does not. In Numbers, choose File > Set Password. Here are the steps for both, and what each password really covers.'
name: 'Password protect an Excel file'
updated: '30 October 2026'
order: 16
points:
  - '**A password to open** encrypts the workbook. It is the one that protects it.'
  - '**Protect Sheet and Protect Workbook structure** stop edits, not readers. Microsoft says sheet protection is not a security feature.'
  - '**Numbers** encrypts a spreadsheet when you choose File > Set Password.'
related: ['/guides/encrypt-files-on-mac/', '/guides/password-protect-a-folder-on-mac/', '/guides/encrypt-pdf-on-mac/', '/tools/passphrase-generator/', '/compare/encrypted-disk-image/']
faq:
  - q: 'How do I password protect an Excel file on a Mac?'
    a: 'Open the workbook, choose Review > Protect Workbook (or File > Passwords), type a password in the box for opening the file, retype it, click OK and save. Only a password to open encrypts the file.'
  - q: 'Is Protect Sheet in Excel secure?'
    a: 'No. Microsoft says worksheet level protection is not intended as a security feature. It stops people changing locked cells, but anyone who opens the file can read everything in it.'
  - q: 'How do I password protect a Numbers spreadsheet?'
    a: 'Open it in Numbers, choose File > Set Password, enter the requested information, then click Set Password. Apple says adding a password encrypts the file, and there is no way to recover a forgotten one.'
  - q: 'Why will my Excel password not work on a Mac?'
    a: 'Microsoft says passwords in Excel for Mac have a 15-character limit. A file protected on Windows with a longer password cannot be opened in Excel for Mac; the person who set it needs to shorten it.'
  - q: 'Can Microsoft recover a forgotten Excel password?'
    a: 'No. Microsoft says it cannot retrieve forgotten passwords, and that without the password you cannot open the workbook.'
sources:
  - label: 'Microsoft: Require a password to open or modify a workbook'
    url: 'https://support.microsoft.com/en-us/excel/require-a-password-to-open-or-modify-a-workbook'
  - label: 'Microsoft: Prompt to open a workbook as read-only in Excel for Mac'
    url: 'https://support.microsoft.com/excel/prompt-to-open-a-workbook-as-read-only-in-excel-for-mac'
  - label: 'Microsoft: Change or remove workbook passwords'
    url: 'https://support.microsoft.com/en-us/office/change-or-remove-workbook-passwords-1c17af87-25e2-4dc6-94f0-19ce21ad0b68'
  - label: 'Microsoft: Protect a worksheet'
    url: 'https://support.microsoft.com/en-us/office/protect-a-worksheet-3179efdb-1285-4d49-a9c3-f4ca36276de6'
  - label: 'Microsoft: Protect a workbook'
    url: 'https://support.microsoft.com/en-us/office/protect-a-workbook-7e365a4d-3e89-4616-84ca-1931257c1517'
  - label: 'Microsoft: Protect an Excel file'
    url: 'https://support.microsoft.com/en-us/office/protect-an-excel-file-7359d4ae-7213-4ac2-b058-f75e9311b599'
  - label: 'Apple: Password-protect a spreadsheet in Numbers on Mac'
    url: 'https://support.apple.com/guide/numbers/tan42502bf11/mac'
---

## Four passwords, one lock

Excel has several things that ask for a password, and they protect very different things. Only one of them keeps people from reading your file.

| Setting | What it stops | Encrypts the file? |
| --- | --- | --- |
| Password to open | Anyone without it opening the file | Yes |
| Password to modify | Saving changes without it; anyone can still open it read-only | No |
| Protect Sheet | Changing locked cells on one sheet | No |
| Protect Workbook structure | Adding, moving, hiding or unhiding sheets | No |

Microsoft is direct about the last two: "Worksheet level protection isn't intended as a security feature," and protecting a sheet or workbook structure "is not the same as protecting an Excel file" with a password. If a spreadsheet holds salaries, account numbers or anything else private, you need the password to open.

## Set a password to open in Excel for Mac

These steps are for Excel for Microsoft 365 for Mac, Excel 2024 and Excel 2021. Microsoft's guide puts the passwords on the Review tab; the same passwords are also under the **File** menu as **Passwords**.

1. Open the workbook.
2. On the **Review** tab, click **Protect Workbook**. (Or choose **File > Passwords**.)
3. In the box for a password to open the file, type a password. Type it again to verify.
4. If you also want people to need a password to save changes, enter one in the box for modifying the file. Leave it empty if not.
5. Click **OK**.
6. **Save the workbook.** The password is not applied until you save.

Close the file and open it again to check: Excel should ask for the password before it shows anything.

Two Mac details worth knowing:

- **15 characters at most.** Microsoft says passwords in Excel for Mac have a 15-character limit, and a file protected on Windows with a longer password won't open in Excel for Mac. Within that limit, use something random rather than a word, because 15 characters is the whole of your protection.
- **No recovery.** Microsoft says that if you lose the password, you can't open the workbook, and that it cannot retrieve forgotten passwords.

To remove the password, open the workbook with it, go back to the same place, delete the password, click **OK**, and save.

### Protect Sheet, and read-only recommended

On the same **Review** tab, **Protect Sheet** locks cells so they can't be changed, and **Protect Workbook** can also protect the workbook's structure. They are useful for stopping a colleague overwriting a formula by accident. They do not hide the numbers from anyone who opens the file.

Under **File > Passwords** there is also **Read-only recommended**. Microsoft notes that this "will not prevent changes from being made": it only asks people to open the file read-only.

## Set a password in Numbers

Apple's Numbers has one password per spreadsheet, and Apple says adding it encrypts the file.

1. Open the spreadsheet in Numbers.
2. Choose **File > Set Password**.
3. Enter the password and the other details it asks for, then click **Set Password**.

If your Mac doesn't have Touch ID, you may see **Remember this password in my keychain**. If it does, you can choose **Numbers > Settings** and select **Use Touch ID** to open protected spreadsheets with your finger.

To change it, choose **File > Change Password**. To remove it, choose **File > Change Password**, type the old password, and click **Remove Password**.

Apple's warnings: there is no way to recover the password if you forget it, and on a shared spreadsheet anyone with permission to edit can add, change or remove the password.

## What a file password does well, and what it doesn't

**Good for:**

- Sending one workbook by email or upload. The password goes with the file wherever it is copied.
- Built in, free, and easy for the other person to open.

**Not good for:**

- **Many files.** Each workbook needs its own password, chosen and remembered.
- **Copies you forget about.** Earlier versions, exports to CSV, attachments in your Sent mail, and the copy in Downloads are not protected.
- **Once it is open, it is open.** Anyone at your Mac while the workbook is open can read it.
- **Short passwords.** Excel for Mac's 15-character cap makes it easy to pick something guessable.

Send the password a different way from the file. And for a folder of spreadsheets you keep, an encrypted disk image (one password for all of them) is less work: see [how to password protect a folder on a Mac](/guides/password-protect-a-folder-on-mac/).

## Where Stillroom Vault fits

[Stillroom Vault](/features/) is for private spreadsheets you keep and update, alongside the other documents that go with them.

- **Every item is sealed on its own,** with AES-256-GCM and a fresh random key, under one vault password stretched with [Argon2id](/learn/argon2id/). That password has no 15-character limit, and the strength check refuses guessable ones.
- **Edit in Place** opens a spreadsheet in Excel or Numbers from a RAM disk, not your SSD, and seals your changes back into the vault when you are done.
- **Every item keeps earlier versions,** so an edit you regret can be undone.
- **Names, folders and contents do not show on disk,** and search covers names and contents from an encrypted word index.
- **It locks itself** after a set time, when the Mac sleeps, or with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>L</kbd> from any app.
- **It never goes online.** No account, no server, no sync.

What it does not do:

- **Excel or Numbers may keep their own traces.** Edit in Place opens the file in its own app, which may remember its name in recent files or keep its own copy. Stillroom warns you when you use it.
- **It does not make a protected file to send.** To share a workbook, export it and set a password to open in Excel.
- **It cannot recover a forgotten password.** Keep the recovery key it gives you.
- **It does not protect against malware with admin rights while the vault is open.**
- **Someone with a copy of the vault folder can see how many items it holds and their rough sizes,** but not names or contents.
- It needs Apple silicon and macOS 26 or later. It is free for 25 items, then $39 once ([pricing](/pricing/)). No independent security audit has been done yet; the [format is public](/format/).

## Which to use

- **One workbook to send:** a password to open in Excel, or File > Set Password in Numbers.
- **Stopping accidental edits to formulas:** Protect Sheet. Not for privacy.
- **A folder of spreadsheets you keep:** an encrypted disk image, or a vault such as Stillroom, on top of FileVault. See [how to encrypt files on a Mac](/guides/encrypt-files-on-mac/) for the full picture.
