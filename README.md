# 3D Print Download Toolkit

Scripts for backing up the 3D-print files you've **purchased or subscribed to** from **MyMiniFactory**, **Loot Studios** and **Heroes Infinite** to your own storage - a local disk or a NAS.

Each site has its own folder with a step-by-step guide:

- **[MyMiniFactory/README.md](MyMiniFactory/README.md)** - library IDs, metadata, checking, organizing, extracting, renaming
- **[LootStudios/README.md](LootStudios/README.md)** - collecting and downloading every bundle's files, extracting and sorting them by model
- **[HeroesInfinite/README.md](HeroesInfinite/README.md)** - collecting and downloading every file in your library

## What runs where

| Folder | Runs on | How |
|---|---|---|
| `*/browser/*.js` | Your browser (Chrome/Edge), logged in to the site | Paste into the Console (F12) |
| `*/linux/*.sh` | Linux (bash, curl; plus jq for MyMiniFactory, unzip for testing archives) | `bash scriptname.sh` |
| `MyMiniFactory/windows/*.ps1` | Windows PowerShell (PowerShell 7 recommended) | `pwsh -ExecutionPolicy Bypass -File .\scriptname.ps1` |

## Script names

Every script starts with its **step number** and a site prefix (`mmf_`, `loot_`, `hi_`), so the files sort in the order you use them:

- `1_`, `2_`, `3_` ... are the steps, in order. A missing number (e.g. MyMiniFactory step 4) is a manual step, explained in that site's guide.
- `99_` marks **optional** scripts (extracting, renaming, resetting).

## Where the files go: the script's own folder

Make one folder per site and **copy that site's scripts into it**. The scripts store everything in the folder they're in, so there's nothing to configure. For example, on a NAS:

```
/mnt/nas/3DPrints/
├── MyMiniFactory/         all MyMiniFactory scripts (Linux and Windows), cookie, lists, reports
│   ├── downloads/         JSON metadata per model
│   └── models/            model_<id>/ folders with the files
├── LootStudios/           3_loot_download_all_bundles.sh, its lists, and the bundle folders
└── HeroesInfinite/        3_hi_download.sh, its lists, and the collection folders
```

The folder names and location are up to you. The examples in the guides use `/mnt/nas/3DPrints/<site>` - replace that with your own folder.

If Linux and Windows both use the scripts (MyMiniFactory), use a folder both can see, for example a NAS share mounted on Linux and mapped as a drive on Windows, and run the scripts from there.

**Want the files somewhere else?** Each script has its folders as plain settings at the top (`LOOT_DIR`, `HI_DIR`, `JSON_DIR`, `DOWNLOAD_DIR`, `$MODELS_PATH`, ...). They're empty by default, which means "the script's own folder"; put a full path in to use another folder. If you change a MyMiniFactory folder, change it in every MyMiniFactory script, since they work on the same folders.

Other optional settings are at the top of each script too (folder layout, filters, delays). The MyMiniFactory Windows scripts also have `$DOWN_PATH` - where your browser's download manager saves MyMiniFactory files (empty = `%USERPROFILE%\Downloads\www.myminifactory.com\download`).

## One-time browser setup

The first time you paste code into Chrome's Console, it refuses and shows a warning. Type `allow pasting` and press Enter, then paste again. Only paste code you've read and trust.

### Hide the Console "noise"

While a script runs, the Console also fills with messages that have nothing to do with it, often in red: blocked trackers (`ERR_BLOCKED_BY_CLIENT`), CORS errors, and warnings from the sites' own scripts (for Loot Studios, also from every bundle page the collector opens in the background). They're harmless, but they bury the script's own lines. No script can switch them off, but Chrome and Edge can hide them:

1. In the **Console** tab, click the **gear icon** (⚙, *Console settings*) at the top right of the Console panel.
2. Tick **Hide network** - hides the red network error lines.
3. Tick **Selected context only** - shows only messages from the page you ran the script on, so everything from background frames disappears. The dropdown at the top left of the Console must show **top** (the default).
4. Click the gear icon again to close the settings. To clear what's already there, click the 🚫 icon (*Clear console*) or press **Ctrl+L**.

You only need to do this once; Chrome remembers it. To see everything again, untick both.

The collectors also show their progress in a small panel at the bottom right of the page, so you can close DevTools entirely once they've started.

## Keep your cookie private

The MyMiniFactory and Heroes Infinite scripts use your login cookie for that site, stored in `cookie.txt` in that site's folder, next to the scripts. Anyone who has it can use your account.

- Never put it in a script, a commit, a chat, or a forum post. Keep it only in `cookie.txt` (the included `.gitignore` excludes it).
- `chmod 600 cookie.txt` so only your user can read it.
- If it ever leaks, log out of the site (or change your password) to invalidate it, then save a fresh one.

## Line endings

The `.sh` scripts need Unix (LF) line endings. The included `.gitattributes` makes git keep them that way. If a script fails with `cannot execute: required file not found` or `$'\r': command not found`, it was saved with Windows line endings - fix it with:

```bash
sed -i 's/\r$//' *.sh
```

## Be a good citizen

- Only use these scripts for content your account has access to, and check each site's terms of use.
- The scripts pause between requests and back off when a site says it's busy. Please keep the delays reasonable.
- Sites change; if a script stops finding things, the site's pages have probably changed and the script needs updating.
