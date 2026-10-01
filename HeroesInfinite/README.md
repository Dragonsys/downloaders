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
2. Press **F12** → **Console** (first time: type `allow pasting`, Enter).
3. Open `browser/1_hi_collect_downloads.js` in Notepad.
   - **First time:** set `MAX_PRODUCTS = 1` for a short test.
   - Then set it back to `0` and run again for everything.
4. Copy the whole file, paste into the Console, press **Enter**.
5. It prints the library pages, each collection with its number of posts, then each post with its number of downloads, and ends with **DONE**.

Roughly 1-2 minutes per collection (1.5 s pause between pages). If it stops for any reason (logged out, connection), just run it again - it continues where it left off. Later runs only read new collections; set `RECHECK = true` to re-read everything.

## Step 2 - Export the list (browser)

1. Paste `browser/2_hi_export_list.js` into the Console, press **Enter**.
2. Paste into **Notepad** and save as `hi_downloads.tsv` (Save as type: **All files**, Encoding: **UTF-8**), e.g. in the working folder `%PRINTS_DIR%\.hi_downloads\` (see Step 3).

Columns: `collection`, `post`, `label`, `name`, `id`, `url`, `post_url`.

## Step 3 - One-time Linux setup

1. Install the tools (Debian/Ubuntu): `sudo apt install curl unzip` (and `unrar` or `7zip` if you get .rar files).
2. Make a working folder and put the downloader in it:

   ```bash
   mkdir -p "$PRINTS_DIR/.hi_downloads"
   cp 3_hi_download.sh "$PRINTS_DIR/.hi_downloads/"
   cd "$PRINTS_DIR/.hi_downloads"
   sed -i 's/\r$//' 3_hi_download.sh     # only needed if it was copied or edited on Windows
   ```

3. In that folder, create:
   - **`cookie.txt`** - from **heroesinfinite.com** (not MyMiniFactory): log in, open your library, F12 → **Network** → **Doc** → F5 → click the `library` request → **Headers** → **Request Headers** → right-click `cookie` → **Copy value**. Paste into the file, save, then `chmod 600 cookie.txt`.
   - **`user_agent.txt`** - run `navigator.userAgent` in the same browser's Console and paste the result.
4. Check the **SETTINGS** at the top of `3_hi_download.sh`:

   | Setting | Default | Meaning |
   |---|---|---|
   | `HI_DIR` | `$PRINTS_DIR/HeroesInfinite` | Where the files are stored |
   | `ORGANIZE` | `"collection_post"` | `HI_DIR/<collection>/<post>/<file>`; `"collection"` puts all of a collection's files in one folder |
   | `DELAY_SECONDS` | `5` | Pause between files |
   | `MAX_DOWNLOADS` | `0` (no limit) | Set to `2` for your first test |

## Step 4 - Download (Linux)

Save the export from Step 2 as `hi_downloads.tsv` in the working folder (`%PRINTS_DIR%\.hi_downloads\` on Windows), then:

```bash
cd "$PRINTS_DIR/.hi_downloads"
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

Files it writes in the working folder: `hi_missing.tsv` (still missing, same format as the list) and `hi_failed.txt` (failures and why).

If two different downloads in one folder have the same filename, the second is kept as `name_<id>.zip` instead of overwriting the first. Characters Windows doesn't allow in names (`: ? *` etc.) are replaced with `_`.

## New collections later

Run the collector again (Step 1) - it only reads new collections - then export (Step 2) and run the downloader (Step 4). Everything already downloaded is skipped.

## Troubleshooting

| Message | What to do |
|---|---|
| Collector: `Open your library page first` | Run it on heroesinfinite.com/library |
| Collector: `redirected to the login page` | Log in again and rerun - it continues where it stopped |
| Collector: `Browser storage is full` | Export what you have (Step 2); the library is too large for browser storage |
| Downloader: `List file not found` | Save the export as `hi_downloads.tsv` in the working folder |
| Downloader: `No cookie set` | Create `cookie.txt` next to the script (Step 3) |
| Downloader: `blocked by Cloudflare bot check` | Make sure `user_agent.txt` matches the browser the cookie came from |
| `cannot execute: required file not found` | Windows line endings: `sed -i 's/\r$//' 3_hi_download.sh` |
