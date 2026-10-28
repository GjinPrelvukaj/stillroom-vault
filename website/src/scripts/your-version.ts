// The app's Check for Updates opens /changelog/?v=1.0.0 in the browser (the app itself never connects). This reads
// that version, compares it with /releases.json (from this site) and says at the top of the changelog whether a newer
// one is out, and whether any newer one fixes a security problem. Without ?v= it does nothing.
import { compareVersions } from '../lib/versions.ts';

interface Release {
  version: string;
  date: string;
  security: boolean;
  slug: string;
}

const yours = new URLSearchParams(location.search).get('v') ?? '';
const prose = document.querySelector<HTMLElement>('.prose');

if (/^\d+\.\d+\.\d+$/.test(yours) && prose) {
  fetch('/releases.json')
    .then((r) => r.json() as Promise<Release[]>)
    .then((all) => {
      const newer = all.filter((r) => compareVersions(r.version, yours) > 0);
      const latest = all[0];
      const note = document.createElement('div');
      note.className = 'your-version';
      note.setAttribute('role', 'status');
      const line = (strong: string, rest: string) => {
        const p = document.createElement('p');
        const b = document.createElement('strong');
        b.textContent = strong;
        p.append(b, ` ${rest}`);
        return p;
      };
      if (newer.length && latest) {
        const security = newer.some((r) => r.security);
        note.classList.toggle('urgent', security);
        note.append(
          line(`Stillroom Vault ${latest.version} is out.`, `You have ${yours}.${security ? ' A newer version fixes a security problem: please update soon.' : ''}`),
        );
        const p = document.createElement('p');
        const a = document.createElement('a');
        a.className = 'btn primary';
        a.href = '/download/';
        a.textContent = `Download ${latest.version}`;
        const how = document.createElement('span');
        how.textContent = 'Drag it over the old copy in Applications. Your vault, licence and settings stay as they are.';
        p.append(a, how);
        note.append(p);
      } else {
        note.append(line('You’re up to date.', `You have ${yours}${latest && compareVersions(yours, latest.version) === 0 ? ', the newest version' : ''}.`));
      }
      prose.prepend(note);
    })
    .catch(() => {});
}
