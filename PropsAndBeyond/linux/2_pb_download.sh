#!/bin/bash
# ================================================================
# Props & Beyond - Step 2: download your library from pb_list.tsv
#
# Reads the list saved by browser/1_pb_collect.js (pb_list*.tsv next to this script), downloads
# the whole-pack zips (monthly Prop Drops, Welcome Pack) and the props that are in no pack,
# extracts them and sorts them like this (FOLDER_STRUCTURE, see the settings):
#   PB_DIR/01-2023 - Viking Saga/Beard-Beads/images/   the prop's pictures (from the zip + the shop)
#   PB_DIR/01-2023 - Viking Saga/Beard-Beads/files/    everything else (cards/, supportless/ ...)
#   PB_DIR/01-2023 - Viking Saga/images/  + files/     the pack's cover and item cards
#   PB_DIR/Single props/Ioun-Stones/{images,files}     props that are in no pack
#
# The download links expire 1 HOUR after the list was collected. Links that have expired are not
# requested; run 1_pb_collect.js again and then this script - it continues where it stopped.
# Everything finished is recorded in PB_DIR/.pb_downloaded.tsv (keep it): nothing recorded is
# downloaded again, also after you've deleted or moved the files.
# A pack or prop whose folder is already there but isn't recorded (e.g. sorted by hand earlier)
# is left alone and listed - delete or move that folder to download it, or use MARK_ALL_DOWNLOADED.
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;94m'
NC='\033[0m'

# ==============================
# SETTINGS
# ==============================
LIST_FILES="pb_list*.tsv"   # the list(s) from 1_pb_collect.js, next to this script
# Where the files are stored. Empty = the folder this script is in.
# To use another folder, put its full path here, e.g. "/mnt/nas/3DPrints/PropsAndBeyond".
PB_DIR=""

# Folder structure - available options:
#   "MM-YYYY - PACK/PROP"  -> 01-2023 - Viking Saga/Beard-Beads/{images,files}   (default)
#   "PACK/PROP"            -> Viking Saga/Beard-Beads/{images,files}
#   "PROP"                 -> Beard-Beads/{images,files}   (all props side by side; a pack's cover
#                             and item cards go to "01-2023 - Viking Saga/{images,files}")
#   "MM-YYYY - PACK"       -> 01-2023 - Viking Saga/Beard-Beads/...   (as in the zip, no images/files
#                             split; the shop pictures go into each prop's folder)
# (Packs without a month, e.g. the Welcome Pack, use their name: "Welcome-Pack".)
# Each pack's place is recorded when it's downloaded, so a change only applies to packs after it.
FOLDER_STRUCTURE="MM-YYYY - PACK/PROP"
SINGLES_FOLDER="Single props"   # folder for props that are in no pack ("PROP": not used)

WHAT="packs"          # "packs" = the whole-pack zips + props in no pack (no duplicates)
                      # "props" = each prop's own zip instead of the whole-pack zip
EXTRACT=1             # 1 = extract and sort the zips (the zip is deleted when that worked); 0 = keep the zips
IMAGES=1              # 1 = also download the pictures from the shop pages

# Every finished file is recorded in PB_DIR/.pb_downloaded.tsv (keep that file!).
SKIP_DOWNLOADED=1     # 1 = skip what's recorded, even if you've deleted it since; 0 = download it again
MARK_ALL_DOWNLOADED=0 # 1 = download nothing; record everything in the list as downloaded
                      #     (use once if you already have everything in your current list)

