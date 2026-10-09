#!/bin/bash
# ================================================================
# Loot Studios checker + downloader (All Bundle archives, individual figure files, magazines)
# Reads the list exported by 1_loot_collect_all_bundles.js (tab-separated, with
# a header row) and downloads every file that isn't downloaded yet.
#
# The download links are temporary (they expire about an hour after the
# collector reads them). Expired links are skipped without contacting the
# server; refresh them by running 1_loot_collect_all_bundles.js again,
# exporting again, and rerunning this script. Files already downloaded
# are always skipped, so each run continues where the last one stopped.
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;94m'
NC='\033[0m'

# ==============================
# SETTINGS
# ==============================
LIST_FILE="loot_all_bundles.tsv"            # exported list (next to this script, or a full path)
# Where the bundles are stored. Empty = the folder this script is in.
# To use another folder, put its full path here, e.g. "/mnt/nas/LootStudios".
LOOT_DIR=""

# Folder structure - available options:
#   "BUNDLE_FOLDER" -> FaewoodHaven/All_FaewoodHaven_Bust.zip    (default; bundle name from the download link)
#   "BUNDLE_TITLE"  -> Faewood Haven/All_FaewoodHaven_Bust.zip   (bundle title as shown on the site)
# Inside the bundle folder it's the same for both: single figure files in <group>/, pictures in
# Images/<group>/. Files already downloaded are found under either name, so changing it causes no
# re-downloads (it doesn't move them, though). Use the same setting in 99_loot_fix_folders.sh.
FOLDER_STRUCTURE="BUNDLE_FOLDER"

MATERIALS=""          # only these materials, e.g. "resin" or "resin fdm"; empty = all
SCALES=""             # only these scales, e.g. "32mm bust"; empty = all

INDIVIDUAL=1          # 1 = download the individual figure files when a bundle has no All Bundle
                      #     for that scale and material; 0 = All Bundle archives only
VARIANTS=""           # individual files: only these kinds, e.g. "hollow"; empty = all
                      #     (all, hollow, solid, slicer, unsupported)
EXTRAS=1              # 1 = also download the magazine, digital magazine and statblocks
IMAGES=1              # 1 = also download each figure's images (into <bundle>/Images/<group>/)
IMAGE_TYPES=""        # only these images, e.g. "painted"; empty = all ("render painted")
IMAGE_DELAY_SECONDS=1 # pause between images (small files)
# Images that don't exist (many figures have no painted or FDM image) and magazine
# links that are broken on the site are remembered in LOOT_DIR/.loot_unavailable.tsv
# and only tried again after this many days:
UNAVAILABLE_RECHECK_DAYS=30

# Every finished file is recorded in LOOT_DIR/.loot_downloaded.tsv (keep that file!).
SKIP_DOWNLOADED=1     # 1 = skip files recorded as downloaded, even if you've since extracted
                      #     and deleted them; 0 = download them again if they're no longer there
MARK_ALL_DOWNLOADED=0 # 1 = download nothing; record every file in the list as downloaded.
                      #     Use once if you already have (or deleted) everything in your current
                      #     list, so that from then on only new bundles are downloaded.

DOWNLOAD=1            # 1 = download missing files, 0 = check only
DELAY_SECONDS=5       # pause between downloads
MAX_DOWNLOADS=0       # stop after this many downloads this run (0 = no limit)
MAX_RETRIES=4         # retries for rate limits, server errors and network errors
BACKOFF_SECONDS=30    # first retry wait; doubles each retry unless the server says otherwise
EXPIRY_MARGIN=120     # treat links as expired this many seconds before they really expire
STALL_SECONDS=120     # abort a download that receives almost nothing for this long
REFUSED_LIMIT=3       # stop after this many refused downloads in a row
VERIFY=1              # 1 = test each archive after downloading (needs unzip; unrar/7z for .rar)
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

