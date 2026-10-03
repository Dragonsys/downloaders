#!/bin/bash
# ================================================================
# Loot Studios - extract all downloaded zips and sort them by model
#
# A Loot Studios zip holds a whole bundle (or part of one) in folders like
#   All_ShadowCourt_32mm/All_ShadowCourt_32mm_LYCHEE/2-Enemies/DeathGiant_32mm_LYCHEE/...
#   All_CelticDawn_32mm/All_Enemies_CelticDawn_32mm/CelticDawn_Enemies_32mm_UnSupported/Selkie_32mm_Unsupported/...
# Every model's folder name says the model, the scale and the type. This script puts each
# model's files into its bundle folder as
#
#   <bundle>/<group>/<Model>-<type>/<scale>/      e.g. ShadowCourt/Enemies/DeathGiant-lychee/32mm/
#   <bundle>/<group>/images/                      the model pictures (each picture kept once)
#
#   type:  lychee      LYCHEE, Supported_LYCHEE, Supported_SLICER (.lys files)
#          supported   ReadyToSlice, Supported
#          hollow      Supported_Hollow          solid  Supported_Solid
#          unsupported UnSupported, NoSupports   chitubox  Supported_CHITUBOX
#          fdm         FDM                       3mf    3mf
#   scale: 32mm, 75mm, bust, prop ... (from the folder names or the zip's name)
#   group: Heroes, Enemies, Environment, Prop ... (from the folders above the model). Busts
#          usually have no group: they go to the group their model has in the bundle's other
#          zips, otherwise to "Busts".
# Parts in subfolders stay in subfolders (Megalodon-lychee/32mm/SharkTail/...). Zips inside
# zips are extracted too. Thumbs.db / desktop.ini are dropped. Anything that can't be placed
# keeps its folders in <bundle>/<zip name>/.
# The pictures the downloader saved in <bundle>/Images/<group>/ move to <bundle>/<group>/images/.
#
# Nothing is overwritten. Each zip is extracted in a temporary folder first, so an interrupted
# run leaves nothing half-done. What was extracted is remembered in LOOT_DIR/.loot_extracted.tsv,
# so later runs skip it - even after you've deleted the zips.
#
# Deleting the zips afterwards is safe: 3_loot_download_all_bundles.sh remembers what it
# downloaded (LOOT_DIR/.loot_downloaded.tsv), so they aren't downloaded again.
#
# Run it with DRY_RUN=1 (the default) first: it only reads the zips' tables of contents and
# shows where everything would go (full list in loot_extract_plan.tsv).
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;94m'
NC='\033[0m'

# ==============================
# SETTINGS
# ==============================
# Where the Loot Studios bundles are (same as LOOT_DIR in 3_loot_download_all_bundles.sh).
# Empty = the folder this script is in.
LOOT_DIR=""
BUSTS_GROUP="Busts"      # group folder for busts whose model isn't in another group of the bundle
MOVE_IMAGES=1            # 1 = move the downloader's <bundle>/Images/<group>/ to <bundle>/<group>/images/
DELETE_AFTER_EXTRACT=0   # 1 = delete each zip after it was extracted completely
KEEP_READMES=0           # 1 = keep the "... - Read me.txt" notes Loot puts next to the folders
                         #     (and "There are no files that would go in this folder.txt")
