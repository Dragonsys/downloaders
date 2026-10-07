// Cults3D - collect your purchases and download them (as normal browser downloads).
// Run in the browser Console (F12) on https://cults3d.com while logged in (Chrome or Edge).
// It reads all your orders (cults3d.com/en/orders), and for every model:
//   - its title, creator, licence, description, picture links and file list, saved together as
//     cults_list.json (into your Downloads folder) for 2_cults_sort_downloads.ps1;
//   - clicks its "Download all" (or each file's "Download" when there is no "Download all"),
//     one at a time, so the browser saves the files into your Downloads folder.
// Then run windows/2_cults_sort_downloads.ps1: it recognises each download by its contents,
// unpacks it into <creator>/<model>/files/, fetches the pictures and writes description.html.
// The first time, the browser may ask whether cults3d.com may download multiple files - allow it.
// Models already sorted (cults_done.js from the Windows script, pasted once) and models clicked
// on an earlier run are not downloaded again (RECLICK = true clicks them again).
// Hide unrelated Console "noise" (red errors/warnings from the site's own scripts): click the
// gear icon at the top right of the Console, tick "Hide network" and "Selected context only".
(async () => {
  // ===== SETTINGS =====
  const DOWNLOAD      = true;    // false = only collect and save cults_list.json
  const DELAY_MS      = 20000;   // pause between downloads (big files need longer - the next one
                                 // only starts after this pause, not after the previous finished)
  const PAGE_DELAY_MS = 1000;    // pause between page reads
  const MAX_DOWNLOADS = 0;       // stop after this many models this run (0 = all); 1 for a first test
  const RECLICK       = false;   // true = also click models clicked on an earlier run
  // ====================

  if (location.hostname !== 'cults3d.com') return 'Open cults3d.com (logged in) first.';
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  // ---- Status panel ----
  document.getElementById('__dl_status_panel')?.remove();
  const panel = document.createElement('div');
  panel.id = '__dl_status_panel';
  panel.style.cssText = 'position:fixed;right:16px;bottom:16px;z-index:2147483647;width:460px;max-width:calc(100vw - 32px);' +
    'max-height:50vh;overflow:auto;background:#141414;color:#e8e8e8;font:12px/1.45 ui-monospace,Consolas,monospace;' +
    'padding:10px 12px;border:1px solid #444;border-radius:8px;box-shadow:0 6px 20px rgba(0,0,0,.45);white-space:pre-wrap;';
  const head = document.createElement('div');
  head.style.cssText = 'display:flex;justify-content:space-between;margin-bottom:6px;font-weight:bold;';
  head.textContent = 'Cults3D downloader';
  const stopBtn = document.createElement('span');
  stopBtn.textContent = 'Stop'; stopBtn.style.cssText = 'cursor:pointer;color:#ff9b9b;font-weight:normal;';
  head.appendChild(stopBtn);
  const body = document.createElement('div');
  panel.append(head, body); document.body.appendChild(panel);
  const show = (msg, color) => { const l = document.createElement('div'); l.textContent = msg; if (color) l.style.color = color;
    body.appendChild(l); while (body.childElementCount > 300) body.firstChild.remove(); panel.scrollTop = panel.scrollHeight; };
  const log = m => { console.log(m); show(m); };
  const warn = m => { console.warn(m); show(m, '#f5c542'); };
  let stop = false;
  stopBtn.onclick = () => { stop = true; warn('Stopping ...'); };

  const get = async (url) => {
    for (let attempt = 0; ; attempt++) {
      const r = await fetch(url, { credentials: 'include' });
      if (r.ok) return new DOMParser().parseFromString(await r.text(), 'text/html');
      if ((r.status === 429 || r.status >= 500) && attempt < 4) { warn(`HTTP ${r.status} - waiting`); await sleep(30000 * 2 ** attempt); continue; }
      throw new Error(`HTTP ${r.status} for ${url.split('?')[0]}`);
    }
  };
  const text = el => (el ? el.textContent : '').replace(/\s+/g, ' ').trim();
  const SIZE_RE = /^(.*\S)\s+([\d.,]+\s*(?:B|KB|MB|GB|TB))$/i;

  // ---- 1. all orders ----
  const orders = [];
  for (let page = 1; page <= 200 && !stop; page++) {
    let d;
    // a page past the last one answers HTTP 406 instead of an empty page
    try { d = await get(`/en/orders?page=${page}`); } catch (e) { if (page > 1) break; throw e; }
    const ids = [...new Set([...d.querySelectorAll('a[href]')].map(a => (a.getAttribute('href').match(/^\/en\/orders\/(\d+)$/) || [])[1]).filter(Boolean))];
    const fresh = ids.filter(i => !orders.includes(i));
    if (!fresh.length) break;
    orders.push(...fresh);
    await sleep(PAGE_DELAY_MS);
  }
  log(`${orders.length} orders`);

  // ---- 2. every model in every order ----
  const models = [];
  for (const [n, o] of orders.entries()) {
    if (stop) break;
    const d = await get(`/en/orders/${o}`);
    const main = d.querySelector('main') || d.body;
    // one block per model: the biggest part of the page around its download links that has no
    // other model's links in it (a bundle order lists several models in one frame)
    const creationOf = a => new URL(a.getAttribute('href'), location.origin).searchParams.get('creation') || '';
    const blocks = new Map();
    for (const a of main.querySelectorAll('a[href*="/downloads/"]')) {
      const c = creationOf(a);
      if (blocks.has(c)) continue;
      let b = a;
      while (b.parentElement && b.parentElement !== main &&
             [...b.parentElement.querySelectorAll('a[href*="/downloads/"]')].every(x => creationOf(x) === c)) b = b.parentElement;
      blocks.set(c, b);
    }
    for (const [creation, b] of blocks) {
      const titleA = [...b.querySelectorAll('a[href*="/3d-model/"]')].find(a => text(a));
      const t = text(b);
      const files = [], downloads = [];
      for (const row of b.querySelectorAll('.grid--vertically_aligned')) {
        const cells = [...row.children].map(text).filter(Boolean);
        const last = cells[cells.length - 1] || '';
        const m = last.match(SIZE_RE);
        const a = row.querySelector('a[href*="/downloads/"]');
        if (a && /download all/i.test(text(a))) {
          const s = text(row).match(/([\d.,]+\s*(?:B|KB|MB|GB|TB))$/i);
          downloads.unshift({ kind: 'all', href: new URL(a.getAttribute('href'), location.origin).href, size: s ? s[1] : '' }); continue;
        }
        if (!m) continue;
        files.push({ name: m[1], size: m[2] });
        if (a) downloads.push({ kind: 'file', name: m[1], href: new URL(a.getAttribute('href'), location.origin).href, size: m[2] });
      }
      models.push({ key: `${o}-${creation}`, order: o, creation, title: text(titleA) || `Order ${o}`,
        url: titleA ? new URL(titleA.getAttribute('href').split('?')[0], location.origin).href : '',
        creator: (t.match(/design sold by\s+(.+?)\s+(?:Unfollow|Follow|Contact|Download|License)/i) || [])[1] || '',
        license: (t.match(/License:\s*(.+?)\s+(?:design sold by|Download)/i) || [])[1] || '',
        files, downloads: downloads.some(x => x.kind === 'all') ? downloads.filter(x => x.kind === 'all') : downloads });
    }
    if ((n + 1) % 10 === 0) log(`  read ${n + 1}/${orders.length} orders`);
    await sleep(PAGE_DELAY_MS);
  }
  log(`${models.length} models`);

  // ---- 3. description and pictures from each model's page ----
  for (const [n, m] of models.entries()) {
    if (stop || !m.url) continue;
    try {
      const r0 = await fetch(m.url, { credentials: 'include', method: 'HEAD' });
      if (r0.status === 410 || r0.status === 404) { m.gone = true; await sleep(PAGE_DELAY_MS); continue; }   // the creator removed the page; the files are still in your order
      const d = await get(m.url);
      m.title = text(d.querySelector('h1')) || m.title;
      const rich = d.querySelector('div.rich');
      m.description = rich ? rich.innerHTML : '';
      try { const j = JSON.parse(d.querySelector('script[type="application/ld+json"]').textContent); const x = Array.isArray(j) ? j[0] : j;
        if (!m.creator && x.creator) m.creator = x.creator.name || ''; if (x.license) { m.licenseUrl = x.license; if (!m.license) m.license = x.license; } } catch (e) {}
      // the original pictures (fbi.cults3d.com), not the resized copies
      const pics = new Set();
      for (const e of d.querySelectorAll('img, source, a, meta[property="og:image"]'))
        for (const u of [e.getAttribute('src'), e.getAttribute('href'), e.getAttribute('content'), ...(e.getAttribute('srcset') || '').split(',').map(s => s.trim().split(' ')[0])])
          if (u && u.includes('https://fbi.cults3d.com/uploaders/') && /illustration-file/.test(u)) pics.add(u.slice(u.indexOf('https://fbi.cults3d.com')));
      m.pictures = [...pics];
    } catch (e) { warn(`  ${m.title}: ${e.message}`); }
    if ((n + 1) % 10 === 0) log(`  read ${n + 1}/${models.length} model pages`);
    await sleep(PAGE_DELAY_MS);
  }

  // ---- 4. save the list (into your Downloads folder) ----
  const list = { saved: new Date().toISOString(), models };
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([JSON.stringify(list, null, 1)], { type: 'application/json' }));
  a.download = 'cults_list.json'; document.body.appendChild(a); a.click(); a.remove();
  log('Saved cults_list.json to your Downloads folder.');

  // ---- 5. download (one model at a time) ----
  if (!DOWNLOAD) return `Collected ${models.length} models; DOWNLOAD is false, nothing downloaded.`;
  let done = []; try { done = JSON.parse(localStorage.getItem('cultsDone') || '[]'); } catch (e) {}
  const clicked = JSON.parse(localStorage.getItem('cultsClicked') || '{}');
  let count = 0, skippedDone = 0, skippedClicked = 0;
  for (const m of models) {
    if (stop) break;
    if (done.includes(m.key)) { skippedDone++; continue; }
    if (clicked[m.key] && !RECLICK) { skippedClicked++; continue; }
    if (!m.downloads.length) { warn(`  ${m.title}: no download link`); continue; }
    if (MAX_DOWNLOADS && count >= MAX_DOWNLOADS) { log(`Reached MAX_DOWNLOADS (${MAX_DOWNLOADS}).`); break; }
    count++;
    log(`  ↓ [${count}] ${m.title} (${m.downloads.map(x => x.size).filter(Boolean).join(' + ') || '?'})`);
    for (const dl of m.downloads) {
      // Opened in a hidden frame: a working download is saved to Downloads as usual, and when
      // Cults3D's file server fails (e.g. ERR_INVALID_RESPONSE) only the hidden frame shows the
      // error - with a plain link click the whole page (and this script) would be replaced by it.
      const f = document.createElement('iframe');
      f.style.display = 'none'; f.src = dl.href;
      document.body.appendChild(f);
      setTimeout(() => f.remove(), 10 * 60000);   // removing it earlier could cancel a slow download
      await sleep(dl === m.downloads[m.downloads.length - 1] ? DELAY_MS : 5000);
    }
    clicked[m.key] = Date.now();
    localStorage.setItem('cultsClicked', JSON.stringify(clicked));
  }
  const msg = `Done: ${models.length} models, ${count} downloads started` +
    (skippedDone ? `, ${skippedDone} already sorted` : '') + (skippedClicked ? `, ${skippedClicked} clicked on an earlier run (RECLICK = true to click them again)` : '') +
    '. When the browser has finished downloading, run 2_cults_sort_downloads.ps1.';
  log(msg);
  return msg;
})();
