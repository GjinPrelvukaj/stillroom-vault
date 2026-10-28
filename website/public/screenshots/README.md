# Real screenshots go here

The site shows the app through illustrations drawn from its design kit and labelled as such. Nothing here is
presented as a real screenshot until a real one exists.

When there are real screenshots, put them in this folder:

| File | What it shows |
|---|---|
| `vault.png` | the vault window, All Files, a demo vault with made-up files |
| `lock.png` | the lock screen |
| `twofactor.png` | a login secret with a live two-factor code |
| `settings.png` | Settings, Access tab |

How to take them:
- Take them from a demo copy, never a real vault (the README's Building section says how).
- Stillroom hides its windows from capture. Turn on **Show in screenshots & screen sharing** in that demo vault first.
- Use 2× PNGs at the app's default window size (1180×760 points), cropped to the window.

Then swap the matching illustration in `src/components/home/Showcase.astro` and `src/pages/features.astro` for an
`<img>`, with alt text that says what's on screen.
