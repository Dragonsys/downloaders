// MyMiniFactory - collect the model IDs from your library.
// Run in the browser Console (F12) on https://www.myminifactory.com/library while logged in.
// Scroll to the bottom first so every item is loaded. If the library only shows
// items as you scroll, scroll further and run it again: IDs are added up.
// The IDs are copied to your clipboard, one per line, for model_ids.txt.
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
