#!/bin/bash
# ================================================================
# MakerWorld downloader (Linux, curl) - OPTIONAL: use browser/1_mw_download.js instead.
#
# MakerWorld's Cloudflare bot check refuses Linux curl on the personal requests (your lists),
# with or without a cookie (seen 2026-10-05; plain Windows curl was accepted). If that happens
# ("blocked by Cloudflare's bot check"), use the browser script. Both use the same layout and
# the same record file (.mw_downloaded.tsv), so you can switch between them.
#
# Reads your collections, your download history and your liked models on makerworld.com
# (with your login cookie) and downloads every model into
#   MW_DIR/<collection>/<creator>/<model>/
#       files/              the model files (MakerWorld's "download all" zip, extracted)
#       profiles/           the print profiles (.3mf)
#       images/             the model's pictures
#       description.html    description, licence, creator and link
# Models only in your download history go to "Downloads", liked ones to "Likes". A model that
# is in several collections is stored once: in the first of your own collections, then the
# "Default Collection", then Downloads, then Likes.
#
# MakerWorld hands out download links only to logged-in users, and they expire after 5
# minutes, so this script asks for each link right before downloading it. Your cookie is only
# sent to makerworld.com, never to the file server. Every request to download counts as a
# download on MakerWorld, like clicking Download on the site.
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;94m'
NC='\033[0m'

# ==============================
# SETTINGS
# ==============================
# Where the models are stored. Empty = the folder this script is in.
# To use another folder, put its full path here, e.g. "/mnt/nas/3DPrints/MakerWorld".
MW_DIR=""

SOURCES="collections downloads likes"   # what to download: your collections, your download
                                        # history, your liked models (remove what you don't want)
COLLECTIONS=""        # only these collections, e.g. "Pokemon|D&D" (names separated by |); empty = all
PROFILES="creator"    # print profiles: "creator" = the model creator's own, "all" = also the ones
                      # other users made (popular models can have dozens), "none"
IMAGES=1              # 1 = the model's pictures
DESCRIPTION=1         # 1 = description.html
EXTRACT=1             # 1 = extract the model zip into files/ (and delete the zip); 0 = keep the zip
# Folder structure - available options:
#   "COLLECTION/CREATOR/MODEL"  -> Pokemon/Ghosty/Gengar Puzzle Box/   (default)
#   "COLLECTION/MODEL"          -> Pokemon/Gengar Puzzle Box/
#   "CREATOR/MODEL"             -> Ghosty/Gengar Puzzle Box/
#   "MODEL"                     -> Gengar Puzzle Box/
# (COLLECTION = the collection, or Downloads / Likes for models in no collection.) Use the same as in
# the browser script. A model's folder is recorded when it's first downloaded, so a change only
# applies to models downloaded after it.
FOLDER_STRUCTURE="COLLECTION/CREATOR/MODEL"

# Cookie and user agent: leave empty to use cookie.txt / user_agent.txt next to this script
# (from makerworld.com), or set the MW_COOKIE / MW_USER_AGENT environment variables.
# Never share the cookie.
COOKIE=''
COOKIE_FILE="cookie.txt"
USER_AGENT=''
USER_AGENT_FILE="user_agent.txt"

# Every finished part is recorded in MW_DIR/.mw_downloaded.tsv (keep that file!).
SKIP_DOWNLOADED=1     # 1 = skip what's recorded as downloaded, even if you've deleted it since
RECHECK=0             # 1 = read every model again (finds print profiles added since; costs one
                      #     request per model), 0 = skip models downloaded completely before
