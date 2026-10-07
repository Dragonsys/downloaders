// MakerWorld - download your collections, download history and liked models straight into a
// folder you choose (e.g. your MakerWorld folder on the NAS, as a mapped drive).
// Run in the browser Console (F12) on https://makerworld.com while logged in (Chrome or Edge).
// A panel appears at the bottom right: click "Choose folder" and pick your MakerWorld folder;
// the browser asks once whether the page may save files there - allow it ("Edit files").
// Every model goes to <collection>/<creator>/<model>/ with images/, files/ (the model files,
// extracted), profiles/ (print profiles, .3mf) and description.html. What's finished is recorded
// in .mw_downloaded.tsv in that folder, so the next run only downloads what's new.
// Each download link request counts as a download on MakerWorld, like clicking Download.
// Hide unrelated Console "noise" (red errors/warnings from the site's own scripts): click the
// gear icon at the top right of the Console, tick "Hide network" and "Selected context only".
(async () => {
  // ===== SETTINGS =====
  const SOURCES     = ['collections', 'downloads', 'likes'];  // remove what you don't want
  const COLLECTIONS = [];        // only these collections, e.g. ['Pokemon', 'D&D']; empty = all
  const PROFILES    = 'creator'; // print profiles: 'creator' (the model creator's own), 'all', 'none'
  const IMAGES      = true;      // the model's pictures
  const DESCRIPTION = true;      // description.html
  const EXTRACT     = true;      // extract the model zip into files/ (false = keep the zip in files/)
  const DELAY_MS    = 15000;     // pause before each download link request (shorter = MakerWorld's
                                 // "not a robot" check comes sooner)
  const API_DELAY_MS = 1000;     // pause before other requests (lists, model details)
  const MAX_MODELS  = 0;         // stop after this many models with something to download (0 = all); 2 for a first test
  const RECHECK     = false;     // true = read every model again (finds print profiles added since)
  const REFUSAL_LIMIT = 3;       // stop after this many refused download links in a row
  // ====================

  if (location.hostname !== 'makerworld.com') return 'Open makerworld.com (logged in) first.';
  if (typeof window.showDirectoryPicker !== 'function') return 'This browser cannot save into a folder - use Chrome or Edge.';
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const API = '/api/v1/design-service';

  // ---- Status panel ----
  document.getElementById('__dl_status_panel')?.remove();
  const panel = document.createElement('div');
  panel.id = '__dl_status_panel';
  panel.style.cssText = 'position:fixed;right:16px;bottom:16px;z-index:2147483647;width:480px;max-width:calc(100vw - 32px);' +
    'max-height:50vh;overflow:auto;background:#141414;color:#e8e8e8;font:12px/1.45 ui-monospace,Consolas,monospace;' +
    'padding:10px 12px;border:1px solid #444;border-radius:8px;box-shadow:0 6px 20px rgba(0,0,0,.45);white-space:pre-wrap;';
  const head = document.createElement('div');
  head.style.cssText = 'display:flex;gap:8px;align-items:center;margin-bottom:6px;font-weight:bold;';
  head.append('MakerWorld downloader');
  const btn = (text) => { const b = document.createElement('button'); b.textContent = text;
    b.style.cssText = 'margin-left:auto;background:#2d6cdf;color:#fff;border:0;border-radius:4px;padding:3px 10px;cursor:pointer;font:inherit;'; return b; };
  const goBtn = btn('Choose folder'), stopBtn = btn('Stop');
  stopBtn.style.marginLeft = '0'; stopBtn.style.background = '#8a2b2b'; stopBtn.style.display = 'none';
  head.append(goBtn, stopBtn);
  const body = document.createElement('div');
  panel.append(head, body);
  document.body.appendChild(panel);
  const show = (msg, color) => {
    const line = document.createElement('div'); line.textContent = msg; if (color) line.style.color = color;
    body.appendChild(line); while (body.childElementCount > 400) body.firstChild.remove();
    panel.scrollTop = panel.scrollHeight;
  };
  const log  = msg => { console.log(msg); show(msg); };
  const ok   = msg => { console.log(msg); show(msg, '#7ad37a'); };
  const warn = msg => { console.warn(msg); show(msg, '#f5c542'); };
  const bad  = msg => { console.warn(msg); show(msg, '#ff7b7b'); };
  let stopRequested = false;
  stopBtn.onclick = () => { stopRequested = true; warn('Stopping after the current file ...'); };

  // ---- the folder: remembered between runs (the browser asks again for permission) ----
  const idb = await new Promise((res, rej) => { const r = indexedDB.open('mwDownloader', 1);
    r.onupgradeneeded = () => r.result.createObjectStore('data'); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  const idbGet = k => new Promise(res => { const q = idb.transaction('data').objectStore('data').get(k); q.onsuccess = () => res(q.result); q.onerror = () => res(undefined); });
  const idbPut = (k, v) => new Promise(res => { const t = idb.transaction('data', 'readwrite'); t.objectStore('data').put(v, k); t.oncomplete = res; t.onerror = res; });
  const known = await idbGet('root');
  if (known) { goBtn.textContent = `Continue in "${known.name}"`; log(`Last folder: ${known.name}. Click the button to continue there, or Shift+click to choose another.`); }
  else log('Click "Choose folder" and pick your MakerWorld folder.');
  const root = await new Promise(resolve => {
    goBtn.onclick = async (ev) => {
      try {
        let h = known && !ev.shiftKey ? known : await window.showDirectoryPicker({ id: 'makerworld', mode: 'readwrite' });
        if ((await h.requestPermission({ mode: 'readwrite' })) !== 'granted') { bad('No permission to save in that folder.'); return; }
        await idbPut('root', h); resolve(h);
      } catch (e) { if (e.name !== 'AbortError') bad('Could not open the folder: ' + e.message); }
    };
  });
  goBtn.style.display = 'none'; stopBtn.style.display = '';
  log(`Saving into: ${root.name}`);

  // ---- files and folders in the chosen folder ----
  const safeName = (s, max = 100) => {
    s = String(s || '').replace(/[\u0000-\u001f]/g, '').replace(/[<>:"/\\|?*]/g, '_').replace(/^[\s.]+|[\s.]+$/g, '');
    if (s.length > max) s = s.slice(0, max).replace(/[\s.]+$/, '');
    return s;
  };
  const dirOf = async (rel, create = true) => {
    let d = root;
    for (const part of rel.split('/').filter(Boolean)) d = await d.getDirectoryHandle(part, { create });
    return d;
  };
  const exists = async (rel) => {
    const i = rel.lastIndexOf('/');
    try { const d = await dirOf(rel.slice(0, i), false); await d.getFileHandle(rel.slice(i + 1)); return true; } catch (e) { return false; }
  };
  // Write a file; never overwrites (an existing file is kept, returns false). The browser writes
  // into its own temporary file (name.crswap) and renames it when done, so a half-written file
  // never appears under the real name. Network shares sometimes report "the state had changed
  // since it was read from disk" during busy writing: then the file is tried again.
  const writeFile = async (rel, data) => {
    const i = rel.lastIndexOf('/');
    const name = rel.slice(i + 1);
    for (let attempt = 1; ; attempt++) {
      try {
        const d = await dirOf(rel.slice(0, i));
        try { await d.getFileHandle(name); return false; } catch (e) { if (e.name !== 'NotFoundError') throw e; }
        const f = await d.getFileHandle(name, { create: true });
        const w = await f.createWritable();
        try { await w.write(data); await w.close(); }
        catch (e) { try { await w.abort(); } catch (e2) {} throw e; }
        return true;
      } catch (e) {
        if (attempt >= 3 || !/InvalidStateError|NotReadableError|InvalidModificationError/.test(e.name)) throw e;
        await sleep(1500 * attempt);
        // a file left behind by the failed attempt is removed before the next try
        try { const d = await dirOf(rel.slice(0, i)); if ((await (await d.getFileHandle(name)).getFile()).size !== data.size) await d.removeEntry(name); } catch (e2) {}
      }
    }
  };

  // ---- the record of finished parts (same file and format as linux/99_mw_download.sh) ----
  const LEDGER = '.mw_downloaded.tsv';
  const ledger = {};
  let ledgerText = '';
  try { ledgerText = await (await (await root.getFileHandle(LEDGER)).getFile()).text(); } catch (e) {}
  for (const l of ledgerText.split(/\r?\n/)) { const [k, v] = l.split('\t'); if (k) ledger[k] = v || ''; }
  const dirOwner = {};
  for (const [k, v] of Object.entries(ledger)) if (k.startsWith('dir:')) dirOwner[v] = k.slice(4);
  const record = async (k, v) => {
    if (ledger[k] === v) return;
    ledger[k] = v;
    const h = await root.getFileHandle(LEDGER, { create: true });
    const size = (await h.getFile()).size;
    const w = await h.createWritable({ keepExistingData: true });
    await w.seek(size);
    const d = new Date(), p = n => String(n).padStart(2, '0');
    await w.write(`${k}\t${v}\t${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}\n`);
    await w.close();
  };
  const done = k => k in ledger;

  // ---- MakerWorld's API (the same requests the site makes) ----
  class Stop extends Error {}
  class RobotCheck extends Error {}
  const api = async (path) => {
    for (let attempt = 0; ; attempt++) {
      const r = await fetch(API + path, { credentials: 'include', headers: { Accept: 'application/json' } });
      let j = null; try { j = await r.json(); } catch (e) {}
      if (r.ok) return j;
      const msg = (j && (j.error || j.message)) || '';
      if (r.status === 401 || /log ?in/i.test(msg)) throw new Stop('MakerWorld says you are not logged in - log in and run again.');
      if (r.status === 418 || /not a robot/i.test(msg)) throw new RobotCheck(msg || 'MakerWorld wants to confirm that you are not a robot');
      if ((r.status === 429 || r.status >= 500) && attempt < 4) {
        const wait = (parseInt(r.headers.get('Retry-After'), 10) || 30 * 2 ** attempt) * 1000;
        warn(`  HTTP ${r.status} - waiting ${Math.round(wait / 1000)}s`); await sleep(wait); continue;
      }
      const e = new Error(`HTTP ${r.status}${msg ? ': ' + msg : ''}`); e.status = r.status; throw e;
    }
  };
  const getBlob = async (url) => {
    for (let attempt = 0; ; attempt++) {
      const r = await fetch(url);
      if (r.ok) return r.blob();
      if ((r.status === 429 || r.status >= 500) && attempt < 4) { await sleep(30000 * 2 ** attempt); continue; }
      throw new Error(`HTTP ${r.status} from the file server`);
    }
  };
  // MakerWorld's own "confirm that you are not a robot" check (HTTP 418): wait for YOU to solve it
  // on the site, then try the same request again. The script never answers it itself.
  const waitForCheck = (pageUrl) => new Promise(resolve => {
    warn('MakerWorld wants to confirm that you are not a robot. To continue:');
    const box = document.createElement('div');
    box.style.cssText = 'margin:6px 0;padding:6px;border:1px solid #f5c542;border-radius:4px;';
    const a = document.createElement('a');
    a.href = pageUrl; a.target = '_blank'; a.rel = 'noopener'; a.style.color = '#8ab4ff';
    a.textContent = '1. Open this model in a new tab, click Download there and complete the check';
    const c = btn('2. Continue'); c.style.marginLeft = '0'; c.style.marginTop = '6px';
    box.append(a, document.createElement('br'), c);
    body.appendChild(box); panel.scrollTop = panel.scrollHeight;
    c.onclick = () => { box.remove(); log('Continuing ...'); resolve(); };
  });
  let refused = 0;
  const linkRequest = async (path, pageUrl) => {
    for (;;) {
      await sleep(DELAY_MS);
      try { const j = await api(path); refused = 0; if (!j || !j.url) throw new Error('no link in the answer'); return j; }
      catch (e) {
        if (e instanceof RobotCheck) { await waitForCheck(pageUrl); continue; }   // then the same request again
        if (e instanceof Stop) throw e;
        if (++refused >= REFUSAL_LIMIT) throw new Stop(`${refused} download links in a row were refused (last: ${e.message}) - try again in a few hours.`);
        throw e;
      }
    }
  };

  // ---- a small zip reader (stored and deflated entries; the browser does the inflating) ----
  const unzip = async (blob) => {
    const buf = new Uint8Array(await blob.arrayBuffer());
    const dv = new DataView(buf.buffer);
    let eocd = -1;
    for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
    if (eocd < 0) throw new Error('not a zip file');
    const count = dv.getUint16(eocd + 10, true);
    let p = dv.getUint32(eocd + 16, true);
    if (p === 0xffffffff || count === 0xffff) throw new Error('zip64 archive');
    const out = [];
    for (let n = 0; n < count; n++) {
      if (dv.getUint32(p, true) !== 0x02014b50) throw new Error('damaged zip directory');
      const flags = dv.getUint16(p + 8, true), method = dv.getUint16(p + 10, true);
      const csize = dv.getUint32(p + 20, true), nlen = dv.getUint16(p + 28, true);
      const elen = dv.getUint16(p + 30, true), clen = dv.getUint16(p + 32, true), off = dv.getUint32(p + 42, true);
      if (csize === 0xffffffff || off === 0xffffffff) throw new Error('zip64 archive');
      const name = new TextDecoder(flags & 0x800 ? 'utf-8' : 'utf-8').decode(buf.subarray(p + 46, p + 46 + nlen));
      p += 46 + nlen + elen + clen;
      if (name.endsWith('/')) continue;
      const start = off + 30 + dv.getUint16(off + 26, true) + dv.getUint16(off + 28, true);
      const raw = new Blob([buf.subarray(start, start + csize)]);
      let data;
      if (method === 0) data = raw;
      else if (method === 8) data = await new Response(raw.stream().pipeThrough(new DecompressionStream('deflate-raw'))).blob();
      else throw new Error(`zip compression method ${method} is not supported`);
      out.push({ name: name.replace(/\\/g, '/'), data });
    }
    // a single folder that wraps everything is left out (files go straight into files/)
    while (out.length && out.every(f => f.name.includes('/')) && new Set(out.map(f => f.name.split('/')[0])).size === 1)
      out.forEach(f => { f.name = f.name.slice(f.name.indexOf('/') + 1); });
    return out;
  };

  // ---- which models ----
  const models = new Map();   // id -> { src, title, creator }
  const add = (src, list) => { let n = 0; for (const d of list || []) if (d && d.id && !models.has(String(d.id))) {
    models.set(String(d.id), { src, title: d.title || '', creator: (d.designCreator && d.designCreator.name) || (d.creator && d.creator.name) || '' }); n++; } return n; };
  try {
    if (SOURCES.includes('collections')) {
      const cl = await api('/my/favorites/listlite?offset=0&limit=100');
      const cols = (cl.hits || []).slice().sort((a, b) => (a.isDefault === true) - (b.isDefault === true));
      for (const c of cols) {
        if (COLLECTIONS.length && !COLLECTIONS.map(s => s.toLowerCase()).includes(String(c.title).toLowerCase())) continue;
        await sleep(API_DELAY_MS);
        const j = await api('/favorites/' + c.id);
        const n = add(c.title, j.designs);
        log(`  ${c.title}: ${(j.designs || []).length} models (${n} new)`);
      }
    }
    const pages = async (path, src, label) => {
      let off = 0, total = 1, n = 0;
      while (off < total) {
        await sleep(API_DELAY_MS);
        const j = await api(`${path}${path.includes('?') ? '&' : '?'}offset=${off}&limit=20`);
        total = j.total || 0; const hits = j.hits || [];
        n += add(src, hits);
        if (!hits.length) break; off += hits.length;
      }
      log(`  ${label}: ${total} models (${n} new)`);
    };
    if (SOURCES.includes('downloads')) await pages('/my/favorites/download/designs', 'Downloads', 'Download history');
    if (SOURCES.includes('likes')) await pages('/my/design/like', 'Likes', 'Liked models');
  } catch (e) { bad(e.message); stopBtn.style.display = 'none'; return e.message; }
  log(`${models.size} models`);

  // ---- download ----
  let worked = 0, filesOk = 0, profOk = 0, picsOk = 0, failed = 0, n = 0;
  const failures = [];
  const fail = (what, e) => { failed++; failures.push(`${what}: ${e.message || e}`); bad(`    ✗ ${what}: ${e.message || e}`); };
  let stoppedMsg = '';
  for (const [id, m] of models) {
    n++;
    if (stopRequested) { stoppedMsg = 'stopped'; break; }
    const label = `[${n}/${models.size}] ${m.title}`;
    if (!RECHECK && done('complete:' + id)) { log(`  ✓ ${label}`); continue; }
    let rel = ledger['dir:' + id];
    if (!rel) {
      rel = `${safeName(m.src)}/${safeName(m.creator) || 'Unknown creator'}/${safeName(m.title) || 'Model ' + id}`;
      if (dirOwner[rel] && dirOwner[rel] !== id) rel += ` (${id})`;
    }
    try {
      await sleep(API_DELAY_MS);
      const d = await api('/design/' + id);
      const ext = d.designExtension || {};
      const pageUrl = `https://makerworld.com/en/models/${id}-${d.slug || ''}`;
      const owner = d.designCreator && d.designCreator.uid;
      const insts = (d.instances || []).filter(i => PROFILES === 'all' || (PROFILES === 'creator' && i.instanceCreator && i.instanceCreator.uid === owner));
      const hasFiles = (ext.model_files || []).length > 0;
      const todo = (hasFiles && !done('files:' + id)) || insts.some(i => !done('inst:' + i.id)) ||
        (IMAGES && !done('pics:' + id)) || (DESCRIPTION && !done('desc:' + id));
      if (!todo) { await record('complete:' + id, rel); log(`  ✓ ${label}`); continue; }
      if (MAX_MODELS && worked >= MAX_MODELS) { stoppedMsg = `reached MAX_MODELS (${MAX_MODELS})`; break; }
      worked++;
      log(`  ↓ ${label} -> ${rel}/`);
      await dirOf(rel);
      await record('dir:' + id, rel); dirOwner[rel] = id;
      const failedBefore = failed;

      if (DESCRIPTION && !done('desc:' + id)) {
        const esc = s => String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        const html = `<!doctype html><meta charset="utf-8"><title>${esc(d.title)}</title>\n<h1>${esc(d.title)}</h1>\n` +
          `<p>by ${esc(d.designCreator && d.designCreator.name)} - <a href="https://makerworld.com/en/models/${id}-${esc(d.slug)}">makerworld.com/en/models/${id}</a><br>Licence: ${esc(d.license)}</p>\n${d.summary || ''}`;
        await writeFile(`${rel}/description.html`, new Blob([html], { type: 'text/html' }));
        await record('desc:' + id, `${rel}/description.html`);
      }

      if (hasFiles && !done('files:' + id)) {
        try {
          const link = await linkRequest(`/design/${id}/model?modelType=all&type=download`, pageUrl);
          const zip = await getBlob(link.url);
          let extracted = false;
          if (EXTRACT) {
            try {
              const entries = await unzip(zip);
              const used = new Set(), bad = [];
              for (const f of entries) {
                // two names that only differ in upper/lower case are the same file on Windows shares
                let path = `${rel}/files/${f.name.split('/').map(s => safeName(s, 120)).join('/')}`;
                for (let k = 2; used.has(path.toLowerCase()); k++) path = path.replace(/(\.[^./]*)?$/, m => `_${k}${m}`);
                used.add(path.toLowerCase());
                try { await writeFile(path, f.data); } catch (e) { bad.push(`${f.name} (${e.message})`); }
              }
              if (bad.length) {
                warn(`    ${bad.length} of ${entries.length} files could not be saved - the zip is kept as well: ${bad.slice(0, 3).join('; ')}${bad.length > 3 ? ' ...' : ''}`);
                failures.push(`${label} - files not saved from the zip: ${bad.join('; ')}`);
              } else extracted = true;
            } catch (e) { warn(`    could not extract (${e.message}) - the zip is kept`); }
          }
          if (!extracted) await writeFile(`${rel}/files/${safeName(link.name || m.title || 'model') .replace(/\.zip$/i, '')}.zip`, zip);
          await record('files:' + id, `${rel}/files`); filesOk++; ok(`    ✓ files/`);
        } catch (e) { if (e instanceof Stop) throw e; fail(`${label} - model files`, e); }
      }

      for (const inst of insts) {
        if (done('inst:' + inst.id) || stopRequested) continue;
        try {
          const link = await linkRequest(`/instance/${inst.id}/f3mf?type=download`, pageUrl);
          let name = safeName(link.name || `profile_${inst.id}.3mf`); if (!/\.3mf$/i.test(name)) name += '.3mf';
          if (await exists(`${rel}/profiles/${name}`)) name = safeName(`${name.replace(/\.3mf$/i, '')} - ${(inst.title || '').slice(0, 60)}`) + '.3mf';
          if (await exists(`${rel}/profiles/${name}`)) name = name.replace(/\.3mf$/i, `_${inst.id}.3mf`);
          await writeFile(`${rel}/profiles/${name}`, await getBlob(link.url));
          await record('inst:' + inst.id, `${rel}/profiles/${name}`); profOk++; ok(`    ✓ profiles/${name}`);
        } catch (e) { if (e instanceof Stop) throw e; fail(`${label} - profile ${inst.title}`, e); }
      }

      if (IMAGES && !done('pics:' + id)) {
        let allOk = true, got = 0;
        for (const p of ext.design_pictures || []) {
          if (!p.url) continue;
          const name = safeName(p.name || decodeURIComponent(p.url.split('?')[0].split('/').pop()));
          if (await exists(`${rel}/images/${name}`)) continue;
          try { await sleep(300); if (await writeFile(`${rel}/images/${name}`, await getBlob(p.url))) got++; }
          catch (e) { allOk = false; fail(`${label} - picture ${name}`, e); }
        }
        if (allOk) await record('pics:' + id, `${rel}/images`);
        picsOk += got; if (got) ok(`    ✓ images/ (${got})`);
      }
      if (failed === failedBefore) await record('complete:' + id, rel);
    } catch (e) {
      if (e instanceof Stop) { stoppedMsg = e.message; bad(e.message); break; }
      fail(label, e);
    }
  }

  stopBtn.style.display = 'none';
  const summary = `Done: ${models.size} models, worked on ${worked}: ${filesOk} model files, ${profOk} print profiles, ${picsOk} pictures, ${failed} failed.` +
    (stoppedMsg ? ` Stopped early: ${stoppedMsg}.` : '');
  (failed ? warn : ok)(summary);
  if (failures.length) { console.warn('Failures:\n' + failures.join('\n')); log('Failures are listed in the Console; they are tried again on the next run.'); }
  return summary;
})();
