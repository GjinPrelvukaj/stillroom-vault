// The site search (components/Search.astro, after Skiper UI's command search, 92). Opens from the header's button, "/"
// or ⌘K (Ctrl+K); fetches /search.json from this site once, then filters it as you type: every word must appear in a
// page's name, line or section, or in one of its headings. Results are grouped by section; arrows move, Enter goes,
// Esc closes (the <dialog>'s own). The list's height is set here so it changes on the CSS spring.
interface Entry {
  t: string;
  u: string;
  g: string;
  d: string;
  h?: [string, string][];
}
interface Hit {
  title: string;
  sub: string;
  url: string;
  group: string;
  score: number;
}

const dialog = document.querySelector<HTMLDialogElement>('[data-search]');
const openButton = document.querySelector<HTMLButtonElement>('[data-search-open]');

if (dialog && openButton) {
  const input = dialog.querySelector<HTMLInputElement>('[data-search-input]')!;
  const wrap = dialog.querySelector<HTMLElement>('[data-search-wrap]')!;
  const list = dialog.querySelector<HTMLElement>('[data-search-results]')!;
  const status = dialog.querySelector<HTMLElement>('[data-search-status]')!;
  let index: Entry[] | null = null;
  let loading: Promise<void> | null = null;
  let options: HTMLAnchorElement[] = [];
  let active = 0;

  openButton.hidden = false;

  const load = () =>
    (loading ??= fetch('/search.json')
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((data: Entry[]) => {
        index = data;
      })
      .catch(() => {
        index = [];
        loading = null; // try again on the next open
      }));

  const search = (query: string): Hit[] => {
    if (!index) return [];
    const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
    if (!terms.length) return index.filter((e) => e.g === 'Pages').map((e, i) => ({ title: e.t, sub: '', url: e.u, group: e.g, score: i }));
    const all = (text: string) => terms.every((w) => text.includes(w));
    const hits: Hit[] = [];
    for (const e of index) {
      const name = e.t.toLowerCase();
      if (all(`${name} ${e.d} ${e.g}`.toLowerCase())) {
        hits.push({ title: e.t, sub: '', url: e.u, group: e.g, score: name.startsWith(terms[0]!) ? 0 : all(name) ? 1 : 3 });
      }
      // ponytail: at most two headings a page, so one long document can't fill the list.
      let shown = 0;
      for (const [text, slug] of e.h ?? []) {
        const h = text.toLowerCase();
        if (shown < 2 && terms.some((w) => h.includes(w)) && all(`${h} ${name}`)) {
          hits.push({ title: text, sub: e.t, url: `${e.u}#${slug}`, group: e.g, score: 2 });
          shown++;
        }
      }
    }
    // The group holding the best hit comes first (ties keep the index's order: pages, sections, questions, legal);
    // best first inside each.
    const order = [...new Set(index.map((e) => e.g))];
    const best = new Map<string, number>();
    for (const h of hits) best.set(h.group, Math.min(best.get(h.group) ?? 9, h.score));
    const rank = (g: string) => best.get(g)! * 100 + order.indexOf(g);
    return hits.sort((a, b) => rank(a.group) - rank(b.group) || a.score - b.score).slice(0, 40);
  };

  /** The title with the typed words in violet, built as text nodes (never as HTML). */
  const marked = (text: string, terms: string[]) => {
    const frag = document.createDocumentFragment();
    const re = terms.length ? new RegExp(`(${terms.map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')})`, 'gi') : null;
    (re ? text.split(re) : [text]).forEach((part, i) => {
      if (i % 2) {
        const m = document.createElement('mark');
        m.textContent = part;
        frag.append(m);
      } else if (part) frag.append(part);
    });
    return frag;
  };

  const select = (i: number, scroll = true) => {
    options[active]?.setAttribute('aria-selected', 'false');
    active = Math.max(0, Math.min(i, options.length - 1));
    const el = options[active];
    if (!el) {
      input.removeAttribute('aria-activedescendant');
      return;
    }
    el.setAttribute('aria-selected', 'true');
    input.setAttribute('aria-activedescendant', el.id);
    if (scroll) el.scrollIntoView({ block: 'nearest' });
  };

  const render = () => {
    const query = input.value.trim();
    const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
    const hits = search(query);
    list.replaceChildren();
    options = [];
    let group = '';
    let box: HTMLElement = list;
    hits.forEach((hit, n) => {
      if (hit.group !== group) {
        group = hit.group;
        box = document.createElement('div');
        box.setAttribute('role', 'group');
        const title = document.createElement('p');
        title.className = 'group-title';
        title.id = `search-g-${n}`;
        title.textContent = group;
        box.setAttribute('aria-labelledby', title.id);
        box.append(title);
        list.append(box);
      }
      const a = document.createElement('a');
      a.href = hit.url;
      a.id = `search-o-${n}`;
      a.setAttribute('role', 'option');
      a.setAttribute('aria-selected', 'false');
      a.tabIndex = -1;
      const t = document.createElement('span');
      t.className = 't';
      t.append(marked(hit.title, terms));
      if (hit.sub) {
        const s = document.createElement('small');
        s.textContent = ` in ${hit.sub}`;
        t.append(s);
      }
      a.append(t);
      box.append(a);
      options.push(a);
    });
    if (!hits.length) {
      const p = document.createElement('p');
      p.className = 'empty';
      p.textContent = index?.length ? `Nothing found for “${query}”.` : 'Search couldn’t load. Every page is in the menu.';
      list.append(p);
    }
    status.textContent = query ? `${hits.length} ${hits.length === 1 ? 'result' : 'results'}` : '';
    active = 0;
    select(0, false);
    list.scrollTop = 0;
    wrap.style.height = `${list.offsetHeight}px`;
  };

  const open = () => {
    if (dialog.open) return;
    dialog.showModal();
    input.select();
    render();
    void load().then(() => {
      if (dialog.open) render();
    });
  };

  openButton.addEventListener('click', open);
  document.addEventListener('keydown', (e) => {
    const t = e.target as HTMLElement;
    const typing = t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName);
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      if (dialog.open) dialog.close();
      else open();
    } else if (e.key === '/' && !typing && !e.metaKey && !e.ctrlKey && !e.altKey) {
      e.preventDefault();
      open();
    }
  });
  input.addEventListener('input', render);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      select(active + (e.key === 'ArrowDown' ? 1 : -1));
    } else if (e.key === 'Enter' && options[active]) {
      e.preventDefault();
      options[active]?.click();
    }
  });
  list.addEventListener('mousemove', (e) => {
    const a = (e.target as Element).closest<HTMLAnchorElement>('a[role="option"]');
    if (a && a !== options[active]) select(options.indexOf(a), false);
  });
  // A result closes the search as it goes (a link to this same page only scrolls, so it must close here).
  list.addEventListener('click', (e) => {
    if ((e.target as Element).closest('a')) dialog.close();
  });
  // A click on the dim backdrop (the dialog itself, outside its content) closes it.
  dialog.addEventListener('click', (e) => {
    if (e.target === dialog) dialog.close();
  });
}