DOWNLOAD=1            # 1 = download, 0 = only list what's missing
DELAY_SECONDS=5       # pause before each download link request to MakerWorld
API_DELAY_SECONDS=1   # pause before other requests (lists, model details)
IMAGE_DELAY_SECONDS=1 # pause between pictures
MAX_MODELS=0          # stop after this many models with something to download (0 = no limit)
MAX_RETRIES=4         # retries for rate limits, server errors and network errors
BACKOFF_SECONDS=30    # first retry wait; doubles each retry unless the server says otherwise
STALL_SECONDS=120     # abort a download that receives almost nothing for this long
REFUSAL_LIMIT=3       # stop after this many refused download links in a row
API="https://makerworld.com/api/v1"
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "$MW_DIR" ]] && MW_DIR="$script_dir"
[[ "$MW_DIR" != /* ]] && MW_DIR="$script_dir/$MW_DIR"
MW_DIR="${MW_DIR%/}"
FOLDER_STRUCTURE="${FOLDER_STRUCTURE^^}"; FOLDER_STRUCTURE="${FOLDER_STRUCTURE//\\//}"
case "$FOLDER_STRUCTURE" in
    COLLECTION/CREATOR/MODEL|COLLECTION/MODEL|CREATOR/MODEL|MODEL) ;;
    *) echo -e "${RED}Unknown FOLDER_STRUCTURE \"$FOLDER_STRUCTURE\" - use COLLECTION/CREATOR/MODEL, COLLECTION/MODEL, CREATOR/MODEL or MODEL.${NC}"; exit 1 ;;
esac
LEDGER="$MW_DIR/.mw_downloaded.tsv"     # key <TAB> value <TAB> date
FAILED_OUT="mw_failed.txt"
MISSING_OUT="mw_missing.txt"

echo -e "${BLUE}MakerWorld downloader${NC}"
printf "Destination: ${YELLOW}%s${NC}\n" "$MW_DIR"
printf "Sources:     ${YELLOW}%s${NC}%s\n" "$SOURCES" "${COLLECTIONS:+ (collections: $COLLECTIONS)}"
(( DOWNLOAD )) || printf "Mode:        ${YELLOW}check only${NC}\n"
echo ""
for t in curl jq; do command -v $t &>/dev/null || { echo -e "${RED}$t is not installed (sudo apt install curl jq unzip).${NC}"; exit 1; }; done
(( EXTRACT )) && ! command -v unzip &>/dev/null && { echo -e "${RED}unzip is not installed (sudo apt install unzip), or set EXTRACT=0.${NC}"; exit 1; }
mkdir -p "$MW_DIR" 2>/dev/null; [[ -w "$MW_DIR" ]] || { echo -e "${RED}No write permission for $MW_DIR${NC}"; exit 1; }

[[ -z "$COOKIE" && -n "$MW_COOKIE" ]] && COOKIE="$MW_COOKIE"
[[ -z "$COOKIE" && -f "$script_dir/$COOKIE_FILE" ]] && COOKIE="$(tr -d '\r\n' < "$script_dir/$COOKIE_FILE")"
[[ -z "$USER_AGENT" && -n "$MW_USER_AGENT" ]] && USER_AGENT="$MW_USER_AGENT"
[[ -z "$USER_AGENT" && -f "$script_dir/$USER_AGENT_FILE" ]] && USER_AGENT="$(tr -d '\r\n' < "$script_dir/$USER_AGENT_FILE")"
COOKIE="${COOKIE#\"}"; COOKIE="${COOKIE%\"}"; USER_AGENT="${USER_AGENT#\"}"; USER_AGENT="${USER_AGENT%\"}"
[[ -z "$COOKIE" ]] && { echo -e "${RED}No cookie set ($COOKIE_FILE next to the script, COOKIE, or MW_COOKIE).${NC}"; exit 1; }
# Leave out Cloudflare's own cookies (cf_clearance, __cf_bm, _cfuvid, __cflb): they belong to the
# browser they were issued to (its connection fingerprint), and sent by curl they make Cloudflare
# challenge the request. MakerWorld's login cookies are separate and are kept.
cf_dropped=""
kept_cookie=""
IFS=';' read -r -a cookie_parts <<< "$COOKIE"
for cp in "${cookie_parts[@]}"; do
    cp="${cp#"${cp%%[![:space:]]*}"}"; [[ -n "$cp" ]] || continue
    case "${cp%%=*}" in
        cf_clearance|__cf_bm|_cfuvid|__cflb|cf_chl_*) cf_dropped+="${cp%%=*} " ;;
        *) kept_cookie+="${kept_cookie:+; }$cp" ;;
    esac
done
COOKIE="$kept_cookie"
[[ -n "$cf_dropped" ]] && printf "Cookie:      Cloudflare's own cookies are not sent (%s)\n" "${cf_dropped% }"
[[ -z "$USER_AGENT" ]] && USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

# ---------- helpers ----------
safe_name() {   # usable as a file/folder name on Linux and Windows shares
    local s="$1"
    s="$(printf '%s' "$s" | tr -d '\000-\037' | sed 's#[<>:"/\\|?*]#_#g')"
    s="${s#"${s%%[![:space:].]*}"}"
    s="${s%"${s##*[![:space:].]}"}"
    (( ${#s} > 100 )) && s="${s:0:100}" && s="${s%"${s##*[![:space:].]}"}"
    printf '%s' "$s"
}

# api_get PATH - GET $API$PATH with your cookie (makerworld.com only). The answer is in $BODY.
# 0 = OK, 1 = failed (LAST_ERROR), 2 = not logged in (stop), 3 = bot check (stop)
BODY="$(mktemp)"; HDR="$(mktemp)"; trap 'rm -f "$BODY" "$HDR"' EXIT
api_get() {
    local url="$API$1" code rc attempt=0 wait ra msg
    while :; do
        code=$(curl --silent --show-error --compressed --connect-timeout 30 --max-time 120 \
            -H "User-Agent: $USER_AGENT" -H "Accept: application/json" -H "Cookie: $COOKIE" \
            -H "Referer: https://makerworld.com/" -D "$HDR" -o "$BODY" -w '%{http_code}' "$url" 2>/dev/null); rc=$?
        msg="$(jq -r '.error // .message // empty' "$BODY" 2>/dev/null | head -c 150)"
        LAST_ERROR="HTTP ${code:-none}${msg:+: $msg}"
        if grep -qi '^cf-mitigated:' "$HDR"; then LAST_ERROR="blocked by Cloudflare's bot check (HTTP $code)"; return 3; fi
        if (( rc == 0 )) && [[ "$code" == 200 ]]; then return 0; fi
        if [[ "$code" == 401 ]] || { [[ "$code" == 403 ]] && [[ "$msg" == *"log in"* || "$msg" == *"login"* ]]; }; then return 2; fi
        if [[ "$code" == 429 || "$code" == 5?? || "$code" == 000 || -z "$code" ]] && (( attempt < MAX_RETRIES )); then
            attempt=$((attempt + 1))
            ra=$(grep -i '^retry-after:' "$HDR" | tail -1 | tr -dc '0-9')
            if [[ -n "$ra" ]]; then wait=$ra; else wait=$(( BACKOFF_SECONDS * (1 << (attempt - 1)) )); fi
            (( wait > 900 )) && wait=900
            printf "    ${YELLOW}%s - waiting %ss before retry %s/%s${NC}\n" "$LAST_ERROR" "$wait" "$attempt" "$MAX_RETRIES"
            sleep "$wait"; continue
        fi
        return 1
    done
}

# fetch_file URL DEST - download a signed file link (NO cookie) via DEST.part. 0 = OK, 1 = failed
fetch_file() {
    local url="$1" dest="$2" tmp="${2}.part" result rc code ctype attempt=0 wait
    mkdir -p "$(dirname "$dest")" || { LAST_ERROR="cannot create folder"; return 1; }
    while :; do
        result=$(curl --silent --show-error --location --connect-timeout 30 \
            --speed-limit 1024 --speed-time "$STALL_SECONDS" -H "User-Agent: $USER_AGENT" \
            -o "$tmp" -w '%{http_code} %{content_type}' "$url" 2>/dev/null); rc=$?
        code="${result%% *}"; ctype="${result#* }"
        LAST_ERROR="curl exit $rc, HTTP ${code:-none}"
        if (( rc == 0 )) && [[ "$code" == 200 && -s "$tmp" && "$ctype" != text/html* ]]; then
            mv -f "$tmp" "$dest" && return 0
            LAST_ERROR="could not move the finished download into place"; rm -f "$tmp"; return 1
        fi
        rm -f "$tmp"
        if [[ "$code" == 429 || "$code" == 5?? || "$code" == 000 || -z "$code" || $rc -eq 28 ]] && (( attempt < MAX_RETRIES )); then
            attempt=$((attempt + 1)); wait=$(( BACKOFF_SECONDS * (1 << (attempt - 1)) )); (( wait > 900 )) && wait=900
            printf "    ${YELLOW}%s - waiting %ss before retry %s/%s${NC}\n" "$LAST_ERROR" "$wait" "$attempt" "$MAX_RETRIES"
            sleep "$wait"; continue
        fi
        return 1
    done
}

# flatten DIR - while DIR holds nothing but one folder, move that folder's contents up
flatten() {
    local d="$1" items hold
    shopt -s dotglob nullglob
    while :; do
        items=("$d"/*)
        (( ${#items[@]} == 1 )) && [[ -d "${items[0]}" ]] || break
        hold="$d/.flatten_$$"
        mv -- "${items[0]}" "$hold" || break
        items=("$hold"/*)
        (( ${#items[@]} )) && mv -- "${items[@]}" "$d"/
        rmdir -- "$hold" 2>/dev/null
    done
    shopt -u dotglob nullglob
}
# merge SRC DEST - move SRC's contents into DEST without overwriting
merge() {
    local src="$1" dst="$2" e b
    shopt -s dotglob nullglob
    mkdir -p -- "$dst"
    for e in "$src"/*; do
        b="${e##*/}"
        if [[ ! -e "$dst/$b" ]]; then mv -- "$e" "$dst/$b"
        elif [[ -d "$e" && -d "$dst/$b" ]]; then merge "$e" "$dst/$b"; fi
    done
    shopt -u dotglob nullglob
}

