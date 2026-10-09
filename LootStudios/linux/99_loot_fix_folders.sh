#!/bin/bash
# ================================================================
# Loot Studios - move downloads that ended up outside their bundle's folder
#
# A bundle's folder is named after its download links, and those have changed over time:
#  - Older versions of 3_loot_download_all_bundles.sh named newer bundles' folder after the
#    first part of new-dls.loot-studios.com/Fantasy/ShadowCourt/... ("Fantasy"), so their All
#    Bundle archives ended up together in LOOT_DIR/Fantasy/ (or SciFi/, ...).
#  - Some bundles moved from old-dls.loot-studios.com/FreeMini/... to .../AedanValiantShield/...,
#    so files downloaded earlier are in LOOT_DIR/FreeMini/ and newer ones (e.g. the pictures)
#    in LOOT_DIR/AedanValiantShield/.
# This script compares, for every file in the list, where .loot_downloaded.tsv says it is with
# where the downloader puts it now, moves it into the bundle's own folder, and updates the
# paths in .loot_downloaded.tsv. Files you've already deleted are only updated in that record.
#
# It needs the exported list (loot_all_bundles.tsv, any version) to know which
# file belongs to which bundle. Run with DRY_RUN=1 first to see what it would do.
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;94m'
NC='\033[0m'

