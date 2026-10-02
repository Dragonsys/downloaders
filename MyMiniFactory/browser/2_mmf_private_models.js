// MyMiniFactory - file lists of private models (for 2_mmf_download_metadata.sh).
// Models the creator has made private or taken off sale are still in your library, but the
// public API answers 404 for them, and MyMiniFactory's bot check blocks scripts from the
// library's own API. This reads their file lists in your browser, the way the library page does.
//
// 1. Paste the IDs that 2_mmf_download_metadata.sh couldn't get (downloads/failed_ids.txt)
//    between the backticks below.
// 2. Run it in the Console (F12) on https://www.myminifactory.com/library while logged in.
// 3. Paste the result into Notepad and save it as private_models.json next to model_ids.txt
//    (Save as type: All files), then run 2_mmf_download_metadata.sh again.
// Hide unrelated Console "noise" (red errors/warnings from the site's own scripts): click the
// gear icon at the top right of the Console, tick "Hide network" and "Selected context only".
(async () => {
  // ===== SETTINGS =====
  const IDS = `
  `;                         // one model ID per line (or separated by spaces/commas)
  const DELAY_MS = 1500;     // pause between requests
  // ====================

  if (!/myminifactory\.com$/.test(location.hostname)) return 'Open myminifactory.com/library first.';
  const ids = [...new Set((IDS.match(/\d+/g) || []))];
  if (!ids.length) return 'Paste the IDs from failed_ids.txt into IDS at the top of this snippet first.';
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const getJson = async url => {
    const r = await fetch(url, { credentials: 'same-origin', headers: { Accept: 'application/json' } });
    if (r.status === 401 || r.redirected && /login/.test(r.url)) throw new Error('not logged in');
    if (!r.ok) return null;
    try { return await r.json(); } catch (e) { return null; }
  };

  // Names and page addresses, 20 at a time (as the library page asks for them)
  const meta = {};
  for (let i = 0; i < ids.length; i += 20) {
    if (i) await sleep(DELAY_MS);
    const q = ids.slice(i, i + 20).map(id => 'ids%5B%5D=' + id).join('&');
    (await getJson('/api/data-library/objects?' + q) || []).forEach(o => { meta[String(o.originalId ?? String(o.id).split('-')[1])] = o; });
  }

  // File lists, in the same layout as api/v2/objects/<id>, so the other scripts work unchanged.
  // Download links as the library page builds them: /download/<id>?archive_id=<archive>,
  // /download/<id> for an archive without id, /download/<id>?downloadfile=<part> for single files.
  const out = {}, missing = [];
  for (const id of ids) {
    await sleep(DELAY_MS);
    const d = await getJson(`/api/data-library/myObjects/object-${id}/downloadables`);
    const base = `https://www.myminifactory.com/download/${id}`;
    let items = ((d && d.archives) || []).map(a => ({ id: a.id ?? null, filename: a.name, size: a.size,
      download_url: a.id ? `${base}?archive_id=${a.id}` : base }));
    if (!items.length) items = ((d && d.parts) || []).map(p => ({ id: null, part_id: p.id, filename: p.name, size: p.size,
      download_url: `${base}?downloadfile=${p.id}` }));
    if (!items.length) { missing.push(id); console.warn(`${id}: no files found (not in your library?)`); continue; }
    const m = meta[id] || {};
    out[id] = { id: +id, name: m.name || 'UNKNOWN_NAME', url: m.url ? `https://www.myminifactory.com/object/3d-print-${m.url}` : null,
      source: 'library (object is private or no longer public)', files: { total_count: items.length, items } };
    console.log(`${id}: ${out[id].name} - ${items.map(x => x.filename).join(', ')}`);
  }

  if (!Object.keys(out).length) return `No file lists found for ${ids.length} ID(s).`;
  copy(JSON.stringify(out, null, 1));
  return `Copied file lists of ${Object.keys(out).length} model(s) - save them as private_models.json next to model_ids.txt.` +
    (missing.length ? ` Not found: ${missing.join(', ')}` : '');
})()
