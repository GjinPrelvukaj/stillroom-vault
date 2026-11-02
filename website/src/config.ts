// Everything the site says about itself that might change: one place, so a price or an address is never stale on
// one page and right on another.

export const site = {
  name: 'Stillroom Vault',
  url: 'https://www.stillroomvault.com',
  tagline: 'The encrypted vault for your Mac that never goes online.',
  description:
    'Stillroom Vault keeps files, notes, passwords and two-factor codes sealed with AES-256-GCM on your Mac. No server, no account, no sync. $39 once, or free for 25 items.',
  seller: 'Gjin Prelvukaj',
  /** Joint copyright holders, by written agreement. The seller of record is `seller` alone. */
  owners: ['Gjin Prelvukaj', 'Lis Shala'],
  sellerCountry: 'Kosovo',
  year: 2026,
  version: '1.0',
  repo: 'https://github.com/GjinPrelvukaj/stillroom-vault',
} as const;

export const email = {
  hello: 'hello@stillroomvault.com',
  support: 'support@stillroomvault.com',
  security: 'security@stillroomvault.com',
  legal: 'legal@stillroomvault.com',
} as const;

/** The current download (public/download/). For a new version: put the zip there under its new name, change these, and
 *  set sha256 to what make-dist.sh printed. Every download button follows. */
export const download = {
  url: '/download/Stillroom-1.1.1.zip',
  placeholder: false,
  file: 'Stillroom-1.1.1.zip',
  version: '1.1.1',
  sha256: '3f05fdbb480b65794baa66cf1baafca5d57902b4b4e37cad3251fc8a3479c7a3',
  /** Apple Developer Team ID the app is signed with (codesign -dv shows it as TeamIdentifier). */
  teamId: 'WP56DL33UR',
  requires: 'Apple silicon (M1 or later), macOS 26 or later',
} as const;

export const pricing = {
  freeItems: 25,
  tiers: [
    {
      id: 'free',
      name: 'Free',
      price: '$0',
      cadence: 'forever',
      blurb: 'Every feature, up to 25 files, notes or secrets.',
      points: [
        'Every way in, the decoy, backups and export',
        'Opening, exporting and backing up never stop',
        'Upgrade with a key, nothing to reinstall',
      ],
    },
    {
      id: 'personal',
      name: 'Personal',
      price: '$39',
      cadence: 'one-time, plus tax where applicable',
      blurb: 'Every feature, no limit, on all of one person’s Macs.',
      points: ['Unlimited items', 'All of your own Macs', 'Every 1.x update included'],
      featured: true,
    },
    {
      id: 'family',
      name: 'Family',
      price: '$79',
      cadence: 'one-time, plus tax where applicable',
      blurb: 'Stillroom Vault for up to 5 people.',
      points: ['Five people, each on all their Macs', 'Each person’s vault stays their own', 'Every 1.x update included'],
    },
    {
      id: 'teams',
      name: 'Teams',
      price: 'Upon request',
      cadence: 'per seat',
      blurb: 'For small offices: law, medical, journalism.',
      points: ['Priced per seat, when you ask', 'The same app, the same protection', 'No admin key: nobody can open a colleague’s vault'],
    },
  ],
} as const;

/**
 * Paddle checkout. Empty until the Paddle account exists; while empty, every buy button reads "Coming soon".
 * Set these as Cloudflare Pages environment variables (they're public by design: a client token and price ids).
 */
export const paddle = {
  clientToken: import.meta.env.PUBLIC_PADDLE_CLIENT_TOKEN ?? '',
  environment: (import.meta.env.PUBLIC_PADDLE_ENV ?? 'production') as 'production' | 'sandbox',
  prices: {
    personal: import.meta.env.PUBLIC_PADDLE_PRICE_PERSONAL ?? '',
    family: import.meta.env.PUBLIC_PADDLE_PRICE_FAMILY ?? '',
  } as Record<string, string>,
};

export const paddleWording =
  'Our order process is conducted by our online reseller Paddle.com. Paddle.com is the Merchant of Record for all our orders. Paddle provides all customer service inquiries and handles returns.';

/** A launch to point at from the bar above the header (components/LaunchBar.astro). Dates are the launch site's own
 *  (Pacific time); the bar shows until `until`. */
export const launch = {
  url: 'https://www.producthunt.com/products/stillroom-vault',
  day: '2026-11-08',
  until: '2026-11-15',
  before: 'Launching on Product Hunt, Sunday 8 November',
  live: 'We’re live on Product Hunt today',
} as const;

export const nav = [
  { href: '/features/', label: 'Features' },
  { href: '/security/', label: 'Security' },
  { href: '/format/', label: 'Format' },
  { href: '/pricing/', label: 'Pricing' },
  { href: '/support/', label: 'Support' },
] as const;