DOWNLOAD=1            # 1 = download, 0 = check only
DELAY_SECONDS=5       # pause between zips
IMAGE_DELAY_SECONDS=1 # pause between pictures
MAX_DOWNLOADS=0       # stop after this many zips this run (0 = no limit)
MAX_RETRIES=4         # retries for rate limits, server errors and network errors
BACKOFF_SECONDS=30    # first retry wait; doubles each retry unless the server says otherwise
STALL_SECONDS=120     # abort a download that receives almost nothing for this long
EXPIRY_MARGIN=300     # treat links expiring within this many seconds as expired (big zips take a while)
REFUSAL_LIMIT=3       # stop after this many refused links in a row
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "$PB_DIR" ]] && PB_DIR="$script_dir"
[[ "$PB_DIR" != /* ]] && PB_DIR="$script_dir/$PB_DIR"
PB_DIR="${PB_DIR%/}"
FOLDER_STRUCTURE="${FOLDER_STRUCTURE^^}"; FOLDER_STRUCTURE="${FOLDER_STRUCTURE//\\//}"
case "$FOLDER_STRUCTURE" in
    "MM-YYYY - PACK/PROP"|"PACK/PROP"|"PROP"|"MM-YYYY - PACK") ;;
    *) echo -e "${RED}Unknown FOLDER_STRUCTURE \"$FOLDER_STRUCTURE\" - use \"MM-YYYY - PACK/PROP\", \"PACK/PROP\", \"PROP\" or \"MM-YYYY - PACK\".${NC}"; exit 1 ;;
esac
case "$WHAT" in packs|props) ;; *) echo -e "${RED}Unknown WHAT \"$WHAT\" - use packs or props.${NC}"; exit 1 ;; esac
LEDGER="$PB_DIR/.pb_downloaded.tsv"   # key <TAB> path relative to PB_DIR <TAB> date
FAILED_OUT="pb_failed.txt"
SKIPPED_OUT="pb_skipped.txt"

echo -e "${BLUE}Props & Beyond downloader${NC}"
shopt -s nullglob
lists=()
for f in "$script_dir"/$LIST_FILES ./$LIST_FILES; do
    f="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
    [[ " ${lists[*]} " == *" $f "* ]] || lists+=("$f")
done
shopt -u nullglob
(( ${#lists[@]} )) || { echo -e "${RED}No list found ($LIST_FILES next to this script). Collect it with 1_pb_collect.js.${NC}"; exit 1; }
for f in "${lists[@]}"; do printf "List:        ${YELLOW}%s${NC}\n" "$f"; done
printf "Destination: ${YELLOW}%s${NC} (%s, %s)\n" "$PB_DIR" "$FOLDER_STRUCTURE" "$WHAT"
if [[ $MARK_ALL_DOWNLOADED -eq 1 ]]; then printf "Mode:        ${YELLOW}record everything in the list as downloaded (nothing is downloaded)${NC}\n"; DOWNLOAD=0
elif [[ $DOWNLOAD -eq 1 ]]; then printf "Mode:        ${YELLOW}download missing files${NC} (%ss between zips)\n" "$DELAY_SECONDS"
else printf "Mode:        ${YELLOW}check only${NC}\n"; fi
echo ""
mkdir -p "$PB_DIR" 2>/dev/null; [[ -w "$PB_DIR" ]] || { echo -e "${RED}No write permission for $PB_DIR${NC}"; exit 1; }
command -v curl &>/dev/null || { echo -e "${RED}curl is not installed.${NC}"; exit 1; }
if (( EXTRACT )) && ! command -v unzip &>/dev/null; then echo -e "${RED}unzip is not installed (sudo apt install unzip), or set EXTRACT=0.${NC}"; exit 1; fi

# ---------- helpers ----------
safe_name() {   # usable as a file/folder name on Linux and Windows shares
    local s="$1"
    s="${s//’/\'}"; s="${s//‘/\'}"; s="${s//“/\"}"; s="${s//”/\"}"; s="${s//–/-}"
    s="$(printf '%s' "$s" | tr -d '\000-\037' | sed 's#[<>:"/\\|?*]#_#g')"
    s="${s#"${s%%[![:space:].]*}"}"
    s="${s%"${s##*[![:space:].]}"}"
    (( ${#s} > 120 )) && s="${s:0:120}" && s="${s%"${s##*[![:space:].]}"}"
    printf '%s' "$s"
}
norm() { local s="${1,,}"; printf '%s' "${s//[^a-z0-9]/}"; }   # for comparing names
is_picture() { [[ "${1,,}" =~ \.(jpe?g|png|webp|gif)$ ]]; }

# Check a finished file. 0 = OK, 1 = broken, 2 = not checked
verify_file() {
    local f="$1" magic
    magic=$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')
    case "${f,,}" in
        *.png) [[ "$magic" == 89504e47* ]] || { LAST_ERROR="not a PNG image"; return 1; } ;;
        *.jpg|*.jpeg) [[ "$magic" == ffd8ff* ]] || { LAST_ERROR="not a JPEG image"; return 1; } ;;
        *.pdf) [[ "$magic" == 25504446* ]] || { LAST_ERROR="not a PDF file"; return 1; } ;;
        *.zip)
            [[ "$magic" == 504b0304* || "$magic" == 504b0506* ]] || { LAST_ERROR="not a zip file (got: $(head -c 60 "$f" | tr -cd '[:print:]'))"; return 1; }
            command -v unzip &>/dev/null || return 2
            # unzip exit codes: 0 = OK, 1 = warnings only (e.g. odd file names), 2+ = real errors
            local zout zrc
            zout=$(unzip -tq "$f" 2>&1); zrc=$?
            (( zrc <= 1 )) || { LAST_ERROR="zip test failed (damaged or incomplete): $(grep -m1 -v -e '^[[:space:]]*$' -e '^\[' <<< "$zout" | tr -s ' ' | head -c 150)"; return 1; } ;;
        *) return 2 ;;
    esac
    return 0
}

# Seconds until a presigned link expires (X-Amz-Date + X-Amz-Expires); empty if it doesn't say
expires_in() {
    local url="$1" d e t
    [[ "$url" =~ [?\&]X-Amz-Date=([0-9]{8})T([0-9]{2})([0-9]{2})([0-9]{2})Z ]] || return
    d="${BASH_REMATCH[1]}"; t="${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}"
    [[ "$url" =~ [?\&]X-Amz-Expires=([0-9]+) ]] || return
    e="${BASH_REMATCH[1]}"
    printf '%s' $(( $(date -u -d "${d:0:4}-${d:4:2}-${d:6:2} $t" +%s) + e - $(date -u +%s) ))
}

# Download URL to DEST via DEST.part (no cookie). 0 = OK, 1 = failed, 2 = refused (403/410)
fetch_file() {
    local url="$1" dest="$2" tmp="${2}.part" errf result rc code ctype attempt=0 wait hdr retry_after
    mkdir -p "$(dirname "$dest")" || { LAST_ERROR="cannot create folder"; return 1; }
    while :; do
        hdr=$(mktemp); errf=$(mktemp)
        result=$(curl --silent --show-error --location --connect-timeout 30 \
            --speed-limit 1024 --speed-time "$STALL_SECONDS" \
            -H "User-Agent: $USER_AGENT" \
            -D "$hdr" -o "$tmp" -w '%{http_code} %{content_type}' "$url" 2>"$errf")
        rc=$?; code="${result%% *}"; ctype="${result#* }"; [[ "$ctype" == "$result" ]] && ctype=""
        retry_after=$(grep -i '^retry-after:' "$hdr" | tail -1 | tr -dc '0-9')
        LAST_ERROR="curl exit $rc, HTTP ${code:-none}$( [[ -s "$errf" ]] && printf ', %s' "$(head -c 150 "$errf" | tr '\n' ' ')")"
        grep -qi '^cf-mitigated:' "$hdr" && LAST_ERROR="blocked by a bot check (HTTP $code)"
        rm -f "$hdr" "$errf"
        if (( rc == 0 )) && [[ "$code" == "200" && -s "$tmp" && "$ctype" != text/html* ]]; then
            mv -f "$tmp" "$dest" && return 0
            LAST_ERROR="could not move the finished download into place"; rm -f "$tmp"; return 1
        fi
        rm -f "$tmp"
        if [[ "$code" == "403" || "$code" == "410" ]]; then [[ "$LAST_ERROR" == blocked* ]] || LAST_ERROR="link refused (HTTP $code) - probably expired"; return 2; fi
        [[ "$code" == "404" ]] && { LAST_ERROR="not on the server (HTTP 404)"; return 1; }
        if [[ "$code" == "429" || "$code" == 5?? || "$code" == "000" || -z "$code" || $rc -eq 28 ]] && (( attempt < MAX_RETRIES )); then
            attempt=$((attempt + 1))
            if [[ -n "$retry_after" ]]; then wait=$retry_after; else wait=$(( BACKOFF_SECONDS * (1 << (attempt - 1)) )); fi
            (( wait > 900 )) && wait=900
            printf "    ${YELLOW}%s - waiting %ss before retry %s/%s${NC}\n" "$LAST_ERROR" "$wait" "$attempt" "$MAX_RETRIES"
            sleep "$wait"; continue
        fi
        return 1
    done
}

# Move everything in SRC into DST, keeping the folder structure; never overwrite. A file that is
# already there with the same contents is dropped; with other contents it's left in SRC and
# counted in MERGE_CONFLICTS.
MERGE_CONFLICTS=0
merge_into() {
    local src="$1" dst="$2" e name
    mkdir -p "$dst" || return 1
    for e in "$src"/* "$src"/.[!.]*; do
        [[ -e "$e" ]] || continue
        name="${e##*/}"
        if [[ -d "$e" ]]; then
            if [[ -e "$dst/$name" ]]; then merge_into "$e" "$dst/$name"; rmdir "$e" 2>/dev/null
            else mv "$e" "$dst/$name"; fi
        elif [[ -e "$dst/$name" ]]; then
            if cmp -s "$e" "$dst/$name"; then rm -f "$e"; else MERGE_CONFLICTS=$((MERGE_CONFLICTS + 1)); fi
        else
            mv "$e" "$dst/$name"
        fi
    done
}

