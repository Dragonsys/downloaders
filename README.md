# 3D Print Download Toolkit

Scripts for backing up the 3D-print files you've **purchased or subscribed to** from **MyMiniFactory**, **Loot Studios** and **Heroes Infinite** to your own storage - a local disk or a NAS.

Each site has its own folder with a step-by-step guide:

- **[MyMiniFactory/README.md](MyMiniFactory/README.md)** - library IDs, metadata, checking, organizing, extracting, renaming
- **[LootStudios/README.md](LootStudios/README.md)** - collecting and downloading every bundle's "All Bundle" files
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

## Configuration: one setting, `PRINTS_DIR`

All scripts store everything under one root folder, **`PRINTS_DIR`**:

| | Default if not set |
|---|---|
| Linux | `~/3DPrints` |
| Windows | `%USERPROFILE%\3DPrints` |

Set it once as an environment variable instead of editing the scripts:

```bash
# Linux - add to ~/.bashrc, then open a new terminal
export PRINTS_DIR=/mnt/nas/3DPrints
```

```powershell
# Windows - run once, then open a new PowerShell window
setx PRINTS_DIR "D:\3DPrints"
```

If Linux and Windows both use the scripts, point `PRINTS_DIR` at the **same folder** on both (for example a NAS share mounted on Linux and mapped as a drive on Windows), so files saved on one side are seen on the other.

Layout under `PRINTS_DIR`:

```
PRINTS_DIR/
├── .mmf_downloads/        MyMiniFactory working folder (scripts, cookie, lists, reports)
│   ├── downloads/         JSON metadata per model
│   └── models/            model_<id>/ folders with the files
├── .loot_downloads/       Loot Studios working folder
├── LootStudios/           Loot Studios bundles
├── .hi_downloads/         Heroes Infinite working folder
└── HeroesInfinite/        Heroes Infinite collections
```

Other optional settings are at the top of each script (folder layout, filters, delays). The MyMiniFactory Windows scripts also read `MMF_DOWNLOAD_PATH` - where your browser's download manager saves MyMiniFactory files (default `%USERPROFILE%\Downloads\www.myminifactory.com\download`).

## One-time browser setup

The first time you paste code into Chrome's Console, it refuses and shows a warning. Type `allow pasting` and press Enter, then paste again. Only paste code you've read and trust.

## Keep your cookie private

The MyMiniFactory and Heroes Infinite scripts use your login cookie for that site, stored in `cookie.txt` in each site's working folder. Anyone who has it can use your account.

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