# is_zip FILE - 0 if FILE starts like a zip (also .3mf files are zips)
is_zip() { [[ "$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')" == 504b0304* ]]; }
is_image() { case "$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')" in 89504e47*|ffd8ff*|52494646*|47494638*) return 0 ;; esac; return 1; }

# ---------- the record of finished parts ----------
declare -A ledger=() dir_owner=()
if [[ -f "$LEDGER" ]]; then
    while IFS=$'\t' read -r lk lv _; do
        [[ -n "$lk" ]] || continue
        ledger[$lk]="$lv"
        [[ "$lk" == dir:* ]] && dir_owner[$lv]="${lk#dir:}"
    done < <(tr -d '\r' < "$LEDGER")
fi
record() { [[ "${ledger[$1]}" == "$2" ]] && return; ledger[$1]="$2"; printf '%s\t%s\t%s\n' "$1" "$2" "$(date '+%Y-%m-%d %H:%M')" >> "$LEDGER"; }
done_part() { [[ -n "${ledger[$1]}" ]]; }

stop_for() {   # stop_for RC - stop everything on a login problem or bot check
    case "$1" in
        2) echo -e "${RED}MakerWorld says you're not logged in: save a fresh cookie.txt from makerworld.com and run again.${NC}"; exit 1 ;;
        3) echo -e "${RED}${LAST_ERROR}: make sure user_agent.txt matches the browser the cookie came from. Stopping.${NC}"; exit 1 ;;
    esac
}