DRY_RUN=1                # 1 = only show what would happen; 0 = do it
SHOW_FOLDERS=5           # dry run: model folders shown per zip (the full list is in PLAN_FILE)
PLAN_FILE="loot_extract_plan.tsv"
FAILED_FILE="loot_failed_archives.txt"
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "$LOOT_DIR" ]] && LOOT_DIR="$script_dir"
[[ "$LOOT_DIR" != /* ]] && LOOT_DIR="$script_dir/$LOOT_DIR"
LOOT_DIR="${LOOT_DIR%/}"
LEDGER="$LOOT_DIR/.loot_extracted.tsv"     # zip (relative) <TAB> what happened <TAB> date

echo -e "${BLUE}Loot Studios - extract and sort zips${NC}"
printf "Folder:  ${YELLOW}%s${NC}\n" "$LOOT_DIR"
[[ -d "$LOOT_DIR" ]] || { echo -e "${RED}Folder not found: $LOOT_DIR${NC}"; exit 1; }

have() { command -v "$1" &>/dev/null; }
SEVENZ=""; for t in 7z 7za 7zz; do have "$t" && { SEVENZ="$t"; break; }; done
have unzip || [[ -n "$SEVENZ" ]] || { echo -e "${RED}Neither unzip nor 7z is installed (sudo apt install unzip).${NC}"; exit 1; }
have unzip || echo -e "${YELLOW}Note: without unzip the dry run can't look inside the zips (sudo apt install unzip).${NC}"
(( DRY_RUN )) && printf "         ${YELLOW}DRY RUN - nothing is changed (set DRY_RUN=0 to do it)${NC}\n"
echo ""

shopt -s dotglob nullglob

# ================================================================
# Recognising model folders
# (helpers set variables instead of printing: no subshells, so thousands of folders stay fast)
# ================================================================

# norm TEXT - sets NORM: lower-case letters and digits only
norm() { NORM="${1,,}"; NORM="${NORM//[^a-z0-9]/}"; }

# Folder-name endings -> type. Checked in this order, case doesn't matter, "_", "-" and " " all
# count as separators. Tolerates the typos seen in real zips (LYHCEE, UnSuppoted, NoSuppports,
# ReadyToSlicer, ReadyToPrint).
TYPE_RULES=(
    'Supported[_ -]*(LY[CH]+E+|SLICER)|LY[CH]+E+|SLICER|LYS=lychee'
    'Supported[_ -]*CHITU(BOX)?|CHITU(BOX)?=chitubox'
    'Supported[_ -]*Solid|Solid[_ -]*Supported|Solid=solid'
    'Supported[_ -]*Hollow|Hollow[_ -]*Supported|Hollow=hollow'
    'Un[_ -]*Sup+or?te?d|No[_ -]*Sup+or?ts?|No[_ -]*Sup+or?ted=unsupported'
    'Ready[_ -]*To[_ -]*(Slicer?|Print)|Pre[_ -]*Sup+or?ted|Sup+or?ted=supported'
    '3mf=3mf'
    'FDM=fdm'
)
SCALE_RE='[0-9]+mm|Busts?|Buts|Props?|EpicScale|Statue'
declare -a TYPE_RE1=() TYPE_RE2=() TYPE_NAME=()
for r in "${TYPE_RULES[@]}"; do
    TYPE_RE1+=("^(.*[^_ -])[_ -]+(${r%=*})\$"); TYPE_RE2+=("^(${r%=*})\$"); TYPE_NAME+=("${r##*=}")
done
SCALE_END_RE="^(.*[^_ -])[_ -]+($SCALE_RE)\$"
SCALE_ANY_RE="(^|[_ -])($SCALE_RE)([_ -]|\$)"
SCALE_ONLY_RE="^($SCALE_RE)\$"
NUMBERED_RE='^[0-9]+[[:space:]]+(.*)$'
VERSION_RE='^(.*[^_ -])[_ -]+(V[0-9]+|[0-9]{1,2})$'
LEFTOVER_RE='^(.*[^_ -])[_ -]+Sup+or?ted$'

# split_type NAME - if NAME ends in a type word: sets ST_TYPE and ST_REST (NAME without it,
# a version suffix like "_V2" kept: "Argenturam_75mm_Supported_Hollow_V2" -> Argenturam_75mm_V2)
split_type() {
    local i n="$1" ver=""
    ST_TYPE=""; ST_REST="$n"
    shopt -s nocasematch
    while :; do
        for i in "${!TYPE_NAME[@]}"; do
            if [[ "$n" =~ ${TYPE_RE1[$i]} ]]; then ST_TYPE="${TYPE_NAME[$i]}"; ST_REST="${BASH_REMATCH[1]}"; break; fi
            if [[ "$n" =~ ${TYPE_RE2[$i]} ]]; then ST_TYPE="${TYPE_NAME[$i]}"; ST_REST=""; break; fi
        done
        [[ -n "$ST_TYPE" || -n "$ver" || ! "$n" =~ $VERSION_RE ]] && break
        n="${BASH_REMATCH[1]}"; ver="${BASH_REMATCH[2]}"
    done
    # "X_Supported_Hollow" matches "Hollow" first: drop the "Supported" that's left
    [[ -n "$ST_TYPE" && "$ST_REST" =~ $LEFTOVER_RE ]] && ST_REST="${BASH_REMATCH[1]}"
    shopt -u nocasematch
    # "FDM" stuck to the name: "SilentCoinTaproomFDM", "ArchieOwlbearWizard(FDM)", "FDMSwamphut"
    if [[ -z "$ST_TYPE" ]]; then
        if [[ "$n" =~ ^(.*[a-z0-9])\(?FDM\)?$ ]]; then ST_TYPE=fdm; ST_REST="${BASH_REMATCH[1]}"
        elif [[ "$n" =~ ^FDM([A-Z].*)$ ]]; then ST_TYPE=fdm; ST_REST="${BASH_REMATCH[1]}"; fi
    fi
    [[ -n "$ST_TYPE" && -n "$ver" ]] && ST_REST_VER="$ver" || ST_REST_VER=""
    [[ -n "$ST_TYPE" ]]
}

# cut_scale NAME - sets CS_NAME (NAME without a trailing scale) and CS_SCALE
cut_scale() {
    CS_NAME="$1"; CS_SCALE=""
    shopt -s nocasematch
    if [[ "$1" =~ $SCALE_END_RE ]]; then CS_NAME="${BASH_REMATCH[1]}"; CS_SCALE="${BASH_REMATCH[2],,}"
    elif [[ "$1" =~ $SCALE_ONLY_RE ]]; then CS_NAME=""; CS_SCALE="${BASH_REMATCH[1],,}"; fi
    shopt -u nocasematch
    case "$CS_SCALE" in busts|buts) CS_SCALE=bust ;; props) CS_SCALE=prop ;; esac
}

# scale_word TEXT - sets SCALE to the scale anywhere in TEXT, or ""
scale_word() {
    SCALE=""
    shopt -s nocasematch
    [[ "$1" =~ $SCALE_ANY_RE ]] && SCALE="${BASH_REMATCH[2],,}"
    shopt -u nocasematch
    case "$SCALE" in busts|buts) SCALE=bust ;; props) SCALE=prop ;; esac
}

# group_word COMPONENT [NORMED_NAMES_TO_DROP...] - sets GROUP to what's left of a folder name like
# "All_Enemies_CelticDawn_32mm", "CelticDawn_Enemies_32mm_LYCHEE", "1-Heroes", "3 - Environment"
# once "All", the bundle name, scale, type and numbering are removed; GROUP_HAD_BUNDLE=1 if a
# bundle name or "All" was removed (= a folder holding many models, not a model)
group_word() {
    local c="$1" t b skip; shift
    GROUP=""; GROUP_HAD_BUNDLE=0
    c="${c//-/ }"; c="${c//_/ }"
    [[ "$c" =~ $NUMBERED_RE ]] && c="${BASH_REMATCH[1]}"
    for t in $c; do
        norm "$t"
        case "$NORM" in
            "") continue ;;
            all|downloadall) GROUP_HAD_BUNDLE=1; continue ;;
            extra|extras|resin|supports|ready|to|slice|no|un) continue ;;
        esac
        shopt -s nocasematch
        if [[ "$t" =~ $SCALE_ONLY_RE ]]; then shopt -u nocasematch; continue; fi
        shopt -u nocasematch
        split_type "$t" && [[ -z "$ST_REST" ]] && continue
        skip=0; for b in "$@"; do [[ -n "$b" && ( "$NORM" == "$b" || "$NORM" == "all$b" ) ]] && { skip=1; break; }; done
        (( skip )) && { GROUP_HAD_BUNDLE=1; continue; }
        GROUP="${GROUP:+$GROUP }$t"
    done
}

# classify DIR ZIP_REL - DIR is a folder inside the zip (a/b/c) that holds files.
# Sets C_TYPE ("" = not recognised), C_MODEL, C_SCALE, C_GROUP, C_SUB (folders below the model's)
classify() {
    local p="$1" arel="$2" i m=-1 mi g mn b1 b3 abase rest
    local -a parts
    C_MODEL=""; C_TYPE=""; C_SCALE=""; C_GROUP=""; C_SUB=""
    IFS=/ read -r -a parts <<< "$p"
    (( ${#parts[@]} )) || return
    abase="${arel##*/}"; abase="${abase%.*}"
    # bundle names to ignore inside folder names: the bundle folder and the zip's own name
    # without "All" and scale ("All_ShadowCourt_32mm" -> ShadowCourt)
    norm "${arel%%/*}"; b1="$NORM"
    group_word "$abase"; norm "$GROUP"; b3="$NORM"
    # the model's folder: the deepest folder whose name ends in a type word
    for (( i=${#parts[@]}-1; i>=0; i-- )); do
        if split_type "${parts[$i]}"; then m=$i; break; fi
    done
    (( m < 0 )) && return
    # a bare "Hollow" / "Solid" folder inside a model's folder ("Layer2_Supported_LYCHEE/Hollow"):
    # the model's folder is the parent, the bare one stays a subfolder
    if [[ -z "$ST_REST" ]] && (( m > 0 )) && split_type "${parts[$((m - 1))]}" && [[ -n "$ST_REST" ]]; then
        m=$((m - 1))
    else
        split_type "${parts[$m]}"
    fi
    C_TYPE="$ST_TYPE"; rest="$ST_REST"; local ver="$ST_REST_VER"
    cut_scale "$rest"; rest="$CS_NAME"; C_SCALE="$CS_SCALE"
    mi=$m
    if (( m < ${#parts[@]}-1 )); then
        # a folder like "CelticDawn_Heroes_32mm_UnSupported" or "All_Bundle_LYCHEE" holds many
        # models: the model is the folder below it
        group_word "${parts[$m]}" "$b1" "$b3"
        if [[ -z "$rest" ]] || (( GROUP_HAD_BUNDLE )); then
            mi=$((m + 1)); rest="${parts[$mi]}"; ver=""
            cut_scale "$rest"; rest="$CS_NAME"; [[ -n "$CS_SCALE" ]] && C_SCALE="$CS_SCALE"
        fi
    fi
    # only a type in the name ("Gate/LYCHEE/...", "Bust_Bases/Supported/Hollow/..."): the model
    # is the nearest folder above that has more than a type in its name
    if [[ -z "$rest" ]]; then
        for (( i=mi-1; i>=0; i-- )); do
            split_type "${parts[$i]}" && [[ -z "$ST_REST" ]] && continue
            rest="${parts[$i]}"; split_type "$rest" && rest="$ST_REST"
            cut_scale "$rest"; rest="$CS_NAME"; [[ -z "$C_SCALE" ]] && C_SCALE="$CS_SCALE"
            break
        done
    fi
    [[ -z "$rest" ]] && rest="$abase"
    # drop "All", the bundle name and a scale in front ("AllWelcomePack3.0v2_32mm_SilentCoinTaproom")
    local first
    while [[ "$rest" == *_* ]]; do
        first="${rest%%_*}"; norm "$first"
        if [[ "$NORM" == all || "$NORM" == "$b1" || "$NORM" == "all$b1" ]]; then rest="${rest#*_}"; continue; fi
        cut_scale "$first"; [[ "$CS_SCALE" == *mm && -z "$CS_NAME" ]] && { [[ -z "$C_SCALE" ]] && C_SCALE="$CS_SCALE"; rest="${rest#*_}"; continue; }
        break
    done
    C_MODEL="$rest${ver:+_$ver}"
    for (( i=mi+1; i<${#parts[@]}; i++ )); do C_SUB="${C_SUB:+$C_SUB/}${parts[$i]}"; done
    # scale not in the model's folder name: from a parent folder, else from the zip's name
    if [[ -z "$C_SCALE" ]]; then
        SCALE=""
        for (( i=mi-1; i>=0; i-- )); do scale_word "${parts[$i]}"; [[ -n "$SCALE" ]] && break; done
        [[ -z "$SCALE" ]] && scale_word "$abase"
        [[ -z "$SCALE" ]] && SCALE="${DL_SCALE[/$arel]}"                 # what the downloader knew
        [[ -z "$SCALE" && "$arel" == */*/* ]] && { g="${arel%/*}"; scale_word "${g##*/}"; }   # downloader folder "Prop"
        C_SCALE="$SCALE"
    fi
    # group: the nearest folder above the model's that names one (and isn't the model itself)
    norm "$C_MODEL"; mn="$NORM"
    for (( i=mi-1; i>=0; i-- )); do
        group_word "${parts[$i]}" "$b1" "$b3"
        [[ -z "$GROUP" ]] && continue
        norm "$GROUP"; [[ "$NORM" == "$mn" ]] && continue
        cut_scale "${parts[$i]}"; norm "$CS_NAME"; [[ "$NORM" == "$mn" ]] && continue   # "Oogle_32mm", "X - Extra Head"
        C_GROUP="$GROUP"; break
    done
    # single-figure downloads: the downloader put them in <bundle>/<group>/file.zip
    if [[ -z "$C_GROUP" && "$arel" == */*/* ]]; then
        g="${arel#*/}"; g="${g%%/*}"; norm "$g"
        [[ "$NORM" != "$mn" ]] && C_GROUP="$g"
    fi
}

# ================================================================
# Group folders: one per group and bundle, whatever the spelling
# ("Prop"/"Props", "NPC"/"NPCs", "Enviroment", "heroes" -> the first one used)
# ================================================================
declare -A GROUP_DIR=() MODEL_GROUP=() BUNDLE_SCANNED=()

group_key() {
    norm "$1"; GKEY="$NORM"
    [[ "$GKEY" == enviroment* ]] && GKEY="environment${GKEY#enviroment}"
    (( ${#GKEY} > 3 )) && GKEY="${GKEY%s}"
}

# group_dir BUNDLE GROUP - sets GDIR: the folder name to use for GROUP in BUNDLE
group_dir() {
    local b="$1" g="$2" d n key
    group_key "$g"; key="$GKEY"
    if [[ -z "${GROUP_DIR[$b|$key]}" ]]; then
        [[ "${g,,}" == enviroment* ]] && g="Environment${g:10}"
        GROUP_DIR[$b|$key]="$g"
        for d in "$LOOT_DIR/$b"/*/; do        # an existing folder for that group, any spelling
            n="${d%/}"; n="${n##*/}"
            [[ "$n" == .* || "${n,,}" == images ]] && continue
            group_key "$n"
            [[ "$GKEY" == "$key" ]] && { GROUP_DIR[$b|$key]="$n"; break; }
        done
    fi
    GDIR="${GROUP_DIR[$b|$key]}"
}

# zip_dirs ZIP - fills ZDIRS with the folders of the files in ZIP, from its table of contents
# (a zip inside counts as a folder of its own name; files at the top count as folder "")
zip_dirs() {
    local e d
    ZDIRS=(); ZFILES=0
    declare -A seen=()
    while IFS= read -r e; do
        e="${e%$'\r'}"
        [[ -z "$e" || "$e" == */ ]] && continue
        ZFILES=$((ZFILES + 1))
        d="${e##*/}"; d="${d,,}"
        [[ "$d" =~ $JUNK_RE ]] && continue
        (( ! KEEP_READMES )) && [[ "$d" =~ $README_RE ]] && continue
        if [[ "${e,,}" == *.zip ]]; then d="${e%.*}"
        elif [[ "$e" == */* ]]; then d="${e%/*}"
        else d=""; fi
        [[ -n "${seen[/$d]+x}" ]] && continue
        seen[/$d]=1; ZDIRS+=("$d")
    done < <(unzip -Z1 "$1" 2>/dev/null)
}

# scan_bundle BUNDLE - learn which group each model of the bundle is in (from all its zips and
# from folders sorted earlier), so a bust can go to its model's group
scan_bundle() {
    local b="$1" a d n
    [[ -n "${BUNDLE_SCANNED[$b]}" ]] && return
    BUNDLE_SCANNED[$b]=1
    for d in "$LOOT_DIR/$b"/*/*-*/; do
        n="${d%/}"; n="${n##*/}"; n="${n%-*}"; norm "$n"
        d="${d%/*/}"; d="${d##*/}"
        [[ -n "$NORM" && -z "${MODEL_GROUP[$b|$NORM]}" ]] && MODEL_GROUP[$b|$NORM]="$d"
    done
    have unzip || return
    for a in "${archives[@]}"; do
        [[ "$(rel "$a")" == "$b"/* ]] || continue
        zip_dirs "$a"
        for d in "${ZDIRS[@]}"; do
            classify "$d" "$(rel "$a")"
            [[ -n "$C_TYPE" && -n "$C_GROUP" ]] || continue
            norm "$C_MODEL"
            [[ -z "${MODEL_GROUP[$b|$NORM]}" ]] && MODEL_GROUP[$b|$NORM]="$C_GROUP"
        done
    done
}

# target_dir DIR ZIP_REL BUNDLE - sets TDIR (relative to the bundle) and TIMG (images folder) for
# the files in DIR; TDIR "" = not recognised
target_dir() {
    local d="$1" arel="$2" b="$3" g
    TDIR=""; TIMG=""; TMODEL=""
    if [[ -z "$d" ]]; then d="${arel##*/}"; d="${d%.*}"; fi     # files at the top: use the zip's name
    classify "$d" "$arel"
    [[ -z "$C_TYPE" ]] && return
    g="$C_GROUP"
    if [[ -z "$g" ]]; then
        norm "$C_MODEL"; g="${MODEL_GROUP[$b|$NORM]}"
        [[ -z "$g" && "$C_SCALE" == bust ]] && g="$BUSTS_GROUP"
    fi
    if [[ -n "$g" ]]; then group_dir "$b" "$g"; TDIR="$GDIR/"; TIMG="$GDIR/images"; else TIMG="images"; fi
    TMODEL="$TDIR$C_MODEL-$C_TYPE${C_SCALE:+/$C_SCALE}"; TDIR="$TMODEL${C_SUB:+/$C_SUB}"
}

# ================================================================
# Moving files
# ================================================================
JUNK_RE='^(thumbs\.db|desktop\.ini|\.ds_store)$'
README_RE='(read[ _-]?me.*|^there are no files.*)\.txt$'
IMAGE_RE='\.(png|jpe?g|gif|webp)$'

# place FILE DESTDIR - move FILE into DESTDIR, never overwriting. Identical file already there:
# FILE is dropped. Different file with the same name: FILE stays where it is (KEPT counts it).
place() {
    local f="$1" dst="$2" b="${1##*/}"
    mkdir -p -- "$dst" || return 1
    if [[ ! -e "$dst/$b" ]]; then mv -- "$f" "$dst/$b" && PLACED=$((PLACED + 1)); return; fi
    if cmp -s -- "$f" "$dst/$b"; then rm -f -- "$f"; return; fi
    KEPT=$((KEPT + 1))
}

# place_image FILE IMAGES_DIR - like place, but a different picture with the same name is
# kept as name_2.png, name_3.png ...
place_image() {
    local f="$1" dst="$2" b="${1##*/}" t i
    mkdir -p -- "$dst" || return 1
    t="$dst/$b"
    if [[ -e "$t" ]]; then
        cmp -s -- "$f" "$t" && { rm -f -- "$f"; return; }
        i=2; while [[ -e "$dst/${b%.*}_$i.${b##*.}" ]]; do
            cmp -s -- "$f" "$dst/${b%.*}_$i.${b##*.}" && { rm -f -- "$f"; return; }
            i=$((i + 1))
        done
        t="$dst/${b%.*}_$i.${b##*.}"
    fi
    mv -- "$f" "$t" && IMAGES_MOVED=$((IMAGES_MOVED + 1))
}

# extract ZIP DEST - 0 = OK; error text in LAST_ERROR
extract() {
    local a="$1" d="$2" out rc
    if have unzip; then
        out=$(unzip -q -n "$a" -d "$d" 2>&1); rc=$?
        (( rc <= 1 )) && return 0          # 1 = warnings only (e.g. odd file names)
    else
        out=$("$SEVENZ" x -y -bso0 -bsp0 "-o$d" -- "$a" 2>&1); rc=$?
        (( rc == 0 )) && return 0
    fi
    out="${out//"$LOOT_DIR/"/}"
    LAST_ERROR="exit code $rc$( [[ -n "$out" ]] && printf ': %s' "$(printf '%s' "$out" | grep -v '^[[:space:]]*$' | tail -n 2 | tr '\n' ' ' | tr -s ' ' | head -c 200)")"
    return 1
}

# extract_inner DIR - extract zips found inside DIR into a folder of the same name, repeatedly
# (zips in zips in zips); a zip that fails stays as it is
extract_inner() {
    local d="$1" z round
    for round in 1 2 3; do
        local found=0
        while IFS= read -r -d '' z; do
            [[ -e "${z%.*}" && ! -d "${z%.*}" ]] && continue
            if extract "$z" "${z%.*}"; then rm -f -- "$z"; found=1; INNER=$((INNER + 1)); fi
        done < <(find "$d" -type f -iname '*.zip' -print0)
        (( found )) || break
    done
}

# flatten DIR - while DIR holds nothing but one folder, move that folder's contents up
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

# merge SRC DEST - move SRC's contents into DEST without overwriting (KEPT counts what stays)
merge() {
    local src="$1" dst="$2" e b
    mkdir -p -- "$dst"
    for e in "$src"/*; do
        b="${e##*/}"
        if [[ ! -e "$dst/$b" ]]; then mv -- "$e" "$dst/$b"
        elif [[ -d "$e" && -d "$dst/$b" ]]; then merge "$e" "$dst/$b"
        elif cmp -s -- "$e" "$dst/$b"; then rm -f -- "$e"
        else KEPT=$((KEPT + 1)); fi
    done
}

rel() { printf '%s' "${1#"$LOOT_DIR/"}"; }

# ================================================================
# What to do
# ================================================================
declare -A done_before=()
if [[ -f "$LEDGER" ]]; then
    while IFS=$'\t' read -r la _; do [[ -n "$la" ]] && done_before[$la]=1; done < <(tr -d '\r' < "$LEDGER")
fi
record() { (( DRY_RUN )) || printf '%s\t%s\t%s\n' "$1" "$2" "$(date '+%Y-%m-%d %H:%M')" >> "$LEDGER"; }

# The downloader's record knows each zip's scale ("page|scale|material|file" -> path); used for
# single-figure zips whose names don't say it (e.g. "DawnkeepGate_FDM.zip")
declare -A DL_SCALE=()
if [[ -f "$LOOT_DIR/.loot_downloaded.tsv" ]]; then
    while IFS=$'\t' read -r lkey lpath _; do
        [[ "$lpath" == *.zip ]] || continue
        IFS='|' read -r _ lscale _ <<< "$lkey"
        case "${lscale,,}" in ""|all) continue ;; other) lscale=prop ;; esac
        DL_SCALE[/$lpath]="${lscale,,}"
    done < <(tr -d '\r' < "$LOOT_DIR/.loot_downloaded.tsv")
fi

# All zips in the bundle folders (not in hidden folders like the temporary .extract_*)
mapfile -d '' archives < <(find "$LOOT_DIR" -mindepth 2 \( -name '.*' -prune \) -o -type f -iname '*.zip' -print0 | sort -z)
total=${#archives[@]}
echo "Found $total zip(s)"
echo ""

ok=0; already=0; failed=0; deleted=0; kept_total=0; n=0; IMAGES_MOVED=0; leftover_total=0; INNER=0
if (( DRY_RUN )); then printf 'zip\tfolder in zip\tgoes to\n' > "$PLAN_FILE"; else : > "$FAILED_FILE"; fi
fail() { ((failed++)); printf "  ${RED}✗ FAILED${NC} %s: %s\n" "$1" "$LAST_ERROR"; (( DRY_RUN )) || printf '%s\t%s\n' "$2" "$LAST_ERROR" >> "$FAILED_FILE"; }

for a in "${archives[@]}"; do
    n=$((n + 1))
    ar="$(rel "$a")"; bundle="${ar%%/*}"; base="${a##*/}"; base="${base%.*}"
    label="[$n/$total] $ar"
    LAST_ERROR=""

    if [[ -n "${done_before[$ar]}" ]]; then
        printf "  ${GREEN}✓${NC} %s ${YELLOW}(already extracted)${NC}\n" "$label"
        ((already++))
        if (( DELETE_AFTER_EXTRACT && ! DRY_RUN )); then rm -f -- "$a" && ((deleted++)); fi
        continue
    fi
    scan_bundle "$bundle"

    # ---------- dry run: plan from the table of contents ----------
    if (( DRY_RUN )); then
        if ! have unzip; then printf "  ${BLUE}->${NC} %s\n" "$label"; ((ok++)); continue; fi
        zip_dirs "$a"
        if (( ZFILES == 0 )); then LAST_ERROR="empty or unreadable zip"; fail "$label" "$a"; continue; fi
        declare -A tdirs=(); unplaced=0
        for d in "${ZDIRS[@]}"; do
            target_dir "$d" "$ar" "$bundle"
            if [[ -n "$TDIR" ]]; then
                tdirs["$TMODEL"]=1
                printf '%s\t%s\t%s\n' "$ar" "$d" "$bundle/$TDIR" >> "$PLAN_FILE"
            else
                unplaced=$((unplaced + 1))
                printf '%s\t%s\t%s\n' "$ar" "$d" "$bundle/$base/  (not recognised)" >> "$PLAN_FILE"
            fi
        done
        printf "  ${BLUE}->${NC} %s: %s model folder(s)%s\n" "$label" "${#tdirs[@]}" \
            "$( (( unplaced )) && printf ", ${YELLOW}%s folder(s) not recognised -> %s/%s/${NC}" "$unplaced" "$bundle" "$base")"
        i=0; while IFS= read -r t; do
            (( i++ < SHOW_FOLDERS )) || break; printf "       %s/%s\n" "$bundle" "$t"
        done < <( (( ${#tdirs[@]} )) && printf '%s\n' "${!tdirs[@]}" | sort)
        (( ${#tdirs[@]} > SHOW_FOLDERS )) && printf "       ... (all in %s)\n" "$PLAN_FILE"
        leftover_total=$((leftover_total + unplaced))
        unset tdirs
        ((ok++)); continue
    fi

    # ---------- real run ----------
    tmp="$LOOT_DIR/$bundle/.extract_${n}_$$"
    rm -rf -- "${tmp:?}"; mkdir -p -- "$tmp" || { LAST_ERROR="cannot create a temporary folder"; fail "$label" "$a"; continue; }
    printf "  ${BLUE}↓ Extracting${NC} %s ...\n" "$label"
    if ! extract "$a" "$tmp"; then rm -rf -- "${tmp:?}"; fail "$label" "$a"; continue; fi
    extract_inner "$tmp"
    PLACED=0; KEPT=0; models=0
    declare -A cache=() seen_models=()
    while IFS= read -r -d '' f; do
        fr="${f#"$tmp/"}"; fn="${f##*/}"
        if [[ "${fn,,}" =~ $JUNK_RE ]] || { (( ! KEEP_READMES )) && [[ "${fn,,}" =~ $README_RE ]]; }; then rm -f -- "$f"; continue; fi
        if [[ "$fr" == */* ]]; then d="${fr%/*}"; else d=""; fi
        if [[ -z "${cache[/$d]+x}" ]]; then
            target_dir "$d" "$ar" "$bundle"
            cache[/$d]="$TDIR"$'\t'"$TIMG"$'\t'"$TMODEL"
        fi
        IFS=$'\t' read -r TDIR TIMG TMODEL <<< "${cache[/$d]}"
        [[ -z "$TDIR" ]] && continue                       # not recognised: handled below
        if [[ "${fn,,}" =~ $IMAGE_RE ]]; then place_image "$f" "$LOOT_DIR/$bundle/$TIMG"; continue; fi
        [[ -z "${seen_models[/$TMODEL]}" ]] && { seen_models[/$TMODEL]=1; models=$((models + 1)); }
        place "$f" "$LOOT_DIR/$bundle/$TDIR"
    done < <(find "$tmp" -type f -print0)
    unset cache seen_models
    # whatever is left (not recognised, or a different file with the same name was already
    # there): keep it, with its folders, in <bundle>/<zip name>/
    find "$tmp" -depth -mindepth 1 -type d -empty -delete 2>/dev/null
    left=0
    if [[ -n "$(ls -A "$tmp")" ]]; then
        left=$(find "$tmp" -type f | wc -l)
        flatten "$tmp"
        if [[ -e "$LOOT_DIR/$bundle/$base" ]]; then merge "$tmp" "$LOOT_DIR/$bundle/$base"; else mv -- "$tmp" "$LOOT_DIR/$bundle/$base"; fi
    fi
    rm -rf -- "${tmp:?}"
    kept_total=$((kept_total + KEPT)); leftover_total=$((leftover_total + left - KEPT))
    record "$ar" "$models model folders, $PLACED files$( (( left )) && printf ', %s left in %s/' "$left" "$base")"
    ((ok++))
    printf "  ${GREEN}✓ EXTRACTED${NC} %s model folder(s), %s file(s)%s\n" "$models" "$PLACED" \
        "$( (( left )) && printf " ${YELLOW}- %s file(s) kept in %s/%s/%s${NC}" "$left" "$bundle" "$base" "$( (( KEPT )) && printf ' (%s of them differ from a file with the same name)' "$KEPT")")"
    if (( DELETE_AFTER_EXTRACT )); then
        if (( KEPT )); then printf "    ${YELLOW}zip kept: some of its files differ from ones already there${NC}\n"
        else rm -f -- "$a" && ((deleted++)); fi
    fi
done

# ---------- the downloader's pictures: <bundle>/Images/<group>/ -> <bundle>/<group>/images/ ----------
img_moves=0
if (( MOVE_IMAGES )); then
    for idir in "$LOOT_DIR"/*/Images/; do
        idir="${idir%/}"; b="${idir%/Images}"; b="${b##*/}"
        for f in "$idir"/*/*; do
            [[ -f "$f" ]] || continue
            g="${f%/*}"; g="${g##*/}"; group_dir "$b" "$g"
            if (( DRY_RUN )); then img_moves=$((img_moves + 1)); continue; fi
            place_image "$f" "$LOOT_DIR/$b/$GDIR/images" && img_moves=$((img_moves + 1))
        done
        (( DRY_RUN )) && continue
        find "$idir" -mindepth 1 -type d -empty -delete 2>/dev/null
        # pictures without a group: Images -> images, via a temporary name (on network shares
        # that ignore case "Images" and "images" are the same folder)
        if [[ -n "$(ls -A "$idir" 2>/dev/null)" ]]; then
            hold="$LOOT_DIR/$b/.images_$$"
            mv -- "$idir" "$hold" && { if [[ -e "$LOOT_DIR/$b/images" ]]; then merge "$hold" "$LOOT_DIR/$b/images"; rm -rf -- "${hold:?}"; else mv -- "$hold" "$LOOT_DIR/$b/images"; fi; }
        else
            rmdir -- "$idir" 2>/dev/null
        fi
    done
fi

echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e " Zips found:             ${BLUE}${total}${NC}"
echo -e " $( (( DRY_RUN )) && echo 'Would extract:   ' || echo 'Extracted now:   ')       ${GREEN}${ok}${NC}"
echo -e " Already extracted:      ${already}"
(( INNER )) && echo -e " Zips inside zips:       ${INNER}"
(( IMAGES_MOVED )) && echo -e " Pictures to images/:    ${IMAGES_MOVED} (identical copies kept once)"
(( img_moves )) && echo -e " Downloaded pictures:    ${img_moves} $( (( DRY_RUN )) && echo 'would move' || echo 'moved') from Images/<group>/ to <group>/images/"
(( leftover_total )) && echo -e " Not recognised:         ${YELLOW}${leftover_total}${NC} $( (( DRY_RUN )) && echo 'folder(s)' || echo 'file(s)') - kept in <bundle>/<zip name>/"
echo -e " Failed:                 ${RED}${failed}${NC}"
(( kept_total )) && echo -e " Files kept (a different file with the same name was already there): ${YELLOW}${kept_total}${NC}"
(( deleted && ! DRY_RUN )) && echo -e " Zips deleted:           ${deleted}"
echo -e "${YELLOW}================================================${NC}"
if (( DRY_RUN )); then
    echo -e "${YELLOW}Dry run - nothing was changed.${NC} Where everything would go: ${YELLOW}${PLAN_FILE}${NC}"
    echo "If it looks right, set DRY_RUN=0 and run it again."
elif (( failed )); then echo -e "Failures are listed in ${YELLOW}${FAILED_FILE}${NC} - those zips were kept; they're retried on the next run."
else rm -f "$FAILED_FILE"; fi
