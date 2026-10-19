# Props & Beyond - your library

Downloads everything in your **My Library** on [propsandbeyond.com](https://propsandbeyond.com) (monthly Prop Drops, the Welcome Pack, props bought on their own), extracts it and sorts it like this:

```
PropsAndBeyond/
├── 01-2023 - Viking Saga/
│   ├── Beard-Beads/
│   │   ├── images/                   the prop's pictures (from the zip, plus the one from the shop)
│   │   └── files/                    everything else: cards/, supportless/, pre-supported/ ...
│   ├── Tankard-of-Feasting/ ...
│   ├── images/                       the pack's cover
│   └── files/                        the pack's item cards (PDF)
├── Welcome-Pack/ ...
└── Single props/                     props that are in no pack
    └── Ioun-Stones/{images,files}
```

## How it works

1. **In your browser** (on propsandbeyond.com, logged in): `1_pb_collect.js` reads all pages of My Library and every product's shop page (for the pictures), and saves **`pb_list.tsv`** into your Downloads folder.
2. **On Linux** (or Git Bash): `2_pb_download.sh` downloads from that list, tests and extracts the zips, sorts them and fetches the pictures.

The download links in My Library **expire 1 hour** after the page made them, so run step 2 within the hour. Expired links aren't requested: the script says so, you collect again (step 1) and run step 2 again - it continues where it stopped. The files are on Backblaze and the pictures on the site; neither needs your login, so there's no cookie to copy.

**Packs, not duplicates:** a monthly pack lists a zip of the whole month *and* one zip per prop (the same props again), and many props are also products of their own. By default only the whole-pack zips are downloaded, plus the props that are in no pack - each prop once. (Some packs include props stored elsewhere: January 2023 has "Horn" and "Pauldrons"; those count as in the pack.)

## Files

| Step | File | Where | Purpose |
|---|---|---|---|
| 1 | `browser/1_pb_collect.js` | Browser Console | Collects your library and saves `pb_list.tsv` |
| 2 | `linux/2_pb_download.sh` | Linux (or Git Bash) | Downloads, extracts and sorts; fetches the pictures |

---

## One-time setup

- **Linux:** `sudo apt install curl unzip`. (Git Bash on Windows has both.)
- Make your **Props & Beyond folder** (e.g. `/mnt/nas/3DPrints/PropsAndBeyond`) and put `2_pb_download.sh` in it.
- Browser: use Chrome or Edge, logged in on propsandbeyond.com. Console setup: open the Console (F12 → Console). If it asks, type `allow pasting` and press Enter. To hide unrelated Console "noise" (red errors from the site's own scripts): click the gear icon at the top right of the Console, tick **"Hide network"** and **"Selected context only"**.

## Step 1 - Collect (browser)

On **propsandbeyond.com** (logged in), paste `browser/1_pb_collect.js` into the Console and press Enter. A panel at the bottom right shows the progress (about 2 minutes for 100 products - one page per second). It saves **`pb_list.tsv`** into your Downloads folder; copy it next to `2_pb_download.sh`.

## Step 2 - Download (Linux)

```bash
cd /mnt/nas/3DPrints/PropsAndBeyond
bash 2_pb_download.sh
```

| Setting | Default | Meaning |
|---|---|---|
| `PB_DIR` | empty (the script's folder) | Where the packs go |
| `FOLDER_STRUCTURE` | `"MM-YYYY - PACK/PROP"` | How the folders are arranged - the options are listed in the script: `"MM-YYYY - PACK/PROP"` (`01-2023 - Viking Saga/Beard-Beads/{images,files}`), `"PACK/PROP"` (`Viking Saga/Beard-Beads/...`), `"PROP"` (all props side by side), `"MM-YYYY - PACK"` (as in the zip, no images/files split). Applies to packs downloaded after a change |
| `SINGLES_FOLDER` | `"Single props"` | Folder for props that are in no pack |
| `WHAT` | `"packs"` | `"props"` = each prop's own zip instead of the whole-pack zip |
| `EXTRACT` | `1` | `0` = keep the zips (in the pack/prop folder) |
| `IMAGES` | `1` | `0` = no pictures from the shop pages |
| `SKIP_DOWNLOADED` | `1` | `0` = download again what's recorded but no longer there |
| `MARK_ALL_DOWNLOADED` | `0` | `1` = download nothing, record everything in the list as downloaded |
| `DELAY_SECONDS` | `5` | Pause between zips |
| `MAX_DOWNLOADS` | `0` (no limit) | Stop after this many zips |

Everything finished is recorded in **`.pb_downloaded.tsv`** in your Props & Beyond folder (keep it): nothing recorded is downloaded again, also after you've moved or deleted the files. A zip is deleted once it's extracted. Nothing is overwritten: if a file is already there with other contents, the extraction stops, the zip is kept in `.pb_downloads/` and the clashing files are put in `<pack>/.pb_conflicts_<date>/`.

**Packs you already have** (e.g. sorted by hand, or from MyMiniFactory's Prop Drop): if a pack's folder is already there but not recorded, it's **left alone** and listed in `pb_skipped.txt` - nothing is mixed into it. To have the script download it in its own layout, move or rename that folder; to just mark it as done, use `MARK_ALL_DOWNLOADED=1` once.

## Adding new months later

Run step 1 again, then step 2: what's recorded is skipped, only new packs are downloaded.

## Troubleshooting

| Message | What to do |
|---|---|
| `link expired - collect again` | The links are older than an hour (minus a few minutes' margin): run step 1 again, copy the new `pb_list.tsv`, run step 2 |
| `link refused (HTTP 403)` | Same - expired. After 3 in a row the script stops |
| `Not logged in` (step 1) | Log in on propsandbeyond.com and run it again |
| `folder already there ... left alone` | See "Packs you already have" above |
| `unzip is not installed` | `sudo apt install unzip`, or `EXTRACT=0` |
