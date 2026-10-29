# stillroomvault.com

The website for Stillroom Vault: an [Astro](https://astro.build) static site, deployed on Cloudflare Pages.

It practises what the app preaches:
- **Almost nothing third-party.** No cookies, trackers, web fonts, CDNs or embeds. The one outside script is Cloudflare
  Web Analytics' beacon (in `Base.astro`), which counts visits without cookies and can't identify anyone; the privacy
  page says so. Checkout loads Paddle, on `/checkout/` only.
  - `scripts/check-offline.mjs` runs after every build and fails it on any URL to a host outside its list
    (stillroomvault.com, paddle.com, github.com, cloudflareinsights.com).
  - `public/_headers` sets a strict Content-Security-Policy: no inline styles, scripts only from this site and the
    analytics beacon, and connections only back to this site and Cloudflare's analytics.
- **No drift.** These pages are rendered from the repository's own files at build time, never copied by hand:
  - the security page, from `docs/SECURITY.md`; its threat-model panel is parsed out of the same file
  - the format page, from `docs/FORMAT.md`
  - the changelog, from `CHANGELOG.md`
  - the security policy, from `.github/SECURITY.md`
  - the licence page, from `LICENSE.md`
  - the features page, from README.md's Features section
  - `/tools/stillroom-open.py`, served as is, with its SHA-256 shown on the format page
- **Works without JavaScript.** Scripts only add motion and the live demos; the menu is a `<details>` and opens without
  them.
- **Calm motion.** `prefers-reduced-motion` gets a still version of every animation.

## Run and build

Needs Node 22.23 or later (Astro 7); Node 24 LTS from nodejs.org is easiest. Works the same on macOS, Windows and
Linux. From `website/`:

```bash
npm install
npm run dev          # http://localhost:4321, live reload (Astro's telemetry is switched off first)
npm run build        # dist/, then the offline check
npm run check        # astro check: TypeScript (strictest) and template diagnostics
npm run serve        # serve dist/ with the real _headers (CSP included), gzipped like Cloudflare
npm run screenshots  # with `serve` running: every page at 390, 768 and 1440 px, plus console errors and CSP violations
node scripts/interact.mjs   # with `serve` running: drives the tabs, seal demo, decoy and live count; reports errors
node scripts/make-og.mjs     # after a build: redraw every page's link preview (public/og.png, public/og/*.jpg), then build again
node scripts/make-icons.mjs  # redraw the tab and home-screen icons from public/favicon.svg and scripts/site-icon.png
python3 scripts/add-art.py [--plate] <image> <slot> ...   # add generated art (see ART.md)
```

`screenshots`, `interact`, `make-og` and `make-icons` use Playwright (`require('playwright')`); `npm install` may prune
it, so `npm i --no-save playwright` first if it's missing. `add-art.py` needs Pillow.

## Cloudflare Pages

| Setting | Value |
|---|---|
| Framework preset | Astro |
| Root directory | `website` |
| Build command | `npm run build` |
| Build output directory | `dist` |
| Build watch paths | `website/*`, `docs/*`, `CHANGELOG.md`, `.github/SECURITY.md`, `LICENSE.md`, `README.md`, `tools/*` |
| Environment variable | `NODE_VERSION` = `24` |

The last three watch paths are added on purpose: the licence page renders `LICENSE.md`, the features page reads
`README.md`, and the site serves `tools/stillroom-open.py`.

In the Cloudflare dashboard, keep off everything that injects code into pages. Each one would break the CSP:
- Web Analytics' automatic injection (the beacon is already in `Base.astro`; a second copy would count twice), and
  Rocket Loader
- Email Address Obfuscation (Scrape Shield). It rewrites `mailto:` links and adds a script.
- Automatic HTTPS Rewrites can stay on. Zaraz, and any "Speed" setting that edits HTML, stay off.

## Where things live

- `src/config.ts` holds prices, email addresses, the download link and the Paddle settings. Change them there and
  every page follows.
- `src/styles/tokens.css` holds the design as web tokens: colours, radii, type, spacing, the page widths (content runs
  up to 1760px between 48px and 80px margins), and the app's three springs (SwiftUI response and damping) sampled into
  CSS `linear()` curves. `src/scripts/gsap.ts` has the same springs as GSAP eases.
- Real screenshots of the app go in `public/screenshots/` (see its README), made from the demo vault.
- The look is paper and ink: warm paper (`#f7f6f2`), near-black ink, one violet (`#6043ca`) for what is sealed. Every
  h1 and h2 is in the system serif, everything else in the system sans; there are no web fonts. `.ink` (in
  `tokens.css`) is the dark surface: the menu, the footer, the app's window, and whole pages given `theme="night"`
  (the format page and About). Everything inside it reads the dark token values. Panels, demos and code blocks are
  raised paper.
- Corners: rounded boxes, cards, fields and pictures use `corner-shape: squircle` (Apple's continuous corners) where
  the browser draws it, which is Chromium today; elsewhere they stay round. The radii grow a little inside that
  `@supports` block, and pills and circles are listed there to keep their round ends (`global.css`, "Squircle
  corners"). Add a new pill's class to that list.
- The fade at the foot of the screen (`.bottom-fade` in `Header.astro`) takes the page's own `--bg`, so it's paper on
  paper pages and ink on dark ones.
- Pictures are collages in one series (a vintage watercolour inside a framed panel, a sun-faded photograph around it)
  in `public/art/`, one slot each (`src/components/Art.astro`, `src/lib/art.ts`).
  Framed ones (the home plate, Learn more, the cards, the pricing tiers, the menu) keep their printed paper on a
  rounded plate; the rest sit loose beside text on the page's own paper. `ART.md` has the look, every slot and its
  prompt.
  Each picture also has an 800px copy beside it (`<slot>-800.webp`, made by `scripts/add-art.py`), offered through
  `srcset` so phones and cards don't download the full 1600px; `public/_headers` caches pictures and link previews
  for a week.
- The header (`Header.astro`, `scripts/header.ts`) stays put; away from the top the wordmark folds into "S" and the
  ring, letter by letter. Its menu is a full-screen ink panel that drops in as a curtain and lifts on close.
- Where pictures sit: section hubs show theirs beside the heading (`PageLayout`); articles show their own print
  framed under the heading; tool pages show it large beside the heading (`ToolHero`); About opens with it wide across
  a dark band. Security, format, the changelog and the legal pages show none on the page, but their prints still
  make their link previews (ART.md, "Per page").
- Link previews (`scripts/make-og.mjs`): a page with a picture gets that picture full-bleed, with the wordmark and its
  heading over a soft fade; it finds it by the classes `hero-picture`, `cover` or `og-picture`, or falls back to the
  page's print from the `prints` table in the script. A page with neither gets a paper card with its eyebrow and
  heading. Run it after any new picture, then build again.
- Layouts: `PageLayout` (a heading with its picture beside it, then the page) and `DocLayout` (articles, the
  repository's documents and the legal pages, which are written in their page files and passed in, their headings
  read out for the contents: a centred heading, then numbered contents, the text under its picture, and a column with when the page
  was checked, its section and more like it; a bar under the header names the chapter being read, a violet thread
  runs down the text's margin through its chapters, and faint paper washes lie behind it, placed differently on
  every page; see ART.md, "Paper washes"). `DocLayout` takes an optional `hero` slot (a tool page's `ToolHero`) and a
  `tool` slot shown first in the text column; the hero slot counts only if it renders something, since an empty
  conditional slot still reports as present (that once dropped every article's heading).
- `src/pages/about.astro` is About, on the dark surface: the masks picture, then each section in a layout of its own.
  Every claim on it is one the site or `docs/SECURITY.md` already makes, except the story, which is the owners' words.
- The home page runs: hero and plate, three start-here cards, the app, what it does, the seal demo, never goes
  online, pricing (plain cards: the prints are saved for Learn more), questions, Learn more, download. Each idea is said once; the detail lives on its own page.
- `src/scripts/` holds the motion and the live parts:
  - the file names under the home picture turning to ciphertext as you reach it (`home-plate.ts`)
  - the footer's groups easing open and shut in every browser (`disclosure.ts`, on any `<details data-glide>`)
  - the in-browser AES-256-GCM demo (`seal.ts`)
  - the decoy guess (`decoy.ts`)
  - the live count of files from other sites, from the browser's own Resource Timing record (`netpanel.ts`)
  - the format page's terminal and the Argon2 ring (`terminal.ts`, `argon.ts`)
  - the header and menu (`header.ts`), and the contents lists and chapter bar (`toc.ts`)
  - the features page's tabs, through the shared `.segments` tab control in `site.ts`
  - the free tools, one script per tool in its component, with their logic in `src/scripts/tools/` (below)
  - site search, opened by the header's button, `/` or ⌘K, over `/search.json` built at build time (`search.ts`)
  - the menu's letter roll (`text-roll.ts`), the home app tabs (`xtabs.ts`), the seal demo's caret (`caret.ts`)
    and the never-online heading's words closing up (`converge.ts`)
- Some pieces are rebuilt from [Skiper UI](https://skiper-ui.com) components (React there, Astro, CSS and GSAP here),
  numbered as on that site:
  - everywhere: the blur under the header (41), scroll fades (87), the text link hover (40), the menu letter roll
    (58), search (92), the questions' bouncy accordion (103, all CSS)
  - home: the app tabs (96), Learn more widening on hover (52), the seal demo's caret (106), the never-online
    heading (31), the start-here cards arriving (104), the row icons' motions (99)
  - articles and documents: the thread drawn down the margin through the chapters, or the security page's rules
    (19, `thread.ts`)
  - security: the 512 MB odometer (37, `argon.ts`)
  - format: term definitions on hover or focus (101, `terms.ts`, words in `src/lib/glossary.ts`)
  - changelog: the versions as a timeline (74, `timeline.ts`)
- `src/content/pages/<section>/<slug>.md` are the site's articles, served at `/<section>/<slug>/`: `compare`, `guides`,
  `features` (listed on /features/), `moving-from`, `learn`, `for` and `tools`. Each section's hub is built from
  `src/lib/sections.ts`, and every page lands in the sitemap by itself. The frontmatter (title, description, related
  pages, FAQ, sources) is checked by the schema in `src/content.config.ts`. Claims about Stillroom must match
  `docs/SECURITY.md`; claims about other products need an official page in `sources`, and the page's `updated` date
  says when they were checked. `scripts/check-copy.mjs` fails the build on an em or en dash in them.
- The free tools (`/tools/`): each is an article in `src/content/pages/tools/` whose frontmatter names its `tool`, drawn
  by a component in `src/components/tools/` inside `ToolFrame` (a small app window) under `ToolHero`. The hub groups
  them by topic from `src/lib/tools.ts` (`ToolCards`); a tool missing from a group fails the build. Their logic is
  pure and tested by hand against published vectors: `otp.ts` (RFC 6238 and 4226, Google Authenticator exports),
  `strength.ts` (a line-for-line copy of the app's `PasswordStrength.swift`, 50 bits and 12 characters; keep them in
  step), `shamir.ts`, `pin.ts`, `random.ts` (no modulo bias) and the EFF long word list (`eff-words.ts`, CC BY 3.0).
  The QR reader uses jsQR, bundled. Nothing a tool is given leaves the page.
- `src/content.config.ts` is the loader that renders the repository's markdown. It rewrites the documents' relative
  links to this site's pages, or to GitHub.

## Releases and checkout

- **Download** (`src/config.ts`, `download`). The zip is served from `public/download/`. For a new version, put the zip
  there under its new name and set `url`, `file`, `version` and `sha256` (what `make-dist.sh` printed); every
  download button and the checksum tool follow.
- **Checkout.** Every buy button reads "Coming soon" until these are set as Cloudflare Pages environment variables:
  `PUBLIC_PADDLE_CLIENT_TOKEN`, `PUBLIC_PADDLE_PRICE_PERSONAL` and `PUBLIC_PADDLE_PRICE_FAMILY` (and
  `PUBLIC_PADDLE_ENV=sandbox` for testing). See "Turning on checkout" below.
- **Structured data** (`src/lib/schema.ts`): the app, its offers (`InStock`) and the public repository (`sameAs`).

### Turning on checkout

Buy buttons lead to `/checkout/?plan=personal|family` (`src/pages/checkout.astro`, `src/scripts/checkout.ts`): Paddle's
form inline, beside our own order summary filled from the totals Paddle sends (Paddle requires the summary, the full
frame with its footer, and a refund-policy link), and a thank-you once paid. It works once `PUBLIC_PADDLE_CLIENT_TOKEN`
and the price ids are set (Cloudflare Pages variables, read at build time). `public/_headers` gives `/checkout/` alone
the CSP, Permissions-Policy and opener policy Paddle's checkout needs. Paddle's default payment link is
`https://www.stillroomvault.com/checkout/` (Checkout › Checkout configuration); without one, every checkout opens on
"Something went wrong".

### The licence signer

`functions/api/paddle-webhook.ts` is a Cloudflare Pages Function, deployed with the site at
`https://www.stillroomvault.com/api/paddle-webhook`. The work is in `server/` (`webhook.ts`, `licence.ts`, `email.ts`),
outside `src/`, so nothing of it reaches the built pages; `public/_routes.json` runs Functions on `/api/*` only, so
every page is still served as a plain file. On `transaction.completed` it checks Paddle's signature (at most five
minutes old), skips an event id it has handled, looks the customer up in Paddle's API, signs a licence with Ed25519
and emails it. The same transaction always signs to the same key. It stores nothing about the buyer.

```bash
npm test                                                  # the signer's tests (Node's own runner, test key pair)
node scripts/make-licence-keys.mjs ~/stillroom-licence.key  # once, by hand: the production key pair
LICENCE_PRIVATE_KEY=… node scripts/issue-licence.mjs --edition teams --seats 12 --name "…" --email …   # by hand
```

`server/fixtures/test-licence.json` is a test key pair and a key it signed; the Swift tests check that same key, so the
app and the signer can't drift. It is never the production pair.

To switch it on (Pages project › Settings):

1. **Key pair.** Run `make-licence-keys.mjs` with a file outside the repository. Put the public key it prints in
   `License.publicKey` (`macos/Sources/Stillroom/Security/License.swift`) and build the app. Keep the private key in a
   password manager and one offline backup, and never commit it.
2. **Secrets** (Variables and Secrets, type Secret, Production; or `npx wrangler pages secret put NAME --project-name …`):
   - `LICENCE_PRIVATE_KEY`: the private key file's one line
   - `PADDLE_WEBHOOK_SECRET`: the endpoint's secret key from Paddle (step 5)
   - `PADDLE_API_KEY`: a Paddle API key allowed to read customers (`customer.read`)
   - `EMAIL_API_KEY`: the email provider's API key
3. **Plain variables:** `EMAIL_PROVIDER` (`resend` or `postmark`, or add a case to `server/email.ts`), `EMAIL_FROM`
   (`Stillroom Vault <licences@stillroomvault.com>`, on a domain the provider has verified), `PADDLE_ENV=sandbox` while
   testing. `PUBLIC_PADDLE_PRICE_PERSONAL` and `PUBLIC_PADDLE_PRICE_FAMILY` (already set for checkout) tell it the
   edition.
4. **KV:** create a namespace (Storage › KV, for example `stillroom-paddle-events`) and bind it to the project as
   `PADDLE_EVENTS` (Settings › Bindings). It holds handled event ids for a week, nothing else.
5. **Paddle:** Developer Tools › Notifications › New destination: URL `https://www.stillroomvault.com/api/paddle-webhook`,
   type webhook, event `transaction.completed`. Copy its secret key into `PADDLE_WEBHOOK_SECRET`, redeploy, then buy
   once in the sandbox and paste the key into a demo copy of the app.

If the email fails, the function answers 500 and remembers nothing, so Paddle retries and the retry sends the same key.
A key posted publicly: add its id to `License.blocked` in the app and ship a release; the buyer gets a new key by hand.
A lost key: `issue-licence.mjs` with the order's `txn_…` id, its billing day as `--issued`, and the name and email
Paddle has gives back the same key.
