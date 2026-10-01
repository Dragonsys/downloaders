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

2. Make your **Loot Studios folder** and put the downloader in it. The bundles are downloaded into the folder the script is in. These examples use `/mnt/nas/3DPrints/LootStudios`; use your own folder:

   ```bash
   mkdir -p /mnt/nas/3DPrints/LootStudios
   cp 3_loot_download_all_bundles.sh /mnt/nas/3DPrints/LootStudios/
   ```

   If it's a network share that your Windows PC also sees (for example as `Z:\3DPrints\LootStudios`), you can save the list there straight from the browser.

3. Open `3_loot_download_all_bundles.sh` in a text editor and check the **SETTINGS** at the top:

   | Setting | Default | Meaning |
   |---|---|---|
   | `LOOT_DIR` | empty (the script's folder) | Where the bundles are stored; put a full path here to use another folder |
   | `ORGANIZE` | `"folder"` | `"folder"` → `FaewoodHaven/All_FaewoodHaven_Bust.zip`; `"bundle"` → `Faewood Haven/...` |
   | `MATERIALS` | empty (all) | e.g. `"resin"` to skip FDM versions |
   | `SCALES` | empty (all) | e.g. `"32mm bust"` to skip 75mm |
   | `DELAY_SECONDS` | `5` | Pause between downloads |
   | `MAX_DOWNLOADS` | `0` (no limit) | Set to `2` for your first test |
   | `SKIP_DOWNLOADED` | `1` | Skip files recorded as downloaded even if you've deleted them since (see below); `0` = download them again if they're gone |
   | `MARK_ALL_DOWNLOADED` | `0` | `1` = download nothing, just record everything in the list as downloaded (see below) |

### In your browser

Do this once (Chrome remembers it):

1. Open the Console (F12), type `allow pasting`, press Enter.
2. Hide the Console "noise" - red errors and warnings from the site's own scripts and from the bundle pages the collector opens in the background: click the **gear icon** (⚙) at the top right of the Console panel, tick **Hide network** and **Selected context only**, and click the gear again. The dropdown at the top left of the Console must show **top**. Details: [Hide the Console "noise"](../README.md#hide-the-console-noise).

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

   The same progress appears in a **status panel at the bottom right of the page**, so you can close DevTools once it has started (the ✕ only closes the panel; the collector keeps running).

   Red errors in the Console come from the bundle pages' own tracking scripts - they're normal and harmless. If you see them, do step 2 of [In your browser](#in-your-browser) (gear icon → **Hide network** + **Selected context only**).

8. Repeat steps 2-7 for **Sci-Fi**, **Valhalla** and **Nidavellir**. Everything goes into the same list.

Keep the tab open while it runs (you can use other tabs). If it stops early, the summary says why (see Troubleshooting).

### Step 2 - Export the list (browser)

1. In the Console, paste `browser/2_loot_export_list.js` and press **Enter**. It says `Copied N rows.`
2. Open **Notepad**, paste (**Ctrl+V**).
3. **File → Save as**:
   - Folder: your Loot Studios folder, next to the downloader (e.g. `Z:\3DPrints\LootStudios`, or copy the file there afterwards)
   - File name: `loot_all_bundles.tsv`
   - Save as type: **All files**
   - Encoding: **UTF-8**
4. Replace the old file if asked.

### Step 3 - Download (Linux, straight away)

```bash
cd /mnt/nas/3DPrints/LootStudios
bash 3_loot_download_all_bundles.sh
```

For each file you'll see one of:

| Line | Meaning |
|---|---|
| `✓ name` | Already downloaded, skipped |
| `↓ Downloading ...` then `✓ DOWNLOADED` | Downloaded and tested OK |
| `⏱ LINK EXPIRED` | The link is too old; it will be fetched next round |
| `✗ Download failed` / `damaged` | Didn't work; the reason is in `loot_failed.txt` |

At the end there's a summary. Files it creates in the folder you ran it from:

- `loot_missing.tsv` - everything still missing (same format as the list)
- `loot_failed.txt` - failures and why
- `loot_expired.txt` - bundles whose links need refreshing
- `loot_done_bundles.js` - the bundles that are completely downloaded (see Step 4)

**First run:** set `MAX_DOWNLOADS=2`, run it, and check the two files landed where you want. Then set it back to `0`.

### Step 4 - Repeat until done

If the summary shows **Expired links** or downloads stopped because links expired, do another round: Step 1 → Step 2 → Step 3. Finished files are skipped, so each round only fetches what's left. When it prints **"Everything in the list is downloaded"**, you're done.

**New bundles later?** Just do another round. Bundles already downloaded are skipped, so only the new ones are downloaded.

**Make the collector skip finished bundles (optional, saves time):** the collector normally re-reads every bundle whose links have expired, about 10 seconds each. Before Step 1, open `loot_done_bundles.js` (written by the downloader) in Notepad, paste it into the Console on app.lootstudios.com and press Enter. The collector then skips those bundles ("already downloaded"). Only bundles whose files have **all** been downloaded are in that file, so a bundle that still needs fresh links is never skipped. Paste the newest copy each time; if you don't, the collector just reads more bundles than it needs to.

---

## Deleting the zips after extracting

You don't have to keep the downloaded zips. Every finished file is recorded in **`.loot_downloaded.tsv`** in your Loot Studios folder, and with `SKIP_DOWNLOADED=1` (the default) a recorded file is never downloaded again, even after you've extracted it, imported it into your model manager and deleted the zip. **Keep `.loot_downloaded.tsv`** - it's what remembers what you have.

- Files already in the folder are recorded the first time the downloader runs. So run the downloader **once before deleting** zips you downloaded before this feature existed.
- **Already deleted everything you had?** Collect and export as usual (Step 1-2), set `MARK_ALL_DOWNLOADED=1`, and run the downloader once: it downloads nothing and records every file in the list as downloaded. Set it back to `0`. From then on only bundles that weren't in that list are downloaded. Only do this with a list that contains just what you already have.
- **Want one file again?** Delete its line from `.loot_downloaded.tsv` and do a round. To get back everything that's no longer in the folder, set `SKIP_DOWNLOADED=0`.

---

## Optional: extract the zips

The MyMiniFactory extract script works for these too. In `MyMiniFactory/windows/99_mmf_extract_all_zips.ps1`, set:

```powershell
$BASE_PATH = 'Z:\3DPrints\LootStudios'   # your Loot Studios folder
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
| Collector: `no All Bundle downloads` | That bundle has no All Bundle section (yet). It's checked again after 24 hours (`NO_ALL_RECHECK_HOURS`), so new purchases and releases are picked up once the section appears; set it to `0` to check every run. Download it by hand if it never gets one |
| Downloader: `List file not found` | Save the export as `loot_all_bundles.tsv` in your Loot Studios folder, next to the downloader (Step 2) |
| Downloader: `The list has no 'url' column` | Re-export with `2_loot_export_list.js` and save with "All files", not ".txt" |
| Downloader: `3 refused downloads in a row` | Links expired - do another round |
| Downloader: `HTTP 403` on one bundle every round | You may not have access to that bundle (check in the browser) |
| Downloader: `zip test failed` | The download was damaged; it was deleted and will be retried next round |

To start over completely, paste `browser/99_loot_reset.js` into the Console.
