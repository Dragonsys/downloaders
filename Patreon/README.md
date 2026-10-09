# Patreon - attachments of the creators you support

Downloads the files attached to the posts of every creator you support on Patreon, straight to your storage (e.g. a NAS):

```
Patreon/
├── eXoDus/
│   ├── 2026-09-20 - Custom Cover Art Pack/
│   │   └── CoverArt.zip
│   └── 2026-09-01 - Easy Scanlines v1.0/
│       └── EasyScanlines.zip
└── Other Creator/
    └── 2026-09-05 - September Release/ ...
```

Only posts your tier can see are used. Links in the post text (Google Drive, MEGA, MyMiniFactory, ...) are **not** downloaded - those sites need their own handling - but every one of them is listed in `patreon_links.txt`, per post, so you can fetch them yourself.

**Several Patreon accounts** are no problem: run the browser part once in each account and save each account's list separately (`patreon_list.tsv`, `patreon_list_2.tsv`, ...). The downloader reads all of them and puts every creator into its own folder.

It works in two halves:

1. **In your browser:** a script reads your memberships and every post of each creator, and collects the file links.
2. **On Linux:** a script downloads every file that isn't downloaded yet, and tests each zip.

> **The file links expire about 2 days after they're collected.** Collect, export and download in one go; if some links expire before they're downloaded, just collect again - finished files are always skipped.

## Files

| File | Where | Purpose |
|---|---|---|
| `browser/1_patreon_collect.js` | Browser Console | Collects the attached files and the links in the post text of every creator you support |
| `browser/2_patreon_export_list.js` | Browser Console | Saves the collected list as `patreon_list.tsv` (and copies it to the clipboard) |
| `linux/3_patreon_download.sh` | Linux | Downloads what's missing |
| `browser/99_patreon_reset.js` | Browser Console | Forgets everything collected in this browser (only if you want to start fresh) |

---

## One-time setup

### On Linux

1. Install the tools (Debian/Ubuntu): `sudo apt install curl unzip` (`unrar` / `7zip` too if creators post `.rar` / `.7z` files).
2. Make your **Patreon folder** and put `3_patreon_download.sh` in it. The files are stored in the folder the script is in (to use another folder, set `PATREON_DIR` at the top of the script). These examples use `/mnt/nas/3DPrints/Patreon`.

No cookie is needed on Linux: the collected links work without your login.

### In your browser

Use the browser where that Patreon account is logged in (Chrome or Edge). For a second account, use another browser, another browser profile, or log out and in again - the collector only sees the account that is logged in.

One-time: open the Console (F12 → Console). If it asks, type `allow pasting` and press Enter. To hide unrelated Console "noise" (red errors from Patreon's own scripts): click the gear icon at the top right of the Console, tick **"Hide network"** and **"Selected context only"**.

---

## Each round (collect → export → download)

### Step 1 - Collect (browser)

On any **www.patreon.com** page, logged in: paste `browser/1_patreon_collect.js` into the Console and press Enter. A panel at the bottom right shows the progress (1.5 seconds between requests, 20 posts per request). At the top of the script:

| Setting | Default | Meaning |
|---|---|---|
| `CREATORS` | `[]` (all) | Only these creators, e.g. `['eXoDus']` (the name or the page name from the creator's address) |
| `MAX_PAGES` | `0` (all) | Only this many pages of 20 posts per creator - use `1` for a first test |
| `DELAY_MS` | `1500` | Pause between requests |

Every run reads all posts again, so every link is fresh.

### Step 2 - Export (browser)

Paste `browser/2_patreon_export_list.js` into the Console. Your browser saves **`patreon_list.tsv`** to your Downloads folder (it's also copied to the clipboard). Put it next to the downloader. For your second account, rename its list to **`patreon_list_2.tsv`** - any name starting with `patreon_list` and ending in `.tsv` works. (If the browser asks whether to allow the download from patreon.com, allow it.)

### Step 3 - Download (Linux, within 2 days)

```bash
cd /mnt/nas/3DPrints/Patreon
bash 3_patreon_download.sh
```

It reads every `patreon_list*.tsv`, downloads each file into `<creator>/<date> - <post title>/`, tests zips (`unzip -t`) and records each finished file in `.patreon_downloaded.tsv`. If the same file is in two lists, the newest link is used. Two different files with the same name in one post are both kept (`Pack.zip`, `Pack_<id>.zip`).

| Message | Meaning |
|---|---|
| `⏱ LINK EXPIRED` | The link is older than about 2 days - collect and export again (Step 1-2) |
| `link refused (HTTP 403)` | Usually an expired link too; after 3 in a row the script stops - collect again |
| `blocked by a bot check` | Patreon's file server refused the script - please report it |
| `Downloaded file is damaged` | The download was incomplete; it's deleted and tried again on the next run |

| Setting | Default | Meaning |
|---|---|---|
| `PATREON_DIR` | empty (the script's folder) | Where the creator folders go |
| `CREATORS` | empty (all) | Only these creators, e.g. `"eXoDus"` (several: `"eXoDus|Other Creator"`) |
| `FOLDER_STRUCTURE` | `"CREATOR/POST"` | How the folders are arranged - the options are listed in the script: `"CREATOR/POST"` (`eXoDus/2026-09-14 - Orc Warband/`), `"CREATOR/YEAR/POST"` (`eXoDus/2026/2026-09-14 - Orc Warband/`), `"CREATOR"` (all of a creator's files together). Applies to files downloaded after a change |
| `DELAY_SECONDS` | `3` | Pause between files |
| `MAX_DOWNLOADS` | `0` (no limit) | Stop after this many downloads |
| `SKIP_DOWNLOADED` | `1` | Skip files recorded as downloaded, even if you've deleted them since |
| `MARK_ALL_DOWNLOADED` | `0` | `1` = download nothing, record everything in the lists as downloaded (for files you already have) |
| `DOWNLOAD` | `1` | `0` = only check what's missing |

Reports (next to the script): `patreon_missing.tsv` (files still missing), `patreon_failed.txt` (failures with the reason), `patreon_links.txt` (links in the post text and older attachments, per post, to fetch yourself).

## Deleting the files after extracting

You don't have to keep the downloads. Every finished file is recorded in **`.patreon_downloaded.tsv`** in your Patreon folder, and with `SKIP_DOWNLOADED=1` (the default) a recorded file is never downloaded again, even after you've extracted and deleted it. **Keep `.patreon_downloaded.tsv`.** Want a file again? Delete its line (the first column is the file's id from the list) and run again.

## Older attachments

Very old Patreon posts have attachments behind `patreon.com/file?...` links instead of direct file links. Those only work with your Patreon login, so the downloader doesn't fetch them; they're listed in `patreon_links.txt` as `[attachment - needs your Patreon login ...]` with the post's address - open the post in your browser and download them there.

## Troubleshooting

| Problem | What to do |
|---|---|
| Collector: `No active memberships found` | You're not logged in, or this account supports nobody right now (only active memberships are read) |
| Collector: `Patreon refused the request (HTTP 401/403)` | Log in again and rerun |
| Collector: `HTTP 429 - waiting ...` | Patreon asks to slow down; the collector waits and continues (raise `DELAY_MS` if it keeps happening) |
| A creator's posts show `posts your tier can't see` | Those posts need a higher tier - they're skipped |
| Files you expected are missing | Some creators link to Google Drive / MEGA / their shop instead of attaching files - see `patreon_links.txt` |
