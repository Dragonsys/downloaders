#!/bin/bash
# ================================================================
# Loot Studios - fix the folders of bundles downloaded by older versions
#
# Newer bundles have links like  new-dls.loot-studios.com/Fantasy/ShadowCourt/Resin/...
# Older versions of 3_loot_download_all_bundles.sh named the folder after the
# first part ("Fantasy"), so the All Bundle archives of every newer bundle ended
# up together in LOOT_DIR/Fantasy/ (or SciFi/, ...). This script moves them to
# the bundle's own folder (LOOT_DIR/ShadowCourt/) and updates the paths in
# LOOT_DIR/.loot_downloaded.tsv. Files you've already deleted are only updated
# in that record.
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
DRY_RUN=1             # 1 = only show what would be moved, change nothing; 0 = move
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ "$LIST_FILE" != /* && ! -f "$LIST_FILE" && -f "$script_dir/$LIST_FILE" ]] && LIST_FILE="$script_dir/$LIST_FILE"
[[ -z "$LOOT_DIR" ]] && LOOT_DIR="$script_dir"
LOOT_DIR="${LOOT_DIR%/}"
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

# old path (relative to LOOT_DIR) -> new path, for every newer-bundle archive in the list
declare -A target=() conflict=()
for (( n = 1; n < ${#lines[@]}; n++ )); do
    IFS=$'\x1f' read -r -a f <<< "${lines[$n]//$'\t'/$'\x1f'}"
    url="${f[${col[url]}]}"; file="${f[${col[file]}]}"
    kind="${f[${col[kind]:-99}]}"; [[ -z "$kind" ]] && kind="all"
    [[ "$kind" == "all" && -n "$file" && "$url" =~ ^https?://new-dls\.[^/]+/([^/?]+)/([^/?]+)/[^?]*/ ]] || continue
    old_dir="$(safe_name "$(urldecode "${BASH_REMATCH[1]}")")"
    new_dir="$(safe_name "$(urldecode "${BASH_REMATCH[2]}")")"
    [[ -n "$old_dir" && -n "$new_dir" && "$old_dir" != "$new_dir" ]] || continue
    old="$old_dir/$(safe_name "$file")"; new="$new_dir/$(safe_name "$file")"
    if [[ -n "${target[$old]}" && "${target[$old]}" != "$new" ]]; then conflict[$old]=1; fi
    target[$old]="$new"
done

if (( ${#target[@]} == 0 )); then
    echo -e "${GREEN}No newer bundles in the list - nothing to fix.${NC}"
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
    tmp="$LEDGER.tmp"; : > "$tmp"
    while IFS= read -r l || [[ -n "$l" ]]; do
        l="${l%$'\r'}"
        IFS=$'\x1f' read -r lkey lpath ldate <<< "${l//$'\t'/$'\x1f'}"
        if [[ -n "$lpath" && -n "${remap[$lpath]}" ]]; then
            l="$lkey"$'\t'"${remap[$lpath]}"; [[ -n "$ldate" ]] && l+=$'\t'"$ldate"
            ((updated++))
        fi
        printf '%s\n' "$l" >> "$tmp"
    done < "$LEDGER"
    if (( DRY_RUN )); then rm -f "$tmp"
    else cp -p "$LEDGER" "$LEDGER.bak" && mv -f "$tmp" "$LEDGER"; fi
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
