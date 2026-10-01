// Heroes Infinite - copy the collected download list to the clipboard.
// Run in the browser Console (F12) on any heroesinfinite.com page.
// Paste into Notepad and save as hi_downloads.tsv (Save as type: All files).
(() => {
  const rows = Object.values(JSON.parse(localStorage.getItem('hiDownloads') || '{}'));
  const cols = ['collection', 'post', 'label', 'name', 'id', 'url', 'post_url'];
  copy([cols.join('\t'), ...rows.map(r => cols.map(c => String(r[c] ?? '').replace(/[\t\r\n]+/g, ' ')).join('\t'))].join('\n'));
  return `Copied ${rows.length} download links.`;
})()
