// Loot Studios - copy the collected All Bundle list to the clipboard.
// Run in the browser Console (F12) on any app.lootstudios.com page.
// Paste into Notepad and save as loot_all_bundles.tsv.
(() => {
  const rows = Object.values(JSON.parse(localStorage.getItem('lootAllBundles') || '{}'));
  const cols = ['bundle', 'folder', 'scale', 'material', 'file', 'url', 'page'];
  copy([cols.join('\t'), ...rows.map(r => cols.map(c => String(r[c] ?? '').replace(/[\t\r\n]+/g, ' ')).join('\t'))].join('\n'));
  return `Copied ${rows.length} rows.`;
})()