# Sort the contents of one prop (folder SRC) into DEST: pictures at its top -> images/, the rest -> files/
# ("MM-YYYY - PACK": no split - everything into DEST as it is)
sort_prop() {
    local src="$1" dest="$2" e
    if [[ "$FOLDER_STRUCTURE" == "MM-YYYY - PACK" ]]; then merge_into "$src" "$dest"; return; fi
    mkdir -p "$src/.pb_images" "$src/.pb_files"
    for e in "$src"/* "$src"/.[!.]*; do
        [[ -e "$e" ]] || continue
        case "${e##*/}" in .pb_images|.pb_files) continue ;; esac
        if [[ -f "$e" ]] && is_picture "$e"; then mv "$e" "$src/.pb_images/"; else mv "$e" "$src/.pb_files/"; fi
    done
    merge_into "$src/.pb_images" "$dest/images"; merge_into "$src/.pb_files" "$dest/files"
    rmdir "$src/.pb_images" "$src/.pb_files" 2>/dev/null
    rmdir "$dest/images" "$dest/files" 2>/dev/null   # empty ones aren't kept
}

# Remove single-folder wrappers ("January-2023/..." or "Ioun-Stones/..." -> the contents), but not a
# content folder: a prop with only "supportless/" keeps it
CONTENT_DIR_RE='^(supportless|pre-?supported|supported|unsupported|presupported|cards|stl|stls|3mf|obj|hollow|solid|files|images)$'
flatten() {
    local d="$1" entries
    while :; do
        shopt -s nullglob dotglob; entries=("$d"/*); shopt -u nullglob dotglob
        (( ${#entries[@]} == 1 )) && [[ -d "${entries[0]}" ]] || return 0
        local top="${entries[0]##*/}"; [[ "${top,,}" =~ $CONTENT_DIR_RE ]] && return 0
        local inner="${entries[0]}" tmp="$d/.pb_flat_$$"
        mv "$inner" "$tmp" && merge_into "$tmp" "$d" && rmdir "$tmp" 2>/dev/null || return 0
    done
}

