# Loot Studios - All Bundle downloader

Downloads the **All Bundle** archives (for example `All_FaewoodHaven_32mm.zip`, `..._75mm.zip`, `..._Bust.zip`) for every bundle you own, straight to your storage (e.g. a NAS).

It works in two halves:

1. **In your browser:** a script visits your bundle pages and collects the download links.
2. **On Linux:** a script downloads every file that isn't downloaded yet, and tests each zip.

> **The download links expire about one hour after they are collected.** So you always collect, export, and start downloading in one go. If the downloads take longer than an hour, you simply do another round; finished files are always skipped.

## Files

| File | Where | Purpose |
|---|---|---|
| `browser/1_loot_collect_all_bundles.js` | Browser Console | Collects the All Bundle links from all bundles on a My Loots page |
| `browser/2_loot_export_list.js` | Browser Console | Copies the collected list to the clipboard |
| `linux/3_loot_download_all_bundles.sh` | Linux | Checks what's already downloaded and downloads what's missing |
| `browser/99_loot_reset.js` | Browser Console | Forgets everything collected (only if you want to start fresh) |

---

## One-time setup

### On Linux

1. Install the tools (Debian/Ubuntu):

   ```bash
   sudo apt install curl unzip
   ```

   For `.rar` files, also `sudo apt install unrar` (or `7zip`) so they can be tested.

2. Create a working folder and put the downloader in it:

   ```bash
   mkdir -p "$PRINTS_DIR/.loot_downloads"
   cp 3_loot_download_all_bundles.sh "$PRINTS_DIR/.loot_downloads/"
   ```

   If `PRINTS_DIR` is a network share that your Windows PC also sees (for example as `%PRINTS_DIR%\.loot_downloads`), you can save the list there straight from the browser.

3. Open `3_loot_download_all_bundles.sh` in a text editor and check the **SETTINGS** at the top:

   | Setting | Default | Meaning |
   |---|---|---|
   | `LOOT_DIR` | `$PRINTS_DIR/LootStudios` | Where the bundles are stored |
   | `ORGANIZE` | `"folder"` | `"folder"` → `FaewoodHaven/All_FaewoodHaven_Bust.zip`; `"bundle"` → `Faewood Haven/...` |
   | `MATERIALS` | empty (all) | e.g. `"resin"` to skip FDM versions |
   | `SCALES` | empty (all) | e.g. `"32mm bust"` to skip 75mm |
   | `DELAY_SECONDS` | `5` | Pause between downloads |
   | `MAX_DOWNLOADS` | `0` (no limit) | Set to `2` for your first test |

### In your browser

Do this once: open the Console (F12), type `allow pasting`, press Enter.

---

## Each round (collect → export → download)

### Step 1 - Collect the links (browser, ~10 seconds per bundle)

1. Log in at **app.lootstudios.com**.
2. Hover **My Loots** and open **Fantasy**.
3. **Scroll to the bottom** of the list so every bundle is loaded.
4. Press **F12**, open the **Console** tab.
5. Open `browser/1_loot_collect_all_bundles.js` in Notepad and check the settings at the top:
   - **Very first time ever:** set `MAX_PAGES = 3` for a short test, check the output, then set it back to `0` and run again for the rest.
   - Otherwise leave the settings alone. The collector automatically re-reads every bundle whose saved links have expired (or expire within 10 minutes) and skips bundles whose links are still fresh, so each round gets fresh links by itself. (`RESCAN = true` forces it to re-read everything.)
6. Copy the whole file, paste it into the Console, press **Enter**.
7. Wait for the line starting with **DONE**. Progress lines look like:
   `[12/86] Faewood Haven: 32mm resin, 75mm resin, bust resin`

   The Console also fills with red errors from the bundle pages' own tracking scripts - those are normal. To see only the collector, type this in the Console's **Filter** box:

   ```
   /^\[\d+\/\d+\]|^DONE|^Found|^This will|STOPPED/
   ```

8. Repeat steps 2-7 for **Sci-Fi**, **Valhalla** and **Nidavellir**. Everything goes into the same list.

Keep the tab open while it runs (you can use other tabs). If it stops early, the summary says why (see Troubleshooting).

### Step 2 - Export the list (browser)

1. In the Console, paste `browser/2_loot_export_list.js` and press **Enter**. It says `Copied N rows.`
2. Open **Notepad**, paste (**Ctrl+V**).
3. **File → Save as**:
   - Folder: the working folder (`%PRINTS_DIR%\.loot_downloads`, or copy the file there afterwards)
   - File name: `loot_all_bundles.tsv`
   - Save as type: **All files**
   - Encoding: **UTF-8**
4. Replace the old file if asked.

### Step 3 - Download (Linux, straight away)

```bash
cd "$PRINTS_DIR/.loot_downloads"
bash 3_loot_download_all_bundles.sh
```

For each file you'll see one of:

| Line | Meaning |
|---|---|
| `✓ name` | Already downloaded, skipped |
| `↓ Downloading ...` then `✓ DOWNLOADED` | Downloaded and tested OK |
| `⏱ LINK EXPIRED` | The link is too old; it will be fetched next round |
| `✗ Download failed` / `damaged` | Didn't work; the reason is in `loot_failed.txt` |

At the end there's a summary. Files it creates in the working folder:

- `loot_missing.tsv` - everything still missing (same format as the list)
- `loot_failed.txt` - failures and why
- `loot_expired.txt` - bundles whose links need refreshing

**First run:** set `MAX_DOWNLOADS=2`, run it, and check the two files landed where you want. Then set it back to `0`.

### Step 4 - Repeat until done

If the summary shows **Expired links** or downloads stopped because links expired, do another round: Step 1 → Step 2 → Step 3. Finished files are skipped, so each round only fetches what's left. When it prints **"Everything in the list is downloaded"**, you're done.

**New bundles later?** Just do another round. Bundles already downloaded are skipped, so only the new ones are downloaded.

---

## Optional: extract the zips

The MyMiniFactory extract script works for these too. In `MyMiniFactory/windows/99_mmf_extract_all_zips.ps1`, set:

```powershell
$BASE_PATH = Join-Path $PRINTS_DIR 'LootStudios'
```

and run it (see the MyMiniFactory guide, step 8). Each zip is extracted into its own `..._extracted` folder; keep the zips so the downloader still sees them as present.

---

## Troubleshooting

| Message | What to do |
|---|---|
| Collector: `Found 0 bundle link(s)` | You're not on a My Loots list page, or it hasn't loaded - scroll to the bottom and rerun |
| Collector: `Nothing to do` | Every bundle on this page already has fresh links - export and download |
| Collector: `redirected to the login page` | Log in again and rerun |
| Collector: `does not allow its pages to be opened in a frame` | The site changed how it works - the collector needs updating |
| Collector: `no bundle data after 45s` | The page loaded slowly; it's retried on the next run. If it happens for every bundle, the site changed |
| Collector: `no All Bundle downloads` | That bundle has no All Bundle section; download it by hand if needed |
| Downloader: `List file not found` | Save the export as `loot_all_bundles.tsv` in the working folder (Step 2) |
| Downloader: `The list has no 'url' column` | Re-export with `2_loot_export_list.js` and save with "All files", not ".txt" |
| Downloader: `3 refused downloads in a row` | Links expired - do another round |
| Downloader: `HTTP 403` on one bundle every round | You may not have access to that bundle (check in the browser) |
| Downloader: `zip test failed` | The download was damaged; it was deleted and will be retried next round |

To start over completely, paste `browser/99_loot_reset.js` into the Console.