# ==============================
# SETTINGS
# ==============================
LIST_FILE="loot_all_bundles.tsv"   # exported list (next to this script, or a full path)
# Where the bundles are stored (same as LOOT_DIR in 3_loot_download_all_bundles.sh).
# Empty = the folder this script is in.
LOOT_DIR=""
# Folder structure - the same as FOLDER_STRUCTURE in 3_loot_download_all_bundles.sh. Available options:
#   "BUNDLE_FOLDER" -> FaewoodHaven/...    (default; bundle name from the download link)
#   "BUNDLE_TITLE"  -> Faewood Haven/...   (bundle title as shown on the site)
# Files are moved to the bundle folder this gives, so switching it here moves your bundles over.
FOLDER_STRUCTURE="BUNDLE_FOLDER"
DRY_RUN=1             # 1 = only show what would be moved, change nothing; 0 = move
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ "$LIST_FILE" != /* && ! -f "$LIST_FILE" && -f "$script_dir/$LIST_FILE" ]] && LIST_FILE="$script_dir/$LIST_FILE"
[[ -z "$LOOT_DIR" ]] && LOOT_DIR="$script_dir"
LOOT_DIR="${LOOT_DIR%/}"
FOLDER_STRUCTURE="${FOLDER_STRUCTURE^^}"
case "$FOLDER_STRUCTURE" in
    BUNDLE_FOLDER|BUNDLE_TITLE) ;;
    *) echo -e "${RED}Unknown FOLDER_STRUCTURE \"$FOLDER_STRUCTURE\" - use BUNDLE_FOLDER or BUNDLE_TITLE.${NC}"; exit 1 ;;
esac
LEDGER="$LOOT_DIR/.loot_downloaded.tsv"

echo -e "${BLUE}Loot Studios - fix bundle folders${NC}"
printf "List file:   ${YELLOW}%s${NC}\n" "$LIST_FILE"
printf "Bundles in:  ${YELLOW}%s${NC}\n" "$LOOT_DIR"
(( DRY_RUN )) && printf "Mode:        ${YELLOW}dry run - nothing is changed${NC} (set DRY_RUN=0 to move)\n" \
              || printf "Mode:        ${YELLOW}move files${NC}\n"
echo ""
[[ -f "$LIST_FILE" ]] || { echo -e "${RED}List file not found: $LIST_FILE${NC}"; exit 1; }
[[ -d "$LOOT_DIR" ]] || { echo -e "${RED}Folder not found: $LOOT_DIR${NC}"; exit 1; }

# Same as in 3_loot_download_all_bundles.sh
safe_name() {
    local s="$1"
    s="${s//\//_}"
    s="$(printf '%s' "$s" | tr -d '\000-\037')"
    s="${s#"${s%%[![:space:].]*}"}"
    s="${s%"${s##*[![:space:].]}"}"
    printf '%s' "$s"
}
urldecode() { local s="${1//+/ }"; printf '%b' "${s//'%'/'\x'}"; }   # quoted: bash 5.2 treats \ in the replacement differently

# ---------- read the list ----------
mapfile -t lines < <(sed $'1s/^\xEF\xBB\xBF//; s/\r$//' "$LIST_FILE")
(( ${#lines[@]} > 1 )) || { echo -e "${RED}The list is empty.${NC}"; exit 1; }
IFS=$'\x1f' read -r -a header <<< "${lines[0]//$'\t'/$'\x1f'}"
declare -A col=()
for i in "${!header[@]}"; do col["${header[$i],,}"]=$i; done
for c in file url; do
    [[ -n "${col[$c]}" ]] || { echo -e "${RED}The list has no '$c' column.${NC}"; exit 1; }
done

# What the record says was downloaded where (key -> path relative to LOOT_DIR)
declare -A recorded=()
if [[ -f "$LEDGER" ]]; then
    while IFS= read -r l || [[ -n "$l" ]]; do
        l="${l%$'\r'}"
        IFS=$'\x1f' read -r lkey lpath _ <<< "${l//$'\t'/$'\x1f'}"
        [[ -n "$lkey" && -n "$lpath" && "$lpath" != "("* ]] && recorded[$lkey]="$lpath"
    done < "$LEDGER"
fi

# old path (relative to LOOT_DIR) -> new path: every file in the list that the record (or an
# older version's folder naming) puts somewhere else than the downloader would put it now
declare -A target=() conflict=()
add_target() {   # add_target OLD NEW
    [[ -n "$1" && -n "$2" && "$1" != "$2" ]] || return
    if [[ -n "${target[$1]}" && "${target[$1]}" != "$2" ]]; then conflict[$1]=1; fi
    target[$1]="$2"
}
for (( n = 1; n < ${#lines[@]}; n++ )); do
    IFS=$'\x1f' read -r -a f <<< "${lines[$n]//$'\t'/$'\x1f'}"
    url="${f[${col[url]}]}"; file="${f[${col[file]}]}"
    [[ -n "$file" ]] || continue
    kind="${f[${col[kind]:-99}]}"; [[ -z "$kind" ]] && kind="all"
    bundle="${f[${col[bundle]:-99}]}"; folder="${f[${col[folder]:-99}]}"
    scale="${f[${col[scale]:-99}]}"; material="${f[${col[material]:-99}]}"
    page="${f[${col[page]:-99}]}"; group="${f[${col[group]:-99}]}"
    # Where 3_loot_download_all_bundles.sh puts it (same rules)
    if [[ "$FOLDER_STRUCTURE" == "BUNDLE_TITLE" || -z "$folder" ]]; then dir="$(safe_name "$bundle")"; else dir="$(safe_name "$folder")"; fi
    [[ -z "$dir" ]] && dir="Unknown bundle"
    inner="$(safe_name "$file")"
    if [[ "$kind" == "item" ]]; then sub="$(safe_name "$group")"; inner="${sub:-Figures}/$inner"; fi
    if [[ "$kind" == "image" ]]; then sub="$(safe_name "$group")"; inner="Images/${sub:-Figures}/$inner"; fi
    new="$dir/$inner"
    # 1. The record says it's somewhere else (e.g. FreeMini/ - the folder of an older link)
    key="${page:-$bundle}|$scale|$material|$file"
    # pictures: the downloader adds the group to the key (older versions didn't)
    [[ "$kind" == "image" && -n "${recorded[$key|$group]}" ]] && key="$key|$group"
    if [[ -n "${recorded[$key]}" ]]; then
        rec="${recorded[$key]}"
        if [[ "$kind" == "image" ]]; then
            # A figure and its bust often have the same name, so their pictures share one record
            # line; which group folder is right can't be told - only fix the bundle folder.
            [[ "${rec%%/*}" == "${new%%/*}" ]] && continue
            # a picture renamed to its real extension (.jpg that was a PNG) keeps that extension
            [[ "${rec##*.}" != "${new##*.}" ]] && new="${new%.*}.${rec##*.}"
        fi
        add_target "$rec" "$new"
        continue
    fi
    # 2. Not recorded: older versions named newer bundles' folder after the link's first part
    #    (new-dls.loot-studios.com/Fantasy/ShadowCourt/... -> "Fantasy")
    if [[ "$kind" == "all" && "$url" =~ ^https?://new-dls\.[^/]+/([^/?]+)/[^?]*/ ]]; then
        add_target "$(safe_name "$(urldecode "${BASH_REMATCH[1]}")")/$(safe_name "$file")" "$new"
    fi
