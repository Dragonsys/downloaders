// Loot Studios - collect "All Bundle" download links from all your bundles.
// Run in the browser Console (F12) on a My Loots listing page, logged in.
// Scroll to the bottom first so every bundle on the page is loaded.
// Each bundle page is opened in a hidden frame so the site's own code builds
// the download list, exactly as when you visit it. Progress is saved:
// rerun it on each listing page (Fantasy, Sci-Fi, ...).
(async () => {
  // ===== SETTINGS =====
  const MATERIALS   = [];         // e.g. ['resin'] or ['resin', 'fdm']; empty = all materials
  const DELAY_MS    = 4000;       // pause between bundle pages
  const TIMEOUT_MS  = 45000;      // give up on a page after this long
  const MAX_PAGES   = 0;          // stop after this many pages this run (0 = no limit)
  const RESCAN      = false;      // true = read every bundle again (normally not needed: bundles
                                  // whose saved links expire within 10 minutes are re-read anyway)
  const BUNDLE_PATH = '/bundle/'; // only follow links whose path starts with this
  // ====================

  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const allBundleRows = (groups, bundle, page) => {
    const group = groups.find(g => /all\s*bundle/i.test(g.title || ''));
    if (!group) return [];
    const item = (group.items || []).find(i => /all\s*bundle/i.test(i.title || '')) || (group.items || [])[0];
    if (!item || !Array.isArray(item.links)) return [];
    return item.links
      .filter(l => typeof l.all === 'string' && /^https?:\/\//.test(l.all))
      .filter(l => !MATERIALS.length || MATERIALS.includes(String(l.material || '').toLowerCase()))
      .map(l => {
        const u = new URL(l.all);
        return { bundle, folder: decodeURIComponent(u.pathname.split('/').filter(Boolean)[0] || ''),
                 scale: l.scale || '', material: l.material || '',
                 file: decodeURIComponent(u.pathname.split('/').pop()), url: l.all, page };
      });
  };
  const load = k => JSON.parse(localStorage.getItem(k) || '{}');
  // Links expire, so each file is stored once (by bundle page + scale + material + file name)
  // and a newer link always replaces an older one. Older saved lists are converted here.
  const tsOf  = u => +(((u || '').match(/[?&]v=(\d{9,})-/) || [])[1] || 0);
  const keyOf = r => [r.page, r.scale, r.material, r.file].join('|');
  const store = {};
  Object.values(load('lootAllBundles')).forEach(r => { const k = keyOf(r); if (!store[k] || tsOf(r.url) >= tsOf(store[k].url)) store[k] = r; });
  const done  = load('lootBundlePages');
  const save  = () => { localStorage.setItem('lootAllBundles', JSON.stringify(store)); localStorage.setItem('lootBundlePages', JSON.stringify(done)); };

  // Open a page in a hidden frame and wait until the site has built allGroups
  const readBundle = url => new Promise(resolve => {
    const f = document.createElement('iframe');
    f.style.cssText = 'position:fixed;left:-3000px;top:0;width:1280px;height:900px;visibility:hidden;border:0;';
    f.setAttribute('aria-hidden', 'true');
    const start = Date.now();
    let finished = false;
    const finish = result => {
      if (finished) return; finished = true;
      clearInterval(timer);
      try { f.src = 'about:blank'; } catch (e) {}
      setTimeout(() => f.remove(), 500);
      resolve(result);
    };
    const timer = setInterval(() => {
      let w;
      try {
        w = f.contentWindow;
        const path = w.location.pathname;   // throws if the frame was blocked or left the site
        if (/wp-login|\/login/i.test(path)) return finish({ error: 'login' });
        const g = w.allGroups;
        if (Array.isArray(g) && g.length && g.some(x => x && (x.links || x.items))) {
          const groups = JSON.parse(JSON.stringify(g));
          const d = w.document;
          const name = (d.querySelector('h1')?.textContent || d.title || url).trim().replace(/\s+/g, ' ');
          return finish({ groups, name });
        }
      } catch (e) {
        if (Date.now() - start > 5000) return finish({ error: 'blocked' });
      }
      if (Date.now() - start > TIMEOUT_MS) finish({ error: 'timeout' });
    }, 300);
    f.src = url;
    document.body.appendChild(f);
  });

  // --- Find bundle links on this page ---
  let candidates = [...new Set([...document.querySelectorAll('a[href]')]
    .map(a => { try { const u = new URL(a.href, location.href); return u.origin === location.origin && u.pathname.startsWith(BUNDLE_PATH) ? u.origin + u.pathname : null; } catch (e) { return null; } })
    .filter(Boolean))];
  const total = candidates.length;
  // Skip a bundle only if it was read before AND its saved links are still fresh
  const nowSec = Date.now() / 1000;
  const linksFresh = u => {
    const t = Object.values(store).filter(r => r.page === u).map(r => tsOf(r.url));
    return t.length > 0 && Math.min(...t) > nowSec + 600;
  };
  const needsReading = u => !done[u] || (done[u] === 'ok' && !linksFresh(u));
  if (!RESCAN) candidates = candidates.filter(needsReading);
  if (MAX_PAGES > 0) candidates = candidates.slice(0, MAX_PAGES);

  console.log(`Found ${total} bundle link(s) under ${BUNDLE_PATH}; ${candidates.length} to read now.`);
  if (!candidates.length) { console.log('Nothing to do - every bundle on this page has fresh links. Export the list and start the downloader.'); return; }
  console.log(`This will take roughly ${Math.ceil(candidates.length * (DELAY_MS + 8000) / 60000)} minute(s). Progress is shown below; keep this tab open.`);

  let ok = 0, noAll = 0, failed = 0, failStreak = 0, files = 0, stopped = '';
  const noAllList = [], failedList = [];

  for (let i = 0; i < candidates.length; i++) {
    const url = candidates[i];
    if (i > 0) await sleep(DELAY_MS);
    const tag = `[${i + 1}/${candidates.length}]`;
    const r = await readBundle(url);

    if (r.error === 'login')   { stopped = 'redirected to the login page - log in again and rerun'; break; }
    if (r.error === 'blocked') { stopped = 'the site no longer allows its pages to be opened in a frame - the collector needs updating'; break; }
    if (r.error) {
      console.warn(`${tag} no bundle data after ${TIMEOUT_MS / 1000}s: ${url}`);
      failed++; failedList.push(url);
      if (++failStreak >= 3) { stopped = '3 pages in a row had no bundle data'; break; }
      continue;
    }
    failStreak = 0;

    const rows = allBundleRows(r.groups, r.name, url);
    if (!rows.length) {
      done[url] = 'no All Bundle'; noAll++; noAllList.push(r.name); save();
      console.log(`${tag} ${r.name}: no All Bundle downloads`);
      continue;
    }
    rows.forEach(x => { store[keyOf(x)] = x; });
    done[url] = 'ok'; ok++; files += rows.length; save();
    console.log(`${tag} ${r.name}: ${rows.map(x => `${x.scale} ${x.material}`.trim()).join(', ')}`);
  }

  const summary = [
    `Bundles with All Bundle files: ${ok} (${files} files)`,
    `Bundles without All Bundle:    ${noAll}${noAllList.length ? '\n  - ' + noAllList.join('\n  - ') : ''}`,
    `Failed (retried next run):     ${failed}${failedList.length ? '\n  - ' + failedList.join('\n  - ') : ''}`,
    stopped ? `STOPPED EARLY: ${stopped}` : '',
    `Total saved: ${Object.keys(store).length} files from ${new Set(Object.values(store).map(x => x.bundle)).size} bundle(s).`
  ].filter(Boolean).join('\n');
  console.log('DONE\n' + summary);
  return summary;
})()
