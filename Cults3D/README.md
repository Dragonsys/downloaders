# Cults3D - your purchases

Downloads every model you've bought (or got for free) on [cults3d.com](https://cults3d.com) and sorts it into a folder of your choice (e.g. on your NAS):

```
Cults3D/
├── Byzantium3D/                      the model's creator
│   └── Rugged Desktop Organizer/
│       ├── images/                   the model's pictures
│       ├── files/                    the model files, extracted (zips inside the download
│       │                             are extracted into a folder of their own)
│       └── description.html          description, licence, creator, link
└── MatMire_Makes/ ...
```

## How it works

Cults3D is behind Cloudflare's bot check for every scripted request, and its file and picture servers don't let page scripts read files. So the downloads are made by **your browser itself** - exactly like clicking "Download all" on each order - and a Windows script sorts them afterwards:

1. **In your browser** (on cults3d.com, logged in): `1_cults_collect_and_download.js` reads all your orders, saves the list of models (title, creator, licence, description, picture links, file names) as `cults_list.json` into your Downloads folder, and clicks each model's **Download all** one after the other, so the browser saves the files into your Downloads folder.
2. **On Windows**: `2_cults_sort_downloads.ps1` recognises each download **by its contents** (the file names inside a zip are the model's files listed on the order page - the zip's own name is just the creator's upload name), unpacks it into `<creator>\<model>\files\`, fetches the pictures into `images\`, writes `description.html`, and removes the download from your Downloads folder.

Models the creator has removed from Cults3D are still in your orders and are downloaded too - only their description and pictures are gone.

## Files

| Step | File | Where | Purpose |
|---|---|---|---|
| 1 | `browser/1_cults_collect_and_download.js` | Browser Console | Collects your purchases and downloads them (normal browser downloads) |
| 2 | `windows/2_cults_sort_downloads.ps1` | Windows PowerShell | Sorts the downloads into `<creator>\<model>\`, fetches pictures, writes descriptions |

---

## One-time setup

- Use **Chrome or Edge**, logged in on cults3d.com.
- Make your **Cults3D folder** (e.g. `Z:\3DPrints\Cults3D` on the NAS) and put `2_cults_sort_downloads.ps1` in it.
- Console setup: open the Console (F12 → Console). If it asks, type `allow pasting` and press Enter. To hide unrelated Console "noise" (red errors from the site's own scripts): click the gear icon at the top right of the Console, tick **"Hide network"** and **"Selected context only"**.
- Make sure the browser saves downloads without asking where (Chrome: Settings → Downloads → "Ask where to save each file" **off**).
- **Where the downloads land** is decided by the browser, not the script (a web page can't choose the folder). To keep them out of your normal Downloads folder, set Chrome's download **Location** (Settings → Downloads) to a folder of its own, e.g. `Z:\3DPrints\Cults3D\_downloads` - best in a separate Chrome profile used only for Cults3D, so your other downloads aren't affected - and set `$DOWN_PATH` in `2_cults_sort_downloads.ps1` to the same folder. `cults_list.json` is saved there too, and the sort script finds it there.

## Step 1 - Collect and download (browser)

On **cults3d.com** (logged in), paste `browser/1_cults_collect_and_download.js` into the Console and press Enter. A panel at the bottom right shows the progress:

1. It reads your orders and every model's page (1 second apart) and saves **`cults_list.json`** into your Downloads folder.
2. It clicks "Download all" for each model, 20 seconds apart. The first time, the browser may ask whether cults3d.com may **download multiple files** - allow it. Keep the tab open until the browser has finished downloading (watch the browser's download list).

| Setting | Default | Meaning |
|---|---|---|
| `DOWNLOAD` | `true` | `false` = only collect and save `cults_list.json` |
| `DELAY_MS` | `20000` | Pause between downloads |
| `MAX_DOWNLOADS` | `0` (all) | Only this many models this run - use `1` for a first test |
| `RECLICK` | `false` | `true` = also click models clicked on an earlier run |

A model is clicked only once (remembered in the browser); models already sorted by step 2 are skipped once you've pasted `cults_done.js` (see below).

## Step 2 - Sort (Windows)

When the downloads have finished, run in your Cults3D folder:

```powershell
pwsh -ExecutionPolicy Bypass -File .\2_cults_sort_downloads.ps1
```

It starts as a **dry run** and only lists which download goes where. If that looks right, set `$DRY_RUN = $false` at the top and run it again.

| Setting | Default | Meaning |
|---|---|---|
| `$CULTS_PATH` | empty (the script's folder) | Where the models go |
| `$DOWN_PATH` | empty (your Windows Downloads folder) | Where the browser saved the downloads |
| `$LIST_FILE` | empty | `cults_list.json`; empty = the newest one in the Downloads folder or next to the script |
| `$EXTRACT` | `$true` | Extract zips into `files\`; `$false` = keep the zip |
| `$IMAGES` | `$true` | Fetch the pictures |
| `$DELETE_DOWNLOADS` | `$true` | Remove a download from the Downloads folder once it's sorted |
| `$DRY_RUN` | `$true` | `$false` = actually sort |

Sorted models are recorded in **`.cults_downloaded.tsv`** in your Cults3D folder (keep it), and the script writes **`cults_done.js`** next to itself: paste it into the Console on cults3d.com once, and step 1 won't download those models again - useful after you've deleted the sorted files, or when you've bought new models and run step 1 again.

Nothing is overwritten. Downloads that match no model in the list are left alone and listed; models whose download isn't there (yet) are listed as "Not in the Downloads folder (yet)" - let the browser finish, or run step 1 with `RECLICK = true`.

## Troubleshooting

| Problem | What to do |
|---|---|
| Nothing downloads in step 1 | Allow "download multiple files" for cults3d.com (the icon at the right of the address bar) and run it again with `RECLICK = true` |
| `cults_list.json not found` | Run step 1 first, or set `$LIST_FILE` |
| A download fails on Cults3D's side (e.g. `ERR_INVALID_RESPONSE` from `download.cults3d.com`) | The script carries on with the next model (downloads run in a hidden frame, so the error doesn't replace the page). The model shows up in step 2 as "Not in the Downloads folder" - try it again later with `RECLICK = true`, or click "Download all" on its order page; if it keeps failing, it's broken on Cults3D (contact them) |
| A model stays "Not in the Downloads folder" | The download is still running, failed, or was saved elsewhere - check the browser's download list |
| A download is listed as "match no model" | It isn't one of your Cults3D purchases (or `cults_list.json` is older than the purchase - run step 1 again) |