# Folder names for a row: PACK_DIR (pack level), PROP_BASE (where its props go)
pack_dirs() {   # pack_dirs PACKNAME MM YYYY
    local name mm="$2" yyyy="$3"; name="$(safe_name "$1")"
    case "$FOLDER_STRUCTURE" in
        "PACK/PROP") PACK_DIR="$name" ;;
        *) PACK_DIR="${mm:+$mm-$yyyy - }$name" ;;
    esac
    [[ -z "$PACK_DIR" ]] && PACK_DIR="Pack"
    if [[ "$FOLDER_STRUCTURE" == "PROP" ]]; then PROP_BASE=""; else PROP_BASE="$PACK_DIR"; fi
}

# Extract ZIP and sort it. KIND = pack (folders inside = props) | prop (the zip is one prop, NAME).
# 0 = OK (zip may be deleted), 1 = failed (zip kept)
extract_sort() {
    local zip="$1" kind="$2" name="$3" tmp e zrc
    tmp="$(mktemp -d "$PB_DIR/.pb_extract_XXXXXX")" || { LAST_ERROR="cannot create a temporary folder"; return 1; }
    unzip -q -o "$zip" -d "$tmp" >/dev/null 2>&1; zrc=$?
    (( zrc <= 1 )) || { rm -rf "$tmp"; LAST_ERROR="unzip failed (exit $zrc)"; return 1; }
    flatten "$tmp"
    MERGE_CONFLICTS=0
    if [[ "$kind" == "prop" ]]; then
        sort_prop "$tmp" "$PB_DIR/${PROP_BASE:+$PROP_BASE/}$name"
    else
        mkdir -p "$tmp/.pb_top"
        for e in "$tmp"/* "$tmp"/.[!.]*; do
            [[ -e "$e" ]] || continue
            case "${e##*/}" in .pb_top) continue ;; esac
            if [[ -d "$e" ]]; then sort_prop "$e" "$PB_DIR/${PROP_BASE:+$PROP_BASE/}${e##*/}"; rmdir "$e" 2>/dev/null
            else mv "$e" "$tmp/.pb_top/"; fi
        done
        sort_prop "$tmp/.pb_top" "$PB_DIR/$PACK_DIR"
    fi
    if (( MERGE_CONFLICTS )); then
        local keep="$PB_DIR/$PACK_DIR/.pb_conflicts_$(date +%Y%m%d%H%M%S)"
        mkdir -p "$keep" && merge_into "$tmp" "$keep"
        LAST_ERROR="$MERGE_CONFLICTS file(s) were already there with other contents - kept in ${keep#"$PB_DIR"/}"
        rm -rf "$tmp"; return 1
    fi
    rm -rf "$tmp"; return 0
}