LEDGER="$LOOT_DIR/.loot_downloaded.tsv"   # record of finished files (key, path, date)
UNAVAILABLE="$LOOT_DIR/.loot_unavailable.tsv"   # files the site doesn't have (key, unix time, reason)
MISSING_OUT="loot_missing.tsv"     # rows still missing after this run (same format as the input)
FAILED_OUT="loot_failed.txt"       # failures with reasons
EXPIRED_OUT="loot_expired.txt"     # bundles whose links need refreshing
DONE_JS="loot_done_bundles.js"     # paste into the Console so the collector skips finished bundles

echo -e "${BLUE}Loot Studios downloader${NC}"
printf "List file:   ${YELLOW}%s${NC}\n" "$LIST_FILE"
printf "Destination: ${YELLOW}%s${NC} (folder structure %s)\n" "$LOOT_DIR" "$FOLDER_STRUCTURE"
if [[ $MARK_ALL_DOWNLOADED -eq 1 ]]; then
    printf "Mode:        ${YELLOW}record everything in the list as downloaded (nothing is downloaded)${NC}\n"
elif [[ $DOWNLOAD -eq 1 ]]; then
    printf "Mode:        ${YELLOW}download missing files${NC} (%ss between downloads)\n" "$DELAY_SECONDS"
else
    printf "Mode:        ${YELLOW}check only${NC}\n"
fi
(( SKIP_DOWNLOADED )) && printf "Recorded files are skipped even if they're no longer in the folder.\n"
echo ""

[[ -f "$LIST_FILE" ]] || { echo -e "${RED}List file not found: $LIST_FILE${NC}"; exit 1; }
[[ -d "$LOOT_DIR" ]] || mkdir -p "$LOOT_DIR" 2>/dev/null || { echo -e "${RED}Cannot create $LOOT_DIR${NC}"; exit 1; }
[[ -w "$LOOT_DIR" ]] || { echo -e "${RED}No write permission for $LOOT_DIR${NC}"; exit 1; }
command -v curl &>/dev/null || { echo -e "${RED}curl is not installed.${NC}"; exit 1; }
if [[ $VERIFY -eq 1 ]] && ! command -v unzip &>/dev/null; then
    echo -e "${YELLOW}Note: unzip not installed - .zip files won't be tested (sudo apt install unzip).${NC}"
fi

# ---------- helpers ----------
# Make a safe single folder/file name
safe_name() {
    local s="$1"
    s="${s//\//_}"
    s="$(printf '%s' "$s" | tr -d '\000-\037')"
    s="${s#"${s%%[![:space:].]*}"}"       # trim leading spaces/dots
    s="${s%"${s##*[![:space:].]}"}"       # trim trailing spaces/dots
    printf '%s' "$s"
}

in_list() {   # in_list "value" "space separated list"  (case-insensitive; empty list = match)
    [[ -z "$2" ]] && return 0
    local v="${1,,}" x
    for x in ${2,,}; do [[ "$v" == "$x" ]] && return 0; done
    return 1
}

# The site names some pictures wrongly (a "...-painted-resin.jpg" that is really a PNG).
# image_real_ext FILE - prints the extension the content shows (png/jpg/webp/gif), or nothing
image_real_ext() {
    case "$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')" in
        89504e47*) echo png ;; ffd8ff*) echo jpg ;; 52494646*) echo webp ;; 47494638*) echo gif ;;
    esac
}
# with_ext PATH EXT - PATH with its extension replaced by EXT
with_ext() { printf '%s.%s' "${1%.*}" "$2"; }

