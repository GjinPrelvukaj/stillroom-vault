// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://stillroomvault.com',
  trailingSlash: 'always',
  // Astro's compression drops the space before an inline link that starts a new source line ("as<a>the format</a>").
  // Cloudflare compresses responses anyway.
  compressHTML: false,
  build: {
    format: 'directory',
    // Every stylesheet is a file: the Content-Security-Policy allows no inline styles.
    inlineStylesheets: 'never',
  },
  // No prefetching or client router: pages change with the browser's own view transitions, and nothing is fetched
  // that you didn't ask for.
  prefetch: false,
  devToolbar: { enabled: false },
  markdown: {
    // Prism marks code with classes; Shiki would write inline styles, which the CSP refuses.
    syntaxHighlight: 'prism',
  },
  integrations: [
    sitemap({
      filter: (page) => !page.includes('/404') && !page.includes('/checkout/'),
    }),
  ],
  vite: {
    build: {
      // Named browsers for the CSS minifier: without them it folds animation-timeline into the animation shorthand,
      // which browsers reject, and every scroll-driven animation silently stops.
      cssTarget: ['chrome120', 'safari17', 'firefox120', 'edge120'],
      // Keep small scripts as files too (script-src 'self', no inline scripts).
      assetsInlineLimit: 0,
    },
  },
});
