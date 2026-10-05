// Patreon - forget everything the collector has saved in this browser.
// Hide unrelated Console "noise" (red errors/warnings from the site's own scripts): click the
// gear icon at the top right of the Console, tick "Hide network" and "Selected context only".
localStorage.removeItem('patreonRows');
indexedDB.deleteDatabase('patreonCollector');
'Collector data cleared.'