# Check a finished archive. Returns 0 = OK, 1 = broken, 2 = not checked.
verify_archive() {
    local f="$1" magic
    magic=$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')
    case "${f,,}" in
        *.png) [[ "$magic" == 89504e47* ]] || { LAST_ERROR="not a PNG image"; return 1; } ;;
        *.jpg|*.jpeg) [[ "$magic" == ffd8ff* ]] || { LAST_ERROR="not a JPEG image"; return 1; } ;;
        *.webp) [[ "$magic" == 52494646* ]] || { LAST_ERROR="not a WebP image"; return 1; } ;;
        *.gif) [[ "$magic" == 47494638* ]] || { LAST_ERROR="not a GIF image"; return 1; } ;;
        *.pdf) [[ "$magic" == 25504446* ]] || { LAST_ERROR="not a PDF file"; return 1; } ;;
        *.zip)
            [[ "$magic" == 504b0304* || "$magic" == 504b0506* ]] || { LAST_ERROR="not a zip file (got: $(head -c 60 "$f" | tr -cd '[:print:]'))"; return 1; }
            command -v unzip &>/dev/null || return 2
            # unzip exit codes: 0 = OK, 1 = warnings only (e.g. a file name stored in two different
            # encodings - the data is fine, Windows doesn't mind), 2+ = real errors
            local zout zrc
            zout=$(unzip -tq "$f" 2>&1); zrc=$?
            (( zrc <= 1 )) || { LAST_ERROR="zip test failed (damaged or incomplete): $(grep -m1 -v -e '^[[:space:]]*$' -e '^\[' <<< "$zout" | tr -s ' ' | head -c 150)"; return 1; } ;;
        *.rar)
            [[ "$magic" == 52617221* ]] || { LAST_ERROR="not a rar file"; return 1; }
            if command -v unrar &>/dev/null; then unrar t -idq "$f" &>/dev/null || { LAST_ERROR="rar test failed"; return 1; }
            elif command -v 7z &>/dev/null; then 7z t "$f" &>/dev/null || { LAST_ERROR="rar test failed"; return 1; }
            else return 2; fi ;;
        *.7z)
            [[ "$magic" == 377abcaf* ]] || { LAST_ERROR="not a 7z file"; return 1; }
            command -v 7z &>/dev/null || return 2
            7z t "$f" &>/dev/null || { LAST_ERROR="7z test failed"; return 1; } ;;
        *) return 2 ;;
    esac
    return 0
}

# Download URL to DEST via DEST.part. 0 = OK, 1 = failed, 2 = refused (expired or no access)
download_file() {
    local url="$1" dest="$2" tmp="${2}.part" hdr errf result rc code ctype retry_after wait attempt=0 first
    mkdir -p "$(dirname "$dest")" || { LAST_ERROR="cannot create folder"; return 1; }
    while :; do
        hdr=$(mktemp); errf=$(mktemp)
        result=$(curl --silent --show-error --location --connect-timeout 30 \
            --speed-limit 1024 --speed-time "$STALL_SECONDS" \
            -D "$hdr" -o "$tmp" -w '%{http_code} %{content_type}' "$url" 2>"$errf")
        rc=$?
        code="${result%% *}"; ctype="${result#* }"; [[ "$ctype" == "$result" ]] && ctype=""
        retry_after=$(grep -i '^retry-after:' "$hdr" | tail -1 | tr -dc '0-9')
        LAST_ERROR="curl exit $rc, HTTP ${code:-none}$( [[ -s "$errf" ]] && printf ', %s' "$(head -c 150 "$errf" | tr '\n' ' ')")"
        rm -f "$hdr" "$errf"

        if (( rc == 0 )) && [[ "$code" == "200" && -s "$tmp" ]]; then
            first=$(head -c 1 "$tmp")
            if [[ "$ctype" == text/html* || "$first" == "<" ]]; then
                LAST_ERROR="got a web page instead of the file"
                rm -f "$tmp"; return 2
            fi
            mv -f "$tmp" "$dest" && return 0
            LAST_ERROR="could not move finished download into place"; rm -f "$tmp"; return 1
        fi
        rm -f "$tmp"

        if [[ "$code" == "401" || "$code" == "403" || "$code" == "404" || "$code" == "410" ]]; then
            LAST_ERROR="HTTP $code (link expired, or no access to this bundle)"
            return 2
        fi
        if [[ "$code" == "429" || "$code" == 5?? || "$code" == "000" || -z "$code" || $rc -eq 28 ]] && (( attempt < MAX_RETRIES )); then
            attempt=$((attempt + 1))
            wait=${retry_after:-$(( BACKOFF_SECONDS * (1 << (attempt - 1)) ))}
            (( wait > 900 )) && wait=900
            printf "    ${YELLOW}%s - waiting %ss before retry %s/%s${NC}\n" "$LAST_ERROR" "$wait" "$attempt" "$MAX_RETRIES"
            sleep "$wait"
            continue
        fi
        return 1
    done
}

