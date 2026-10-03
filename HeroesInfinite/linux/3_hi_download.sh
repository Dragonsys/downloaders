#!/bin/bash
# ================================================================
# Heroes Infinite checker + downloader
# Reads the list exported by 2_hi_export_list.js (tab-separated, with a header)
# and downloads every file that isn't downloaded yet, using your login cookie.
#
# Each download link (heroesinfinite.com/courses/downloads/...) redirects to a
# short-lived file link on Amazon S3. The script asks for that redirect just
# before downloading, so nothing expires in the list - only your cookie does.
# Your cookie is only ever sent to heroesinfinite.com, never to the file server.
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;94m'
NC='\033[0m'

# ==============================
# SETTINGS
# ==============================
LIST_FILE="hi_downloads.tsv"                   # exported list (next to this script, or a full path)
# Where the files are stored. Empty = the folder this script is in.
# To use another folder, put its full path here, e.g. "/mnt/nas/HeroesInfinite".
HI_DIR=""

# Folder layout:
#   "collection_post" -> HI_DIR/<collection>/<post>/<file>   (recommended)
#   "collection"      -> HI_DIR/<collection>/<file>
ORGANIZE="collection_post"

# Cookie and user agent: leave empty to use cookie.txt / user_agent.txt next to
# this script (from heroesinfinite.com, NOT MyMiniFactory), or set the
# HI_COOKIE / HI_USER_AGENT environment variables. Never share the cookie.
COOKIE=''
COOKIE_FILE="cookie.txt"
USER_AGENT=''
USER_AGENT_FILE="user_agent.txt"

# Every finished file is recorded in HI_DIR/.hi_downloaded.tsv (keep that file!).
SKIP_DOWNLOADED=1     # 1 = skip files recorded as downloaded, even if you've since extracted
                      #     and deleted them; 0 = download them again if they're no longer there
MARK_ALL_DOWNLOADED=0 # 1 = download nothing; record every file in the list as downloaded.
                      #     Use once if you already have (or deleted) everything in your current
                      #     list, so that from then on only new collections are downloaded.

IMAGES=1              # 1 = also download the pictures: collection covers (into <collection>/) and
                      #     the pictures of each post with downloads (into <collection>/<post>/Images/)
IMAGE_DELAY_SECONDS=1 # pause between pictures (they come from Kajabi's image server, no cookie)