# ---------- read the ledger (key -> path relative to PB_DIR) ----------
declare -A ledger=()
if [[ -f "$LEDGER" ]]; then
    while IFS=$'\t' read -r lid lpath _; do
        [[ -n "$lid" && -n "$lpath" ]] && ledger[$lid]="$lpath"
    done < <(tr -d '\r' < "$LEDGER")
fi
record() {   # record KEY RELPATH   (third column: date, for your information)
    [[ "${ledger[$1]}" == "$2" ]] && return
    ledger[$1]="$2"
    printf '%s\t%s\t%s\n' "$1" "$2" "$(date '+%Y-%m-%d %H:%M')" >> "$LEDGER"
}

# ---------- read the list(s) (the newest link per file wins) ----------
COLS="kind role pack mm yyyy product prop name key url product_url"
declare -A row=() row_time=()
order=()
for lf in "${lists[@]}"; do
    mapfile -t lines < <(sed $'1s/^\xEF\xBB\xBF//; s/\r$//' "$lf")
    (( ${#lines[@]} > 1 )) || { echo -e "${YELLOW}Empty list: $lf${NC}"; continue; }
    # Split on tabs via \x1f: with a tab in IFS, empty columns would be merged and the rest would shift
    IFS=$'\x1f' read -r -a header <<< "${lines[0]//$'\t'/$'\x1f'}"
    declare -A lcol=()
    for i in "${!header[@]}"; do lcol["${header[$i],,}"]=$i; done
    for c in $COLS; do [[ -n "${lcol[$c]}" ]] || { echo -e "${RED}$lf has no '$c' column. Collect it again with 1_pb_collect.js.${NC}"; exit 1; }; done
    for (( n = 1; n < ${#lines[@]}; n++ )); do
        line="${lines[$n]}"; [[ -z "${line//[[:space:]]/}" ]] && continue
        IFS=$'\x1f' read -r -a f <<< "${line//$'\t'/$'\x1f'}"
        k="${f[${lcol[kind]}]}|${f[${lcol[key]}]}"
        [[ "${f[${lcol[kind]}]}" == "image" ]] && k+="|${f[${lcol[pack]}]}"
        url="${f[${lcol[url]}]}"; t=0
        [[ "$url" =~ [?\&]X-Amz-Date=([0-9]{8}T[0-9]{6}) ]] && t="${BASH_REMATCH[1]//T/}"
        if [[ -z "${row[$k]}" ]]; then order+=("$k"); fi
        if [[ -z "${row[$k]}" ]] || (( t > ${row_time[$k]} )); then
            v=""; for c in $COLS; do v+="${f[${lcol[$c]}]}"$'\x1f'; done
            row[$k]="$v"; row_time[$k]=$t
        fi
    done
    unset lcol
done
(( ${#order[@]} )) || { echo -e "${RED}The list is empty.${NC}"; exit 1; }

# ---------- what to download ----------
# packs: the whole-pack zips + props in no pack; props: each prop's zip (packitem) + props in no pack
zips=(); pics=()
for k in "${order[@]}"; do
    IFS=$'\x1f' read -r kind role _ <<< "${row[$k]}"
    if [[ "$kind" == "file" ]]; then
        case "$WHAT:$role" in packs:pack|packs:single|props:packitem|props:single) zips+=("$k") ;; esac
    else
        pics+=("$k")
    fi
done

: > "$FAILED_OUT"; : > "$SKIPPED_OUT"
done_n=0; new_n=0; failed=0; skipped_dir=0; expired=0; refused_row=0; stopped=""; pics_new=0; pics_failed=0
first=1
declare -A ready=()   # "p:<pack>" / "s:<prop>" -> 1 when its files are in place (for the pictures)

mark_ready() { if [[ "$role" == "single" ]]; then ready["s:$prop"]=1; else ready["p:$pack"]=1; fi; }
for k in "${zips[@]}"; do
    IFS=$'\x1f' read -r kind role pack mm yyyy product prop name key url product_url <<< "${row[$k]}"
    pack_dirs "$pack" "$mm" "$yyyy"
    if [[ "$role" == "single" ]]; then PACK_DIR="$(safe_name "$SINGLES_FOLDER")"; [[ "$FOLDER_STRUCTURE" == "PROP" ]] && PROP_BASE="" || PROP_BASE="$PACK_DIR"; fi
    label="${product}${prop:+ - $prop}"
    pname="$(safe_name "$prop")"
    # where it goes: a pack -> its pack folder; a prop -> its prop folder
    if [[ "$role" == "pack" ]]; then target="$PACK_DIR"; else target="${PROP_BASE:+$PROP_BASE/}$pname"; fi
    # a prop zip that's really a file (e.g. the item cards PDF) goes to the pack's files/
    is_zip=1; [[ "${key,,}" == *.zip ]] || is_zip=0

    if [[ -n "${ledger[$key]}" && $SKIP_DOWNLOADED -eq 1 ]]; then
        done_n=$((done_n + 1)); mark_ready; printf "  ${GREEN}✓${NC} %s\n" "$label"; continue
    fi
    if [[ $MARK_ALL_DOWNLOADED -eq 1 ]]; then record "$key" "$target"; done_n=$((done_n + 1)); printf "  ${GREEN}✓ recorded${NC} %s\n" "$label"; continue; fi
    # its folder is there already, but not from this downloader: leave it alone
    if [[ -z "${ledger[$key]}" && -d "$PB_DIR/$target" && -n "$(ls -A "$PB_DIR/$target" 2>/dev/null)" ]]; then
        skipped_dir=$((skipped_dir + 1)); printf "  ${YELLOW}↷ %s: folder already there (%s) - not recorded, left alone${NC}\n" "$label" "$target"
        printf '%s\t%s\n' "$target" "$label" >> "$SKIPPED_OUT"; continue
    fi
    [[ $DOWNLOAD -eq 1 && -z "$stopped" ]] || { printf "  ${YELLOW}✗ missing${NC} %s\n" "$label"; continue; }
    if (( MAX_DOWNLOADS > 0 && new_n >= MAX_DOWNLOADS )); then stopped="reached MAX_DOWNLOADS ($MAX_DOWNLOADS)"; printf "  ${YELLOW}✗ missing${NC} %s\n" "$label"; continue; fi
    left="$(expires_in "$url")"
    if [[ -n "$left" ]] && (( left < EXPIRY_MARGIN )); then
        expired=$((expired + 1)); printf "  ${YELLOW}⌛ %s: link expired - collect again with 1_pb_collect.js${NC}\n" "$label"; continue
    fi

    (( first )) || sleep "$DELAY_SECONDS"; first=0
    file="$(safe_name "${key##*/}")"
    if (( is_zip )); then dest="$PB_DIR/.pb_downloads/$file"; else dest="$PB_DIR/$PACK_DIR/$( [[ "$FOLDER_STRUCTURE" == "MM-YYYY - PACK" ]] || printf 'files/')$file"; fi
    printf "  ${BLUE}↓${NC} %s\n" "$label"
    fetch_file "$url" "$dest"; r=$?
    if (( r == 2 )); then
        refused_row=$((refused_row + 1)); failed=$((failed + 1)); printf "    ${RED}✗ %s${NC}\n" "$LAST_ERROR"; printf '%s\t%s\n' "$label" "$LAST_ERROR" >> "$FAILED_OUT"
        (( refused_row >= REFUSAL_LIMIT )) && stopped="$REFUSAL_LIMIT links in a row were refused - collect again with 1_pb_collect.js"
        continue
    fi
    refused_row=0
    if (( r != 0 )); then failed=$((failed + 1)); printf "    ${RED}✗ %s${NC}\n" "$LAST_ERROR"; printf '%s\t%s\n' "$label" "$LAST_ERROR" >> "$FAILED_OUT"; continue; fi
    verify_file "$dest"; vr=$?
    if (( vr == 1 )); then failed=$((failed + 1)); rm -f "$dest"; printf "    ${RED}✗ %s (deleted, try again next run)${NC}\n" "$LAST_ERROR"; printf '%s\t%s\n' "$label" "$LAST_ERROR" >> "$FAILED_OUT"; continue; fi
    new_n=$((new_n + 1))
    if (( ! is_zip )); then record "$key" "${dest#"$PB_DIR"/}"; mark_ready; printf "    ${GREEN}✓ saved${NC}\n"; continue; fi
    if (( EXTRACT )); then
        if [[ "$role" == "pack" ]]; then extract_sort "$dest" pack; else extract_sort "$dest" prop "$pname"; fi
        if (( $? == 0 )); then
            rm -f "$dest"; record "$key" "$target"; mark_ready; printf "    ${GREEN}✓ extracted to %s${NC}\n" "$target"
        else
            failed=$((failed + 1)); printf "    ${RED}✗ %s - zip kept in .pb_downloads/${NC}\n" "$LAST_ERROR"; printf '%s\t%s\n' "$label" "$LAST_ERROR" >> "$FAILED_OUT"
        fi
    else
        kd="$PB_DIR/$target"; mkdir -p "$kd" && mv -f "$dest" "$kd/$file" && record "$key" "${target}/$file" && mark_ready
        printf "    ${GREEN}✓ saved to %s${NC}\n" "$target/$file"
    fi
done
rmdir "$PB_DIR/.pb_downloads" 2>/dev/null

# ---------- pictures (only where the pack's / prop's files are in place) ----------
if (( IMAGES )) && [[ $MARK_ALL_DOWNLOADED -eq 0 ]]; then
    firstpic=1
    for k in "${pics[@]}"; do
        IFS=$'\x1f' read -r kind role pack mm yyyy product prop name key url product_url <<< "${row[$k]}"
        [[ -n "${ledger[$key|$pack]}" ]] && continue
        if [[ "$role" == "single" ]]; then [[ -n "${ready["s:$prop"]}" ]] || continue
        else [[ -n "${ready["p:$pack"]}" ]] || continue; fi
        pack_dirs "$pack" "$mm" "$yyyy"
        if [[ "$role" == "single" ]]; then PACK_DIR="$(safe_name "$SINGLES_FOLDER")"; [[ "$FOLDER_STRUCTURE" == "PROP" ]] && PROP_BASE="" || PROP_BASE="$PACK_DIR"; fi
        # which folder: the prop's (by name; the zip's folder may be named a bit differently,
        # e.g. "Horn" -> "Throwback-Viking-Blowing-Horn"), else the pack's own
        dir="$PB_DIR/$PACK_DIR"
        if [[ -n "$prop" ]]; then
            base="$PB_DIR${PROP_BASE:+/$PROP_BASE}"; want="$(norm "$prop")"; hit=""; hits=0; exact=""
            for d in "$base"/*/; do
                d="${d%/}"; dn="${d##*/}"; n="$(norm "$dn")"
                [[ "$dn" == images || "$dn" == files || "$dn" == .* ]] && continue
                if [[ "$n" == "$want" ]]; then exact="$d"; break; fi
                [[ -n "$want" && -n "$n" && ( "$n" == *"$want"* || "$want" == *"$n"* ) ]] && { hit="$d"; hits=$((hits + 1)); }
            done
            if [[ -n "$exact" ]]; then dir="$exact"; elif (( hits == 1 )); then dir="$hit"; fi
        fi
        [[ "$FOLDER_STRUCTURE" == "MM-YYYY - PACK" ]] || dir="$dir/images"
        file="$(safe_name "$name")"; dest="$dir/$file"
        if [[ -e "$dest" ]]; then record "$key|$pack" "${dest#"$PB_DIR"/}"; continue; fi
        (( firstpic )) || sleep "$IMAGE_DELAY_SECONDS"; firstpic=0
        ok=0
        if fetch_file "$url" "$dest"; then verify_file "$dest"; (( $? != 1 )) && ok=1; fi
        if (( ok )); then
            record "$key|$pack" "${dest#"$PB_DIR"/}"; pics_new=$((pics_new + 1))
        else
            rm -f "$dest"; pics_failed=$((pics_failed + 1)); printf '%s\t%s\n' "picture $name ($product)" "$LAST_ERROR" >> "$FAILED_OUT"
        fi
    done
fi

echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e " Zips:                   ${#zips[@]} ($WHAT)"
echo -e " Already done:           ${done_n}"
echo -e " Downloaded now:         ${GREEN}${new_n}${NC}"
(( skipped_dir )) && echo -e " Folder already there:   ${YELLOW}${skipped_dir}${NC} (not recorded - left alone, listed in $SKIPPED_OUT)"
(( expired )) && echo -e " Links expired:          ${YELLOW}${expired}${NC} - collect again with 1_pb_collect.js and run this again"
(( failed )) && echo -e " Failed:                 ${RED}${failed}${NC} (see $FAILED_OUT)"
(( IMAGES )) && echo -e " Pictures:               ${GREEN}${pics_new}${NC} new$( (( pics_failed )) && printf ", ${RED}%s failed${NC}" "$pics_failed")"
[[ -n "$stopped" ]] && echo -e " ${RED}Stopped early: ${stopped}${NC}"
echo -e "${YELLOW}================================================${NC}"
[[ -s "$FAILED_OUT" ]] || rm -f "$FAILED_OUT"
[[ -s "$SKIPPED_OUT" ]] || rm -f "$SKIPPED_OUT"
