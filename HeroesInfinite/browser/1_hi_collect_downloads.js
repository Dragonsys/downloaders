// Heroes Infinite - collect every download link from your library.
// Run in the browser Console (F12) on https://www.heroesinfinite.com/library while logged in.
// It reads all library pages, every collection and every post in the background,
// pausing between pages. Progress is saved in this browser: if it stops, just run it
// again and it continues where it left off. New collections are picked up on later runs.
// Hide unrelated Console "noise" (red errors/warnings from the site's own scripts): click the
// gear icon at the top right of the Console, tick "Hide network" and "Selected context only".
(async () => {
  // ===== SETTINGS =====
  const DELAY_MS     = 1500;   // pause between page loads
  const MAX_PRODUCTS = 0;      // only this many collections this run (0 = all); use 1 for a first test
  const RECHECK      = false;  // true = re-read collections and posts already done (e.g. if files were added)
  // ====================

  if (!location.pathname.startsWith('/library')) return 'Open your library page (heroesinfinite.com/library) first.';
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  // ---- Status panel on the page (you can close DevTools while it runs) ----
  const panelTitle = 'Heroes Infinite collector';
  const statusBox = (() => {
    document.getElementById('__dl_status_panel')?.remove();
    const el = document.createElement('div');
    el.id = '__dl_status_panel';
    el.style.cssText = 'position:fixed;right:16px;bottom:16px;z-index:2147483647;width:440px;max-width:calc(100vw - 32px);' +
      'max-height:45vh;overflow:auto;background:#141414;color:#e8e8e8;font:12px/1.45 ui-monospace,Consolas,monospace;' +
      'padding:10px 12px;border:1px solid #444;border-radius:8px;box-shadow:0 6px 20px rgba(0,0,0,.45);white-space:pre-wrap;';
    const head = document.createElement('div');
    head.style.cssText = 'display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;font-weight:bold;';
    head.textContent = panelTitle;
    const close = document.createElement('span');
    close.textContent = '\u2715'; close.title = 'Close this panel (the script keeps running)';
    close.style.cssText = 'cursor:pointer;padding:0 4px;font-weight:normal;';
    close.onclick = () => el.remove();
    head.appendChild(close);
    const body = document.createElement('div');
    el.append(head, body);
    document.body.appendChild(el);
    return body;
  })();
  const show = (msg, color) => {
    if (!statusBox.isConnected) return;
    const line = document.createElement('div');
    line.textContent = msg;
    if (color) line.style.color = color;
    statusBox.appendChild(line);
    while (statusBox.childElementCount > 300) statusBox.firstChild.remove();
    statusBox.parentElement.scrollTop = statusBox.parentElement.scrollHeight;
  };
  const log  = msg => { console.log(msg);  show(msg); };
  const warn = msg => { console.warn(msg); show(msg, '#f5c542'); };
  const load = k => JSON.parse(localStorage.getItem(k) || '{}');
  const store    = load('hiDownloads');   // download id -> row
  const products = load('hiProducts');    // collection url -> { title, posts: [[url, title], ...] }
  const posts    = load('hiPosts');       // post url -> number of downloads found
  const save = () => {
    try {
      localStorage.setItem('hiDownloads', JSON.stringify(store));
      localStorage.setItem('hiProducts', JSON.stringify(products));
      localStorage.setItem('hiPosts', JSON.stringify(posts));
    } catch (e) { throw new Error('Browser storage is full - export the list now (2_hi_export_list.js); the library is too large for browser storage.'); }
  };
  const clean = s => String(s || '').trim().replace(/\s+/g, ' ');
  const path = href => { try { const u = new URL(href, location.origin); return u.origin === location.origin ? u.pathname.replace(/\/+$/, '') : null; } catch (e) { return null; } };

  let requests = 0, failStreak = 0;
  const get = async rel => {
    if (requests++ > 0) await sleep(DELAY_MS);
    for (let attempt = 0; ; attempt++) {
      let res;
      try { res = await fetch(new URL(rel, location.origin), { credentials: 'same-origin' }); }
      catch (e) { if (attempt < 3) { await sleep(10000 * (attempt + 1)); continue; } throw new Error('network error'); }
      if (/\/login/.test(new URL(res.url).pathname)) throw new Error('LOGIN');
      if ((res.status === 429 || res.status >= 500) && attempt < 4) {
        const ra = parseInt(res.headers.get('Retry-After'), 10);
        const w = Number.isFinite(ra) ? Math.max(ra, 5) : 30 * (attempt + 1);
        warn(`  server busy (HTTP ${res.status}) - waiting ${w}s`); await sleep(w * 1000); continue;
      }
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return new DOMParser().parseFromString(await res.text(), 'text/html');
    }
  };
  const titleOf = doc => clean((doc.querySelector('h1, h2, .panel__title, .post-title')?.textContent) || doc.title);

  let stopped = '';
  try {
    // ---- 1. Library pages -> collections ----
    const found = new Map();
    for (let p = 1; p <= 200; p++) {
      const doc = await get('/library?page=' + p);
      let added = 0;
      doc.querySelectorAll('a[href]').forEach(a => {
        const pth = path(a.getAttribute('href'));
        if (!pth || !/^\/products\/[^/]+$/.test(pth)) return;
        const t = clean(a.textContent);
        if (!found.has(pth)) { found.set(pth, t); added++; }
        else if (t.length > (found.get(pth) || '').length) found.set(pth, t);
      });
      log(`Library page ${p}: ${added} new collection(s)`);
      if (!added) break;
    }
    let list = [...found.keys()];
    log(`Found ${list.length} collection(s) in your library.`);
    if (MAX_PRODUCTS > 0) list = list.slice(0, MAX_PRODUCTS);

    // ---- 2. Collections -> posts ----
    for (const [i, pu] of list.entries()) {
      if (products[pu] && !RECHECK) continue;
      const doc = await get(pu);
      const postList = new Map();
      doc.querySelectorAll('a[href]').forEach(a => {
        const pth = path(a.getAttribute('href'));
        if (pth && pth.startsWith(pu + '/categories/') && /\/posts\/\d+$/.test(pth)) {
          const t = clean(a.textContent);
          if (!postList.has(pth) || t.length > postList.get(pth).length) postList.set(pth, t);
        }
      });
      products[pu] = { title: titleOf(doc) || found.get(pu) || pu.split('/').pop(), posts: [...postList] };
      save();
      log(`[collection ${i + 1}/${list.length}] ${products[pu].title}: ${postList.size} post(s)`);
    }

    // ---- 3. Posts -> downloads ----
    const todo = [];
    list.forEach(pu => (products[pu]?.posts || []).forEach(([post]) => { if (RECHECK || posts[post] === undefined) todo.push([pu, post]); }));
    log(`${todo.length} post(s) to read - about ${Math.ceil(todo.length * (DELAY_MS + 700) / 60000)} minute(s). Progress is shown in the panel at the bottom right. Keep this tab open (DevTools can be closed).`);

    for (const [i, [pu, post]] of todo.entries()) {
      let doc;
      try { doc = await get(post); failStreak = 0; }
      catch (e) {
        if (e.message === 'LOGIN') throw e;
        warn(`  could not read ${post}: ${e.message}`);
        if (++failStreak >= 3) throw new Error('3 pages in a row failed');
        continue;
      }
      const postTitle = titleOf(doc);
      let n = 0;
      doc.querySelectorAll('a[href*="/courses/downloads/"]').forEach(a => {
        const u = new URL(a.getAttribute('href'), location.origin);
        const m = u.pathname.match(/\/courses\/downloads\/(\d+)(?:\/([^/]+))?/);
        if (!m) return;
        n++;
        store[m[1]] = { collection: products[pu].title, post: postTitle, label: clean(a.textContent), name: decodeURIComponent(m[2] || ''),
                        id: m[1], url: u.origin + u.pathname, post_url: location.origin + post };
      });
      posts[post] = n;
      save();
      log(`[post ${i + 1}/${todo.length}] ${products[pu].title} - ${postTitle}: ${n} download(s)`);
    }
  } catch (e) {
    stopped = e.message === 'LOGIN' ? 'redirected to the login page - log in again and rerun' : e.message;
  }

  const total = Object.keys(store).length;
  const summary = [
    `Collections read: ${Object.keys(products).length}`,
    `Posts read:       ${Object.keys(posts).length} (${Object.values(posts).filter(n => n > 0).length} with downloads)`,
    `Download links saved: ${total}`,
    stopped ? `STOPPED EARLY: ${stopped} (run it again to continue)` : 'Finished. Export the list with 2_hi_export_list.js'
  ].join('\n');
  log('DONE\n' + summary); show('Finished - you can close this panel.', '#7ddc7d');
  return summary;
})()
