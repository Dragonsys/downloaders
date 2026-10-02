// Loot Studios - collect the download links from all your bundles:
//   - the "All Bundle" archives (one per scale and material),
//   - the individual figure files, for any scale/material the All Bundle doesn't cover
//     (or for bundles that have no All Bundle at all),
//   - the extra contents: magazine, digital magazine, statblocks,
//   - each figure's images (render and painted, resin and FDM; the downloader skips missing ones).
// Run in the browser Console (F12) on a My Loots listing page, logged in.
// Scroll to the bottom first so every bundle on the page is loaded.
// Each bundle page is opened in a hidden frame so the site's own code builds
// the download list, exactly as when you visit it. Progress is saved:
// rerun it on each listing page (Fantasy, Sci-Fi, ...).
// Hide unrelated Console "noise" (red errors/warnings from the site's own scripts): click the
// gear icon at the top right of the Console, tick "Hide network" and "Selected context only".
(async () => {
  // ===== SETTINGS =====
  const MATERIALS   = [];         // e.g. ['resin'] or ['resin', 'fdm']; empty = all materials
  const DELAY_MS    = 4000;       // pause between bundle pages
  const TIMEOUT_MS  = 45000;      // give up on a page after this long
  const EXTRAS_WAIT_MS = 8000;    // after the downloads appear, wait up to this long for the magazine section
  const MAX_PAGES   = 0;          // stop after this many pages this run (0 = no limit)
  const RESCAN      = false;      // true = read every bundle again (normally not needed: bundles
                                  // whose saved links expire within 10 minutes are re-read anyway)
  const RECHECK_HOURS = 24;       // re-read bundles that had no downloads, or weren't in your account,
                                  // after this many hours (new purchases and releases; 0 = every run)
  const BUNDLE_PATH = '/bundle/'; // only follow links whose path starts with this
  // ====================

  const sleep = ms => new Promise(r => setTimeout(r, ms));

  // ---- Status panel on the page (you can close DevTools while it runs) ----
  const panelTitle = 'Loot Studios collector';
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
    close.textContent = '✕'; close.title = 'Close this panel (the script keeps running)';
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

  // ---- Turning a bundle page's data into download rows ----
  const isUrl = v => typeof v === 'string' && /^https?:\/\//.test(v);
  const segs  = u => u.pathname.split('/').filter(Boolean).map(s => { try { return decodeURIComponent(s); } catch (e) { return s; } });
  const fileOf = u => segs(new URL(u)).pop() || '';
  // Bundle folder name from a download link. old-dls: /<Bundle>/...;
  // new-dls: /<Category>/<Bundle>/<Material>/... (e.g. /Fantasy/ShadowCourt/Resin/...)
  const folderOf = url => { const u = new URL(url), s = segs(u); return (/^new-dls\./i.test(u.host) && s.length > 2) ? s[1] : (s[0] || ''); };
  const matOk = m => !MATERIALS.length || MATERIALS.includes(String(m || '').toLowerCase());
  const VARIANTS = ['all', 'hollow', 'solid', 'slicer', 'unsupported'];   // file kinds of a figure

  const buildRows = (r, page) => {
    const groups = r.groups, bundle = r.name;
    const abGroup = groups.find(g => /all\s*bundle/i.test(g.title || ''));
    const abItem = abGroup && ((abGroup.items || []).find(i => /all\s*bundle/i.test(i.title || '')) || (abGroup.items || [])[0]);
    const abLinks = ((abItem && abItem.links) || []).filter(l => isUrl(l.all) && matOk(l.material));
    // All figure links (individual files), grouped by scale + material
    const items = [];
    groups.filter(g => g !== abGroup).forEach(g => (g.items || []).forEach(it => (it.links || []).forEach(l => {
      if (!matOk(l.material)) return;
      VARIANTS.forEach(v => { if (isUrl(l[v])) items.push({ group: g.title || '', item: it.title || '', variant: v, scale: l.scale || '', material: l.material || '', url: l[v] }); });
    })));
    // One folder name per bundle, so the All Bundle, figures and extras end up together
    let folder = abLinks.length ? folderOf(abLinks[0].all) : '';
    if (!folder && items.length) {
      const n = {}; items.forEach(x => { const f = folderOf(x.url); n[f] = (n[f] || 0) + 1; });
      folder = Object.keys(n).sort((a, b) => n[b] - n[a])[0];
    }
    if (!folder) folder = segs(new URL(page)).pop() || bundle;
    const base = { bundle, folder, page };
    const rows = abLinks.map(l => ({ ...base, kind: 'all', group: 'All Bundle', item: '', variant: '',
      scale: l.scale || '', material: l.material || '', file: fileOf(l.all), url: l.all }));
    // Individual files only for scale + material combinations the All Bundle doesn't cover
    const covered = new Set(abLinks.map(l => `${l.scale}|${l.material}`));
    items.filter(x => !covered.has(`${x.scale}|${x.material}`))
      .forEach(x => rows.push({ ...base, kind: 'item', ...x, file: fileOf(x.url) }));
    // Extra contents (magazine, digital magazine, statblocks)
    (r.extras || []).forEach(e => rows.push({ ...base, kind: 'extra', group: 'Extras', item: e.name, variant: '',
      scale: '', material: '', file: fileOf(e.href), url: e.href }));
    // Same file listed twice (e.g. a figure in two groups): keep one
    const seen = new Set();
    return rows.filter(x => { const k = keyOf(x); if (seen.has(k)) return false; seen.add(k); return true; });
  };
  // Figure images. The site guesses their addresses (assets.loot-studios.com/bundles/<bundle>/<figure>-
  // render|painted-resin|fdm.png|jpg) and shows the ones that load, so only the common part is saved
  // here - compact, as there are hundreds per bundle. 2_loot_export_list.js turns it into rows.
  const buildImages = (r) => {
    const out = [], seen = new Set();
    r.groups.filter(g => !/all\s*bundle/i.test(g.title || '')).forEach(g => (g.items || []).forEach(it => {
      const a = it.assets && it.assets.render;
      const first = a && [...(a.resin || []), ...(a.fdm || [])].find(isUrl);
      const m = first && first.match(/^(https:\/\/assets\.loot-studios\.com\/.+?)-render-(?:resin|fdm)\.png$/);
      if (!m || seen.has(m[1])) return;
      seen.add(m[1]);
      const mats = ['resin', 'fdm'].filter(x => it[`has_${x}`] !== false && matOk(x));
      if (mats.length) out.push([g.title || '', it.title || '', m[1], mats.join(' ')]);
    }));
    return out;
  };

  const load = k => { try { return JSON.parse(localStorage.getItem(k) || '{}'); } catch (e) { return {}; } };
  // Links expire, so each file is stored once (by bundle page + scale + material + file name)
  // and a newer link always replaces an older one. Older saved lists are converted here.
  const tsOf  = u => +(((u || '').match(/[?&]v=(\d{9,})-/) || [])[1] || 0);
  const keyOf = r => [r.page, r.scale, r.material, r.file].join('|');
  const store = {};
  Object.values(load('lootAllBundles')).forEach(r => { const k = keyOf(r); if (!store[k] || tsOf(r.url) >= tsOf(store[k].url)) store[k] = r; });
  const done  = load('lootBundlePages');    // bundle page -> 'ok' / 'no downloads' / 'not owned'
  const names = load('lootBundleNames');    // bundle page -> bundle name (for the skipped list)
  const checkedAt = load('lootNoAllChecked'); // bundle page -> when 'no downloads' / 'not owned' was found (ms)
  const images = load('lootImages');        // bundle page -> { bundle, folder, items: [[group, title, base, materials]] }
  // Bundles the downloader reported as fully downloaded (pasted from loot_done_bundles.js)
  let downloaded;
  try { downloaded = new Set(JSON.parse(localStorage.getItem('lootDonePages') || '[]')); } catch (e) { downloaded = new Set(); }
  let storageFull = false;
  const save  = () => {
    try {
      localStorage.setItem('lootAllBundles', JSON.stringify(store));
      localStorage.setItem('lootBundlePages', JSON.stringify(done));
      localStorage.setItem('lootBundleNames', JSON.stringify(names));
      localStorage.setItem('lootNoAllChecked', JSON.stringify(checkedAt));
      localStorage.setItem('lootImages', JSON.stringify(images));
    } catch (e) { storageFull = true; }
  };

  // Open a page in a hidden frame, wait until the site has built allGroups, then
  // give the separately loaded magazine section a few seconds to appear
  const readBundle = url => new Promise(resolve => {
    const f = document.createElement('iframe');
    f.style.cssText = 'position:fixed;left:-3000px;top:0;width:1280px;height:900px;visibility:hidden;border:0;';
    f.setAttribute('aria-hidden', 'true');
    const start = Date.now();
    let finished = false, groupsAt = 0;
    const finish = result => {
      if (finished) return; finished = true;
      clearInterval(timer);
      try { f.src = 'about:blank'; } catch (e) {}
      setTimeout(() => f.remove(), 500);
      resolve(result);
    };
    const extrasOf = d => [...d.querySelectorAll('#newExtraContents a[href]')]
      .filter(a => isUrl(a.href) && !/\.(png|jpe?g|webp|gif|mp4)(\?|$)/i.test(a.href))
      .map(a => {
        const id = (a.closest('[id^="download"]') || {}).id || '';
        const name = id.replace(/^download/, '').replace(/-.*$/, '') || a.textContent.trim().replace(/\s+/g, ' ').replace(/download$/i, '').trim();
        return { name, href: a.href };
      });
    const timer = setInterval(() => {
      let w;
      try {
        w = f.contentWindow;
        const path = w.location.pathname;   // throws if the frame was blocked or left the site
        if (/wp-login|\/login/i.test(path)) return finish({ error: 'login' });
        const g = w.allGroups;
        if (Array.isArray(g) && g.length && g.some(x => x && (x.links || x.items))) {
          const d = w.document;
          const owned = String(w.LootConfig?.hasBundle ?? 'true') !== 'false';
          if (!groupsAt) groupsAt = Date.now();
          const extras = extrasOf(d);
          if (owned && !extras.length && Date.now() - groupsAt < EXTRAS_WAIT_MS) return;   // magazine section still loading
          const name = (d.querySelector('h1')?.textContent || d.title || url).trim().replace(/\s+/g, ' ');
          return finish({ groups: JSON.parse(JSON.stringify(g)), name, owned, extras });
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
    .map(a => { try { const u = new URL(a.href, location.href); return u.origin === location.origin && u.pathname.startsWith(BUNDLE_PATH) && u.pathname.length > BUNDLE_PATH.length ? u.origin + u.pathname : null; } catch (e) { return null; } })
    .filter(Boolean))];
  const total = candidates.length;
  // Skip a bundle if it is fully downloaded, or was read before AND its saved links are still fresh
  const nowSec = Date.now() / 1000;
  const rowsOf = u => Object.values(store).filter(r => r.page === u);
  const linksFresh = u => {
    const rows = rowsOf(u), t = rows.map(r => tsOf(r.url)).filter(Boolean);   // magazine links don't expire
    return rows.length > 0 && (!t.length || Math.min(...t) > nowSec + 600);
  };
  const hoursSince = u => (Date.now() - (checkedAt[u] || 0)) / 3600000;
  const needsReading = u => {
    if (done[u] === 'no All Bundle') return true;   // from an older version: read again with the new rules
    if (done[u] === 'no downloads' || done[u] === 'not owned') return hoursSince(u) >= RECHECK_HOURS;
    if (downloaded.has(u)) return false;
    return !done[u] || !linksFresh(u);
  };
  const slugName = u => decodeURIComponent(new URL(u).pathname.split('/').filter(Boolean).pop() || u)
    .replace(/[-_]+/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
  const nameOf = u => names[u] || rowsOf(u)[0]?.bundle || slugName(u);
  const skipped = RESCAN ? [] : candidates.filter(u => !needsReading(u)).map(u => {
    const left = Math.max(1, Math.ceil(RECHECK_HOURS - hoursSince(u)));
    if (done[u] === 'not owned') return { u, name: nameOf(u), why: `not in your account (checked again in ${left} h)` };
    if (done[u] === 'no downloads') return { u, name: nameOf(u), why: `no downloads on an earlier run (checked again in ${left} h)` };
    if (downloaded.has(u)) return { u, name: nameOf(u), why: 'already downloaded (from loot_done_bundles.js)' };
    const t = rowsOf(u).map(r => tsOf(r.url)).filter(Boolean);
    return { u, name: nameOf(u), why: t.length ? `links still fresh (${Math.round((Math.min(...t) - nowSec) / 60)} min left)` : 'links don\'t expire' };
  });
  if (!RESCAN) candidates = candidates.filter(needsReading);
  if (MAX_PAGES > 0) candidates = candidates.slice(0, MAX_PAGES);

  log(`Found ${total} bundle link(s) under ${BUNDLE_PATH}; ${candidates.length} to read now.`);
  if (skipped.length) {
    log(`Skipping ${skipped.length} bundle(s) that don't need reading this run:`);
    skipped.sort((a, b) => a.why.localeCompare(b.why) || a.name.localeCompare(b.name))
      .forEach(x => log(`  - ${x.name}: ${x.why}`));
    log('  (Set RESCAN = true to read every bundle again.)');
  }
  if (!candidates.length) { log('Nothing to do - every bundle on this page is downloaded or has fresh links. Export the list and start the downloader.'); return; }
  log(`This will take roughly ${Math.ceil(candidates.length * (DELAY_MS + 12000) / 60000)} minute(s). Progress is shown in the panel at the bottom right. Keep this tab open (DevTools can be closed).`);

  let ok = 0, failed = 0, failStreak = 0, files = 0, stopped = '';
  const emptyList = [], notOwnedList = [], itemsList = [], failedList = [];

  for (let i = 0; i < candidates.length; i++) {
    const url = candidates[i];
    if (i > 0) await sleep(DELAY_MS);
    const tag = `[${i + 1}/${candidates.length}]`;
    const r = await readBundle(url);

    if (r.error === 'login')   { stopped = 'redirected to the login page - log in again and rerun'; break; }
    if (r.error === 'blocked') { stopped = 'the site no longer allows its pages to be opened in a frame - the collector needs updating'; break; }
    if (r.error) {
      warn(`${tag} no bundle data after ${TIMEOUT_MS / 1000}s: ${url}`);
      failed++; failedList.push(url);
      if (++failStreak >= 3) { stopped = '3 pages in a row had no bundle data'; break; }
      continue;
    }
    failStreak = 0;
    names[url] = r.name;

    if (!r.owned) {
      done[url] = 'not owned'; checkedAt[url] = Date.now(); notOwnedList.push(r.name); save();
      log(`${tag} ${r.name}: not in your account - skipped`);
      continue;
    }
    const rows = buildRows(r, url);
    if (!rows.length) {
      done[url] = 'no downloads'; checkedAt[url] = Date.now(); emptyList.push(r.name); save();
      log(`${tag} ${r.name}: no downloads on the page`);
      continue;
    }
    // Replace this bundle's earlier rows, so files the page no longer lists are dropped
    rowsOf(url).forEach(x => delete store[keyOf(x)]);
    rows.forEach(x => { store[keyOf(x)] = x; });
    const imgs = buildImages(r);
    if (imgs.length) images[url] = { bundle: r.name, folder: rows[0].folder, items: imgs }; else delete images[url];
    delete checkedAt[url];
    done[url] = 'ok'; ok++; files += rows.length; save();
    if (storageFull) { stopped = 'the browser storage is full - export what you have (2_loot_export_list.js) and download it'; break; }

    const all = rows.filter(x => x.kind === 'all'), items = rows.filter(x => x.kind === 'item'), extras = rows.filter(x => x.kind === 'extra');
    const parts = [];
    if (all.length) parts.push('All Bundle ' + all.map(x => `${x.scale} ${x.material}`.trim()).join(', '));
    if (items.length) {
      const combos = [...new Set(items.map(x => `${x.scale} ${x.material}`.trim()))].join(', ');
      parts.push(`${items.length} individual file(s) (${all.length ? 'not in the All Bundle' : 'no All Bundle'}: ${combos})`);
      itemsList.push(r.name);
    }
    if (extras.length) parts.push(extras.map(x => x.item).join(', '));
    if (imgs.length) parts.push(`images of ${imgs.length} figure(s)`);
    log(`${tag} ${r.name}: ${parts.join(' + ')}`);
  }

  const list = a => a.length ? '\n  - ' + a.join('\n  - ') : '';
  const summary = [
    `Bundles read:                   ${ok} (${files} files)`,
    itemsList.length ? `  with individual files:        ${itemsList.length}${list(itemsList)}` : '',
    `Bundles without any downloads:  ${emptyList.length}${list(emptyList)}`,
    notOwnedList.length ? `Not in your account (skipped):  ${notOwnedList.length}${list(notOwnedList)}` : '',
    `Failed (retried next run):      ${failed}${list(failedList)}`,
    stopped ? `STOPPED EARLY: ${stopped}` : '',
    `Total saved: ${Object.keys(store).length} files from ${new Set(Object.values(store).map(x => x.page)).size} bundle(s).`
  ].filter(Boolean).join('\n');
  log('DONE\n' + summary); show('Finished - you can close this panel.', '#7ddc7d');
  return summary;
})()
