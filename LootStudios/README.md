# Loot Studios - bundle downloader

Downloads, for every bundle you own, straight to your storage (e.g. a NAS):

- the **All Bundle** archives (for example `All_FaewoodHaven_32mm.zip`, `..._75mm.zip`, `..._Bust.zip`);
- the **individual figure files** wherever there's no All Bundle archive - for a bundle that has no All Bundle at all, or for a scale or material it doesn't cover (e.g. FDM files when the All Bundle is resin only);
- the **extra contents**: magazine, digital magazine and statblocks;
- each figure's **images**: the render and, where one exists, the painted version (resin and FDM).

Each bundle gets one folder: the All Bundle archives and extras at the top, individual figure files in a subfolder per group (`Heroes`, `Enemies`, `Bust`, ...), and images in `Images/<group>/`, named after the figure (`Awyn, Arcane Investigator - painted resin.jpg`). Bundles that are shown on the site but aren't in your account are skipped.

It works in two halves:

1. **In your browser:** a script visits your bundle pages and collects the download links.
2. **On Linux:** a script downloads every file that isn't downloaded yet, and tests each zip.

> **The download links expire about one hour after they are collected.** So you always collect, export, and start downloading in one go. If the downloads take longer than an hour, you simply do another round; finished files are always skipped.

## Files