DOWNLOAD=1            # 1 = download missing files, 0 = check only (uses the record of past downloads)
DELAY_SECONDS=5       # pause between files
MAX_DOWNLOADS=0       # stop after this many downloads this run (0 = no limit)
MAX_RETRIES=4         # retries for rate limits, server errors and network errors
BACKOFF_SECONDS=30    # first retry wait; doubles each retry unless the server says otherwise
STALL_SECONDS=120     # abort a download that receives almost nothing for this long
VERIFY=1              # 1 = test each archive after downloading (needs unzip; unrar/7z for .rar)
BASE_URL="https://www.heroesinfinite.com"
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ "$LIST_FILE" != /* && ! -f "$LIST_FILE" && -f "$script_dir/$LIST_FILE" ]] && LIST_FILE="$script_dir/$LIST_FILE"
[[ -z "$HI_DIR" ]] && HI_DIR="$script_dir"
HI_DIR="${HI_DIR%/}"
LEDGER="$HI_DIR/.hi_downloaded.tsv"     # record of which download id became which file
MISSING_OUT="hi_missing.tsv"
FAILED_OUT="hi_failed.txt"

echo -e "${BLUE}Heroes Infinite downloader${NC}"
printf "List file:   ${YELLOW}%s${NC}\n" "$LIST_FILE"
printf "Destination: ${YELLOW}%s${NC} (layout: %s)\n" "$HI_DIR" "$ORGANIZE"
if [[ $MARK_ALL_DOWNLOADED -eq 1 ]]; then
    printf "Mode:        ${YELLOW}record everything in the list as downloaded (nothing is downloaded)${NC}\n"
    DOWNLOAD=0   # no cookie needed
elif [[ $DOWNLOAD -eq 1 ]]; then
    printf "Mode:        ${YELLOW}download missing files${NC} (%ss between files)\n" "$DELAY_SECONDS"
else
    printf "Mode:        ${YELLOW}check only${NC}\n"
fi
(( SKIP_DOWNLOADED )) && printf "Recorded files are skipped even if they're no longer in the folder.\n"
echo ""

[[ -f "$LIST_FILE" ]] || { echo -e "${RED}List file not found: $LIST_FILE${NC}"; exit 1; }
mkdir -p "$HI_DIR" 2>/dev/null; [[ -w "$HI_DIR" ]] || { echo -e "${RED}No write permission for $HI_DIR${NC}"; exit 1; }
command -v curl &>/dev/null || { echo -e "${RED}curl is not installed.${NC}"; exit 1; }

if [[ $DOWNLOAD -eq 1 ]]; then
    [[ -z "$COOKIE" && -n "$HI_COOKIE" ]] && COOKIE="$HI_COOKIE"
    [[ -z "$COOKIE" && -f "$script_dir/$COOKIE_FILE" ]] && COOKIE="$(tr -d '\r\n' < "$script_dir/$COOKIE_FILE")"
    [[ -z "$USER_AGENT" && -n "$HI_USER_AGENT" ]] && USER_AGENT="$HI_USER_AGENT"
    [[ -z "$USER_AGENT" && -f "$script_dir/$USER_AGENT_FILE" ]] && USER_AGENT="$(tr -d '\r\n' < "$script_dir/$USER_AGENT_FILE")"
    USER_AGENT="${USER_AGENT#\"}"; USER_AGENT="${USER_AGENT%\"}"
    [[ -z "$COOKIE" ]] && { echo -e "${RED}No cookie set ($COOKIE_FILE next to the script, COOKIE, or HI_COOKIE).${NC}"; exit 1; }
    [[ -z "$USER_AGENT" ]] && { echo -e "${RED}No user agent set ($USER_AGENT_FILE next to the script, USER_AGENT, or HI_USER_AGENT).${NC}"; exit 1; }
    if [[ $VERIFY -eq 1 ]] && ! command -v unzip &>/dev/null; then
        echo -e "${YELLOW}Note: unzip not installed - .zip files won't be tested (sudo apt install unzip).${NC}"
    fi
fi

# ---------- helpers ----------
# Safe single folder/file name (also valid when the folder is used from Windows)
safe_name() {
    local s="$1"
    s="$(printf '%s' "$s" | tr -d '\000-\037' | sed 's#[<>:"/\\|?*]#_#g')"
    s="${s#"${s%%[![:space:].]*}"}"
    s="${s%"${s##*[![:space:].]}"}"
    printf '%s' "$s"
}

# Check a finished archive. 0 = OK, 1 = broken, 2 = not checked
verify_archive() {
    local f="$1" magic
    magic=$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')
    case "${f,,}" in
        *.png) [[ "$magic" == 89504e47* ]] || { LAST_ERROR="not a PNG image"; return 1; } ;;
        *.jpg|*.jpeg) [[ "$magic" == ffd8ff* ]] || { LAST_ERROR="not a JPEG image"; return 1; } ;;
        *.gif) [[ "$magic" == 47494638* ]] || { LAST_ERROR="not a GIF image"; return 1; } ;;
        *.webp) [[ "$magic" == 52494646* ]] || { LAST_ERROR="not a WebP image"; return 1; } ;;
        *.zip)
            [[ "$magic" == 504b0304* || "$magic" == 504b0506* ]] || { LAST_ERROR="not a zip file (got: $(head -c 60 "$f" | tr -cd '[:print:]'))"; return 1; }
            command -v unzip &>/dev/null || return 2
            # unzip exit codes: 0 = OK, 1 = warnings only (e.g. a file name stored in two different
            # encodings, like "Shee’Far" - the data is fine, Windows doesn't mind), 2+ = real errors
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

# Ask heroesinfinite.com where a download lives (without following the redirect).
# Sets FILE_URL and FILE_NAME. 0 = OK, 1 = failed, 2 = login problem (stop), 3 = bot check (stop)
resolve_link() {
    local url="$1" hdr result rc code loc retry_after wait attempt=0
    while :; do
        hdr=$(mktemp)
        result=$(curl --silent --show-error --connect-timeout 30 --max-time 60 \
            -H "User-Agent: $USER_AGENT" -H "Cookie: $COOKIE" -H "Referer: ${BASE_URL}/library" \
            -D "$hdr" -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)
        rc=$?; code="$result"
        loc=$(grep -i '^location:' "$hdr" | tail -1 | sed 's/^[Ll]ocation:[[:space:]]*//' | tr -d '\r')
        retry_after=$(grep -i '^retry-after:' "$hdr" | tail -1 | tr -dc '0-9')
        local cf; cf=$(grep -i '^cf-mitigated:' "$hdr")
        rm -f "$hdr"

        if [[ -n "$cf" ]]; then LAST_ERROR="blocked by Cloudflare bot check"; return 3; fi
        if [[ "$code" == 30? && -n "$loc" ]]; then
            [[ "$loc" == /* ]] && loc="${BASE_URL}${loc}"
            if [[ "$loc" == */login* || "$loc" == */sign_in* ]]; then
                LAST_ERROR="redirected to the login page (cookie expired or not from heroesinfinite.com)"; return 2
            fi
            FILE_URL="$loc"
            # Filename from the file link: strip the query and Kajabi's id prefix ("<uuid>_")
            local base="${loc%%\?*}"; base="${base##*/}"
            base="$(printf '%b' "${base//'%'/'\x'}")"   # quoted: bash 5.2 treats \ in the replacement differently
            FILE_NAME="$(printf '%s' "$base" | sed -E 's/^[0-9a-fA-F]{6,}(-[0-9a-fA-F]{2,})+_//')"
            return 0
        fi
        if [[ "$code" == "401" || "$code" == "403" ]]; then LAST_ERROR="HTTP $code (no access?)"; return 1; fi
        if [[ "$code" == "404" || "$code" == "410" ]]; then LAST_ERROR="HTTP $code (download removed from the site)"; return 1; fi
        if [[ "$code" == "429" || "$code" == 5?? || "$code" == "000" || -z "$code" ]] && (( attempt < MAX_RETRIES )); then
            attempt=$((attempt + 1))
            wait=${retry_after:-$(( BACKOFF_SECONDS * (1 << (attempt - 1)) ))}; (( wait > 900 )) && wait=900
            printf "    ${YELLOW}HTTP %s - waiting %ss before retry %s/%s${NC}\n" "${code:-none}" "$wait" "$attempt" "$MAX_RETRIES"
            sleep "$wait"; continue
        fi
        LAST_ERROR="unexpected answer: curl exit $rc, HTTP ${code:-none}"
        return 1
    done
}

