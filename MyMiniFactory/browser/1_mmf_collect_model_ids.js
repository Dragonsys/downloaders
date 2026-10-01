// MyMiniFactory - collect the model IDs from your library.
// Run in the browser Console (F12) on https://www.myminifactory.com/library while logged in.
// Turn on the library's "not downloaded" filter to collect only items you haven't
// downloaded yet (clear it once for a first complete backup); reload the page (F5)
// after changing the filter, since IDs collected before are kept until a reload.
// Scroll to the bottom first so every item is loaded. If the library only shows
// items as you scroll, scroll further and run it again: IDs are added up.
// The IDs are copied to your clipboard, one per line, for model_ids.txt.
// Hide unrelated Console "noise" (red errors/warnings from the site's own scripts): click the
// gear icon at the top right of the Console, tick "Hide network" and "Selected context only".
(() => {
  const ids = (window.__mmfIds ||= new Set());
  const walk = root => root.querySelectorAll('*').forEach(el => {
    const m = (el.getAttribute('href') || '').match(/\/object\/[\w-]*-(\d+)(?![\w-])/);
    if (m) ids.add(m[1]);
    if (el.shadowRoot) walk(el.shadowRoot);
  });
  walk(document);
  copy([...ids].join('\n'));
  return `${ids.size} model IDs copied to the clipboard.`;
})()
