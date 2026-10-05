#!/bin/bash
# ================================================================
# Patreon downloader
# Reads the lists exported by 2_patreon_export_list.js (patreon_list*.tsv - one per Patreon
# account) and downloads every attached file that isn't downloaded yet, into
#   PATREON_DIR/<creator>/<date> - <post title>/<file>
#
# The file links in the list are signed links on Patreon's file server: no login or cookie is
# needed, but they expire about 2 days after they were collected. Expired links are skipped
# and listed - collect and export again, then rerun.
# Links found in the post text (Google Drive, MEGA, ...) and older attachments that need your
# Patreon login are not downloaded; they're listed in patreon_links.txt.
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;94m'
NC='\033[0m'

# ==============================
# SETTINGS
# ==============================
LIST_FILES="patreon_list*.tsv"   # exported lists (next to this script); one per account
# Where the files are stored. Empty = the folder this script is in.
# To use another folder, put its full path here, e.g. "/mnt/nas/3DPrints/Patreon".
PATREON_DIR=""
CREATORS=""           # only these creators, e.g. "eXoDus" (separate several with |); empty = all

# Every finished file is recorded in PATREON_DIR/.patreon_downloaded.tsv (keep that file!).
SKIP_DOWNLOADED=1     # 1 = skip files recorded as downloaded, even if you've since extracted
                      #     and deleted them; 0 = download them again if they're no longer there
MARK_ALL_DOWNLOADED=0 # 1 = download nothing; record every file in the lists as downloaded
                      #     (use once if you already have everything in your current lists)

