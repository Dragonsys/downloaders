#!/bin/bash
# ================================================================
# Heroes Infinite - move extracted model files into a "files" folder
#
# Earlier versions of 99_hi_extract_all.sh put a model's type folders straight into the
# model's folder:
#   <collection>/<category>/<Model>/supported/  unsupported/  lychee/  chitubox/  stl/
# Now they go into a "files" folder next to the pictures:
#   <collection>/<category>/<Model>/images/
#   <collection>/<category>/<Model>/files/supported/  unsupported/  lychee/ ...
# This script moves folders extracted the old way. A category's own files
# (<category>/supported/ ...) and sizes (<category>/25mm/supported/ ...) stay as they are.
# The paths in HI_DIR/.hi_extracted.tsv are updated too. Nothing is overwritten; running it
# again is harmless.
#
# Run it with DRY_RUN=1 (the default) first: it only shows what it would move.
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;94m'
NC='\033[0m'

# ==============================
# SETTINGS
# ==============================
# Where the Heroes Infinite files are (same as HI_DIR in 99_hi_extract_all.sh).
# Empty = the folder this script is in.
HI_DIR=""
DRY_RUN=1                # 1 = only show what would be moved; 0 = move
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "$HI_DIR" ]] && HI_DIR="$script_dir"
[[ "$HI_DIR" != /* ]] && HI_DIR="$script_dir/$HI_DIR"
HI_DIR="${HI_DIR%/}"
LEDGER="$HI_DIR/.hi_extracted.tsv"

echo -e "${BLUE}Heroes Infinite - move model files into <Model>/files/${NC}"
printf "Folder:  ${YELLOW}%s${NC}\n" "$HI_DIR"
[[ -d "$HI_DIR" ]] || { echo -e "${RED}Folder not found: $HI_DIR${NC}"; exit 1; }
(( DRY_RUN )) && printf "         ${YELLOW}DRY RUN - nothing is changed (set DRY_RUN=0 to do it)${NC}\n"
echo ""

shopt -s dotglob nullglob
TYPES_RE='^(supported|unsupported|lychee|chitubox|stl)$'
SIZE_RE='^[0-9]+mm$'
rel() { printf '%s' "${1#"$HI_DIR/"}"; }

# merge SRC DEST - move SRC's contents into DEST without overwriting (KEPT counts what stays)
KEPT=0
merge() {
    local src="$1" dst="$2" e b
    mkdir -p -- "$dst"
    for e in "$src"/*; do
        b="${e##*/}"
        if [[ ! -e "$dst/$b" ]]; then mv -- "$e" "$dst/$b"
        elif [[ -d "$e" && -d "$dst/$b" ]]; then merge "$e" "$dst/$b"
        elif cmp -s -- "$e" "$dst/$b"; then rm -f -- "$e"
        else KEPT=$((KEPT + 1)); printf "    ${YELLOW}kept (a different file is already there): %s${NC}\n" "$(rel "$e")"; fi
    done
    rmdir -- "$src" 2>/dev/null
}

models=0; moved=0
declare -A remap=()
# <collection>/<category>/<Model>/<type>/
for m in "$HI_DIR"/*/*/*/; do
    m="${m%/}"; name="${m##*/}"
    [[ "$name" == .* || "${name,,}" == images || "${name,,}" == files || "$name" =~ $TYPES_RE || "$name" =~ $SIZE_RE ]] && continue
    found=0
    for t in "$m"/*/; do
        t="${t%/}"; tn="${t##*/}"
        [[ "$tn" =~ $TYPES_RE ]] || continue
        (( found )) || { models=$((models + 1)); found=1; }
        printf "  ${BLUE}->${NC} %s/  =>  %s/files/%s/\n" "$(rel "$t")" "$(rel "$m")" "$tn"
        remap["$(rel "$t")"]="$(rel "$m")/files/$tn"
        moved=$((moved + 1))
        (( DRY_RUN )) && continue
        if [[ -e "$m/files/$tn" ]]; then merge "$t" "$m/files/$tn"
        else mkdir -p -- "$m/files" && mv -- "$t" "$m/files/$tn"; fi
    done
done

# Paths in .hi_extracted.tsv (archive <TAB> target <TAB> date)
updated=0
if [[ -f "$LEDGER" && ${#remap[@]} -gt 0 ]]; then
    tmp="$LEDGER.tmp"; (( DRY_RUN )) && tmp=/dev/null || : > "$tmp"
    while IFS= read -r l || [[ -n "$l" ]]; do
        l="${l%$'\r'}"
        IFS=$'\x1f' read -r la lt ld <<< "${l//$'\t'/$'\x1f'}"
        if [[ -n "$lt" && -n "${remap[$lt]}" ]]; then
            l="$la"$'\t'"${remap[$lt]}"; [[ -n "$ld" ]] && l+=$'\t'"$ld"
            updated=$((updated + 1))
        fi
        printf '%s\n' "$l" >> "$tmp"
    done < "$LEDGER"
    (( DRY_RUN )) || { cp -p "$LEDGER" "$LEDGER.bak" && mv -f "$tmp" "$LEDGER"; }
fi

echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e " Models:                 ${BLUE}${models}${NC}"
echo -e " Type folders $( (( DRY_RUN )) && echo 'to move:' || echo 'moved:  ' )  ${GREEN}${moved}${NC}"
echo -e " Record lines updated:   ${updated}$( [[ -f "$LEDGER" ]] || echo ' (no .hi_extracted.tsv)')"
(( KEPT )) && echo -e " Files kept in place:    ${RED}${KEPT}${NC} (a different file with the same name was already in files/)"
echo -e "${YELLOW}================================================${NC}"
if (( DRY_RUN )); then echo -e "${YELLOW}Dry run - nothing was changed.${NC} If this looks right, set DRY_RUN=0 and run it again."
else [[ -f "$LEDGER.bak" ]] && echo "The previous record was saved as .hi_extracted.tsv.bak."; fi