done

if (( ${#target[@]} == 0 )); then
    echo -e "${GREEN}Everything is in its bundle's folder already - nothing to fix.${NC}"
    exit 0
fi

moved=0; already=0; gone=0; fixed=0; problems=0
declare -A emptied=() remap=()
mapfile -t olds < <(printf '%s\n' "${!target[@]}" | sort)
for old in "${olds[@]}"; do
    new="${target[$old]}"
    if [[ -n "${conflict[$old]}" ]]; then
        # Two bundles with the same file name shared one folder: the file holds
        # whichever was downloaded last, so it can't be assigned safely.
        ((problems++))
        printf "  ${RED}? %s${NC} - this name belongs to several bundles; left alone (delete it and its lines in .loot_downloaded.tsv to download them again)\n" "$old"
        continue
    fi
    remap[$old]="$new"
    if [[ ! -e "$LOOT_DIR/$old" ]]; then
        if [[ -e "$LOOT_DIR/$new" ]]; then ((fixed++)); else ((gone++)); fi   # moved before / deleted after extracting
        continue
    fi
    if [[ -e "$LOOT_DIR/$new" ]]; then
        if cmp -s "$LOOT_DIR/$old" "$LOOT_DIR/$new"; then
            ((already++))
            printf "  ${GREEN}=${NC} %s is already at %s - removing the old copy\n" "$old" "$new"
            (( DRY_RUN )) || rm -f "$LOOT_DIR/$old"
            emptied[$(dirname "$old")]=1
        else
            ((problems++))
            printf "  ${RED}! %s${NC} - a different file is already at %s; left alone\n" "$old" "$new"
            unset 'remap[$old]'
        fi
        continue
    fi
    printf "  ${BLUE}->${NC} %s  =>  %s\n" "$old" "$new"
    if (( ! DRY_RUN )); then
        mkdir -p "$LOOT_DIR/$(dirname "$new")" && mv -n "$LOOT_DIR/$old" "$LOOT_DIR/$new" \
            || { ((problems++)); printf "    ${RED}could not move it${NC}\n"; unset 'remap[$old]'; continue; }
    fi
    ((moved++)); emptied[$(dirname "$old")]=1
done

# ---------- update the record of downloaded files ----------
updated=0
if [[ -f "$LEDGER" && ${#remap[@]} -gt 0 ]]; then
    tmp="$LEDGER.tmp"; (( DRY_RUN )) && tmp=/dev/null || : > "$tmp"   # dry run: only count
    while IFS= read -r l || [[ -n "$l" ]]; do
        l="${l%$'\r'}"
        IFS=$'\x1f' read -r lkey lpath ldate <<< "${l//$'\t'/$'\x1f'}"
        if [[ -n "$lpath" && -n "${remap[$lpath]}" ]]; then
            l="$lkey"$'\t'"${remap[$lpath]}"; [[ -n "$ldate" ]] && l+=$'\t'"$ldate"
            ((updated++))
        fi
        printf '%s\n' "$l" >> "$tmp"
    done < "$LEDGER"
    (( DRY_RUN )) || { cp -p "$LEDGER" "$LEDGER.bak" && mv -f "$tmp" "$LEDGER"; }
fi

# Remove old category folders that are now empty
if (( ! DRY_RUN )); then
    for d in "${!emptied[@]}"; do rmdir "$LOOT_DIR/$d" 2>/dev/null && printf "  Removed empty folder %s\n" "$d"; done
fi

echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e " Moved:                  ${GREEN}${moved}${NC}"
echo -e " Old copies removed:     ${GREEN}${already}${NC} (identical file already in the right folder)"
echo -e " Already in place:       ${fixed}"
echo -e " Not there any more:     ${gone} (deleted after extracting - only the record is updated)"
echo -e " Record lines updated:   ${updated}$( [[ -f "$LEDGER" ]] || echo ' (no .loot_downloaded.tsv)')"
echo -e " Left alone (problems):  ${RED}${problems}${NC}"
echo -e "${YELLOW}================================================${NC}"
if (( DRY_RUN )); then
    echo -e "${YELLOW}Dry run - nothing was changed.${NC} If this looks right, set DRY_RUN=0 and run it again."
else
    [[ -f "$LEDGER.bak" ]] && echo "The previous record was saved as .loot_downloaded.tsv.bak."
fi
