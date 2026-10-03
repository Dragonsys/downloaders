#!/bin/bash
# ================================================================
# Heroes Infinite - extract all downloaded archives, and sort them (optional)
#
# Extracts every .zip (and .rar / .7z, if unrar or 7z is installed) below HI_DIR.
#
# ORGANIZE=1 (default): each archive goes straight into a tidy folder inside its
# category folder (the folder the downloader put it in, e.g. "Bases", "Vampires"):
#   STL_<x>_SUPPORTED.zip    -> supported/
#   STL_<x>_UNSUPPORTED.zip  -> unsupported/
#   LYS_<x>_SUPPORTED.zip    -> lychee/
#   where <x> decides the sub-folder:
#     a size ("25mm_Round_Bases")       -> <category>/25mm/supported/ ...
#     the category itself ("Centerpiece" in "Centerpiece") -> <category>/supported/ ...
#     anything else ("King_Varkariack") -> <category>/King_Varkariack/supported/ ...
#   "Complete" archives (STL_Complete_...) are not extracted: they hold the same files
#     again. COMPLETE="delete" deletes them (and folders extracted from them earlier).
#   Names that don't fit the pattern go to <category>/<archive name>/.
#   If an archive's files sit inside one folder (even several levels, e.g.
#   LYS_Centerpiece_SUPPORTED/LYS_Centerpiece_SUPPORTED/...), they're moved up, so the
#   files end up directly in lychee/, supported/ ... The pictures folder "Images" that
#   the downloader makes is renamed to "images".
# ORGANIZE=0: each archive goes into its own "<archive name>_extracted" folder next to it.
#
# Nothing is overwritten: if two archives land in the same folder, existing files are kept.
# Extraction happens in a temporary folder first, so an interrupted run leaves nothing
# half-done. What was extracted where is remembered in HI_DIR/.hi_extracted.tsv, so later
# runs skip it - even after you've deleted the archives.
#
# Deleting the archives afterwards is safe for Heroes Infinite: 3_hi_download.sh remembers
# what it downloaded (HI_DIR/.hi_downloaded.tsv), so they aren't downloaded again.
#
# Run it with DRY_RUN=1 (the default) first: it only shows what it would do.
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
ORGANIZE=1               # 1 = sort into supported/ unsupported/ lychee/ ... (see above)
                         # 0 = each archive into "<archive name>_extracted" next to it
COMPLETE="delete"        # ORGANIZE=1: "delete" = delete "Complete" archives (and folders
                         # extracted from them earlier); "skip" = leave them alone
DELETE_AFTER_EXTRACT=0   # 1 = delete each archive after it was extracted successfully
DRY_RUN=1                # 1 = only show what would happen; 0 = do it
FAILED_FILE="hi_failed_archives.txt"
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "$HI_DIR" ]] && HI_DIR="$script_dir"
[[ "$HI_DIR" != /* ]] && HI_DIR="$script_dir/$HI_DIR"
HI_DIR="${HI_DIR%/}"
LEDGER="$HI_DIR/.hi_extracted.tsv"     # archive (relative) <TAB> target (relative) <TAB> date

echo -e "${BLUE}Heroes Infinite - extract archives${NC}"
printf "Folder:  ${YELLOW}%s${NC}\n" "$HI_DIR"
[[ -d "$HI_DIR" ]] || { echo -e "${RED}Folder not found: $HI_DIR${NC}"; exit 1; }

have() { command -v "$1" &>/dev/null; }
SEVENZ=""; for t in 7z 7za 7zz; do have "$t" && { SEVENZ="$t"; break; }; done
have unzip || [[ -n "$SEVENZ" ]] || { echo -e "${RED}Neither unzip nor 7z is installed (sudo apt install unzip).${NC}"; exit 1; }
can_rar=0; { have unrar || [[ -n "$SEVENZ" ]]; } && can_rar=1
can_7z=0;  [[ -n "$SEVENZ" ]] && can_7z=1
printf "Tools:   %s\n" "$( have unzip && printf 'unzip ' )$( have unrar && printf 'unrar ' )${SEVENZ}"
printf "Mode:    %s%s\n" "$( (( ORGANIZE )) && echo 'sort into supported / unsupported / lychee folders' || echo 'one <name>_extracted folder per archive')" \
    "$( (( DELETE_AFTER_EXTRACT )) && echo ', archives deleted after extracting')"
(( DRY_RUN )) && printf "         ${YELLOW}DRY RUN - nothing is changed (set DRY_RUN=0 to do it)${NC}\n"
echo ""

# ---------- helpers ----------
shopt -s dotglob nullglob

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

# flatten DIR - while DIR holds nothing but one folder, move that folder's contents up
# (handles X/X/files as well as Y/files)
flatten() {
    local d="$1" items hold
    while :; do
        items=("$d"/*)
        (( ${#items[@]} == 1 )) && [[ -d "${items[0]}" ]] || return 0
        hold="$d/.flatten_$$"
        mv -- "${items[0]}" "$hold" || return 1
        items=("$hold"/*)
        (( ${#items[@]} )) && { mv -- "${items[@]}" "$d"/ || return 1; }
        rmdir -- "$hold" || return 1
    done
}

# merge SRC DEST - move SRC's contents into DEST without overwriting anything
# (sets MERGE_KEPT to the number of files that already existed and were left in SRC)
merge() {
    local src="$1" dst="$2" e b
    mkdir -p -- "$dst"
    for e in "$src"/*; do
        b="${e##*/}"
        if [[ ! -e "$dst/$b" ]]; then mv -- "$e" "$dst/$b"
        elif [[ -d "$e" && -d "$dst/$b" ]]; then merge "$e" "$dst/$b"
        else MERGE_KEPT=$((MERGE_KEPT + 1)); fi
    done
}

