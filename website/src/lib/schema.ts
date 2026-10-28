// Structured data (JSON-LD) for search engines. Only facts: no ratings or reviews until real ones exist.
import { download, site } from '../config';

export function softwareJsonLd() {
  const offer = (name: string, price: string, description: string) => ({
    '@type': 'Offer',
    name,
    price,
    priceCurrency: 'USD',
    description,
    url: `${site.url}/pricing/`,
    availability: 'https://schema.org/InStock',
    seller: { '@type': 'Person', name: site.seller },
  });
  return {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    '@id': `${site.url}/#app`,
    name: 'Stillroom Vault',
    alternateName: 'Stillroom',
    description:
      'An encrypted vault for Mac that never goes online: files, notes, passwords and two-factor codes sealed with AES-256-GCM, with no server, no account and no sync.',
    applicationCategory: 'SecurityApplication',
    operatingSystem: 'macOS 26 or later',
    processorRequirements: 'Apple silicon',
    softwareRequirements: download.requires,
    url: site.url,
    downloadUrl: `${site.url}/download/`,
    image: `${site.url}/icon-512.png`,
    publisher: { '@id': `${site.url}/#maker` },
    author: site.owners.map((name) => ({ '@type': 'Person', name })),
    offers: [
      offer('Free', '0', 'Every feature, up to 25 items.'),
      offer('Stillroom Vault', '39', 'Every feature, unlimited, on all of one person’s Macs, with all 1.x updates. One-time.'),
      offer('Family', '129', 'Stillroom Vault for up to 5 people. One-time.'),
    ],
  };
}

export function breadcrumbJsonLd(trail: [string, string][]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: [['Home', '/'] as [string, string], ...trail].map(([name, path], i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name,
      item: new URL(path, site.url).href,
    })),
  };
}
