# MakerWorld - your collections, download history and liked models

Downloads the models in your **collections**, your **download history** and your **liked models** on [makerworld.com](https://makerworld.com) straight into a folder of your choice (e.g. on your NAS), sorted like this:

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

It runs **in your browser**, on makerworld.com, while you're logged in - it uses the site exactly like you do: it reads your lists and, for each model, asks for the download links (the same requests the site makes when you click Download) and saves the files into the folder you picked. Nothing to copy: no cookie, no user agent.

Why the browser: MakerWorld's download links expire after 5 minutes, so they can't be collected now and downloaded later, and MakerWorld's Cloudflare bot check refuses scripts on Linux for your personal lists (with or without a cookie). The Linux script `linux/99_mw_download.sh` is still there - it works where Cloudflare lets it through (e.g. from Windows with Git Bash) and uses the same layout and record file.

Every link request counts as a download on MakerWorld, like clicking Download on the site. The script pauses 15 seconds before each one.

## Files

| File | Where | Purpose |
|---|---|---|
| `browser/1_mw_download.js` | Browser Console | Reads your lists and downloads what's missing into the folder you choose |
| `linux/99_mw_download.sh` | Linux | Optional: the same with curl and your cookie - only where Cloudflare doesn't block it |

---

## One-time setup

- Use **Chrome or Edge** (other browsers can't save into a folder from a web page).
- Make your **MakerWorld folder**, e.g. on the NAS. On Windows, a network share works best as a **mapped drive** (File Explorer → This PC → Map network drive, e.g. `Z:` → `\\192.168.1.10\3D_Printer`).
- Console setup: open the Console (F12 → Console). If it asks, type `allow pasting` and press Enter. To hide unrelated Console "noise" (red errors from the site's own scripts): click the gear icon at the top right of the Console, tick **"Hide network"** and **"Selected context only"**.

## Step 1 - Download (browser)

1. Log in on **makerworld.com**, open the Console (F12) and paste `browser/1_mw_download.js`, press Enter.
2. A panel appears at the bottom right. Click **Choose folder** and pick your MakerWorld folder. The browser asks whether the site may edit files there - **allow** it ("Edit files"). It may also warn about folders with system files; pick a normal folder.
3. It reads your collections, history and likes, then downloads model by model. Keep the tab open (you can close DevTools); **Stop** stops after the current file.

Next time, the button says **Continue in "<folder>"** - one click and the browser asks for permission again (Shift+click to pick another folder). Every finished part (model files, each print profile, the pictures, the description) is recorded in **`.mw_downloaded.tsv`** in the folder, and a model downloaded completely is skipped on later runs without asking MakerWorld again.

For a first test, set `MAX_MODELS = 2` at the top of the script. Settings:

| Setting | Default | Meaning |
|---|---|---|
| `SOURCES` | `['collections', 'downloads', 'likes']` | What to download; remove what you don't want |
| `COLLECTIONS` | `[]` (all) | Only these collections, e.g. `['Pokemon', 'D&D']` |
| `PROFILES` | `'creator'` | Print profiles: `'creator'` = the model creator's own, `'all'` = also the ones other users made (popular models can have dozens), `'none'` |
| `IMAGES` | `true` | The model's pictures |
| `DESCRIPTION` | `true` | `description.html` |
| `EXTRACT` | `true` | Extract the model zip into `files/`; `false` = keep the zip |
| `FOLDER_STRUCTURE` | `'COLLECTION/CREATOR/MODEL'` | How the folders are arranged - the options are listed in the script: `'COLLECTION/CREATOR/MODEL'`, `'COLLECTION/MODEL'`, `'CREATOR/MODEL'`, `'MODEL'`. A model's folder is recorded when it's first downloaded, so a change only applies to models downloaded after it |
| `DELAY_MS` | `15000` | Pause before each download link request (shorter = MakerWorld's "not a robot" check comes sooner) |
| `MAX_MODELS` | `0` (all) | Stop after this many models |
| `RECHECK` | `false` | `true` = read every model again, e.g. to get print profiles added since |

Nothing is overwritten: a file that's already there is kept. A zip the script can't extract itself (very large "zip64" archives) is kept as a zip in `files/`.

## Deleting the files after importing

You don't have to keep the downloads: everything is recorded in **`.mw_downloaded.tsv`** in your MakerWorld folder, and nothing recorded is downloaded again. **Keep that file.** To get a model again, delete its lines (they contain its id) and run again.

## Troubleshooting

| Message | What to do |
|---|---|
| `MakerWorld says you are not logged in` | Log in on makerworld.com and run again |
| `No permission to save in that folder` | Click the button again and allow "Edit files" |
| `HTTP 403: ...` for one model | MakerWorld refuses that model's download (e.g. removed, or paid and not bought) - tried again next run |
| `MakerWorld wants to confirm that you are not a robot` (HTTP 418) | MakerWorld's own check after a number of downloads. The script **pauses**: click the link in the panel (opens the model in a new tab), click **Download** there and complete the check, then click **Continue** in the panel - it retries the same file. If it comes up often, raise `DELAY_MS` |
| Downloads refused after many models in one day | MakerWorld allows only a certain number of downloads **per day**. The script stops after 3 refusals; run it again the next day - it continues where it left off |
| `Stopped early: 3 download links in a row were refused` | Probably a download limit; wait a while (a few hours) and run again |
| `HTTP 429 - waiting ...` | MakerWorld asks to slow down; the script waits and continues (raise `DELAY_MS` if it keeps happening) |
| Linux script: `blocked by Cloudflare's bot check` | Expected on Linux - use the browser script |