# move_images SRC IMAGES_DIR - move the pictures in SRC (any depth) into IMAGES_DIR; an identical
# copy that's already there is dropped, a different one with the same name gets "_2", "_3" ...
move_images() {
    local src="$1" dst="$2" f b t i
    while IFS= read -r -d '' f; do
        mkdir -p -- "$dst"
        b="${f##*/}"; t="$dst/$b"
        if [[ -e "$t" ]]; then
            if cmp -s -- "$f" "$t"; then rm -f -- "$f"; continue; fi
            i=2; while [[ -e "$dst/${b%.*}_$i.${b##*.}" ]]; do
                cmp -s -- "$f" "$dst/${b%.*}_$i.${b##*.}" && { rm -f -- "$f"; continue 2; }
                i=$((i + 1))
            done
            t="$dst/${b%.*}_$i.${b##*.}"
        fi
        mv -- "$f" "$t" && IMAGES_MOVED=$((IMAGES_MOVED + 1))
    done < <(find "$src" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \) -print0)
    # folders that only held pictures are now empty
    find "$src" -mindepth 1 -type d -empty -delete 2>/dev/null
}

# norm TEXT - lower-case letters and digits only (to compare "Centerpiece" with "centerpiece")
norm() { local s="${1,,}"; printf "%s" "${s//[^a-z0-9]/}"; }