# ---------- which models: id -> folder of its source, title, creator ----------
declare -A src=() title=() creator=()
order=()
add_models() {   # add_models SOURCE_NAME  (reads "id<US>title<US>creator" lines from stdin; \x1f, not a
                 # tab: with a tab in IFS an empty title would be merged away and the rest would shift)
    local s="$1" id t c
    while IFS=$'\x1f' read -r id t c; do
        [[ "$id" =~ ^[0-9]+$ ]] || continue
        [[ -n "${src[$id]}" ]] && continue
        src[$id]="$s"; title[$id]="$t"; creator[$id]="$c"; order+=("$id")
    done
}
JQ_ITEMS='.[] | [(.id|tostring), (.title // ""), (.designCreator.name // .creator.name // "")] | map(gsub("[\t\n\r]"; " ")) | join("\u001f")'
JQ_JOIN='map(tostring | gsub("[\t\n\r]"; " ")) | join("\u001f")'   # fields joined by \x1f (see add_models)

if [[ " $SOURCES " == *" collections "* ]]; then
    echo "Reading your collections ..."
    api_get "/design-service/my/favorites/listlite?offset=0&limit=100"; rc=$?; stop_for $rc
    if (( rc != 0 )); then echo -e "${RED}Could not read your collections: $LAST_ERROR${NC}"; exit 1; fi
    # your own collections first, the Default Collection last
    mapfile -t cols < <(jq -r ".hits | sort_by(.isDefault == true) | .[] | [(.id|tostring), (.title // \"\"), (.designCnt|tostring)] | $JQ_JOIN" "$BODY")
    for cl in "${cols[@]}"; do
        IFS=$'\x1f' read -r cid ctitle ccount <<< "$cl"
        if [[ -n "$COLLECTIONS" && "|${COLLECTIONS,,}|" != *"|${ctitle,,}|"* ]]; then continue; fi
        sleep "$API_DELAY_SECONDS"
        api_get "/design-service/favorites/$cid"; rc=$?; stop_for $rc
        if (( rc != 0 )); then echo -e "  ${YELLOW}$ctitle: could not read it ($LAST_ERROR)${NC}"; continue; fi
        before=${#order[@]}
        add_models "$ctitle" < <(jq -r ".designs // [] | $JQ_ITEMS" "$BODY")
        printf "  %s: %s models (%s new)\n" "$ctitle" "$(jq '.designs // [] | length' "$BODY")" "$(( ${#order[@]} - before ))"
    done
fi
read_pages() {   # read_pages PATH_WITHOUT_PAGING SOURCE_NAME LABEL
    local path="$1" s="$2" label="$3" off=0 total=1 n sep before=${#order[@]}
    while (( off < total )); do
        sleep "$API_DELAY_SECONDS"
        sep="?"; [[ "$path" == *\?* ]] && sep="&"
        api_get "$path${sep}offset=$off&limit=20"; rc=$?; stop_for $rc
        if (( rc != 0 )); then echo -e "  ${YELLOW}$label: could not read it ($LAST_ERROR)${NC}"; return; fi
        total=$(jq -r '.total // 0' "$BODY"); n=$(jq '.hits // [] | length' "$BODY")
        add_models "$s" < <(jq -r ".hits // [] | $JQ_ITEMS" "$BODY")
        (( n == 0 )) && break
        off=$((off + n))
    done
    printf "  %s: %s models (%s new)\n" "$label" "$total" "$(( ${#order[@]} - before ))"
}
[[ " $SOURCES " == *" downloads "* ]] && { echo "Reading your download history ..."; read_pages "/design-service/my/favorites/download/designs" "Downloads" "Download history"; }
[[ " $SOURCES " == *" likes "* ]] && { echo "Reading your liked models ..."; read_pages "/design-service/my/design/like" "Likes" "Liked models"; }
echo ""
echo -e "${BLUE}${#order[@]} models${NC}"
echo ""

: > "$FAILED_OUT"; : > "$MISSING_OUT"
models=0; worked=0; files_ok=0; profiles_ok=0; pics_ok=0; failed=0; refused=0; stopped=""
fail() { ((failed++)); printf "    ${RED}✗ %s: %s${NC}\n" "$1" "$LAST_ERROR"; printf '%s\t%s\t%s\n' "$2" "$1" "$LAST_ERROR" >> "$FAILED_OUT"; }

# link_request PATH - ask MakerWorld for a download link: sets LINK_URL and LINK_NAME.
# 0 = OK, 1 = refused (counts towards REFUSAL_LIMIT)
link_request() {
    sleep "$DELAY_SECONDS"
    api_get "$1"; local rc=$?; stop_for $rc
    if (( rc != 0 )); then
        refused=$((refused + 1))
        (( refused >= REFUSAL_LIMIT )) && stopped="$refused download links in a row were refused (last: $LAST_ERROR)"
        return 1
    fi
    LINK_URL="$(jq -r '.url // empty' "$BODY")"; LINK_NAME="$(jq -r '.name // empty' "$BODY")"
    [[ -n "$LINK_URL" ]] || { LAST_ERROR="no link in MakerWorld's answer"; return 1; }
    refused=0; return 0
}

n=0
for id in "${order[@]}"; do
    n=$((n + 1))
    [[ -n "$stopped" ]] && { printf '%s\t%s\n' "$id" "${title[$id]}" >> "$MISSING_OUT"; continue; }
    # the model's folder: decided once, then kept (recorded), even if its collections change
    rel="${ledger[dir:$id]}"
    if [[ -z "$rel" ]]; then
        c="$(safe_name "${creator[$id]}")"; t="$(safe_name "${title[$id]}")"
        rel=""
        IFS=/ read -r -a parts <<< "$FOLDER_STRUCTURE"
        for p in "${parts[@]}"; do
            case "$p" in
                COLLECTION) v="$(safe_name "${src[$id]}")" ;;
                CREATOR)    v="${c:-Unknown creator}" ;;
                MODEL)      v="${t:-Model $id}" ;;
            esac
            rel+="${rel:+/}$v"
        done
        [[ -n "${dir_owner[$rel]}" && "${dir_owner[$rel]}" != "$id" ]] && rel="$rel ($id)"
    fi
    dir="$MW_DIR/$rel"
    label="[$n/${#order[@]}] ${title[$id]}"

    # completely downloaded on an earlier run? (RECHECK=1 reads it again, e.g. for new print profiles)
    if (( SKIP_DOWNLOADED && ! RECHECK )) && done_part "complete:$id"; then
        printf "  ${GREEN}✓${NC} %s\n" "$label"; continue
    fi
    model_failed=$failed
    sleep "$API_DELAY_SECONDS"
    api_get "/design-service/design/$id"; rc=$?; stop_for $rc
    if (( rc != 0 )); then fail "$label - model details" "$id"; continue; fi
    cp "$BODY" "$BODY.model"
    owner_uid="$(jq -r '.designCreator.uid // empty' "$BODY.model")"
    nfiles="$(jq '.designExtension.model_files // [] | length' "$BODY.model")"
    case "$PROFILES" in
        all)     mapfile -t insts < <(jq -r ".instances // [] | .[] | [(.id|tostring), (.title // \"\")] | $JQ_JOIN" "$BODY.model") ;;
        creator) mapfile -t insts < <(jq -r --arg u "$owner_uid" ".instances // [] | .[] | select((.instanceCreator.uid|tostring) == \$u) | [(.id|tostring), (.title // \"\")] | $JQ_JOIN" "$BODY.model") ;;
        *)       insts=() ;;
    esac
    todo=0
    (( nfiles > 0 )) && ! done_part "files:$id" && todo=1
    for i in "${insts[@]}"; do done_part "inst:${i%%$'\x1f'*}" || todo=1; done
    (( IMAGES )) && ! done_part "pics:$id" && todo=1
    (( DESCRIPTION )) && ! done_part "desc:$id" && todo=1
    if (( ! todo )); then printf "  ${GREEN}✓${NC} %s\n" "$label"; record "complete:$id" "$rel"; rm -f "$BODY.model"; continue; fi
    if (( ! DOWNLOAD )); then printf "  ${RED}✗ MISSING${NC} %s\n" "$label"; printf '%s\t%s\n' "$id" "${title[$id]}" >> "$MISSING_OUT"; rm -f "$BODY.model"; continue; fi
    if (( MAX_MODELS > 0 && worked >= MAX_MODELS )); then
        stopped="reached MAX_MODELS ($MAX_MODELS)"; printf '%s\t%s\n' "$id" "${title[$id]}" >> "$MISSING_OUT"; rm -f "$BODY.model"; continue
    fi
    worked=$((worked + 1))
    printf "  ${BLUE}↓${NC} %s -> %s/\n" "$label" "$rel"
    mkdir -p "$dir" || { LAST_ERROR="cannot create the folder"; fail "$label" "$id"; continue; }
    record "dir:$id" "$rel"; dir_owner[$rel]="$id"

    # description
    if (( DESCRIPTION )) && ! done_part "desc:$id"; then
        jq -r --arg id "$id" '"<!doctype html><meta charset=\"utf-8\"><title>" + (.title|@html) + "</title>\n<h1>" + (.title|@html) + "</h1>\n<p>by " + ((.designCreator.name // "")|@html) + " - <a href=\"https://makerworld.com/en/models/" + $id + "-" + (.slug // "") + "\">makerworld.com/en/models/" + $id + "</a><br>Licence: " + ((.license // "")|@html) + "</p>\n" + (.summary // "")' "$BODY.model" > "$dir/description.html" \
            && record "desc:$id" "$rel/description.html"
    fi

    # model files ("download all" zip)
    if (( nfiles > 0 )) && ! done_part "files:$id"; then
        if link_request "/design-service/design/$id/model?modelType=all&type=download"; then
            zip="$dir/.model_$id.zip"
            if fetch_file "$LINK_URL" "$zip" && is_zip "$zip"; then
                if (( EXTRACT )); then
                    # into a temporary folder first; a single folder the zip wraps everything in is removed
                    tmpx="$dir/.files_$id"; rm -rf -- "${tmpx:?}"
                    unzip -q -n "$zip" -d "$tmpx" 2>/dev/null; zrc=$?
                    if (( zrc <= 1 )); then
                        flatten "$tmpx"
                        if [[ -e "$dir/files" ]]; then merge "$tmpx" "$dir/files"; rm -rf -- "${tmpx:?}"; else mv -- "$tmpx" "$dir/files"; fi
                        rm -f "$zip"; record "files:$id" "$rel/files"; ((files_ok++)); printf "    ${GREEN}✓${NC} files/\n"
                    else rm -rf -- "${tmpx:?}"; LAST_ERROR="the zip could not be extracted (unzip exit $zrc) - kept as $(basename "$zip")"; fail "$label - model files" "$id"; fi
                else
                    zname="$(safe_name "${LINK_NAME:-${title[$id]}.zip}")"; [[ "$zname" == *.zip ]] || zname="$zname.zip"
                    mkdir -p "$dir/files" && mv -f "$zip" "$dir/files/$zname" && record "files:$id" "$rel/files/$zname" && ((files_ok++)) && printf "    ${GREEN}✓${NC} files/%s\n" "$zname"
                fi
            else
                rm -f "$zip"; [[ "$LAST_ERROR" == curl* ]] || LAST_ERROR="the download is not a zip file"; fail "$label - model files" "$id"
            fi
        else fail "$label - model files" "$id"; fi
    fi

    # print profiles
    for i in "${insts[@]}"; do
        [[ -n "$stopped" ]] && break
        iid="${i%%$'\x1f'*}"; ititle="${i#*$'\x1f'}"
        done_part "inst:$iid" && continue
        if ! link_request "/design-service/instance/$iid/f3mf?type=download"; then fail "$label - profile $ititle" "$id"; continue; fi
        pname="$(safe_name "${LINK_NAME:-profile_$iid.3mf}")"; [[ "$pname" == *.3mf ]] || pname="$pname.3mf"
        # several profiles often have the same file name: add the profile's title
        [[ -e "$dir/profiles/$pname" ]] && pname="$(safe_name "${pname%.3mf} - ${ititle:0:60}").3mf"
        [[ -e "$dir/profiles/$pname" ]] && pname="${pname%.3mf}_$iid.3mf"
        if fetch_file "$LINK_URL" "$dir/profiles/$pname" && is_zip "$dir/profiles/$pname"; then
            record "inst:$iid" "$rel/profiles/$pname"; ((profiles_ok++)); printf "    ${GREEN}✓${NC} profiles/%s\n" "$pname"
        else
            rm -f "$dir/profiles/$pname"; [[ "$LAST_ERROR" == curl* ]] || LAST_ERROR="the download is not a 3MF file"; fail "$label - profile $ititle" "$id"
        fi
    done

    # pictures (plain links, no cookie)
    if (( IMAGES )) && ! done_part "pics:$id"; then
        ok=1; got=0
        while IFS=$'\x1f' read -r pn pu; do
            [[ -n "$pu" ]] || continue
            pn="$(safe_name "${pn:-$(basename "${pu%%\?*}")}")"
            [[ -s "$dir/images/$pn" ]] && continue
            sleep "$IMAGE_DELAY_SECONDS"
            if fetch_file "$pu" "$dir/images/$pn" && is_image "$dir/images/$pn"; then got=$((got + 1))
            else rm -f "$dir/images/$pn"; ok=0; fail "$label - picture $pn" "$id"; fi
        done < <(jq -r ".designExtension.design_pictures // [] | .[] | [(.name // \"\"), (.url // \"\")] | $JQ_JOIN" "$BODY.model")
        (( ok )) && record "pics:$id" "$rel/images"
        pics_ok=$((pics_ok + got)); (( got )) && printf "    ${GREEN}✓${NC} images/ (%s)\n" "$got"
    fi
    # nothing failed for this model: skip it on later runs (unless RECHECK=1)
    (( failed == model_failed )) && [[ -z "$stopped" ]] && record "complete:$id" "$rel"
    rm -f "$BODY.model"
done

echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e " Models:                 ${BLUE}${#order[@]}${NC}"
echo -e " Worked on this run:     ${worked}"
echo -e " Model files:            ${GREEN}${files_ok}${NC} downloaded"
echo -e " Print profiles:         ${GREEN}${profiles_ok}${NC} downloaded"
(( IMAGES )) && echo -e " Pictures:               ${GREEN}${pics_ok}${NC} downloaded"
echo -e " Failed:                 ${RED}${failed}${NC}"
echo -e "${YELLOW}================================================${NC}"
[[ -n "$stopped" ]] && echo -e "${YELLOW}Stopped early: ${stopped}. The rest is listed in ${MISSING_OUT}.${NC}"
(( failed )) && echo -e "Failures: ${YELLOW}${FAILED_OUT}${NC} - they're tried again on the next run." || rm -f "$FAILED_OUT"
[[ -s "$MISSING_OUT" ]] || rm -f "$MISSING_OUT"