# Download FILE_URL (no cookie) to DEST via DEST.part. Sets CD_NAME from Content-Disposition.
# 0 = OK, 1 = failed
fetch_file() {
    local url="$1" dest="$2" tmp="${2}.part" hdr errf result rc code ctype attempt=0 wait
    CD_NAME=""
    mkdir -p "$(dirname "$dest")" || { LAST_ERROR="cannot create folder"; return 1; }
    while :; do
        hdr=$(mktemp); errf=$(mktemp)
        result=$(curl --silent --show-error --location --connect-timeout 30 \
            --speed-limit 1024 --speed-time "$STALL_SECONDS" \
            -H "User-Agent: $USER_AGENT" \
            -D "$hdr" -o "$tmp" -w '%{http_code} %{content_type}' "$url" 2>"$errf")
        rc=$?; code="${result%% *}"; ctype="${result#* }"; [[ "$ctype" == "$result" ]] && ctype=""
        CD_NAME=$(grep -i '^content-disposition:' "$hdr" | tail -1 | tr -d '\r' |
            sed -nE "s/.*filename\*=(UTF-8|utf-8)''([^;]+).*/\2/p; t; s/.*filename=\"?([^\";]+)\"?.*/\1/p")
        [[ "$CD_NAME" == *%* ]] && CD_NAME="$(printf '%b' "${CD_NAME//'%'/'\x'}")"
        LAST_ERROR="curl exit $rc, HTTP ${code:-none}$( [[ -s "$errf" ]] && printf ', %s' "$(head -c 150 "$errf" | tr '\n' ' ')")"
        rm -f "$hdr" "$errf"

        if (( rc == 0 )) && [[ "$code" == "200" && -s "$tmp" && "$ctype" != text/html* ]]; then
            mv -f "$tmp" "$dest" && return 0
            LAST_ERROR="could not move finished download into place"; rm -f "$tmp"; return 1
        fi
        rm -f "$tmp"
        # The S3 link may have expired during waits; the caller gets a fresh one on retry
        if [[ "$code" == "403" ]]; then LAST_ERROR="file link refused (HTTP 403)"; return 1; fi
        if [[ "$code" == "429" || "$code" == 5?? || "$code" == "000" || -z "$code" || $rc -eq 28 ]] && (( attempt < MAX_RETRIES )); then
            attempt=$((attempt + 1))
            wait=$(( BACKOFF_SECONDS * (1 << (attempt - 1)) )); (( wait > 900 )) && wait=900
            printf "    ${YELLOW}%s - waiting %ss before retry %s/%s${NC}\n" "$LAST_ERROR" "$wait" "$attempt" "$MAX_RETRIES"
            sleep "$wait"; continue
        fi
        return 1
    done
}

# ---------- read the ledger (download id -> file path, relative to HI_DIR) ----------
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
NOT_DOWNLOADED_MARK="(recorded with MARK_ALL_DOWNLOADED)"

# ---------- read the list ----------
mapfile -t lines < <(sed $'1s/^\xEF\xBB\xBF//; s/\r$//' "$LIST_FILE")
(( ${#lines[@]} > 1 )) || { echo -e "${RED}The list is empty.${NC}"; exit 1; }
# Split on tabs via \x1f: with a tab in IFS, empty columns would be merged and the rest would shift
IFS=$'\x1f' read -r -a header <<< "${lines[0]//$'\t'/$'\x1f'}"
declare -A col=()
for i in "${!header[@]}"; do col["${header[$i],,}"]=$i; done
for c in collection id url; do
    [[ -n "${col[$c]}" ]] || { echo -e "${RED}The list has no '$c' column. Export it with 2_hi_export_list.js.${NC}"; exit 1; }
done

printf '%s\n' "${lines[0]}" > "$MISSING_OUT"
: > "$FAILED_OUT"

total=0; present=0; downloaded=0; failed=0; unchecked=0; marked=0; attempts=0; first_request=1; stopped=""; filtered=0
declare -A seen=()

for (( n = 1; n < ${#lines[@]}; n++ )); do
    line="${lines[$n]}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    IFS=$'\x1f' read -r -a f <<< "${line//$'\t'/$'\x1f'}"
    collection="${f[${col[collection]}]}"
    post="${f[${col[post]:-99}]}"
    label="${f[${col[label]:-99}]}"
    id="${f[${col[id]}]}"
    url="${f[${col[url]}]}"
    kind="${f[${col[kind]:-99}]}"; [[ -z "$kind" ]] && kind="file"   # file / image / cover (older lists: file)
    [[ -z "$id" || ! "$url" =~ ^https?:// || -n "${seen[$id]}" ]] && continue
    seen[$id]=1
    if [[ "$kind" != "file" ]] && (( ! IMAGES )); then ((filtered++)); continue; fi
    ((total++))

    cdir="$(safe_name "$collection")"; [[ -z "$cdir" ]] && cdir="Unknown collection"
    pdir="$(safe_name "$post")"; [[ -z "$pdir" ]] && pdir="Post"
    if [[ "$ORGANIZE" == "collection" ]]; then reldir="$cdir"; else reldir="$cdir/$pdir"; fi
    what="$collection - ${post:+$post - }${label:-$id}"
    # Pictures: covers next to the collection's posts, post pictures in an Images subfolder
    if [[ "$kind" == "cover" ]]; then reldir="$cdir"; what="$collection - cover picture"; fi
    if [[ "$kind" == "image" ]]; then reldir="$reldir/Images"; what="$collection - ${post:+$post - }picture ${f[${col[name]:-99}]}"; fi

    # Already downloaded before? (the file may have been extracted and deleted since)
    if [[ -n "${ledger[$id]}" ]] && { (( SKIP_DOWNLOADED )) || [[ -s "$HI_DIR/${ledger[$id]}" ]]; }; then
        ((present++)); printf "  ${GREEN}✓${NC} %s\n" "$what"; continue
    fi
    if [[ $MARK_ALL_DOWNLOADED -eq 1 ]]; then
        record "$id" "$NOT_DOWNLOADED_MARK"
        ((marked++)); printf "  ${GREEN}✓ recorded${NC} %s\n" "$what"; continue
    fi

    if [[ $DOWNLOAD -ne 1 || -n "$stopped" ]]; then
        printf "  ${RED}✗ MISSING${NC} %s\n" "$what"; printf '%s\n' "$line" >> "$MISSING_OUT"; continue
    fi
    if (( MAX_DOWNLOADS > 0 && attempts >= MAX_DOWNLOADS )); then
        stopped="reached MAX_DOWNLOADS ($MAX_DOWNLOADS) for this run"
        printf "  ${YELLOW}Download limit reached - remaining files are only listed.${NC}\n"
        printf "  ${RED}✗ MISSING${NC} %s\n" "$what"; printf '%s\n' "$line" >> "$MISSING_OUT"; continue
    fi

    if (( ! first_request )); then
        if [[ "$kind" == "file" ]]; then sleep "$DELAY_SECONDS"; else sleep "$IMAGE_DELAY_SECONDS"; fi
    fi
    first_request=0
    if [[ "$kind" == "file" ]]; then
        # Ask where the file is (also tells us its name)
        resolve_link "$url"; r=$?
    else
        # Pictures are public files on Kajabi's image server: no cookie, name from the list
        FILE_URL="$url"; FILE_NAME="${f[${col[name]:-99}]}"; r=0
    fi
    if (( r != 0 )); then
        ((failed++))
        printf "  ${RED}✗ %s:${NC} %s\n" "$what" "$LAST_ERROR"
        printf '%s\t%s\t%s\n' "$what" "$LAST_ERROR" "$url" >> "$FAILED_OUT"
        printf '%s\n' "$line" >> "$MISSING_OUT"
        if (( r >= 2 )); then
            stopped="$LAST_ERROR - save a fresh cookie.txt from heroesinfinite.com and rerun"
            printf "  ${RED}Stopping downloads: %s${NC}\n" "$stopped"
        fi
        continue
    fi

    name="$(safe_name "$FILE_NAME")"; [[ -z "$name" ]] && name="$(safe_name "${f[${col[name]:-99}]:-download_$id}")"
    relpath="$reldir/$name"
    # Same name already used by a different download in this folder? Keep both.
    if [[ -n "${path_owner[$relpath]}" && "${path_owner[$relpath]}" != "$id" ]]; then
        relpath="$reldir/${name%.*}_$id${name##"${name%.*}"}"
    fi

    # Already there (downloaded earlier or by hand)?
    if [[ -s "$HI_DIR/$relpath" ]]; then
        record "$id" "$relpath"
        ((present++)); printf "  ${GREEN}✓${NC} %s (%s, already there)\n" "$what" "$name"; continue
    fi

    ((attempts++))
    printf "  ${BLUE}↓ Downloading${NC} %s -> %s ...\n" "$what" "$relpath"
    start=$(date +%s)
    ok=0
    for try in 1 2; do
        if fetch_file "$FILE_URL" "$HI_DIR/$relpath"; then ok=1; break; fi
        # A refused file link usually means it expired while waiting: get a fresh one once
        [[ "$kind" == "file" && $try -eq 1 && "$LAST_ERROR" == *"HTTP 403"* ]] || break
        sleep "$DELAY_SECONDS"; resolve_link "$url" || break
    done

    if (( ok )); then
        # Prefer the server's own filename if it differs
        if [[ "$kind" == "file" && -n "$CD_NAME" ]]; then
            cd_safe="$(safe_name "$CD_NAME")"
            if [[ -n "$cd_safe" && "$cd_safe" != "$name" && ! -e "$HI_DIR/$reldir/$cd_safe" ]]; then
                mv -f "$HI_DIR/$relpath" "$HI_DIR/$reldir/$cd_safe" && relpath="$reldir/$cd_safe"
            fi
        fi
        if [[ $VERIFY -eq 1 ]]; then
            verify_archive "$HI_DIR/$relpath"; v=$?
            if (( v == 1 )); then
                ((failed++))
                printf "  ${RED}✗ Downloaded file is damaged:${NC} %s\n" "$LAST_ERROR"
                printf '%s\t%s\t%s\n' "$what" "$LAST_ERROR" "$url" >> "$FAILED_OUT"
                rm -f "$HI_DIR/$relpath"; printf '%s\n' "$line" >> "$MISSING_OUT"
                continue
            fi
            (( v == 2 )) && ((unchecked++))
        fi
        record "$id" "$relpath"
        ((downloaded++))
        printf "  ${GREEN}✓ DOWNLOADED${NC} %s (%s in %ss)\n" "$relpath" "$(du -h "$HI_DIR/$relpath" | cut -f1)" "$(( $(date +%s) - start ))"
    else
        ((failed++))
        printf "  ${RED}✗ Download failed:${NC} %s\n" "$LAST_ERROR"
        printf '%s\t%s\t%s\n' "$what" "$LAST_ERROR" "$url" >> "$FAILED_OUT"
        printf '%s\n' "$line" >> "$MISSING_OUT"
    fi
done

missing=$((total - present - downloaded - marked))
echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e " Downloads in list:      ${BLUE}${total}${NC}$( (( filtered )) && echo "  (+$filtered pictures skipped: IMAGES=0)")"
echo -e " Already downloaded:     ${GREEN}${present}${NC}"
(( marked )) && echo -e " Recorded as downloaded: ${GREEN}${marked}${NC} (MARK_ALL_DOWNLOADED - nothing was downloaded)"
echo -e " Downloaded this run:    ${GREEN}${downloaded}${NC}"
echo -e " Failed:                 ${RED}${failed}${NC}"
echo -e " Still missing:          ${RED}${missing}${NC}"
echo -e "${YELLOW}================================================${NC}"
[[ -n "$stopped" ]] && echo -e "${YELLOW}Downloads stopped early: ${stopped}${NC}"
(( unchecked > 0 )) && echo -e "${YELLOW}$unchecked file(s) were not tested (not an archive, or unzip/unrar/7z missing).${NC}"
(( missing > 0 )) && echo -e "Still-missing downloads saved to: ${YELLOW}${MISSING_OUT}${NC}"
(( failed > 0 )) && echo -e "Failure reasons saved to:         ${YELLOW}${FAILED_OUT}${NC}"
(( missing == 0 && failed == 0 )) && echo -e "${GREEN}Everything in the list is downloaded.${NC}"
if (( MARK_ALL_DOWNLOADED )); then echo -e "${YELLOW}Set MARK_ALL_DOWNLOADED back to 0 before the next run.${NC}"; fi
