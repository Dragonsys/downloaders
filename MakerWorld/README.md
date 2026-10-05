# MakerWorld - your collections, download history and liked models

Downloads the models in your **collections**, your **download history** and your **liked models** on [makerworld.com](https://makerworld.com) to your storage (e.g. a NAS), sorted like this:

```
MakerWorld/
├── Pokemon/                          one folder per collection
│   └── Ghosty/                       the model's creator
│       └── Gengar Puzzle Box/
│           ├── images/               the model's pictures
│           ├── files/                the model files (STL, STEP ...), extracted
│           ├── profiles/             the print profiles (.3mf), one per profile
│           └── description.html      description, licence, creator, link
├── Default Collection/ ...
├── Downloads/                        models only in your download history
└── Likes/                            models you liked that are in no collection
```

A model that is in several collections is stored **once**: in the first of your own collections (in the order MakerWorld lists them), then the "Default Collection", then Downloads, then Likes. Its folder stays where it is on later runs, even if you move the model to another collection.

Paid models you've bought (or got with points) are in your download history once you've downloaded them on the site. MakerWorld has no separate list of them - the "My Orders" page only has MakerLab and Bambu Store orders.

## How it works

Everything runs on **Linux** - there's no browser step. With your login cookie, the script reads your lists on makerworld.com and, for each model, asks MakerWorld for the download links (the same requests the site makes when you click Download). Those links expire after **5 minutes**, so each one is fetched right before it's used. The cookie is only sent to makerworld.com, never to the file server.

Every link request counts as a download on MakerWorld, like clicking Download on the site. The script pauses 5 seconds before each one.

## Files

| File | Where | Purpose |
|---|---|---|
| `linux/1_mw_download.sh` | Linux | Reads your lists and downloads what's missing |

---

## One-time setup (Linux)

1. Install the tools (Debian/Ubuntu):

   ```bash
   sudo apt install curl jq unzip
   ```

2. Make your **MakerWorld folder** and put `1_mw_download.sh` in it. The models are stored in the folder the script is in (to use another folder, set `MW_DIR` at the top of the script). These examples use `/mnt/nas/3DPrints/MakerWorld`:

   ```bash
   mkdir -p /mnt/nas/3DPrints/MakerWorld
   cp 1_mw_download.sh /mnt/nas/3DPrints/MakerWorld/
   cd /mnt/nas/3DPrints/MakerWorld
   sed -i 's/\r$//' 1_mw_download.sh     # only needed if it was copied or edited on Windows
   ```

3. In that folder, create:
   - **`cookie.txt`** - from **makerworld.com**: log in, open your profile, F12 → **Network** → **Doc** → F5 → click the first request → **Headers** → **Request Headers** → right-click `cookie` → **Copy value**. Paste into the file, save, then `chmod 600 cookie.txt`. Never share this file - it's your login.
   - **`user_agent.txt`** - run `navigator.userAgent` in the same browser's Console and paste the result.

## Step 1 - Download (Linux)

```bash
cd /mnt/nas/3DPrints/MakerWorld
bash 1_mw_download.sh
```

For a first test, set `MAX_MODELS=2`. Stop it any time (Ctrl+C) and run it again - it continues where it left off. Every finished part (model files, each print profile, the pictures, the description) is recorded in `.mw_downloaded.tsv`, and a model downloaded completely is skipped on later runs without asking MakerWorld again.

| Setting | Default | Meaning |
|---|---|---|
| `MW_DIR` | empty (the script's folder) | Where the models go |
| `SOURCES` | `"collections downloads likes"` | What to download; remove what you don't want |
| `COLLECTIONS` | empty (all) | Only these collections, e.g. `"Pokemon|D&D"` |
| `PROFILES` | `"creator"` | Print profiles: `"creator"` = the model creator's own, `"all"` = also the ones other users made (popular models can have dozens), `"none"` |
| `IMAGES` | `1` | The model's pictures |
| `DESCRIPTION` | `1` | `description.html` |
| `EXTRACT` | `1` | Extract the model zip into `files/` (and delete the zip); `0` = keep the zip |
| `DELAY_SECONDS` | `5` | Pause before each download link request |
| `MAX_MODELS` | `0` (no limit) | Stop after this many models |
| `RECHECK` | `0` | `1` = read every model again, e.g. to get print profiles added since (one request per model) |
| `SKIP_DOWNLOADED` | `1` | Skip what's recorded as downloaded, even if you've deleted it since |
| `DOWNLOAD` | `0`/`1` | `0` = only list what's missing (`mw_missing.txt`) |

## Deleting the files after importing

You don't have to keep the downloads: everything is recorded in **`.mw_downloaded.tsv`** in your MakerWorld folder, and with `SKIP_DOWNLOADED=1` (the default) nothing recorded is downloaded again. **Keep that file.** To get a model again, delete its lines (they contain its id) and run again.

## Troubleshooting

| Message | What to do |
|---|---|
| `MakerWorld says you're not logged in` | Your cookie expired - save a fresh `cookie.txt` |
| `blocked by Cloudflare's bot check` | Make sure `user_agent.txt` matches the browser the cookie came from |
| `HTTP 403: ...` for one model | MakerWorld refuses that model's download (e.g. removed, or paid and not bought) - listed in `mw_failed.txt`, tried again next run |
| `Stopped early: 3 download links in a row were refused` | Probably a download limit; wait a while (a few hours) and run again |
| `HTTP 429 - waiting ...` | MakerWorld asks to slow down; the script waits and continues (raise `DELAY_SECONDS` if it keeps happening) |
