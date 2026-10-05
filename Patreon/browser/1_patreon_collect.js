// Patreon - collect the attachments (and the links in the post text) of every creator you support.
// Run in the browser Console (F12) on any https://www.patreon.com page while logged in.
// It reads your active memberships, then every post of each creator (newest first), pausing
// between requests. Only posts your tier can see are used. Run it once per Patreon account
// (in the browser where that account is logged in) and export each account's list separately.
// The file links it collects are valid for about 2 days, so download soon after collecting;
// every run collects fresh links.
// Hide unrelated Console "noise" (red errors/warnings from the site's own scripts): click the
// gear icon at the top right of the Console, tick "Hide network" and "Selected context only".
(async () => {
  // ===== SETTINGS =====
  const DELAY_MS  = 1500;   // pause between requests to Patreon
  const CREATORS  = [];     // only these creators, e.g. ['eXoDus'] (name or page name); empty = all you support
  const MAX_PAGES = 0;      // only this many pages of 20 posts per creator (0 = all); use 1 for a first test
  // ====================

  if (location.hostname !== 'www.patreon.com') return 'Open www.patreon.com (logged in) first.';
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  // ---- Status panel on the page (you can close DevTools while it runs) ----
  const panelTitle = 'Patreon collector';
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
  const redact = u => String(u).replace(/\?.*$/, '?...');   // never show link tokens

  // The list is kept in the browser's database (IndexedDB): Patreon's links are long, and
  // localStorage (about 5 MB, partly used by Patreon itself) fills up with large libraries.
  const db = await new Promise((res, rej) => {
    const r = indexedDB.open('patreonCollector', 1);
    r.onupgradeneeded = () => r.result.createObjectStore('data');
    r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
  });
  const idb = (mode, fn) => new Promise((res, rej) => {
    const t = db.transaction('data', mode), q = fn(t.objectStore('data'));
    t.oncomplete = () => res(q && q.result); t.onerror = () => rej(t.error);
  });
  const rows = (await idb('readonly', s => s.get('rows'))) || {};   // id -> row
  localStorage.removeItem('patreonRows');                            // left over by the first version
  const save = () => idb('readwrite', s => s.put(rows, 'rows'));
  const clean = s => String(s || '').trim().replace(/\s+/g, ' ');

  // ---- Patreon's own API (the same requests its pages make), with polite retries ----
  const api = async (path) => {
    for (let attempt = 0; ; attempt++) {
      const r = await fetch(path, { credentials: 'include', headers: { Accept: 'application/vnd.api+json' } });
      if (r.ok) return r.json();
      if (r.status === 401 || r.status === 403) throw new Error(`Patreon refused the request (HTTP ${r.status}) - are you logged in?`);
      if ((r.status === 429 || r.status >= 500) && attempt < 4) {
        const wait = (parseInt(r.headers.get('Retry-After'), 10) || 30 * 2 ** attempt) * 1000;
        warn(`HTTP ${r.status} - waiting ${Math.round(wait / 1000)}s before trying again`);
        await sleep(wait); continue;
      }
      throw new Error(`HTTP ${r.status} for ${redact(path)}`);
    }
  };

  // ---- The creators you support ----
  const me = await api('/api/current_user?include=active_memberships.campaign&fields[campaign]=name,vanity,url&json-api-version=1.0');
  let campaigns = (me.included || []).filter(x => x.type === 'campaign')
    .map(c => ({ id: c.id, name: clean(c.attributes.name || c.attributes.vanity || c.id), vanity: c.attributes.vanity || '' }));
  if (CREATORS.length) {
    const want = CREATORS.map(s => String(s).toLowerCase());
    campaigns = campaigns.filter(c => want.includes(c.name.toLowerCase()) || want.includes(c.vanity.toLowerCase()) || want.includes(c.id));
  }
  if (!campaigns.length) return CREATORS.length ? 'None of the CREATORS are in your active memberships.' : 'No active memberships found on this account.';
  log(`Creators: ${campaigns.map(c => c.name).join(', ')}`);

  let files = 0, links = 0, attach = 0, locked = 0, postsSeen = 0;
  for (const c of campaigns) {
    // this creator's rows are replaced by fresh ones (the file links change on every read)
    const fresh = {};
    let cFiles = 0, cLinks = 0, cLocked = 0, cPosts = 0, page = 0;
    let next = '/api/posts?filter[campaign_id]=' + c.id + '&filter[contains_exclusive_posts]=true&filter[is_draft]=false&sort=-published_at'
      + '&include=attachments_media,attachments'
      + '&fields[post]=title,published_at,current_user_can_view,url,content,embed'
      + '&fields[media]=file_name,download_url,size_bytes,mimetype&fields[attachment]=name,url'
      + '&json-api-use-default-includes=false&json-api-version=1.0&page[count]=20';
    while (next) {
      page++;
      const j = await api(next);
      const inc = {};
      (j.included || []).forEach(x => { inc[x.type + ':' + x.id] = x; });
      for (const p of j.data || []) {
        const a = p.attributes || {}, rel = p.relationships || {};
        cPosts++;
        if (!a.current_user_can_view) { cLocked++; continue; }
        const base = { creator: c.name, campaign_id: c.id, post_id: p.id, post: clean(a.title) || 'Post ' + p.id,
          published: (a.published_at || '').slice(0, 10), post_url: a.url || '' };
        // attached files: direct, signed links on Patreon's file server (no login needed, ~2 days)
        for (const d of ((rel.attachments_media || {}).data || [])) {
          const m = inc['media:' + d.id]; if (!m) continue;
          const ma = m.attributes || {};
          if (!ma.download_url) continue;
          fresh['m' + d.id] = { ...base, kind: 'file', name: clean(ma.file_name) || 'file_' + d.id, id: 'm' + d.id,
            size: ma.size_bytes || '', url: ma.download_url };
          cFiles++;
        }
        // older posts: attachments behind patreon.com/file?... (these need your login - listed, not downloaded)
        for (const d of ((rel.attachments || {}).data || [])) {
          const t = inc['attachment:' + d.id]; if (!t) continue;
          const ta = t.attributes || {};
          fresh['a' + d.id] = { ...base, kind: 'attachment', name: clean(ta.name) || 'attachment_' + d.id, id: 'a' + d.id,
            size: '', url: ta.url ? new URL(ta.url, location.origin).href : '' };
          attach++;
        }
        // links in the post text and an embedded link (Google Drive, MEGA, MyMiniFactory, ...)
        const found = new Set();
        for (const m of String(a.content || '').matchAll(/href\s*=\s*["']([^"']+)["']/gi)) found.add(m[1].replace(/&amp;/g, '&'));
        if (a.embed && a.embed.url) found.add(a.embed.url);
        let n = 0;
        for (const u of found) {
          let h; try { h = new URL(u).hostname; } catch (e) { continue; }
          if (/(^|\.)patreon(usercontent)?\.com$/i.test(h)) continue;     // Patreon's own pages
          n++;
          fresh['l' + p.id + '-' + n] = { ...base, kind: 'link', name: h, id: 'l' + p.id + '-' + n, size: '', url: u };
          cLinks++;
        }
      }
      log(`  ${c.name}: page ${page} - ${cPosts} posts so far, ${cFiles} files, ${cLinks} links`);
      next = j.links && j.links.next ? j.links.next : '';
      if (MAX_PAGES && page >= MAX_PAGES) { warn(`  stopped after ${MAX_PAGES} page(s) (MAX_PAGES)`); next = ''; }
      if (next) await sleep(DELAY_MS);
    }
    for (const k of Object.keys(rows)) if (rows[k].campaign_id === c.id) delete rows[k];
    Object.assign(rows, fresh);
    await save();
    files += cFiles; links += cLinks; locked += cLocked; postsSeen += cPosts;
    log(`${c.name}: ${cPosts} posts, ${cFiles} files, ${cLinks} links${cLocked ? `, ${cLocked} posts your tier can't see` : ''}`);
    await sleep(DELAY_MS);
  }
  const msg = `Done: ${postsSeen} posts, ${files} files, ${links} links${attach ? `, ${attach} older attachments (need the browser)` : ''}` +
    `${locked ? `, ${locked} locked posts skipped` : ''}. Now run 2_patreon_export_list.js and download within 2 days.`;
  log(msg);
  return msg;
})();
