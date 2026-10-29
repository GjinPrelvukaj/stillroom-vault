# Screenshots

Real screenshots of the app, shown in the home page's "Inside the app" tabs (`src/components/home/Showcase.astro`).
Each is the capture itself, never resized (`<name>.webp`, 2880×1440, lossless), and a 1440-pixel lossless copy (`<name>-1440.webp`) for phones and 1x screens. Resizing or lossy compression blurs the text, with the window's own see-through corners
(the page draws the shadow).

| File | What it shows |
|---|---|
| `vault` | the Documents list |
| `preview` | a tax return open in the preview card |
| `lock` | the lock screen, a password half typed |
| `twofactor` | a Google login with its live code |
| `settings` | Settings, Access tab |

Everything in them is invented: "Elena Marsh" and her files, notes and logins. Never take them from a real vault.

To take them again:
1. Write the demo vault: from `macos/`, `STILLROOM_DEMO_DIR=<scratch>/home/Library/Application\ Support/Stillroom swift test --filter writesDemoVault`
   (`Tests/StillroomTests/DemoVaultTests.swift`; the password is in `password.txt` beside the vault).
2. Run a renamed demo copy of a debug build with `CFFIXED_USER_HOME=<scratch>/home STILLROOM_SHOW_IN_CAPTURE=1`, in
   light appearance, with the window set to 1440×720 points (wide and short, so it fits the page):
   `osascript -e 'tell application "System Events" to tell (first process whose unix id is <pid>) to set size of window 1 to {1440, 720}'`.
3. `screencapture -o -l <window id>` each screen, then save each as lossless WebP here, as captured and at 1440 pixels.
