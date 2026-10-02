// Heroes Infinite - copy the collected download list to the clipboard.
// Run in the browser Console (F12) on any heroesinfinite.com page.
// Paste into Notepad and save as hi_downloads.tsv (Save as type: All files).
// Hide unrelated Console "noise" (red errors/warnings from the site's own scripts): click the
// gear icon at the top right of the Console, tick "Hide network" and "Selected context only".
(() => {
  const load = k => JSON.parse(localStorage.getItem(k) || '{}');
  const rows = Object.values(load('hiDownloads')).map(r => ({ ...r, kind: 'file' }));
  // Pictures: id = Kajabi's upload id (the part before the first "_" in the file name), so the
  // same picture used in several posts is downloaded once; name = the rest of the file name
  const seen = new Set();
  const picture = (collection, post, url, kind, post_url) => {
    let base = url.split('?')[0].split('/').pop();
    try { base = decodeURIComponent(base); } catch (e) {}
    const i = base.indexOf('_');
    const id = 'img-' + (i > 0 ? base.slice(0, i) : base), name = i > 0 ? base.slice(i + 1) : base;
    if (seen.has(id)) return;
    seen.add(id);
    rows.push({ collection, post, label: kind, name, id, url, post_url, kind });
  };
  Object.entries(load('hiCovers')).forEach(([pu, [title, url]]) =>
    picture(title || pu.split('/').pop(), '', url, 'cover', location.origin + pu));
  Object.entries(load('hiImages')).forEach(([post, [collection, title, urls]]) =>
    (urls || []).forEach(u => picture(collection, title, u, 'image', location.origin + post)));
  // kind: file = download from a post, image = picture of a post, cover = collection cover
  const cols = ['collection', 'post', 'label', 'name', 'id', 'url', 'post_url', 'kind'];
  copy([cols.join('\t'), ...rows.map(r => cols.map(c => String(r[c] ?? '').replace(/[\t\r\n]+/g, ' ')).join('\t'))].join('\n'));
  const pics = rows.filter(r => r.kind !== 'file').length;
  return `Copied ${rows.length - pics} download links and ${pics} pictures.`;
})()
