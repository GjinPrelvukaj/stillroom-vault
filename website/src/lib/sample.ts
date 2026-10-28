import type { IconName } from './icons';

// Made-up contents for the app illustrations. Nobody's real files.
export interface Row {
  icon: IconName;
  name: string;
  kind: string;
  size?: string;
  date: string;
  tag?: { name: string; color: string };
  folder?: boolean;
  items?: number;
}

export const tagColors = {
  blue: '#60A5FA',
  pink: '#F472B6',
  green: '#34D399',
  amber: '#FBBF24',
  violet: '#B08CFF',
} as const;

export const vaultRows: Row[] = [
  { icon: 'folder', name: 'Taxes', kind: '', date: '', folder: true, items: 14 },
  { icon: 'doc', name: 'Lease agreement, signed.pdf', kind: 'PDF document', size: '1.8 MB', date: '24 Oct 2026', tag: { name: 'home', color: tagColors.green } },
  { icon: 'key', name: 'Bank login', kind: 'Secret', date: '23 Oct 2026' },
  { icon: 'photo', name: 'Passport photo page.heic', kind: 'HEIC image', size: '3.1 MB', date: '21 Oct 2026', tag: { name: 'travel', color: tagColors.blue } },
  { icon: 'note', name: 'Things to tell the lawyer', kind: 'Note', date: '19 Oct 2026' },
  { icon: 'play', name: 'Grandma’s 90th.mov', kind: 'QuickTime movie', size: '842 MB', date: '12 Oct 2026', tag: { name: 'family', color: tagColors.pink } },
  { icon: 'key', name: 'Home Wi-Fi', kind: 'Secret', date: '2 Oct 2026' },
];

/** What drifts into the hero's vault, one after another. */
export const incoming: Row[] = [
  { icon: 'doc', name: 'Will, final draft.pdf', kind: 'PDF document', size: '412 KB', date: '26 Oct 2026' },
  { icon: 'photo', name: 'Insurance card.jpg', kind: 'JPEG image', size: '1.2 MB', date: '26 Oct 2026' },
  { icon: 'key', name: 'GitHub', kind: 'Secret', date: '26 Oct 2026' },
  { icon: 'note', name: 'Recovery codes', kind: 'Note', date: '26 Oct 2026' },
  { icon: 'doc', name: 'Medical results 2026.pdf', kind: 'PDF document', size: '2.4 MB', date: '26 Oct 2026' },
  { icon: 'waveform', name: 'Voice memo from Dad.m4a', kind: 'MPEG-4 audio', size: '6.8 MB', date: '26 Oct 2026' },
];