| File | Where | Purpose |
|---|---|---|
| `browser/1_loot_collect_all_bundles.js` | Browser Console | Collects the download links (All Bundle, individual files, extras) from all bundles on a My Loots page |
| `browser/2_loot_export_list.js` | Browser Console | Copies the collected list to the clipboard |
| `linux/3_loot_download_all_bundles.sh` | Linux | Checks what's already downloaded and downloads what's missing |
| `browser/99_loot_reset.js` | Browser Console | Forgets everything collected (only if you want to start fresh) |
| `linux/99_loot_extract_all.sh` | Linux | Optional: extracts the zips and sorts them into `<group>/<model>/images/` and `<group>/<model>/files/<scale>/<type>/`, FDM files into `<model>-FDM` (see below) |
| `linux/99_loot_fix_extracted.sh` | Linux | One-off: re-sorts models extracted by earlier versions of the extract script into the current layout, pictures included (see below) |
| `linux/99_loot_fix_folders.sh` | Linux | Moves downloads that ended up outside their bundle's folder (e.g. in `Fantasy/` or `FreeMini/`) into it (see below) |

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
   | `FOLDER_STRUCTURE` | `"BUNDLE_FOLDER"` | How the bundle folders are named - the options are listed in the script: `"BUNDLE_FOLDER"` → `FaewoodHaven/All_FaewoodHaven_Bust.zip` (name from the download link); `"BUNDLE_TITLE"` → `Faewood Haven/...` (title on the site). Set the same in `99_loot_fix_folders.sh`, which moves existing bundles over |
   | `MATERIALS` | empty (all) | e.g. `"resin"` to skip FDM versions |
   | `SCALES` | empty (all) | e.g. `"32mm bust"` to skip 75mm (scales on the site: `32mm`, `75mm`, `bust`, `other`) |
   | `INDIVIDUAL` | `1` | Individual figure files where there's no All Bundle archive; `0` = All Bundle archives only |
   | `VARIANTS` | empty (all) | Individual files: only these kinds, e.g. `"hollow"` (`all`, `hollow`, `solid`, `slicer`, `unsupported`) |
   | `EXTRAS` | `1` | Magazine, digital magazine and statblocks; `0` = skip them |
   | `IMAGES` | `1` | Figure images; `0` = skip them |
   | `IMAGE_TYPES` | empty (all) | Only these images, e.g. `"painted"` (`render`, `painted`) |
   | `IMAGE_DELAY_SECONDS` | `1` | Pause between images (they're small) |
   | `UNAVAILABLE_RECHECK_DAYS` | `30` | Images and magazines the site doesn't have are looked for again after this many days |
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

### Step 1 - Collect the links (browser, ~10-15 seconds per bundle)

1. Log in at **app.lootstudios.com**.
2. Hover **My Loots** and open **Fantasy**.
3. **Scroll to the bottom** of the list so every bundle is loaded.
4. Press **F12**, open the **Console** tab.
5. Open `browser/1_loot_collect_all_bundles.js` in Notepad and check the settings at the top:
   - **Very first time ever:** set `MAX_PAGES = 3` for a short test, check the output, then set it back to `0` and run again for the rest.
   - Otherwise leave the settings alone. The collector automatically re-reads every bundle whose saved links have expired (or expire within 10 minutes) and skips bundles whose links are still fresh, so each round gets fresh links by itself. (`RESCAN = true` forces it to re-read everything.)
6. Copy the whole file, paste it into the Console, press **Enter**.
7. Wait for the line starting with **DONE**. Progress lines look like:
   `[12/86] Faewood Haven: All Bundle 32mm resin, 75mm resin, bust resin + 1 individual file(s) (not in the All Bundle: 32mm fdm) + Magazine, Statblocks`

   Bundles that appear on the page but aren't in your account (for example a new release shown at the top) are listed as `not in your account - skipped`.

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

You don't have to keep the downloaded zips. Every finished file is recorded in **`.loot_downloaded.tsv`** in your Loot Studios folder, and with `SKIP_DOWNLOADED=1` (the default) a recorded file is never downloaded again, even after you've extracted it, imported it into your model manager and deleted the zip. **Keep `.loot_downloaded.tsv`** - it's what remembers what you have. (`.loot_unavailable.tsv` next to it lists images and magazines the site doesn't have; deleting it only means they're looked for once more.)

- Files already in the folder are recorded the first time the downloader runs. So run the downloader **once before deleting** zips you downloaded before this feature existed.
- **Already deleted everything you had?** Collect and export as usual (Step 1-2), set `MARK_ALL_DOWNLOADED=1`, and run the downloader once: it downloads nothing and records every file in the list as downloaded. Set it back to `0`. From then on only bundles that weren't in that list are downloaded. Only do this with a list that contains just what you already have.
- **Want one file again?** Delete its line from `.loot_downloaded.tsv` and do a round. To get back everything that's no longer in the folder, set `SKIP_DOWNLOADED=0`.

---

## Optional: extract and sort the zips (Linux)

Copy `linux/99_loot_extract_all.sh` next to the downloader and run it:

```bash
cd /mnt/nas/3DPrints/LootStudios
bash 99_loot_extract_all.sh
```

A Loot Studios zip holds a whole bundle at one scale, in folders like `All_ShadowCourt_32mm_LYCHEE/2-Enemies/DeathGiant_32mm_LYCHEE/`. The script extracts every zip and **sorts it by model while extracting**, inside the bundle's folder:

```
ShadowCourt/
├── Enemies/
│   ├── DeathGiant/
│   │   ├── images/                     the model's pictures (each kept once)
│   │   └── files/
│   │       ├── 32mm/                   from All_ShadowCourt_32mm.zip
│   │       │   ├── lychee/
│   │       │   ├── supported/
│   │       │   └── unsupported/
│   │       ├── 75mm/                   from All_ShadowCourt_75mm.zip
│   │       │   └── lychee/  supported/  unsupported/
│   │       └── bust/                   from All_ShadowCourt_Bust.zip
│   │           └── lychee/  supported/  unsupported/
│   └── DeathGiant-FDM/                 from ShadowCourt_All_FDM.zip
│       ├── images/
│       └── files/
│           └── 32mm/
│               ├── 3mf/
│               └── unsupported/
├── Heroes/ ...
├── Environment/ ...
└── Prop/
    └── RoyalSeal/
        ├── images/
        └── files/prop/lychee/
```

- **Type** (from the end of the model's folder name): `LYCHEE` / `Supported_LYCHEE` / `Supported_SLICER` → `lychee`, `ReadyToSlice` / `Supported` → `supported`, `Supported_Hollow` → `hollow`, `Supported_Solid` → `solid` (older bundles have both), `UnSupported` / `NoSupports` → `unsupported`, `Supported_CHITUBOX` → `chitubox`, `3mf` → `3mf`. Typos seen in real zips (`LYHCEE`, `UnSuppoted`, `ReadyToSlicer` ...) are understood.
- **FDM** files get their own model folder, `<Model>-FDM/` (with its own `images/` and `files/<scale>/<type>/`): `3mf` files, Loot's FDM STLs (`..._FDM`, which go to `unsupported`), and everything from a zip or folder with "FDM" in its name (`ShadowCourt_All_FDM.zip`) or that the downloader fetched as FDM.
- **Scale**: `32mm`, `75mm`, `bust`, `prop` ... from the folder names, or else the zip's name.
- **Group** (`Heroes`, `Enemies`, `Environment`, `Prop`, `NPCs` ...) from the folders above the model, in every spelling Loot has used (`1-Heroes`, `All_Enemies_CelticDawn_32mm`, `All_75mm_Heroes_Supported_Solid` ...). `Prop`/`Props` or `Enviroment`/`Environment` end up in one folder. **Busts** usually come without a group: a bust goes to the group its model has in the bundle's other zips, otherwise to `Busts/`. Single-figure downloads use the group folder the downloader put them in.
- **Pictures** in the zips go to their model's `images/`. The downloader's pictures (`Images/<group>/`) move there too, matched by name: `Bell Head - render resin.png` → `BellHead/images/`, a `... – Bust` picture to the same model, `... fdm` pictures to `<Model>-FDM/images/` if there is one (`MOVE_IMAGES=1`). Pictures that match no model go to `<group>/images/`.
- Models made of parts in subfolders keep them (`Megalodon/files/32mm/lychee/SharkTail/`). Zips inside zips are extracted too.
- `Thumbs.db`, `desktop.ini` and Loot's "Read me" notes are left out (`KEEP_READMES=1` keeps the notes).
- Zips without model folders (statblocks, GM screen, tools) are extracted into `<bundle>/<zip name>/`, as they are.
- Nothing is ever overwritten. If a different file with the same name is already there, the new one goes to `<bundle>/<zip name>/` instead, and the zip isn't deleted. What was extracted is remembered in `.loot_extracted.tsv`, so each zip is extracted only once - even after you've deleted it.

It starts as a **dry run**: it only reads the zips' tables of contents (quick, even on a NAS), shows a few model folders per zip and writes the full plan - every folder in every zip and where it would go - to `loot_extract_plan.tsv`. If that looks right, set `DRY_RUN=0` and run it again.

| Setting | Default | Meaning |
|---|---|---|
| `LOOT_DIR` | empty (the script's folder) | Where the bundles are (same as in `3_loot_download_all_bundles.sh`) |
| `BUSTS_GROUP` | `"Busts"` | Group folder for busts whose model isn't in another group of the bundle |
| `MOVE_IMAGES` | `1` | `0` = leave the downloader's `Images/` folder alone (otherwise its pictures move to their model's `images/`) |
| `KEEP_READMES` | `0` | `1` = keep Loot's "... - Read me.txt" notes |
| `DELETE_AFTER_EXTRACT` | `0` | `1` = delete each zip once it's extracted completely. Safe: the downloader remembers what it downloaded (see above) |
| `DRY_RUN` | `1` | `0` = actually extract, sort and delete |

### Already extracted with an earlier version?

Earlier versions of the script used other layouts. `linux/99_loot_fix_extracted.sh` moves what they made into the current one - no zips needed, it works on the extracted folders:

| Earlier | Now |
|---|---|
| `DeathGiant-lychee/32mm/` (also `-supported`, `-hollow`, `-solid`, `-chitubox`, `-unsupported`) | `DeathGiant/files/32mm/lychee/` |
| `DeathGiant-3mf/32mm/` | `DeathGiant-FDM/files/32mm/3mf/` |
| `DeathGiant-fdm/32mm/` | `DeathGiant-FDM/files/32mm/unsupported/` |
| FDM files in `DeathGiant-unsupported/32mm/` (`..._FDM.stl`, from the FDM zips) | `DeathGiant-FDM/files/32mm/unsupported/` |
| `DeathGiant/32mm/lychee/` | `DeathGiant/files/32mm/lychee/` |
| pictures in `<group>/images/` and the downloader's `Images/<group>/` | `DeathGiant/images/` (matched by name, as above); pictures that match no model stay in / go to `<group>/images/` |

```bash
cd /mnt/nas/3DPrints/LootStudios
bash 99_loot_fix_extracted.sh
```

It starts as a **dry run** and lists every folder it would move; set `DRY_RUN=0` and run it again to move them. Nothing is overwritten: a file whose new place already holds a different file with the same name stays where it is and is listed in `loot_fix_extracted_problems.txt`. Running it again is harmless. (Two FDM files in Rise of Draconians - Izatal's wings - don't have "FDM" in their name, so they stay with the resin `unsupported` files.)

Damaged zips are kept and listed in `loot_failed_archives.txt`; they're tried again on the next run. Your model manager may want a different layout - the folder names come from a few rules near the top of the script (`TYPE_RULES`), easy to change.

---

## Fix the folders: downloads outside their bundle's folder

A bundle's folder is named after its download links, and Loot Studios has changed those over time. So some files can end up outside their bundle's own folder:

- Older versions of the downloader named newer bundles' folder after the first part of `new-dls.loot-studios.com/Fantasy/ShadowCourt/...`, so the All Bundle archives of **all** newer bundles ended up together in one `Fantasy` folder (or `SciFi`, ...).
- Some bundles moved from `old-dls.loot-studios.com/FreeMini/...` to their own link folder. Files downloaded before that are in `FreeMini/` (e.g. `FreeMini/All_AedanValiantShield_32mm.zip`), while everything downloaded later - the pictures, say - is in `AedanValiantShield/`. The downloader remembers the zips as downloaded, so it doesn't fetch them again and nothing is reported.

`99_loot_fix_folders.sh` compares, for every file in your list, where `.loot_downloaded.tsv` says it is with where the downloader puts it now, and moves what's in the wrong place:

1. Collect and export as usual (Step 1-2), so `loot_all_bundles.tsv` lists your bundles.
2. Copy `linux/99_loot_fix_folders.sh` next to the downloader and run it:

   ```bash
   cd /mnt/nas/3DPrints/LootStudios
   bash 99_loot_fix_folders.sh
   ```

   It starts as a **dry run** and only shows what it would move (`FreeMini/All_AedanValiantShield_32mm.zip => AedanValiantShield/All_AedanValiantShield_32mm.zip`).
3. If that looks right, open the script, set `DRY_RUN=0`, and run it again. It moves the files, updates their paths in `.loot_downloaded.tsv` (the old one is kept as `.loot_downloaded.tsv.bak`), and removes old folders once they're empty.

Set `FOLDER_STRUCTURE` in it the same as in the downloader. To switch an existing collection from one structure to the other, change it in both and run this script: it moves every bundle to its new folder name.

Files you've already extracted and deleted are only updated in `.loot_downloaded.tsv`. If two bundles have an archive with the **same name** (e.g. `All_32mm.zip`) in a shared folder, they overwrote each other; the script leaves that file alone and lists it - delete it and its lines in `.loot_downloaded.tsv` to download both again. Running the script again is harmless.

---

## Troubleshooting

| Message | What to do |
|---|---|
| Collector: `Found 0 bundle link(s)` | You're not on a My Loots list page, or it hasn't loaded - scroll to the bottom and rerun |
| Collector: `Nothing to do` | Every bundle on this page already has fresh links - export and download |
| Collector: `redirected to the login page` | Log in again and rerun |
| Collector: `does not allow its pages to be opened in a frame` | The site changed how it works - the collector needs updating |
| Collector: `no bundle data after 45s` | The page loaded slowly; it's retried on the next run. If it happens for every bundle, the site changed |
| Collector: `not in your account - skipped` | The bundle is shown on the page but you don't own it, so there's nothing to download. It's checked again after 24 hours (`RECHECK_HOURS`), in case you buy it |
| Collector: `no downloads on the page` | The bundle page has no download links at all (yet). Checked again after 24 hours (`RECHECK_HOURS`; `0` = every run) |
| Downloader: `- not on the site (HTTP 404)` | The site doesn't have that file. For images that's normal: the site only guesses image addresses, and many figures have no painted or no FDM image. For magazines/statblocks the link on the bundle page is broken (the button in the browser fails too). It's remembered in `.loot_unavailable.tsv`, counted as done, and looked for again after `UNAVAILABLE_RECHECK_DAYS` (30); nothing to do. Delete a line from that file to try it again sooner |
| Downloader: `List file not found` | Save the export as `loot_all_bundles.tsv` in your Loot Studios folder, next to the downloader (Step 2) |
| Downloader: `The list has no 'url' column` | Re-export with `2_loot_export_list.js` and save with "All files", not ".txt" |
| Downloader: `3 refused downloads in a row` | Links expired - do another round |
| Downloader: `HTTP 403` on one bundle every round | You may not have access to that bundle (check in the browser) |
| Downloader: `zip test failed` | The download was damaged; it was deleted and will be retried next round |

To start over completely, paste `browser/99_loot_reset.js` into the Console.
