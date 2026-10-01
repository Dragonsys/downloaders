# Heroes Infinite - library backup

Collects every download link from your Heroes Infinite library (all library pages, every collection, every post).
Heroes Infinite runs on **Kajabi**; download links look like `https://www.heroesinfinite.com/courses/downloads/{id}/{name}` and **do not expire**, so you can collect once and download whenever you like.

## Files

| File | Where | Purpose |
|---|---|---|
| `browser/1_hi_collect_downloads.js` | Browser Console | Reads your whole library and saves all download links in the browser |
| `browser/2_hi_export_list.js` | Browser Console | Copies the saved list to the clipboard |
| `linux/3_hi_download.sh` | Linux | Downloads every file that isn't downloaded yet, using your cookie |
| `browser/99_hi_reset.js` | Browser Console | Forgets everything collected (only to start fresh) |

## Step 1 - Collect the download links (browser)

1. Log in and open **https://www.heroesinfinite.com/library**.
2. Press **F12** → **Console**. The first time only (Chrome remembers it):
   - Type `allow pasting`, press Enter.
   - Hide the Console "noise" - red errors and warnings from the site's own scripts that have nothing to do with ours: click the **gear icon** (⚙) at the top right of the Console panel, tick **Hide network** and **Selected context only**, and click the gear again. The dropdown at the top left of the Console must show **top**. Details: [Hide the Console "noise"](../README.md#hide-the-console-noise).
3. Open `browser/1_hi_collect_downloads.js` in Notepad.
   - **First time:** set `MAX_PRODUCTS = 1` for a short test.
   - Then set it back to `0` and run again for everything.
4. Copy the whole file, paste into the Console, press **Enter**.
5. It prints the library pages, each collection with its number of posts, then each post with its number of downloads, and ends with **DONE**. The same progress appears in a **status panel at the bottom right of the page**, so you can close DevTools once it has started (the ✕ only closes the panel; the collector keeps running).

Roughly 1-2 minutes per collection (1.5 s pause between pages). If it stops for any reason (logged out, connection), just run it again - it continues where it left off. Later runs only read new collections; set `RECHECK = true` to re-read everything.

## Step 2 - Export the list (browser)

1. Paste `browser/2_hi_export_list.js` into the Console, press **Enter**.
2. Paste into **Notepad** and save as `hi_downloads.tsv` (Save as type: **All files**, Encoding: **UTF-8**), in your Heroes Infinite folder, next to the downloader (e.g. `Z:\3DPrints\HeroesInfinite`, see Step 3).

Columns: `collection`, `post`, `label`, `name`, `id`, `url`, `post_url`.

## Step 3 - One-time Linux setup

1. Install the tools (Debian/Ubuntu): `sudo apt install curl unzip` (and `unrar` or `7zip` if you get .rar files).
2. Make your **Heroes Infinite folder** and put the downloader in it. The files are downloaded into the folder the script is in. These examples use `/mnt/nas/3DPrints/HeroesInfinite`; use your own folder:

   ```bash
   mkdir -p /mnt/nas/3DPrints/HeroesInfinite
   cp 3_hi_download.sh /mnt/nas/3DPrints/HeroesInfinite/
   cd /mnt/nas/3DPrints/HeroesInfinite
   sed -i 's/\r$//' 3_hi_download.sh     # only needed if it was copied or edited on Windows
   ```

3. In that folder, create:
   - **`cookie.txt`** - from **heroesinfinite.com** (not MyMiniFactory): log in, open your library, F12 → **Network** → **Doc** → F5 → click the `library` request → **Headers** → **Request Headers** → right-click `cookie` → **Copy value**. Paste into the file, save, then `chmod 600 cookie.txt`.
   - **`user_agent.txt`** - run `navigator.userAgent` in the same browser's Console and paste the result.
