// Loot Studios - copy the collected list to the clipboard.
// Run in the browser Console (F12) on any app.lootstudios.com page.
// Paste into Notepad and save as loot_all_bundles.tsv.
// Hide unrelated Console "noise" (red errors/warnings from the site's own scripts): click the
// gear icon at the top right of the Console, tick "Hide network" and "Selected context only".
(() => {
  const rows = Object.values(JSON.parse(localStorage.getItem('lootAllBundles') || '{}'));
  // Figure images: render and painted, per material (the downloader skips the ones that don't exist)
  const images = JSON.parse(localStorage.getItem('lootImages') || '{}');
  const types = [['render', 'png'], ['painted', 'jpg']];
  Object.entries(images).forEach(([page, b]) => (b.items || []).forEach(([group, title, base, mats]) =>
    types.forEach(([type, ext]) => String(mats).split(' ').filter(Boolean).forEach(material => rows.push({
      bundle: b.bundle, folder: b.folder, scale: '', material, page, kind: 'image', group, item: title, variant: type,
      file: `${title} - ${type} ${material}.${ext}`, url: `${base}-${type}-${material}.${ext}` })))));
  // kind: all = All Bundle archive, item = individual figure file, extra = magazine / statblocks, image = figure image
  const cols = ['bundle', 'folder', 'scale', 'material', 'file', 'url', 'page', 'kind', 'group', 'item', 'variant'];
  copy([cols.join('\t'), ...rows.map(r => cols.map(c => String(r[c] ?? (c === 'kind' ? 'all' : '')).replace(/[\t\r\n]+/g, ' ')).join('\t'))].join('\n'));
  return `Copied ${rows.length} rows.`;
})()