# target_for ARCHIVE - sets TARGET (absolute folder) and IS_COMPLETE (1/0)
target_for() {
    local a="$1" cat="${1%/*}" name base type item size
    name="${a##*/}"; base="${name%.*}"
    [[ "$base" =~ ^(.*)_[0-9]{4,}$ ]] && base="${BASH_REMATCH[1]}"   # "name_<download id>" from the downloader
    [[ "${base,,}" == *.stl ]] && base="${base%.*}"                   # "STL_Krya_Unsupported.stl.zip"
    IS_COMPLETE=0
    local m=1 pre sup
    # "supported" / "unsupported", also with the typos seen on the site:
    # Ssupported, Suported, SUPORTED, SUPPORED, SUPPORTER, Unsuporte, DUPPORTED ...
    local sw='(UN)?[SD]+U+P+O*R+T*E*[DR]?'
    local re1="^(STL|LYS|CHITU|CHITUBOX)_(.+[^_-])[_-]+${sw}(([_-]|[0-9]).*)?$"   # STL_<item>_SUPPORTED[-v3 ...]
    local re2="^${sw}_(.+)$"                                                       # Unsupported_<item>
    local re3="^(.+[^_-])[_-]+${sw}(([_-]|[0-9]).*)?$"                            # <item>_unsupported
    local re4="^(STL|LYS|CHITU|CHITUBOX)_(.+)$"                                   # STL_<item> (no support word)
    shopt -s nocasematch
    if   [[ "$base" =~ $re1 ]]; then m=0; pre="${BASH_REMATCH[1],,}"; item="${BASH_REMATCH[2]}"; sup="${BASH_REMATCH[3]:+un}supported"
    elif [[ "$base" =~ $re2 ]]; then m=0; pre="stl"; item="${BASH_REMATCH[2]}"; sup="${BASH_REMATCH[1]:+un}supported"
    elif [[ "$base" =~ $re3 ]]; then m=0; pre="stl"; item="${BASH_REMATCH[1]}"; sup="${BASH_REMATCH[2]:+un}supported"
    elif [[ "$base" =~ $re4 ]]; then m=0; pre="${BASH_REMATCH[1],,}"; item="${BASH_REMATCH[2]}"; sup=""
    fi
    shopt -u nocasematch
    if (( m == 0 )); then
        case "$pre" in
            lys)            type="lychee" ;;
            chitu|chitubox) type="chitubox" ;;
            *)  type="$sup"
                # STL_<item> without "supported": it's the supported version if the same folder
                # also has an unsupported one (e.g. Unsupported_<item>.zip), otherwise just "stl"
                if [[ -z "$type" ]]; then
                    type="stl"
                    local sib; for sib in "$cat"/*; do
                        local sb="${sib##*/}"; sb="${sb%.*}"
                        shopt -s nocasematch
                        if [[ "$sb" =~ ^UN[SD]+U+P+O*R+T*E*[DR]?_(.+)$ && "$(norm "${BASH_REMATCH[1]}")" == "$(norm "$item")" ]] || \
                           [[ "$sb" =~ ^STL_(.+[^_-])[_-]+UN[SD]+U+P+O*R+T*E*[DR]? && "$(norm "${BASH_REMATCH[1]}")" == "$(norm "$item")" ]]; then
                            type="supported"; shopt -u nocasematch; break
                        fi
                        shopt -u nocasematch
                    done
                fi ;;
        esac
        [[ "${item,,}" == complete || "${item,,}" == complete_* ]] && IS_COMPLETE=1
        if [[ "$item" =~ (^|_)([0-9]+mm)(_|$) ]]; then
            TARGET="$cat/${BASH_REMATCH[2],,}/$type"; IMAGES_DIR="$cat/images"
        elif [[ "$(norm "$item")" == "$(norm "${cat##*/}")" ]]; then
            TARGET="$cat/$type"; IMAGES_DIR="$cat/images"
        else
            TARGET="$cat/$item/$type"; IMAGES_DIR="$cat/$item/images"
        fi
    else
        TARGET="$cat/$base"; IMAGES_DIR=""          # unknown layout: leave its pictures where they are
    fi
}

# ---------- what was extracted before ----------
declare -A done_before=()
if [[ -f "$LEDGER" ]]; then
    while IFS=$'\t' read -r la lt _; do [[ -n "$la" ]] && done_before[$la]="$lt"; done < <(tr -d '\r' < "$LEDGER")
fi
record() { (( DRY_RUN )) || printf '%s\t%s\t%s\n' "$1" "$2" "$(date '+%Y-%m-%d %H:%M')" >> "$LEDGER"; }
rel() { printf '%s' "${1#"$HI_DIR/"}"; }

# Downloads that Heroes Infinite saved without an extension ("..._SUPPORTED" instead of
# "..._SUPPORTED.zip"): add the one their content shows, so they're found below.
# The downloader's ledger says which files are downloads; the new name is recorded there too.
DL_LEDGER="$HI_DIR/.hi_downloaded.tsv"
if [[ -f "$DL_LEDGER" ]]; then
    declare -A dl_path=()
    while IFS=$'\t' read -r lid lpath _; do [[ -n "$lid" ]] && dl_path[$lid]="$lpath"; done < <(tr -d '\r' < "$DL_LEDGER")
    noext=0
    for lid in "${!dl_path[@]}"; do
        lpath="${dl_path[$lid]}"
        [[ "$lpath" == "("* || ! -s "$HI_DIR/$lpath" ]] && continue
        [[ "${lpath,,}" =~ \.(zip|rar|7z|png|jpe?g|gif|webp|pdf|stl|obj|3mf|lys|chitubox|ctb|mp4|txt)$ ]] && continue
        case "$(head -c 4 "$HI_DIR/$lpath" | od -An -tx1 | tr -d ' \n')" in
            504b0304*|504b0506*) ext=zip ;;
            52617221*) ext=rar ;;
            377abcaf*) ext=7z ;;
            *) continue ;;
        esac
        new="$lpath.$ext"; [[ -e "$HI_DIR/$new" ]] && new="${lpath}_2.$ext"
        ((noext++))
        if (( DRY_RUN )); then
            printf "  ${YELLOW}would add the missing extension:${NC} %s (extracted on the real run)\n" "$new"
        else
            mv -n "$HI_DIR/$lpath" "$HI_DIR/$new" && printf '%s\t%s\t%s\n' "$lid" "$new" "$(date '+%Y-%m-%d %H:%M')" >> "$DL_LEDGER"
            printf "  ${BLUE}Added the missing extension:${NC} %s\n" "$new"
        fi
    done
    (( noext )) && echo ""
