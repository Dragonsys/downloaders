// Props & Beyond - Step 1: collect your library (all products, their download links and pictures)
// Run in the browser Console (F12) on https://propsandbeyond.com while logged in (Chrome or Edge).
// It reads every page of My Library and every product's shop page (for the pictures - about 2
// minutes for 100 products), and saves pb_list.tsv into your Downloads folder. Copy that file next to
// 2_pb_download.sh and run the downloader WITHIN 1 HOUR: the download links expire after an hour
// (the downloader checks, and tells you to collect again when they have).
// Hide unrelated Console "noise" (red errors/warnings from the site's own scripts): click the
// gear icon at the top right of the Console, tick "Hide network" and "Selected context only".
(async () => {
  // ===== SETTINGS =====
  const PAGE_DELAY_MS = 1000;   // pause between page reads
  // ====================

  if (location.hostname !== 'propsandbeyond.com') return 'Open propsandbeyond.com (logged in) first.';
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  // ---- Status panel ----
  document.getElementById('__dl_status_panel')?.remove();
  const panel = document.createElement('div');
  panel.id = '__dl_status_panel';
  panel.style.cssText = 'position:fixed;right:16px;bottom:16px;z-index:2147483647;width:460px;max-width:calc(100vw - 32px);' +
    'max-height:50vh;overflow:auto;background:#141414;color:#e8e8e8;font:12px/1.45 ui-monospace,Consolas,monospace;' +
    'padding:10px 12px;border:1px solid #444;border-radius:8px;box-shadow:0 6px 20px rgba(0,0,0,.45);white-space:pre-wrap;';
  const head = document.createElement('div');
  head.style.cssText = 'font-weight:bold;margin-bottom:6px;';
  head.textContent = 'Props & Beyond collector';
  const body = document.createElement('div');
  panel.append(head, body); document.body.appendChild(panel);
  const show = (msg, color) => { const l = document.createElement('div'); l.textContent = msg; if (color) l.style.color = color;
    body.appendChild(l); while (body.childElementCount > 300) body.firstChild.remove(); panel.scrollTop = panel.scrollHeight; };
  const log = m => { console.log(m); show(m); };
  const warn = m => { console.warn(m); show(m, '#f5c542'); };

  const get = async (url) => {
    for (let attempt = 0; ; attempt++) {
      const r = await fetch(url, { credentials: 'include' });
      if (r.ok) return new DOMParser().parseFromString(await r.text(), 'text/html');
      if ((r.status === 429 || r.status >= 500) && attempt < 4) { warn(`HTTP ${r.status} - waiting`); await sleep(30000 * 2 ** attempt); continue; }
      throw new Error(`HTTP ${r.status} for ${url.split('?')[0]}`);
    }
  };
  const text = el => (el ? el.textContent : '').replace(/\s+/g, ' ').trim();

  // ---- 1. My Library, page by page (?_my-library-pagination=N is rendered on the server) ----
  const products = [];
  let pages = 1;
  for (let page = 1; page <= pages; page++) {
    const d = await get(`/my-library/?_my-library-pagination=${page}`);
    if (page === 1) {
      if (!d.querySelector('a.piotnetgrid-link') && /member-only area/i.test(d.body.textContent)) return 'Not logged in - log in on propsandbeyond.com and run it again.';
      const nums = [...d.querySelectorAll('[data-piotnetgrid-facet-pagination-page-number]')].map(e => +e.getAttribute('data-piotnetgrid-facet-pagination-page-number'));
      pages = Math.max(1, ...nums.filter(n => n > 0));
    }
    for (const a of d.querySelectorAll('a.piotnetgrid-link')) {
      // the product card: the nearest element around the title that also holds its download list
      let card = a; while (card.parentElement && !card.querySelector('a[href*="backblazeb2.com"]')) card = card.parentElement;
      const files = [...card.querySelectorAll('a[href*="backblazeb2.com"]')].map(f => ({ name: text(f), url: f.href,
        key: decodeURIComponent(new URL(f.href).pathname.replace(/^\/[^/]+\//, '')) }));
      products.push({ title: text(a), url: a.getAttribute('href').split('?')[0], files });
    }
    log(`  library page ${page}/${pages}: ${products.length} products so far`);
    await sleep(PAGE_DELAY_MS);
  }
  if (!products.length) return 'No products found in My Library.';

  // ---- 2. What each product is ----
  // A pack (monthly Prop Drop, Welcome Pack) lists its whole-pack zip first, then each prop's zip.
  // A prop that is a product of its own is "covered" when a pack lists its zip too (some packs list
  // props stored elsewhere, e.g. January 2023 has "Horn" from pnp1/), or shares the pack's storage folder.
  const isPack = p => p.files.length > 1;
  const packs = products.filter(isPack);
  const packOfKey = new Map(), packOfFolder = new Map();
  for (const p of packs) { packOfFolder.set(p.files[0].key.split('/')[0], p); p.files.slice(1).forEach(f => packOfKey.set(f.key, p)); }
  const coveringPack = p => packOfKey.get(p.files[0]?.key) || packOfFolder.get(p.files[0]?.key.split('/')[0]) || null;
  const months = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
  const packName = p => {   // "January 2023 Prop Drop – Viking Saga" -> month 01, year 2023, name "Viking Saga"
    const m = p.title.match(/^(\w+)\s+(\d{4})\s+Prop Drop\s*[–-]\s*(.+)$/i);
    if (m && months.includes(m[1].toLowerCase())) return { mm: String(months.indexOf(m[1].toLowerCase()) + 1).padStart(2, '0'), yyyy: m[2], name: m[3].trim() };
    return { mm: '', yyyy: '', name: p.files[0].key.split('/').pop().replace(/\.zip$/i, '') };   // e.g. "Welcome-Pack"
  };
  const propOf = f => f.key.split('/').pop().replace(/\.zip$/i, '');

  // ---- 3. Pictures: the product's own images from its shop page (structured data) ----
  const pictures = async (p) => {
    try {
      const d = await get(p.url);
      for (const s of d.querySelectorAll('script[type="application/ld+json"]')) {
        const j = JSON.parse(s.textContent);
        const prod = (j['@graph'] || [j]).find(x => /Product/.test([].concat(x['@type']).join(' ')));
        if (prod && prod.image) return [].concat(prod.image).map(i => typeof i === 'string' ? i : i.url).filter(Boolean);
      }
    } catch (e) { warn(`  ${p.title}: ${e.message}`); }
    return [];
  };
  let read = 0;
  for (const p of products) {
    p.pics = await pictures(p);
    if (++read % 10 === 0) log(`  read ${read}/${products.length} shop pages (pictures)`);
    await sleep(PAGE_DELAY_MS);
  }
  // Which prop a pack picture shows: a prop's own product page has exactly its zip and its picture
  const propOfPic = new Map();   // pack title + picture path -> prop
  for (const p of products) {
    const pack = !isPack(p) && coveringPack(p);
    if (pack) for (const u of p.pics) propOfPic.set(pack.title + '|' + new URL(u).pathname, propOf(p.files[0]));
  }

  // ---- 4. Rows: one per file and per picture ----
  // columns: kind role pack mm yyyy product prop name key url product_url
  //   kind = file | image; role = pack (whole-pack zip) | packitem (a prop's zip inside a pack)
  //   | single (a product no pack contains) | single-covered (a product a pack contains too)
  //   Pictures: role pack (prop = the prop it shows, empty = the pack's own, e.g. the cover) or single.
  const rows = [];
  const clean = s => String(s || '').replace(/[\t\r\n]+/g, ' ').trim();
  const picRow = (role, pn, p, prop, u) => ['image', role, pn.name, pn.mm, pn.yyyy, p.title, prop,
    decodeURIComponent(u.split('?')[0].split('/').pop()), 'img:' + new URL(u).pathname, u, p.url];
  for (const p of products) {
    const pack = isPack(p), cover = pack ? null : coveringPack(p);
    const pn = pack ? packName(p) : cover ? packName(cover) : { mm: '', yyyy: '', name: '' };
    p.files.forEach((f, i) => {
      const role = pack ? (i === 0 ? 'pack' : 'packitem') : (cover ? 'single-covered' : 'single');
      rows.push(['file', role, pn.name, pn.mm, pn.yyyy, p.title, role === 'pack' ? '' : propOf(f), f.name, f.key, f.url, p.url]);
    });
    if (pack) {
      const seen = new Set(), mine = [];
      for (const u of p.pics) { const path = new URL(u).pathname; seen.add(path); mine.push(picRow('pack', pn, p, propOfPic.get(p.title + '|' + path) || '', u)); }
      // a prop's picture that the pack's own page doesn't show
      for (const q of products) if (!isPack(q) && coveringPack(q) === p)
        for (const u of q.pics) if (!seen.has(new URL(u).pathname)) { seen.add(new URL(u).pathname); mine.push(picRow('pack', pn, p, propOf(q.files[0]), u)); }
      // The same picture is sometimes uploaded twice (other path, same name), or a picture is named
      // like its prop ("Horn.jpg" for the prop "Horn"): those belong to that prop, not to the pack
      const norm = s => String(s).toLowerCase().replace(/\.[a-z0-9]+$/, '').replace(/[^a-z0-9]/g, '');
      const byName = new Map(mine.filter(r => r[6]).map(r => [r[7].toLowerCase(), r[6]]));
      const props = new Map(p.files.slice(1).map(f => [norm(propOf(f)), propOf(f)]));
      const within = n => { const m = [...props].filter(([k]) => k && n.includes(k)); return m.length === 1 ? m[0][1] : ''; };   // "Witches-Cauldron-No-Liquid"
      for (const r of mine) if (!r[6]) r[6] = byName.get(r[7].toLowerCase()) || props.get(norm(r[7])) || within(norm(r[7]));
      rows.push(...mine);
    } else if (!cover) {
      for (const u of p.pics) rows.push(picRow('single', pn, p, propOf(p.files[0]), u));
    }
  }

  // ---- 5. Save pb_list.tsv ----
  const header = ['kind', 'role', 'pack', 'mm', 'yyyy', 'product', 'prop', 'name', 'key', 'url', 'product_url'];
  const tsv = [header, ...rows].map(r => r.map(clean).join('\t')).join('\n') + '\n';
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([tsv], { type: 'text/tab-separated-values' }));
  a.download = 'pb_list.tsv'; document.body.appendChild(a); a.click(); a.remove();
  const singles = products.filter(p => !isPack(p) && !coveringPack(p)).length;
  const msg = `Saved pb_list.tsv: ${products.length} products (${packs.length} packs, ${singles} props in no pack), ` +
    `${rows.filter(r => r[0] === 'file').length} file links, ${rows.filter(r => r[0] === 'image').length} pictures. ` +
    'Run 2_pb_download.sh within 1 hour - the links expire.';
  log(msg);
  return msg;
})();
