// Patreon - save the collected list as patreon_list.tsv (and copy it to the clipboard).
// Run in the browser Console (F12) on any www.patreon.com page, right after 1_patreon_collect.js.
// The browser saves patreon_list.tsv to your Downloads folder; put it next to 3_patreon_download.sh.
// For a second Patreon account, rename its list to patreon_list_2.tsv (any name starting with
// "patreon_list" and ending in ".tsv" works); the downloader reads them all.
// Hide unrelated Console "noise" (red errors/warnings from the site's own scripts): click the
// gear icon at the top right of the Console, tick "Hide network" and "Selected context only".
(async () => {
  const consoleCopy = typeof copy === 'function' ? copy : null;   // capture before the first await
  const db = await new Promise((res, rej) => {
    const r = indexedDB.open('patreonCollector', 1);
    r.onupgradeneeded = () => r.result.createObjectStore('data');
    r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
  });
  const stored = await new Promise((res, rej) => {
    const q = db.transaction('data', 'readonly').objectStore('data').get('rows');
    q.onsuccess = () => res(q.result); q.onerror = () => rej(q.error);
  });
  const rows = Object.values(stored || {});
  if (!rows.length) return 'Nothing collected yet - run 1_patreon_collect.js first.';
  // kind: file = attached file (downloaded), attachment = older attachment that needs the browser,
  //       link = link in the post text (listed in patreon_links.txt, not downloaded)
  const cols = ['creator', 'post', 'published', 'kind', 'name', 'id', 'size', 'url', 'post_url', 'campaign_id', 'post_id'];
  const text = [cols.join('\t'), ...rows.map(r => cols.map(c => String(r[c] ?? '').replace(/[\t\r\n]+/g, ' ')).join('\t'))].join('\n') + '\n';
  // Save as a file (works for lists of any size) ...
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([text], { type: 'text/tab-separated-values' }));
  a.download = 'patreon_list.tsv';
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 60000);
  // ... and copy it to the clipboard too
  try { if (consoleCopy) consoleCopy(text); } catch (e) {}
  const n = k => rows.filter(r => r.kind === k).length;
  return `Saved patreon_list.tsv (${n('file')} files, ${n('link')} links${n('attachment') ? `, ${n('attachment')} older attachments` : ''}) ` +
    'to your Downloads folder (also copied to the clipboard). Second account: rename it to patreon_list_2.tsv.';
})()