fi

# All archives below HI_DIR, but not inside folders made from archives (nested zips stay as they are)
mapfile -d '' archives < <(find "$HI_DIR" -type f \( -iname '*.zip' -o -iname '*.rar' -o -iname '*.7z' \) \
    -not -path '*_extracted/*' -not -path '*_extracted.part/*' -not -path '*/.extract_*' \
    -not -path '*/supported/*' -not -path '*/unsupported/*' -not -path '*/lychee/*' -not -path '*/chitubox/*' -print0 | sort -z)
total=${#archives[@]}
echo "Found $total archive(s)"
echo ""

ok=0; already=0; failed=0; unsupported=0; deleted=0; complete=0; kept_total=0; n=0; IMAGES_MOVED=0
(( DRY_RUN )) || : > "$FAILED_FILE"
fail() { ((failed++)); printf "  ${RED}✗ FAILED${NC} %s: %s\n" "$1" "$LAST_ERROR"; (( DRY_RUN )) || printf '%s\t%s\n' "$2" "$LAST_ERROR" >> "$FAILED_FILE"; }

for a in "${archives[@]}"; do
    n=$((n + 1))
    ar="$(rel "$a")"; name="${a##*/}"; base="${name%.*}"
    label="[$n/$total] $ar"
    LAST_ERROR=""

    if (( ORGANIZE )); then
        target_for "$a"
        if (( IS_COMPLETE )); then
            ((complete++))
            if [[ "$COMPLETE" == "delete" ]]; then
                (( DRY_RUN )) && printf "  ${YELLOW}- %s: \"Complete\" archive - would be deleted${NC}\n" "$label" \
                              || { rm -f -- "$a" && ((deleted++)); printf "  ${YELLOW}- %s: \"Complete\" archive - deleted${NC}\n" "$label"; }
                # folders extracted from it by an earlier run
                for old in "${a%/*}/$base" "${a%/*}/${base}_extracted"; do
                    [[ -d "$old" ]] || continue
                    (( DRY_RUN )) && printf "    would delete folder %s\n" "$(rel "$old")" || { rm -rf -- "${old:?}"; printf "    deleted folder %s\n" "$(rel "$old")"; }
                done
            else
                printf "  ${YELLOW}- %s: \"Complete\" archive - skipped${NC}\n" "$label"
            fi
            continue
        fi
    else
        TARGET="${a%/*}/${base}_extracted"
    fi
    tr_="$(rel "$TARGET")"

    # Extracted before? (recorded, or - without sorting - its _extracted folder exists)
    if [[ -n "${done_before[$ar]}" ]] || { (( ! ORGANIZE )) && [[ -d "$TARGET" && -n "$(ls -A "$TARGET" 2>/dev/null)" ]]; }; then
        printf "  ${GREEN}✓${NC} %s ${YELLOW}(already extracted)${NC}\n" "$label"
        ((already++))
        if (( DELETE_AFTER_EXTRACT && ! DRY_RUN )); then rm -f -- "$a" && ((deleted++)); fi
        continue
    fi
    case "${a,,}" in
        *.rar) (( can_rar )) || { printf "  ${YELLOW}- %s: needs unrar or 7z${NC}\n" "$label"; ((unsupported++)); continue; } ;;
        *.7z)  (( can_7z ))  || { printf "  ${YELLOW}- %s: needs 7z${NC}\n" "$label"; ((unsupported++)); continue; } ;;
    esac

    if (( DRY_RUN )); then
        printf "  ${BLUE}->${NC} %s  =>  %s/\n" "$label" "$tr_"
        ((ok++)); continue
    fi

    # Extract into a temporary folder next to the target, tidy it, then move it into place
    tmp="${a%/*}/.extract_${n}_$$"
    rm -rf -- "${tmp:?}"; mkdir -p -- "$tmp" || { LAST_ERROR="cannot create a temporary folder"; fail "$label" "$a"; continue; }
    printf "  ${BLUE}↓ Extracting${NC} %s ...\n" "$label"
    if ! extract "$a" "$tmp"; then rm -rf -- "${tmp:?}"; fail "$label" "$a"; continue; fi
    if [[ -z "$(ls -A "$tmp")" ]]; then rm -rf -- "${tmp:?}"; LAST_ERROR="the archive is empty"; fail "$label" "$a"; continue; fi
    (( ORGANIZE )) && { flatten "$tmp" || { rm -rf -- "${tmp:?}"; LAST_ERROR="could not tidy up the folders"; fail "$label" "$a"; continue; }; }
    # Pictures inside the archive go to the model's images folder (the same pictures are in
    # the SUPPORTED, UNSUPPORTED and LYS archives - identical copies are kept only once)
    (( ORGANIZE )) && [[ -n "$IMAGES_DIR" ]] && move_images "$tmp" "$IMAGES_DIR"
    MERGE_KEPT=0
    if [[ -e "$TARGET" ]]; then
        merge "$tmp" "$TARGET"            # another archive already filled it: add, never overwrite
    else
        mkdir -p -- "${TARGET%/*}" && mv -- "$tmp" "$TARGET"
    fi
    rm -rf -- "${tmp:?}"
    record "$ar" "$tr_"
    ((ok++)); kept_total=$((kept_total + MERGE_KEPT))
    printf "  ${GREEN}✓ EXTRACTED${NC} => %s/%s\n" "$tr_" "$( (( MERGE_KEPT )) && printf " ${YELLOW}(%s file(s) were already there and were kept)${NC}" "$MERGE_KEPT")"
    if (( DELETE_AFTER_EXTRACT )); then rm -f -- "$a" && ((deleted++)); fi