# ---------- read the list ----------
mapfile -t lines < <(sed $'1s/^\xEF\xBB\xBF//; s/\r$//' "$LIST_FILE")
(( ${#lines[@]} > 1 )) || { echo -e "${RED}The list is empty.${NC}"; exit 1; }
# Split on tabs via \x1f: with a tab in IFS, empty columns would be merged and the rest would shift
IFS=$'\x1f' read -r -a header <<< "${lines[0]//$'\t'/$'\x1f'}"
declare -A col=()
for i in "${!header[@]}"; do col["${header[$i],,}"]=$i; done
for c in bundle file url; do
    [[ -n "${col[$c]}" ]] || { echo -e "${RED}The list has no '$c' column. Export it with the export snippet.${NC}"; exit 1; }
done

head -n 1 <<< "${lines[0]}" > "$MISSING_OUT"
: > "$FAILED_OUT"
: > "$EXPIRED_OUT"

# Parse one list row into variables; sets ROW_OK=0 for rows to ignore
parse_row() {
    local line="$1"
    ROW_OK=0
    [[ -z "${line//[[:space:]]/}" ]] && return
    IFS=$'\x1f' read -r -a f <<< "${line//$'\t'/$'\x1f'}"
    bundle="${f[${col[bundle]}]}"
    folder="${f[${col[folder]:-99}]}"
    scale="${f[${col[scale]:-99}]}"
    material="${f[${col[material]:-99}]}"
    file="${f[${col[file]}]}"
    url="${f[${col[url]}]}"
    kind="${f[${col[kind]:-99}]}"; [[ -z "$kind" ]] && kind="all"   # all / item / extra (older lists: all)
    group="${f[${col[group]:-99}]}"
    item="${f[${col[item]:-99}]}"
    variant="${f[${col[variant]:-99}]}"
    [[ -z "$file" || ! "$url" =~ ^https?:// ]] && return
    if [[ "$FOLDER_STRUCTURE" == "BUNDLE_TITLE" || -z "$folder" ]]; then dir="$(safe_name "$bundle")"; else dir="$(safe_name "$folder")"; fi
    [[ -z "$dir" ]] && dir="Unknown bundle"
    # Inside the bundle folder: All Bundle archives and extras at the top, figures per group
    inner="$(safe_name "$file")"
    if [[ "$kind" == "item" ]]; then sub="$(safe_name "$group")"; inner="${sub:-Figures}/$inner"; fi
    if [[ "$kind" == "image" ]]; then sub="$(safe_name "$group")"; inner="Images/${sub:-Figures}/$inner"; fi
    dest="$LOOT_DIR/$dir/$inner"
    page="${f[${col[page]:-99}]}"
    # Stable id for the ledger (the link itself changes every time it is refreshed)
    key="${page:-$bundle}|$scale|$material|$file"
    # A figure and its bust often have the same name, so their pictures have the same file name
    # (in different group folders): pictures get the group in their key
    oldkey="$key"
    [[ "$kind" == "image" ]] && key="$key|$group"
    link_time=0
    [[ "$url" =~ [?\&]v=([0-9]{9,})- ]] && link_time="${BASH_REMATCH[1]}"
    ROW_OK=1
}

# ---------- ledger of finished files: key <TAB> path relative to LOOT_DIR <TAB> date ----------
declare -A recorded=()
if [[ -f "$LEDGER" ]]; then
    while IFS=$'\t' read -r lkey lpath _; do
        [[ -n "$lkey" ]] && recorded[$lkey]="${lpath:--}"
    done < <(tr -d '\r' < "$LEDGER")
fi
record() {   # record KEY PATH
    [[ "${recorded[$1]}" == "$2" ]] && return
    recorded[$1]="$2"
    printf '%s\t%s\t%s\n' "$1" "$2" "$(date '+%Y-%m-%d %H:%M')" >> "$LEDGER"
}

# ---------- files the site doesn't have: key <TAB> unix time <TAB> reason ----------
declare -A unavail_at=()
if [[ -f "$UNAVAILABLE" ]]; then
    while IFS=$'\t' read -r lkey ltime _; do
        [[ -n "$lkey" && "$ltime" =~ ^[0-9]+$ ]] && unavail_at[$lkey]="$ltime"
    done < <(tr -d '\r' < "$UNAVAILABLE")
fi
mark_unavailable() {   # mark_unavailable KEY REASON
    unavail_at[$1]=$(date +%s)
    printf '%s\t%s\t%s\n' "$1" "${unavail_at[$1]}" "$2" >> "$UNAVAILABLE"
}

# If the list holds several links for the same file (e.g. an older export), use the newest one
declare -A best_row=() best_time=() oldkey_uses=()
for (( n = 1; n < ${#lines[@]}; n++ )); do
    parse_row "${lines[$n]}"; (( ROW_OK )) || continue
    [[ "$kind" == "image" && "${oldkey_uses[$oldkey]}" != *"|$group|"* ]] && oldkey_uses[$oldkey]+="|$group|"
    if [[ -z "${best_row[$dest]}" ]] || (( link_time > ${best_time[$dest]} )); then
        best_row[$dest]=$n; best_time[$dest]=$link_time
    fi
done

now=$(date +%s)
total=0; present=0; downloaded=0; failed=0; expired=0; filtered=0; unchecked=0; marked=0; unavailable=0
refused_streak=0; attempts=0; first_download=1; stopped=""
declare -A expired_bundles=() page_files=() page_done=()
keep_missing() { printf '%s\n' "$line" >> "$MISSING_OUT"; }   # uses the current $line
is_done() { [[ -n "$page" ]] && page_done[$page]=$(( ${page_done[$page]:-0} + 1 )); }

for (( n = 1; n < ${#lines[@]}; n++ )); do
    line="${lines[$n]}"
    parse_row "$line"; (( ROW_OK )) || continue
    (( ${best_row[$dest]} == n )) || continue      # an older link for the same file
    if [[ "$kind" == "extra" ]]; then
        (( EXTRAS )) || { ((filtered++)); continue; }
    elif [[ "$kind" == "image" ]]; then
        if (( ! IMAGES )) || ! in_list "$variant" "$IMAGE_TYPES" || ! in_list "$material" "$MATERIALS"; then ((filtered++)); continue; fi
    else
        if ! in_list "$material" "$MATERIALS" || ! in_list "$scale" "$SCALES"; then ((filtered++)); continue; fi
        if [[ "$kind" == "item" ]] && { (( ! INDIVIDUAL )) || ! in_list "$variant" "$VARIANTS"; }; then ((filtered++)); continue; fi
    fi
    ((total++))
    [[ -n "$page" ]] && page_files[$page]=$(( ${page_files[$page]:-0} + 1 ))

    case "$kind" in
        item)  label="$bundle - $item ${scale:+$scale }${material:+$material }${variant:+$variant }($file)" ;;
        extra) label="$bundle - ${item:-extra} ($file)" ;;
        image) label="$bundle - $item - $variant image ${material}" ;;
        *)     label="$bundle - ${scale:+$scale }${material:+$material }($file)" ;;
    esac

    # Pictures recorded by older versions (key without the group): the recorded path's folder
    # says which group the picture was; only that one counts as downloaded
    if [[ "$kind" == "image" && -z "${recorded[$key]}" && -n "${recorded[$oldkey]}" ]]; then
        rp="${recorded[$oldkey]}"; rg="${rp%/*}"; rg="${rg##*/}"; sg="$(safe_name "$group")"
        [[ "$rg" == "${sg:-Figures}" || "$rp" == "("* ]] && record "$key" "$rp"
    fi
    # ... and "not on the site" from older versions, unless two groups share that name
    if [[ "$kind" == "image" && -z "${unavail_at[$key]}" && -n "${unavail_at[$oldkey]}" \
          && "${oldkey_uses[$oldkey]}" == "|$group|" ]]; then
        unavail_at[$key]="${unavail_at[$oldkey]}"
    fi

    # Recorded as downloaded on an earlier run (the file may have been extracted and deleted since)
    if [[ -n "${recorded[$key]}" ]] && { (( SKIP_DOWNLOADED )) || [[ -s "$LOOT_DIR/${recorded[$key]}" ]]; }; then
        ((present++)); is_done
        printf "  ${GREEN}✓${NC} %s\n" "$label"
        continue
    fi
    # Not on the site when last tried (e.g. no painted image for this figure): skip until it's time to look again
    if [[ -n "${unavail_at[$key]}" ]] && (( $(date +%s) - ${unavail_at[$key]} < UNAVAILABLE_RECHECK_DAYS * 86400 )); then
        ((unavailable++)); is_done
        continue
    fi
    if [[ $MARK_ALL_DOWNLOADED -eq 1 ]]; then
        record "$key" "${dest#"$LOOT_DIR/"}"
        ((marked++)); is_done
        printf "  ${GREEN}✓ recorded${NC} %s\n" "$label"
        continue
    fi

    # A picture saved under its real extension (see below) counts too
    if [[ "$kind" == "image" && ! -s "$dest" ]]; then
        for e in png jpg webp gif; do
            [[ -s "$(with_ext "$dest" "$e")" ]] && { dest="$(with_ext "$dest" "$e")"; break; }
        done
    fi
    if [[ -s "$dest" ]]; then
        record "$key" "${dest#"$LOOT_DIR/"}"
        ((present++)); is_done
        printf "  ${GREEN}✓${NC} %s\n" "$label"
        continue
    fi
    # Also accept the file in this bundle's other possible folder (the other
    # FOLDER_STRUCTURE setting), so changing FOLDER_STRUCTURE doesn't cause re-downloads.
    # Never look in other bundles' folders: many bundles use the same file
    # names (e.g. All_75mm.zip). Older versions named the folder of newer
    # bundles after the first part of the link (e.g. "Fantasy"), so All Bundle
    # archives are looked for there too.
    elsewhere=""
    legacy=""
    if [[ "$kind" == "all" ]]; then legacy="${url#*://}"; legacy="${legacy#*/}"; legacy="$(safe_name "${legacy%%/*}")"; fi
    for alt in "$(safe_name "$folder")" "$(safe_name "$bundle")" "$legacy"; do
        [[ -n "$alt" ]] || continue
        cand="$LOOT_DIR/$alt/$inner"
        if [[ "$cand" != "$dest" && -s "$cand" ]]; then elsewhere="$cand"; break; fi
    done
    if [[ -n "$elsewhere" ]]; then
        record "$key" "${elsewhere#"$LOOT_DIR/"}"
        ((present++)); is_done
        printf "  ${GREEN}✓${NC} %s ${YELLOW}(already at %s)${NC}\n" "$label" "${elsewhere#"$LOOT_DIR/"}"
        continue
    fi

    if [[ $DOWNLOAD -ne 1 || -n "$stopped" ]]; then
        printf "  ${RED}✗ MISSING${NC} %s\n" "$label"
        keep_missing; continue
    fi
    if (( MAX_DOWNLOADS > 0 && attempts >= MAX_DOWNLOADS )); then
        stopped="reached MAX_DOWNLOADS ($MAX_DOWNLOADS) for this run"
        printf "  ${YELLOW}Download limit reached - remaining files are only checked.${NC}\n"
        printf "  ${RED}✗ MISSING${NC} %s\n" "$label"
        keep_missing; continue
    fi

    # Link expiry: v=<unix time>-<signature>
    if (( link_time > 0 )); then
        expires=$link_time
        now=$(date +%s)
        if (( now + EXPIRY_MARGIN >= expires )); then
            ((expired++))
            expired_bundles["$bundle"]=1
            printf "  ${YELLOW}⏱ LINK EXPIRED${NC} %s\n" "$label"
            keep_missing; continue
        fi
    fi

    if (( ! first_download )); then
        if [[ "$kind" == "image" ]]; then sleep "$IMAGE_DELAY_SECONDS"; else sleep "$DELAY_SECONDS"; fi
    fi
    first_download=0
    ((attempts++))
    printf "  ${BLUE}↓ Downloading${NC} %s -> %s ...\n" "$label" "${dest#"$LOOT_DIR/"}"
    start=$(date +%s)
    download_file "$url" "$dest"
    result=$?

    if (( result == 0 )); then
        refused_streak=0
        # A picture whose content doesn't match its name (".jpg" that is really a PNG): give it
        # the right extension instead of calling it damaged
        if [[ "$kind" == "image" ]]; then
            real_ext="$(image_real_ext "$dest")"
            cur_ext="${dest##*.}"; cur_ext="${cur_ext,,}"; [[ "$cur_ext" == jpeg ]] && cur_ext=jpg
            if [[ -n "$real_ext" && "$real_ext" != "$cur_ext" ]]; then
                fixed="$(with_ext "$dest" "$real_ext")"
                if [[ -e "$fixed" ]] && ! cmp -s "$dest" "$fixed"; then fixed="$(with_ext "${dest%.*}_2.x" "$real_ext")"; fi
                mv -f "$dest" "$fixed" && dest="$fixed"
                printf "    ${YELLOW}The site sent a %s picture - saved as %s${NC}\n" "${real_ext^^}" "${dest##*/}"
            fi
        fi
        if [[ $VERIFY -eq 1 ]]; then
            verify_archive "$dest"; v=$?
            if (( v == 1 )); then
                ((failed++))
                printf "  ${RED}✗ Downloaded file is damaged:${NC} %s\n" "$LAST_ERROR"
                printf '%s\t%s\t%s\n' "$bundle" "$file" "$LAST_ERROR" >> "$FAILED_OUT"
                rm -f "$dest"
                keep_missing; continue
            fi
            (( v == 2 )) && ((unchecked++))
        fi
        record "$key" "${dest#"$LOOT_DIR/"}"
        ((downloaded++)); is_done
        secs=$(( $(date +%s) - start ))
        printf "  ${GREEN}✓ DOWNLOADED${NC} %s (%s in %ss)\n" "$label" "$(du -h "$dest" | cut -f1)" "$secs"
        continue
    fi

    # Image and magazine links don't expire: a refusal means the site doesn't have that file
    # (most figures have no painted or FDM image). Remember it and look again in UNAVAILABLE_RECHECK_DAYS.
    if (( result == 2 )) && [[ "$kind" == "extra" || "$kind" == "image" ]]; then
        mark_unavailable "$key" "${LAST_ERROR%% (*}"
        ((unavailable++)); is_done
        printf "  ${YELLOW}- not on the site${NC} (%s) - checked again in %s days\n" "${LAST_ERROR%% (*}" "$UNAVAILABLE_RECHECK_DAYS"
        continue
    fi
    ((failed++))
    printf "  ${RED}✗ Download failed:${NC} %s\n" "$LAST_ERROR"
    printf '%s\t%s\t%s\n' "$bundle" "$file" "$LAST_ERROR" >> "$FAILED_OUT"
    keep_missing
    if (( result == 2 )); then
        ((refused_streak++))
        if (( refused_streak >= REFUSED_LIMIT )); then
            stopped="$REFUSED_LIMIT refused downloads in a row - the links have probably expired; refresh them with 1_loot_collect_all_bundles.js"
            printf "  ${RED}Stopping downloads: %s${NC}\n" "$stopped"
        fi
    else
        refused_streak=0
    fi
done

for b in "${!expired_bundles[@]}"; do echo "$b"; done | sort > "$EXPIRED_OUT"
missing=$((total - present - downloaded - marked - unavailable))

# Bundles whose files are all downloaded -> snippet for the collector, so it doesn't re-read them
done_pages=()
for p in "${!page_files[@]}"; do
    (( ${page_done[$p]:-0} >= ${page_files[$p]} )) && done_pages+=("$p")
done
if (( ${#page_files[@]} > 0 )); then
    {
        printf '// Written by 3_loot_download_all_bundles.sh on %s.\n' "$(date '+%Y-%m-%d %H:%M')"
        printf '// Paste into the Console on app.lootstudios.com before running 1_loot_collect_all_bundles.js:\n'
        printf '// the collector then skips these bundles, because everything in them is downloaded.\n'
        printf '// Hide unrelated Console "noise" (red errors/warnings from the site'"'"'s own scripts): click the\n'
        printf '// gear icon at the top right of the Console, tick "Hide network" and "Selected context only".\n'
        printf "localStorage.setItem('lootDonePages', JSON.stringify([\n"
        for p in "${done_pages[@]}"; do
            p="${p//\\/\\\\}"; p="${p//\"/\\\"}"
            printf '  "%s",\n' "$p"
        done | sort
        printf ']));\n'
        printf "'%s downloaded bundle(s) saved - the collector will skip them.'\n" "${#done_pages[@]}"
    } > "$DONE_JS"
fi

echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e " Files in list:          ${BLUE}${total}${NC}$( (( filtered )) && echo "  (+$filtered skipped by your settings: MATERIALS, SCALES, INDIVIDUAL, VARIANTS, EXTRAS, IMAGES)")"
echo -e " Already downloaded:     ${GREEN}${present}${NC}"
(( marked )) && echo -e " Recorded as downloaded: ${GREEN}${marked}${NC} (MARK_ALL_DOWNLOADED - nothing was downloaded)"
echo -e " Downloaded this run:    ${GREEN}${downloaded}${NC}"
echo -e " Expired links:          ${YELLOW}${expired}${NC}"
echo -e " Not on the site:        ${unavailable} (e.g. figures without a painted image; looked for again after ${UNAVAILABLE_RECHECK_DAYS} days)"
echo -e " Failed:                 ${RED}${failed}${NC}"
echo -e " Still missing:          ${RED}${missing}${NC}"
echo -e "${YELLOW}================================================${NC}"
[[ -n "$stopped" ]] && echo -e "${YELLOW}Downloads stopped early: ${stopped}${NC}"
(( unchecked > 0 )) && echo -e "${YELLOW}$unchecked file(s) could not be tested (install unzip / unrar / 7z to test them).${NC}"
if (( missing > 0 )); then
    echo -e "Still-missing files saved to: ${YELLOW}${MISSING_OUT}${NC} (same format as the list)"
fi
(( failed > 0 )) && echo -e "Failure reasons saved to:     ${YELLOW}${FAILED_OUT}${NC}"
if (( expired > 0 )); then
    echo -e "${YELLOW}Some links have expired.${NC} Bundles needing fresh links are in ${YELLOW}${EXPIRED_OUT}${NC}."
    echo "Refresh: run 1_loot_collect_all_bundles.js again (it re-reads expired bundles), export with 2_loot_export_list.js, and rerun this script."
fi
(( missing == 0 && failed == 0 )) && echo -e "${GREEN}Everything in the list is downloaded.${NC}"
if [[ -s "$DONE_JS" ]] && (( ${#done_pages[@]} > 0 )); then
    echo -e "${#done_pages[@]} bundle(s) are fully downloaded. To make the collector skip them next round, paste"
    echo -e "${YELLOW}${DONE_JS}${NC} into the Console on app.lootstudios.com before running the collector."
fi
if (( MARK_ALL_DOWNLOADED )); then echo -e "${YELLOW}Set MARK_ALL_DOWNLOADED back to 0 before the next run.${NC}"; fi
