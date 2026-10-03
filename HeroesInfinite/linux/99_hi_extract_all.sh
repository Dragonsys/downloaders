#!/bin/bash
# ================================================================
# Heroes Infinite - extract all downloaded archives (optional)
#
# Extracts every .zip (and .rar / .7z, if unrar or 7z is installed) below HI_DIR.
# Each archive goes into its own "<archive name>_extracted" folder next to it, so
# files from different archives can never overwrite each other, and archives that
# are already extracted are skipped on later runs.
#
# Extraction happens in a temporary "<name>_extracted.part" folder that is renamed
# when it's complete, so an interrupted run never leaves a half-filled folder.
#
# Deleting the archives afterwards is safe for Heroes Infinite: 3_hi_download.sh
# remembers what it downloaded (HI_DIR/.hi_downloaded.tsv), so they aren't
# downloaded again. Set DELETE_AFTER_EXTRACT=1 to have this script do it.
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;94m'
NC='\033[0m'

# ==============================
# SETTINGS
# ==============================
# Where the Heroes Infinite files are (same as HI_DIR in 3_hi_download.sh).
# Empty = the folder this script is in.
HI_DIR=""
DELETE_AFTER_EXTRACT=0   # 1 = delete each archive after it was extracted successfully
FAILED_FILE="hi_failed_archives.txt"
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "$HI_DIR" ]] && HI_DIR="$script_dir"
[[ "$HI_DIR" != /* ]] && HI_DIR="$script_dir/$HI_DIR"
HI_DIR="${HI_DIR%/}"

echo -e "${BLUE}Heroes Infinite - extract archives${NC}"
printf "Folder:  ${YELLOW}%s${NC}\n" "$HI_DIR"
[[ -d "$HI_DIR" ]] || { echo -e "${RED}Folder not found: $HI_DIR${NC}"; exit 1; }

have() { command -v "$1" &>/dev/null; }
SEVENZ=""; for t in 7z 7za 7zz; do have "$t" && { SEVENZ="$t"; break; }; done
have unzip || [[ -n "$SEVENZ" ]] || { echo -e "${RED}Neither unzip nor 7z is installed (sudo apt install unzip).${NC}"; exit 1; }
can_rar=0; { have unrar || [[ -n "$SEVENZ" ]]; } && can_rar=1
can_7z=0;  [[ -n "$SEVENZ" ]] && can_7z=1
printf "Tools:   %s\n" "$( have unzip && printf 'unzip ' )$( have unrar && printf 'unrar ' )${SEVENZ}"
(( DELETE_AFTER_EXTRACT )) && printf "Mode:    ${YELLOW}archives are deleted after a successful extraction${NC}\n"
echo ""

# extract ARCHIVE DEST  - 0 = OK; error text in LAST_ERROR
extract() {
    local a="$1" d="$2" out rc
    case "${a,,}" in
        *.zip)
            if have unzip; then
                # -n: never overwrite; unzip refuses paths that would leave the destination
                out=$(unzip -q -n "$a" -d "$d" 2>&1); rc=$?
                (( rc <= 1 )) && return 0          # 1 = warnings only (e.g. odd file names)
            else
                out=$("$SEVENZ" x -y -bso0 -bsp0 "-o$d" -- "$a" 2>&1); rc=$?
                (( rc == 0 )) && return 0
            fi ;;
        *.rar)
            if have unrar; then out=$(unrar x -idq -o- "$a" "$d/" 2>&1); rc=$?
            else out=$("$SEVENZ" x -y -bso0 -bsp0 "-o$d" -- "$a" 2>&1); rc=$?; fi
            (( rc == 0 )) && return 0 ;;
        *.7z)
            out=$("$SEVENZ" x -y -bso0 -bsp0 "-o$d" -- "$a" 2>&1); rc=$?
            (( rc == 0 )) && return 0 ;;
    esac
    out="${out//"$HI_DIR/"/}"   # shorter messages: paths relative to HI_DIR
    LAST_ERROR="exit code $rc$( [[ -n "$out" ]] && printf ': %s' "$(printf '%s' "$out" | tr '\n' ' ' | head -c 200)")"
    return 1
}

# All archives below HI_DIR, but not inside folders this script made ("_extracted")
mapfile -d '' archives < <(find "$HI_DIR" -type f \( -iname '*.zip' -o -iname '*.rar' -o -iname '*.7z' \) \
    -not -path '*_extracted/*' -not -path '*_extracted.part/*' -print0 | sort -z)
total=${#archives[@]}
(( total )) || { echo "No archives found."; exit 0; }
echo "Found $total archive(s)"
echo ""

ok=0; already=0; failed=0; unsupported=0; deleted=0; n=0
: > "$FAILED_FILE"
for a in "${archives[@]}"; do
    n=$((n + 1))
    name="${a##*/}"; base="${name%.*}"
    dest="${a%/*}/${base}_extracted"
    label="[$n/$total] ${a#"$HI_DIR/"}"

    if [[ -d "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
        printf "  ${GREEN}✓${NC} %s ${YELLOW}(already extracted)${NC}\n" "$label"
        ((already++))
        if (( DELETE_AFTER_EXTRACT )); then rm -f -- "$a" && ((deleted++)); fi
        continue
    fi
    case "${a,,}" in
        *.rar) (( can_rar )) || { printf "  ${YELLOW}- %s: needs unrar or 7z${NC}\n" "$label"; ((unsupported++)); continue; } ;;
        *.7z)  (( can_7z ))  || { printf "  ${YELLOW}- %s: needs 7z${NC}\n" "$label"; ((unsupported++)); continue; } ;;
    esac

    tmp="${dest}.part"
    rm -rf -- "${tmp:?}"
    mkdir -p -- "$tmp" || { LAST_ERROR="cannot create $tmp"; ((failed++)); printf '%s\t%s\n' "$a" "$LAST_ERROR" >> "$FAILED_FILE"; continue; }
    printf "  ${BLUE}↓ Extracting${NC} %s ...\n" "$label"
    if extract "$a" "$tmp" && [[ -n "$(ls -A "$tmp")" ]]; then
        rm -rf -- "${dest:?}"            # an empty leftover folder from an earlier attempt
        mv -- "$tmp" "$dest"
        ((ok++))
        printf "  ${GREEN}✓ EXTRACTED${NC} %s\n" "${dest#"$HI_DIR/"}"
        if (( DELETE_AFTER_EXTRACT )); then rm -f -- "$a" && ((deleted++)); fi
    else
        [[ -z "$(ls -A "$tmp" 2>/dev/null)" && -z "$LAST_ERROR" ]] && LAST_ERROR="the archive is empty"
        rm -rf -- "${tmp:?}"
        ((failed++))
        printf "  ${RED}✗ FAILED${NC} %s: %s\n" "$label" "$LAST_ERROR"
        printf '%s\t%s\n' "$a" "$LAST_ERROR" >> "$FAILED_FILE"
    fi
    LAST_ERROR=""
done

echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e " Archives found:         ${BLUE}${total}${NC}"
echo -e " Extracted now:          ${GREEN}${ok}${NC}"
echo -e " Already extracted:      ${already}"
(( unsupported )) && echo -e " Skipped (missing tool): ${YELLOW}${unsupported}${NC} - install unrar / 7zip"
echo -e " Failed:                 ${RED}${failed}${NC}"
(( DELETE_AFTER_EXTRACT )) && echo -e " Archives deleted:       ${deleted}"
echo -e "${YELLOW}================================================${NC}"
if (( failed )); then echo -e "Failures are listed in ${YELLOW}${FAILED_FILE}${NC} - those archives were kept; they're retried on the next run."
else rm -f "$FAILED_FILE"; fi