4. Check the **SETTINGS** at the top of `3_hi_download.sh`:

   | Setting | Default | Meaning |
   |---|---|---|
   | `HI_DIR` | empty (the script's folder) | Where the files are stored; put a full path here to use another folder |
   | `ORGANIZE` | `"collection_post"` | `HI_DIR/<collection>/<post>/<file>`; `"collection"` puts all of a collection's files in one folder |
   | `DELAY_SECONDS` | `5` | Pause between files |
   | `MAX_DOWNLOADS` | `0` (no limit) | Set to `2` for your first test |
   | `SKIP_DOWNLOADED` | `1` | Skip files recorded as downloaded even if you've deleted them since (see below); `0` = download them again if they're gone |
   | `MARK_ALL_DOWNLOADED` | `0` | `1` = download nothing, just record everything in the list as downloaded (see below) |

## Step 4 - Download (Linux)

Save the export from Step 2 as `hi_downloads.tsv` in your Heroes Infinite folder, next to the downloader, then:

```bash
cd /mnt/nas/3DPrints/HeroesInfinite
bash 3_hi_download.sh
```

**First run:** set `MAX_DOWNLOADS=2`, run it, check where the two files landed, then set it back to `0`.

The links in the list **don't expire**, so there's no hurry - stop it any time (Ctrl+C) and run it again later; it continues where it left off. For each file it asks Heroes Infinite where the file is (that's where your cookie is used), then downloads it from Kajabi's file storage (your cookie is never sent there), tests zips, and records it in `HI_DIR/.hi_downloaded.tsv` so it's skipped on later runs.

| Line | Meaning |
|---|---|
| `✓ name` | Already downloaded, skipped |
| `↓ Downloading ... -> path` then `✓ DOWNLOADED` | Downloaded (and tested, for archives) |
| `HTTP 404 (download removed from the site)` | That file no longer exists on Heroes Infinite |
| `Downloaded file is damaged` | Deleted again; retried next run |
| `Stopping downloads: redirected to the login page` | Your cookie expired - save a fresh `cookie.txt` and rerun |

Files it writes in the folder you ran it from: `hi_missing.tsv` (still missing, same format as the list) and `hi_failed.txt` (failures and why).

If two different downloads in one folder have the same filename, the second is kept as `name_<id>.zip` instead of overwriting the first. Characters Windows doesn't allow in names (`: ? *` etc.) are replaced with `_`.

## New collections later

Run the collector again (Step 1) - it only reads new collections - then export (Step 2) and run the downloader (Step 4). Everything already downloaded is skipped.

## Deleting the files after extracting

You don't have to keep the downloaded files. Every finished file is recorded in **`.hi_downloaded.tsv`** in your Heroes Infinite folder, and with `SKIP_DOWNLOADED=1` (the default) a recorded file is never downloaded again, even after you've extracted it, imported it into your model manager and deleted it. **Keep `.hi_downloaded.tsv`** - it's what remembers what you have.

- Files that are already in the folder but not recorded yet (for example copied in by hand) are recorded when the downloader next reaches them. Run it **once before deleting** such files.
- **Already deleted everything you had?** Collect and export as usual (Step 1-2), set `MARK_ALL_DOWNLOADED=1`, and run the downloader once: it downloads nothing (no cookie needed) and records every file in the list as downloaded. Set it back to `0`. From then on only files that weren't in that list - new collections and new posts - are downloaded. Only do this with a list that contains just what you already have.
- **Want one file again?** Delete its line from `.hi_downloaded.tsv` (the first column is the download id from the list) and rerun. To get back everything that's no longer in the folder, set `SKIP_DOWNLOADED=0`.

## Troubleshooting

| Message | What to do |
|---|---|
| Collector: `Open your library page first` | Run it on heroesinfinite.com/library |
| Collector: `redirected to the login page` | Log in again and rerun - it continues where it stopped |
| Collector: `Browser storage is full` | Export what you have (Step 2); the library is too large for browser storage |
| Downloader: `List file not found` | Save the export as `hi_downloads.tsv` in your Heroes Infinite folder, next to the downloader |
| Downloader: `No cookie set` | Create `cookie.txt` next to the script (Step 3) |
| Downloader: `blocked by Cloudflare bot check` | Make sure `user_agent.txt` matches the browser the cookie came from |
| `cannot execute: required file not found` | Windows line endings: `sed -i 's/\r$//' 3_hi_download.sh` |