DOWNLOAD=1            # 1 = download missing files, 0 = check only
DELAY_SECONDS=3       # pause between files
MAX_DOWNLOADS=0       # stop after this many downloads this run (0 = no limit)
MAX_RETRIES=4         # retries for rate limits, server errors and network errors
BACKOFF_SECONDS=30    # first retry wait; doubles each retry unless the server says otherwise
STALL_SECONDS=120     # abort a download that receives almost nothing for this long
EXPIRY_MARGIN=600     # treat links expiring within this many seconds as expired
REFUSAL_LIMIT=3       # stop after this many refused links in a row (expired, or blocked)
VERIFY=1              # 1 = test each archive after downloading (needs unzip; unrar/7z for .rar/.7z)
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "$PATREON_DIR" ]] && PATREON_DIR="$script_dir"
[[ "$PATREON_DIR" != /* ]] && PATREON_DIR="$script_dir/$PATREON_DIR"
PATREON_DIR="${PATREON_DIR%/}"
LEDGER="$PATREON_DIR/.patreon_downloaded.tsv"   # id <TAB> path relative to PATREON_DIR <TAB> date
MISSING_OUT="patreon_missing.tsv"
FAILED_OUT="patreon_failed.txt"
LINKS_OUT="patreon_links.txt"

echo -e "${BLUE}Patreon downloader${NC}"
shopt -s nullglob
lists=()
for f in "$script_dir"/$LIST_FILES ./$LIST_FILES; do
    f="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
    [[ " ${lists[*]} " == *" $f "* ]] || lists+=("$f")
done
shopt -u nullglob
(( ${#lists[@]} )) || { echo -e "${RED}No list found ($LIST_FILES next to this script). Export it with 2_patreon_export_list.js.${NC}"; exit 1; }
for f in "${lists[@]}"; do printf "List:        ${YELLOW}%s${NC}\n" "$f"; done
printf "Destination: ${YELLOW}%s${NC}\n" "$PATREON_DIR"
if [[ $MARK_ALL_DOWNLOADED -eq 1 ]]; then printf "Mode:        ${YELLOW}record everything in the lists as downloaded (nothing is downloaded)${NC}\n"; DOWNLOAD=0
elif [[ $DOWNLOAD -eq 1 ]]; then printf "Mode:        ${YELLOW}download missing files${NC} (%ss between files)\n" "$DELAY_SECONDS"
else printf "Mode:        ${YELLOW}check only${NC}\n"; fi
echo ""
mkdir -p "$PATREON_DIR" 2>/dev/null; [[ -w "$PATREON_DIR" ]] || { echo -e "${RED}No write permission for $PATREON_DIR${NC}"; exit 1; }
command -v curl &>/dev/null || { echo -e "${RED}curl is not installed.${NC}"; exit 1; }

# ---------- helpers ----------
safe_name() {   # usable as a file/folder name on Linux and Windows shares
    local s="$1"
    s="$(printf '%s' "$s" | tr -d '\000-\037' | sed 's#[<>:"/\\|?*]#_#g')"
    s="${s#"${s%%[![:space:].]*}"}"
    s="${s%"${s##*[![:space:].]}"}"
    (( ${#s} > 120 )) && s="${s:0:120}" && s="${s%"${s##*[![:space:].]}"}"
    printf '%s' "$s"
}

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

# ---------- read the ledger (file id -> path relative to PATREON_DIR) ----------
declare -A ledger=() path_owner=()
if [[ -f "$LEDGER" ]]; then
    while IFS=$'\t' read -r lid lpath _; do
        [[ -n "$lid" && -n "$lpath" ]] || continue
        ledger[$lid]="$lpath"; path_owner[$lpath]="$lid"
    done < <(tr -d '\r' < "$LEDGER")
fi
record() {   # record ID RELPATH   (third column: date, for your information)
    [[ "${ledger[$1]}" == "$2" ]] && return
    ledger[$1]="$2"; path_owner[$2]="$1"
    printf '%s\t%s\t%s\n' "$1" "$2" "$(date '+%Y-%m-%d %H:%M')" >> "$LEDGER"
}

# ---------- read the lists (newest link per file wins) ----------
declare -A row=() row_time=()
for lf in "${lists[@]}"; do
    mapfile -t lines < <(sed $'1s/^\xEF\xBB\xBF//; s/\r$//' "$lf")
    (( ${#lines[@]} > 1 )) || { echo -e "${YELLOW}Empty list: $lf${NC}"; continue; }
    # Split on tabs via \x1f: with a tab in IFS, empty columns would be merged and the rest would shift
    IFS=$'\x1f' read -r -a header <<< "${lines[0]//$'\t'/$'\x1f'}"
    declare -A lcol=()
    for i in "${!header[@]}"; do lcol["${header[$i],,}"]=$i; done
    for c in creator post kind name id url; do
        [[ -n "${lcol[$c]}" ]] || { echo -e "${RED}$lf has no '$c' column. Export it with 2_patreon_export_list.js.${NC}"; exit 1; }
    done
    for (( n = 1; n < ${#lines[@]}; n++ )); do
        line="${lines[$n]}"; [[ -z "${line//[[:space:]]/}" ]] && continue
        IFS=$'\x1f' read -r -a f <<< "${line//$'\t'/$'\x1f'}"
        id="${f[${lcol[id]}]}"; url="${f[${lcol[url]}]}"
        [[ -n "$id" ]] || continue
        t=0; [[ "$url" =~ [?\&]token-time=([0-9]{9,}) ]] && t="${BASH_REMATCH[1]}"
        if [[ -z "${row[$id]}" ]] || (( t > ${row_time[$id]} )); then
            # store the row as named fields, so lists with different column orders mix
            v=""; for c in creator post published kind name id size url post_url; do v+="${f[${lcol[$c]:-99}]}"$'\x1f'; done
            row[$id]="$v"; row_time[$id]=$t
        fi
    done
    unset lcol
done

printf 'creator\tpost\tpublished\tkind\tname\tid\tsize\turl\tpost_url\n' > "$MISSING_OUT"
: > "$FAILED_OUT"; : > "$LINKS_OUT"

total=0; present=0; downloaded=0; failed=0; expired=0; unchecked=0; marked=0; attempts=0; refused=0
first=1; stopped=""; filtered=0; nlinks=0
now=$(date +%s)
declare -A link_seen=()

mapfile -t ids < <(for id in "${!row[@]}"; do IFS=$'\x1f' read -r c p d _ <<< "${row[$id]}"; printf '%s\t%s\t%s\t%s\n' "$c" "$d" "$p" "$id"; done | sort -t$'\t' -k1,1 -k2,2r -k3,3 | cut -f4)

last_post=""
for id in "${ids[@]}"; do
    IFS=$'\x1f' read -r creator post published kind name _ size url post_url <<< "${row[$id]}"
    if [[ -n "$CREATORS" ]] && ! [[ "|${CREATORS,,}|" == *"|${creator,,}|"* ]]; then ((filtered++)); continue; fi
    pdir="$(safe_name "${published:+$published - }$post")"; [[ -z "$pdir" ]] && pdir="Post"
    reldir="$(safe_name "$creator")/$pdir"
    what="$creator - ${post:0:60} - $name"

    # Links in the post text and older attachments: listed, not downloaded
    if [[ "$kind" != "file" ]]; then
        [[ -n "${link_seen[$url]}" ]] && continue
        link_seen[$url]=1; ((nlinks++))
        if [[ "$reldir" != "$last_post" ]]; then printf '\n%s\n  %s\n' "$creator - ${published:+$published - }$post" "$post_url" >> "$LINKS_OUT"; last_post="$reldir"; fi
        if [[ "$kind" == "attachment" ]]; then printf '  [attachment - needs your Patreon login, download it in the browser] %s\n' "$name" >> "$LINKS_OUT"
        else printf '  %s\n' "$url" >> "$LINKS_OUT"; fi
        continue
    fi
    ((total++))
    line="$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$creator" "$post" "$published" "$kind" "$name" "$id" "$size" "$url" "$post_url")"

    # Already downloaded before? (the file may have been extracted and deleted since)
    if [[ -n "${ledger[$id]}" ]] && { (( SKIP_DOWNLOADED )) || [[ -s "$PATREON_DIR/${ledger[$id]}" ]]; }; then
        ((present++)); printf "  ${GREEN}✓${NC} %s\n" "$what"; continue
    fi
    fname="$(safe_name "$name")"; [[ -z "$fname" ]] && fname="file_${id}"
    relpath="$reldir/$fname"
    # same name already used by a different file in this post: keep both
    if [[ -n "${path_owner[$relpath]}" && "${path_owner[$relpath]}" != "$id" ]]; then
        if [[ "$fname" == *.* ]]; then relpath="$reldir/${fname%.*}_$id.${fname##*.}"; else relpath="$reldir/${fname}_$id"; fi
    fi
    if [[ $MARK_ALL_DOWNLOADED -eq 1 ]]; then
        record "$id" "$relpath"; ((marked++)); printf "  ${GREEN}✓ recorded${NC} %s\n" "$what"; continue
    fi
    if [[ -s "$PATREON_DIR/$relpath" ]]; then
        record "$id" "$relpath"; ((present++)); printf "  ${GREEN}✓${NC} %s (already there)\n" "$what"; continue
    fi
    if [[ $DOWNLOAD -ne 1 || -n "$stopped" ]]; then
        printf "  ${RED}✗ MISSING${NC} %s\n" "$what"; printf '%s\n' "$line" >> "$MISSING_OUT"; continue
    fi
    if (( MAX_DOWNLOADS > 0 && attempts >= MAX_DOWNLOADS )); then
        stopped="reached MAX_DOWNLOADS ($MAX_DOWNLOADS) for this run"
        printf "  ${YELLOW}Download limit reached - remaining files are only listed.${NC}\n"
        printf "  ${RED}✗ MISSING${NC} %s\n" "$what"; printf '%s\n' "$line" >> "$MISSING_OUT"; continue
    fi
    # link expiry: token-time=<unix time>
    if [[ "$url" =~ [?\&]token-time=([0-9]{9,}) ]] && (( now + EXPIRY_MARGIN >= ${BASH_REMATCH[1]} )); then
        ((expired++)); printf "  ${YELLOW}⏱ LINK EXPIRED${NC} %s\n" "$what"; printf '%s\n' "$line" >> "$MISSING_OUT"; continue
    fi

    (( first )) || sleep "$DELAY_SECONDS"
    first=0; ((attempts++))
    printf "  ${BLUE}↓ Downloading${NC} %s -> %s ...\n" "$what" "$relpath"
    start=$(date +%s)
    fetch_file "$url" "$PATREON_DIR/$relpath"; r=$?
    if (( r == 0 )); then
        refused=0
        if [[ $VERIFY -eq 1 ]]; then
            verify_file "$PATREON_DIR/$relpath"; v=$?
            if (( v == 1 )); then
                ((failed++))
                printf "  ${RED}✗ Downloaded file is damaged:${NC} %s\n" "$LAST_ERROR"
                printf '%s\t%s\t%s\n' "$what" "$LAST_ERROR" "${url%%\?*}" >> "$FAILED_OUT"
                rm -f "$PATREON_DIR/$relpath"; printf '%s\n' "$line" >> "$MISSING_OUT"
                continue
            fi
            (( v == 2 )) && ((unchecked++))
        fi
        record "$id" "$relpath"
        ((downloaded++))
        printf "  ${GREEN}✓ DOWNLOADED${NC} %s (%s in %ss)\n" "$relpath" "$(du -h "$PATREON_DIR/$relpath" | cut -f1)" "$(( $(date +%s) - start ))"
    else
        ((failed++))
        printf "  ${RED}✗ Download failed:${NC} %s\n" "$LAST_ERROR"
        printf '%s\t%s\t%s\n' "$what" "$LAST_ERROR" "${url%%\?*}" >> "$FAILED_OUT"
        printf '%s\n' "$line" >> "$MISSING_OUT"
        if (( r == 2 )); then
            ((refused++))
            if (( refused >= REFUSAL_LIMIT )); then
                stopped="$refused links in a row were refused - collect and export fresh links, then run again"
                printf "  ${RED}Stopping downloads: %s${NC}\n" "$stopped"
            fi
        fi
    fi
done

missing=$((total - present - downloaded - marked))
echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e " Files in the lists:     ${BLUE}${total}${NC}$( (( filtered )) && echo "  (+$filtered of other creators skipped: CREATORS)")"
echo -e " Already downloaded:     ${GREEN}${present}${NC}"
(( marked )) && echo -e " Recorded as downloaded: ${GREEN}${marked}${NC} (MARK_ALL_DOWNLOADED - nothing was downloaded)"
echo -e " Downloaded this run:    ${GREEN}${downloaded}${NC}"
echo -e " Failed:                 ${RED}${failed}${NC}"
(( expired )) && echo -e " Links expired:          ${YELLOW}${expired}${NC} - collect and export again (links last about 2 days)"
echo -e " Still missing:          ${RED}${missing}${NC}"
(( nlinks )) && echo -e " Links to other sites:   ${nlinks} - listed in ${YELLOW}${LINKS_OUT}${NC} (not downloaded)"
echo -e "${YELLOW}================================================${NC}"
[[ -n "$stopped" ]] && echo -e "${YELLOW}Downloads stopped early: ${stopped}${NC}"
(( unchecked > 0 )) && echo -e "${YELLOW}$unchecked file(s) were not tested (not an archive, or unzip/unrar/7z missing).${NC}"
(( missing > 0 )) && echo -e "Still-missing files saved to: ${YELLOW}${MISSING_OUT}${NC}"
(( failed > 0 )) && echo -e "Failures saved to: ${YELLOW}${FAILED_OUT}${NC}"
(( nlinks )) || rm -f "$LINKS_OUT"
(( failed )) || rm -f "$FAILED_OUT"
