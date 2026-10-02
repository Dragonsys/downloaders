# MyMiniFactory - library backup

Backs up the files from your MyMiniFactory library to your storage (e.g. a NAS).

MyMiniFactory blocks file downloads from scripts (Cloudflare bot check), so the **files themselves are downloaded in your browser**. The scripts do everything around that: find your models, fetch their file lists, work out what's missing, then fix names, move, check, extract and rename.

## Files

| Step | File | Runs on |
|---|---|---|
| 1 | `browser/1_mmf_collect_model_ids.js` | Browser Console |
| 2 | `linux/2_mmf_download_metadata.sh` | Linux |
| 2b | `browser/2_mmf_private_models.js` *(only for private models, see step 2)* | Browser Console |
| 3 | `linux/3_mmf_check_and_download.sh` | Linux |
| 4 | *(your browser's download manager)* | Windows |
| 5 | `windows/5_mmf_correct_filenames.ps1` | Windows |
| 6 | `windows/6_mmf_move_downloads.ps1` | Windows |
| 7 | `linux/3_mmf_check_and_download.sh` again (check) | Linux |
| 8 | `windows/99_mmf_extract_all_zips.ps1` *(optional)* | Windows |
| 9 | `windows/99_mmf_rename_folders_from_json.ps1` *(optional, always last)* | Windows |

---

## One-time setup

### On Linux

1. Install the tools (Debian/Ubuntu):

   ```bash
   sudo apt install curl jq
   ```

2. Make your **MyMiniFactory folder** and put the two Linux scripts in it. The scripts keep everything in the folder they're in (`downloads/` for the JSON, `models/` for the files). These examples use `/mnt/nas/3DPrints/MyMiniFactory`; use your own folder:

   ```bash
   mkdir -p /mnt/nas/3DPrints/MyMiniFactory/models
   cp 2_mmf_download_metadata.sh 3_mmf_check_and_download.sh /mnt/nas/3DPrints/MyMiniFactory/
   ```

   Pick a folder your Windows PC can see too (e.g. a NAS share mapped as `Z:`, so this is `Z:\3DPrints\MyMiniFactory`), since the Windows scripts work on the same files.

3. Create **`user_agent.txt`** in that folder: in the browser you use for MyMiniFactory, open the Console (F12), run `navigator.userAgent`, and paste the result into the file (quotes are fine).

4. Create **`cookie.txt`** in that folder:
   1. Log in at myminifactory.com and go to your **library**.
   2. Press **F12** → **Network** tab → click **Doc** → press **F5**.
   3. Click the request named **library** → **Headers** → **Request Headers**.
   4. Right-click the value of **cookie** → **Copy value**.
   5. Paste it into `cookie.txt` and save.

   Then protect it:

   ```bash
   chmod 600 /mnt/nas/3DPrints/MyMiniFactory/cookie.txt
   ```

   The cookie expires eventually; when step 2 starts failing, repeat this. If the browser updates to a new version, refresh `user_agent.txt` too.

### On Windows

1. Copy the `.ps1` files from the `windows` folder into the **same MyMiniFactory folder** as the Linux scripts (e.g. `Z:\3DPrints\MyMiniFactory`). They then find `downloads\` and `models\` by themselves.
2. Install **PowerShell 7** (recommended; `winget install Microsoft.PowerShell`) and optionally **7-Zip** (needed for `.rar`/`.7z`, faster for everything).
3. The folder settings at the top of each `.ps1` file are empty by default, which means:
   - `$DOWN_PATH` - where the download manager saves files: `%USERPROFILE%\Downloads\www.myminifactory.com\download`
   - `$JSON_PATH` - the `downloads` folder next to the script
   - `$MODELS_PATH` / `$FOLDERS_PATH` / `$BASE_PATH` - the `models` folder next to the script

   Only fill them in (with a full path, e.g. `$DOWN_PATH = 'D:\Downloads\mmf'`) if your folders are somewhere else, for example if you keep the scripts in a different folder. Use the same paths in every script.
4. How to run a script: open PowerShell in that folder and run, for example:

   ```powershell
   pwsh -ExecutionPolicy Bypass -File .\5_mmf_correct_filenames.ps1
   ```

   (Use `powershell` instead of `pwsh` if you don't have PowerShell 7.)

### In your browser

Do this once (Chrome remembers it):

1. Open the Console (F12), type `allow pasting`, press Enter.
2. Hide the Console "noise" - red errors and warnings from the site's own scripts that have nothing to do with ours: click the **gear icon** (⚙) at the top right of the Console panel, tick **Hide network** and **Selected context only**, and click the gear again. The dropdown at the top left of the Console must show **top**. Details: [Hide the Console "noise"](../README.md#hide-the-console-noise).

---

## Step by step

### Step 1 - Collect your model IDs (browser)

1. Go to **myminifactory.com/library** and turn on the **"not downloaded"** filter, so the library only shows items you haven't downloaded yet. That keeps the list short: fewer IDs here means fewer metadata requests in step 2 and fewer links in step 4.
   - Items you downloaded from MyMiniFactory earlier (e.g. by hand, to another PC) count as downloaded and won't show. For your **first complete backup**, clear the filter once to get everything; after that, keep it on.
2. **Scroll to the bottom** so every item is loaded.
3. Press **F12** → **Console**, paste `browser/1_mmf_collect_model_ids.js`, press **Enter**.
   It says `N model IDs copied to the clipboard`. (If the number is low, scroll further and run it again - it adds up.)
   The IDs are kept until you reload the page: if you change the filter, press **F5** before running the script again, or the IDs from before the change are included too.
4. Open **Notepad**, paste, and save as **`model_ids.txt`** in your MyMiniFactory folder (e.g. `Z:\3DPrints\MyMiniFactory`, or copy it there afterwards) (Save as type: **All files**).

### Step 2 - Download the metadata (Linux)

```bash
cd /mnt/nas/3DPrints/MyMiniFactory
bash 2_mmf_download_metadata.sh
```

This saves one `downloads/model_<id>.json` per model (3 seconds apart). Failed IDs go to `downloads/failed_ids.txt` with the server's reply in `error_<id>.txt`. To retry only those, copy `downloads/failed_ids.txt` over `model_ids.txt` and run it again.

| Result | Meaning |
|---|---|
| `HTTP 401` | Cookie not accepted - save a fresh `cookie.txt` |
| `HTTP 403` + "Just a moment" | Bot check - make sure `user_agent.txt` matches the browser the cookie came from |
| `FAILED (HTTP 404 - private or removed model)` | Usually a model the creator has made **private** or taken off sale - see below |
| `OK (private model - file list from private_models.json)` | Its file list came from `private_models.json` (see below) |
| `HTTP 429` | Too many requests - raise `DELAY_SECONDS` |

#### Private models (HTTP 404)

Models the creator has made private (or taken off sale) stay in your library, but MyMiniFactory's API answers 404 for them, and its bot check blocks scripts from the library's own data. So their file lists are read in your browser instead:

1. Open `browser/2_mmf_private_models.js` in Notepad and paste the IDs from `downloads/failed_ids.txt` between the backticks after `const IDS =`.
2. On **myminifactory.com/library** (logged in), paste the whole snippet into the Console (F12) and press **Enter**. It lists each model and its files and says `Copied file lists of N model(s)`.
3. Paste into **Notepad** and save as **`private_models.json`** next to `model_ids.txt` (Save as type: **All files**).
4. Copy `downloads/failed_ids.txt` over `model_ids.txt` and run `2_mmf_download_metadata.sh` again. The private models now show `OK (private model ...)`.

Then continue with step 3 as usual. Some older private models have one archive without an archive number; your download manager saves it as just `<model id>` (no `archive_id=` folder) - step 5 handles that. If an ID isn't found by the snippet either, the model was really removed.

### Step 3 - Find what's missing (Linux)

```bash
cd /mnt/nas/3DPrints/MyMiniFactory
bash 3_mmf_check_and_download.sh
```

It checks every file listed in the JSON against `models/model_<id>/` and writes:

- **`missing_downloads.txt`** - download links of everything missing
- **`report.html`** - open in a browser for a colour-coded overview
- **`all_filenames_by_model.txt`** - full text listing

(`DOWNLOAD_MISSING` is `0` because MyMiniFactory blocks script downloads. If that ever changes, setting it to `1` makes this script download the files itself, throttled, using `cookie.txt`/`user_agent.txt`.)

### Step 4 - Download the missing files (browser, Windows)

1. Open `missing_downloads.txt` from your MyMiniFactory folder on your PC (copy it over if Windows can't see that folder).
2. Load the links into your browser's **download manager** extension while logged in to MyMiniFactory.
3. Make it save into **`%USERPROFILE%\Downloads\www.myminifactory.com\download`** (the folder `5_mmf_correct_filenames.ps1` and `6_mmf_move_downloads.ps1` read; set `$DOWN_PATH` in both scripts if yours saves elsewhere), keeping the folder structure it creates from the links. 
4. Download **1-2 files at a time** to stay under the rate limit.

Items that show a **padlock** in your library may be unavailable to your account; those downloads fail in the browser too.

### Step 5 - Fix the filenames (Windows)

```powershell
pwsh -ExecutionPolicy Bypass -File .\5_mmf_correct_filenames.ps1
```

It starts as a **dry run** and only shows what it would rename. If that looks right, open the script, set `$DRY_RUN = $false`, and run it again. It renames files saved as numbers (e.g. `851789`) to their real names, using the `archive_id=` in their path and the JSON files.

### Step 6 - Move them to the models folder (Windows)

```powershell
pwsh -ExecutionPolicy Bypass -File .\6_mmf_move_downloads.ps1
```

Again a **dry run** first; then set `$DRY_RUN = $false` and rerun. Files go to `models\model_<id>\<filename>` in your MyMiniFactory folder, the layout step 3 checks. Empty download folders are cleaned up. Anything needing attention is listed in `move_problems.txt` (files already in the models folder, not renamed yet, unknown model).

### Step 7 - Check, and repeat (Linux)

Run step 3 again. Anything still missing is in the new `missing_downloads.txt` - repeat steps 4-6 for those.

Note: if a filename contained a character Windows doesn't allow (`: ? *` etc.), step 5 replaced it with `_`, and step 3 will keep reporting it as missing. Step 5 prints a note whenever this happens, so you know which ones they are.

### Step 8 (optional) - Extract the archives (Windows)

```powershell
pwsh -ExecutionPolicy Bypass -File .\99_mmf_extract_all_zips.ps1
```

Each archive is extracted into its own `<name>_extracted` folder next to it; already-extracted ones are skipped on later runs. With 7-Zip installed it also handles `.rar`/`.7z`. Failures are listed in `failed_archives.txt`. **Keep the archives** - step 3 looks for them.

### Step 9 (optional, ALWAYS LAST) - Rename the folders (Windows)

```powershell
pwsh -ExecutionPolicy Bypass -File .\99_mmf_rename_folders_from_json.ps1
```

Dry run first, then `$DRY_RUN = $false`. Renames `model_851789` to `851789_Yhal_The_Skygazer`. Every rename is logged in `rename_log.csv`.

**After this, steps 3, 6 and 8 no longer recognise the renamed folders** (they expect `model_<id>`), so only do it once your library is complete.

---

## Adding new purchases later

Repeat steps 1-7, with the **"not downloaded"** filter on in step 1 so only the new models are collected. Files already downloaded are skipped, so only the new models are fetched.

If you have already renamed your folders (step 9), step 3 can no longer see the renamed ones and will list them as missing too. In that case, only download the new models in step 4, then run step 9 again to rename their new `model_<id>` folders.