done

# Pictures folder from the downloader: "Images" -> "images"
renamed_images=0
if (( ORGANIZE )); then
    while IFS= read -r -d '' d; do
        p="${d%/*}"
        if (( DRY_RUN )); then printf "  ${BLUE}->${NC} %s  =>  %s\n" "$(rel "$d")" "$(rel "$p")/images"
        else
            # Via a temporary name: on file systems that ignore case (e.g. many network shares)
            # "Images" and "images" are the same folder
            hold="$p/.images_$$"
            mv -- "$d" "$hold" || continue
            if [[ -e "$p/images" ]]; then MERGE_KEPT=0; merge "$hold" "$p/images"; rm -rf -- "${hold:?}"
            else mv -- "$hold" "$p/images"; fi
        fi
        ((renamed_images++))
    done < <(find "$HI_DIR" -mindepth 2 -type d -name Images -print0)
fi

echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e " Archives found:         ${BLUE}${total}${NC}"
echo -e " $( (( DRY_RUN )) && echo 'Would extract:   ' || echo 'Extracted now:   ')       ${GREEN}${ok}${NC}"
echo -e " Already extracted:      ${already}"
(( ORGANIZE )) && echo -e " \"Complete\" archives:    ${complete}$( [[ "$COMPLETE" == delete ]] && echo " ($( (( DRY_RUN )) && echo 'would be ' )deleted)")"
(( ORGANIZE && renamed_images )) && echo -e " Images -> images:       ${renamed_images}"
(( ORGANIZE && IMAGES_MOVED )) && echo -e " Pictures to images/:    ${IMAGES_MOVED} (identical copies kept once)"
(( unsupported )) && echo -e " Skipped (missing tool): ${YELLOW}${unsupported}${NC} - install unrar / 7zip"
echo -e " Failed:                 ${RED}${failed}${NC}"
(( kept_total )) && echo -e " Files kept (not overwritten): ${YELLOW}${kept_total}${NC}"
(( deleted && ! DRY_RUN )) && echo -e " Archives deleted:       ${deleted}"
echo -e "${YELLOW}================================================${NC}"
if (( DRY_RUN )); then echo -e "${YELLOW}Dry run - nothing was changed.${NC} If this looks right, set DRY_RUN=0 and run it again."
elif (( failed )); then echo -e "Failures are listed in ${YELLOW}${FAILED_FILE}${NC} - those archives were kept; they're retried on the next run."
else rm -f "$FAILED_FILE"; fi
