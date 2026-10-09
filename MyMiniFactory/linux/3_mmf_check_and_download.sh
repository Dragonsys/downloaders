#!/bin/bash
# ================================================================
# MyMiniFactory Download Verifier + Downloader
# Checks every file listed in the JSON metadata and (optionally) downloads the
# missing ones straight into  models/model_<id>/<filename>, using your cookie
# and browser user agent, with throttling and automatic back-off.
# Outputs full filename list + HTML report w/ highlighting, summary links,
# return-to-top links, and collapsible sections.
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;94m'
NC='\033[0m'

# ==============================
# CONFIGURABLE SETTINGS & DIRECTORIES
# ==============================
GENERATE_HTML=1       # set to 1 to enable HTML report
GENERATE_ALLFILES=1   # set to 1 to enable All Files Report
# Folders. Empty = the "downloads" / "models" folder next to this script.
# To use other folders, put their full paths here, e.g. "/mnt/nas/MyMiniFactory/models".
JSON_DIR=""           # JSON metadata from 2_mmf_download_metadata.sh
DOWNLOAD_DIR=""       # model_<id> folders with the files
OUTPUT_FILE="missing_downloads.txt"          # URLs still missing at the end
FAILED_FILE="failed_downloads.txt"           # download failures with reasons
ALL_FILES_OUTPUT="all_filenames_by_model.txt"
HTML_OUTPUT="report.html"
HTML_TEMP="report.tmp"
TEMP_FILE="all_filenames_by_model.tmp"
EXCLUDE_FILE="exclude_models.txt"            # models to leave out: one ID per line ("# ..." = comment),
                                             # in the current folder or next to this script

# ------------------------------
# DOWNLOAD SETTINGS
# ------------------------------
DOWNLOAD_MISSING=0    # 0 = check only (MyMiniFactory blocks scripted file downloads), 1 = try to download

# Cookie: paste it here, OR leave empty and put it in cookie.txt next to this
# script, OR set the MMF_COOKIE environment variable. Never share it.
COOKIE=''
COOKIE_FILE="cookie.txt"

# Must match the browser the cookie came from (run navigator.userAgent in its console).
# Paste it here, OR leave empty and put it in user_agent.txt next to this script,
# OR set the MMF_USER_AGENT environment variable.
USER_AGENT=''
USER_AGENT_FILE="user_agent.txt"

DELAY_SECONDS=5       # pause between downloads (throttling)
MAX_DOWNLOADS=0       # stop after this many download attempts per run (0 = no limit)
MAX_RETRIES=4         # retries for rate limits (429), server errors and network errors
BACKOFF_SECONDS=30    # first retry wait; doubles each retry unless the server says otherwise
AUTH_FAIL_LIMIT=3     # stop downloading after this many login/bot-check failures in a row
                      # (a refused file is only counted if your cookie also fails the API check)
BASE_URL="https://www.myminifactory.com"

# ------------------------------
# IMAGES - the model's pictures (unlike the files, MyMiniFactory lets scripts download these;
# no cookie is sent). Saved in models/model_<id>/Images/, skipped if already there.
# ------------------------------
IMAGES=1                # 1 = download each model's images, 0 = don't
IMAGES_ONLY=0           # 1 = only download images: no file check, and missing_downloads.txt and the
                        #     reports are left as they are (e.g. to add images to models you already have).
                        #     Looks for each model's folder in DOWNLOAD_DIR and in models/ next to this script.
IMAGES_CREATE_FOLDERS=0 # with IMAGES_ONLY=1: 1 = models without a folder get a new "<id>_<name>" folder
                        #     in DOWNLOAD_DIR for their images; 0 = skip them
# Folder structure for those new folders - use the same as in 99_mmf_rename_folders_from_json.ps1.
# Available options:
#   "DESIGNER/ID_NAME"  -> MatMire_Makes/849932_Caterpillar   (default)
#   "ID_NAME"           -> 849932_Caterpillar                 (directly in DOWNLOAD_DIR)
# (The rename script's NAME options aren't offered here: without the ID no script finds the folder.)
# Existing model folders are found in either structure.
FOLDER_STRUCTURE="DESIGNER/ID_NAME"
AUTHOR_NAME="name"      # designer folder name: "name" (display name) or "username" - as in the rename script
UNKNOWN_AUTHOR="_Unknown_designer"   # for models whose metadata names no designer
IMAGE_SIZE="large"      # "large" (1000x1000, ~150 KB), "standard" (720x720, ~80 KB)
                        # or "original" (full size, often 1 MB or more - for a big library that adds up)
IMAGE_DELAY_SECONDS=3   # pause before every image request, like 2_mmf_download_metadata.sh.
                        # (Images already on disk are checked locally - no request, no pause.)
                        # If MyMiniFactory's bot check refuses one, the image downloads stop at once:
                        # every further request would only keep the block going. Run again later.
MAX_IMAGE_DOWNLOADS=0   # stop downloading images after this many this run (0 = no limit)
JPG_TO_BROWSER=1        # 1 = images whose name ends in upper-case ".JPG" are not requested: MyMiniFactory's
                        #     bot check refuses those to scripts (every other image works). They're listed
                        #     in missing_images.txt for your browser's download manager instead, with
                        #     missing_images_map.tsv saying which model folder each one belongs in.
MISSING_IMAGES_FILE="missing_images.txt"
MISSING_IMAGES_MAP="missing_images_map.tsv"
IMAGES_FAILED_FILE="failed_images.txt"
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "$JSON_DIR" ]] && JSON_DIR="$script_dir/downloads"
[[ -z "$DOWNLOAD_DIR" ]] && DOWNLOAD_DIR="$script_dir/models"
DEFAULT_MODELS_DIR="$script_dir/models"
case "${FOLDER_STRUCTURE^^}" in
    DESIGNER/ID_NAME|DESIGNER\ID_NAME) by_designer=1 ;;
    ID_NAME) by_designer=0 ;;
    *) echo -e "${RED}Unknown FOLDER_STRUCTURE \"${FOLDER_STRUCTURE}\" - use \"DESIGNER/ID_NAME\" or \"ID_NAME\".${NC}"; exit 1 ;;
esac
# Relative paths are relative to this script's folder (e.g. "../.Sort/mmf_library")
[[ "$JSON_DIR" != /* ]] && JSON_DIR="$script_dir/$JSON_DIR"
[[ "$DOWNLOAD_DIR" != /* ]] && DOWNLOAD_DIR="$script_dir/$DOWNLOAD_DIR"

# Remove trailing slashes so paths don't contain "//"
JSON_DIR="${JSON_DIR%/}"
DOWNLOAD_DIR="${DOWNLOAD_DIR%/}"

# Models left out on purpose (e.g. ones that always show as missing although you have them):
# an ID, a model URL or a "<id>_<name>" folder name per line in exclude_models.txt
declare -A excluded=()
exclude_file="$EXCLUDE_FILE"
[[ ! -f "$exclude_file" && -f "$script_dir/$exclude_file" ]] && exclude_file="$script_dir/$exclude_file"
if [[ -f "$exclude_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//$'\r'/}"; line="${line#$'\xEF\xBB\xBF'}"; line="${line%%#*}"
        if [[ "$line" =~ /object/[A-Za-z0-9_-]*-([0-9]+)([^A-Za-z0-9_-]|$) ]]; then excluded[${BASH_REMATCH[1]}]=1
        elif [[ "$line" =~ ([0-9]+) ]]; then excluded[${BASH_REMATCH[1]}]=1; fi
    done < "$exclude_file"
fi
n_excluded=0

# Escape text for safe use inside HTML
html_escape() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

echo -e "${BLUE}Checking downloaded files...${NC}"
printf "JSON directory:        ${YELLOW}%s${NC}\n" "$JSON_DIR"
printf "Download directory:    ${YELLOW}%s${NC}\n" "$DOWNLOAD_DIR"
printf "Missing URLs saved to: ${YELLOW}%s${NC}\n" "$OUTPUT_FILE"
if [[ $GENERATE_ALLFILES -eq 1 ]]; then printf "Filename list saved to: ${YELLOW}%s${NC}\n" "$ALL_FILES_OUTPUT"; fi
if [[ $GENERATE_HTML -eq 1 ]]; then printf "HTML report saved to:   ${YELLOW}%s${NC}\n" "$HTML_OUTPUT"; fi

# Validate directories
[[ ! -d "$JSON_DIR" ]] && { echo -e "${RED}JSON directory missing: $JSON_DIR${NC}"; exit 1; }
[[ ! -d "$DOWNLOAD_DIR" ]] && { echo -e "${RED}Download directory missing: $DOWNLOAD_DIR${NC}"; exit 1; }

# Check tools
command -v jq &> /dev/null || { echo -e "${RED}Error: jq not installed.${NC}"; exit 1; }

[[ $IMAGES_ONLY -eq 1 ]] && { IMAGES=1; DOWNLOAD_MISSING=0; }

# User agent: needed for file downloads, and also sent with image requests
[[ -z "$USER_AGENT" && -n "$MMF_USER_AGENT" ]] && USER_AGENT="$MMF_USER_AGENT"
[[ -z "$USER_AGENT" && -f "$script_dir/$USER_AGENT_FILE" ]] && USER_AGENT="$(tr -d '\r\n' < "$script_dir/$USER_AGENT_FILE")"
USER_AGENT="${USER_AGENT#\"}"; USER_AGENT="${USER_AGENT%\"}"   # strip quotes copied from the console
if [[ $IMAGES -eq 1 ]]; then
    command -v curl &> /dev/null || { echo -e "${RED}Error: curl not installed.${NC}"; exit 1; }
    [[ -w "$DOWNLOAD_DIR" ]] || { echo -e "${RED}Error: no write permission for $DOWNLOAD_DIR${NC}"; exit 1; }
    # Images need no cookie; any normal browser user agent will do
    IMAGE_USER_AGENT="${USER_AGENT:-Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36}"
fi

# Download setup
if [[ $DOWNLOAD_MISSING -eq 1 ]]; then
    command -v curl &> /dev/null || { echo -e "${RED}Error: curl not installed.${NC}"; exit 1; }
    [[ -z "$COOKIE" && -n "$MMF_COOKIE" ]] && COOKIE="$MMF_COOKIE"
    [[ -z "$COOKIE" && -f "$script_dir/$COOKIE_FILE" ]] && COOKIE="$(tr -d '\r\n' < "$script_dir/$COOKIE_FILE")"
    [[ -z "$COOKIE" ]] && { echo -e "${RED}Error: no cookie set (COOKIE, $COOKIE_FILE, or MMF_COOKIE).${NC}"; exit 1; }
    [[ -z "$USER_AGENT" ]] && { echo -e "${RED}Error: no user agent set (USER_AGENT, $USER_AGENT_FILE, or MMF_USER_AGENT). Run navigator.userAgent in your browser console.${NC}"; exit 1; }
    [[ -w "$DOWNLOAD_DIR" ]] || { echo -e "${RED}Error: no write permission for $DOWNLOAD_DIR${NC}"; exit 1; }
    printf "Downloading missing files: ${YELLOW}yes${NC} (%ss between downloads%s)\n" "$DELAY_SECONDS" \
        "$( (( MAX_DOWNLOADS > 0 )) && echo ", max $MAX_DOWNLOADS this run")"
else
    printf "Downloading missing files: ${YELLOW}no (check only)${NC}\n"
fi
echo ""

shopt -s nullglob
json_files=("$JSON_DIR"/model_*.json)
(( ${#json_files[@]} == 0 )) && { echo -e "${RED}No model_*.json files found.${NC}"; exit 1; }

if [[ $IMAGES_ONLY -eq 1 ]]; then
    IMAGES=1; DOWNLOAD_MISSING=0
    printf "Mode:                  ${YELLOW}images only${NC} (files are not checked; missing_downloads.txt and the reports are left alone)\n\n"
else
    > "$OUTPUT_FILE"
fi
> "$TEMP_FILE"
> "$HTML_TEMP"
[[ $DOWNLOAD_MISSING -eq 1 ]] && > "$FAILED_FILE"

total_expected=0
total_missing=0
total_downloaded=0
download_failed=0
download_attempts=0
downloads_stopped=0
stop_reason=""
auth_fail_streak=0
first_download=1
no_file_models=0
invalid_json=0
MISSING_ENTRIES=()
NO_FILE_MODELS=()
INVALID_JSON_FILES=()
NO_FOLDER_MODELS=()
NO_IMAGES_MODELS=()
LAST_ERROR=""

# ------------------------------------------------------------
# download_file URL DEST
#   0 = downloaded, 1 = failed, 2 = login/permission problem
# Writes to DEST.part first, so an interrupted download never
# looks like a finished file.
# ------------------------------------------------------------
download_file() {
    local url="$1" dest="$2"
    local tmp="${dest}.part" hdr errf result rc code ctype retry_after wait attempt=0
    [[ "$url" == /* ]] && url="${BASE_URL}${url}"
    mkdir -p "$(dirname "$dest")" || { LAST_ERROR="cannot create folder"; return 1; }

    while :; do
        hdr=$(mktemp); errf=$(mktemp)
        result=$(curl --silent --show-error --location --connect-timeout 30 \
            -H "User-Agent: $USER_AGENT" \
            -H "Accept: */*" \
            -H "Accept-Language: en-US,en;q=0.5" \
            -H "Referer: ${BASE_URL}/library" \
            -H "Cookie: $COOKIE" \
            -D "$hdr" -o "$tmp" -w '%{http_code} %{content_type}' \
            "$url" 2>"$errf")
        rc=$?
        code="${result%% *}"
        ctype="${result#* }"
        [[ "$ctype" == "$result" ]] && ctype=""
        retry_after=$(grep -i '^retry-after:' "$hdr" | tail -1 | tr -dc '0-9')
        cf_mitigated=$(grep -i '^cf-mitigated:' "$hdr" | tail -1)
        LAST_ERROR="curl exit $rc, HTTP ${code:-none}$( [[ -s "$errf" ]] && printf ', %s' "$(head -c 150 "$errf" | tr '\n' ' ')")"
        rm -f "$hdr" "$errf"

        # Success: HTTP 200, non-empty, and not a web page
        if (( rc == 0 )) && [[ "$code" == "200" && "$ctype" != text/html* && -s "$tmp" ]]; then
            mv -f "$tmp" "$dest" && return 0
            LAST_ERROR="could not move finished download into place"
            rm -f "$tmp"; return 1
        fi
        body=$(head -c 2000 "$tmp" 2>/dev/null | tr -d '\0\r' | tr '\n' ' ')
        rm -f "$tmp"

        # Bot protection challenge: retrying will not help
        if [[ -n "$cf_mitigated" ]] || [[ "$body" == *"Just a moment"* || "$body" == *"challenge-platform"* || "$body" == *"cf-chl"* ]]; then
            LAST_ERROR="HTTP $code: blocked by Cloudflare bot check (cookie/user agent mismatch, or downloads not allowed from scripts)"
            return 3
        fi

        # Login page or permission problem: retrying will not help
        if [[ "$code" == "401" || "$code" == "403" ]] || [[ "$code" == "200" && "$ctype" == text/html* ]]; then
            if [[ "$code" == "200" ]]; then
                LAST_ERROR="got a web page instead of the file"
            else
                snippet=$(printf '%s' "$body" | sed 's/<[^>]*>/ /g; s/  */ /g' | head -c 120)
                LAST_ERROR="HTTP $code${snippet:+: $snippet}"
            fi
            return 2
        fi

        # Rate limit, server error or network error: wait and retry
        if [[ "$code" == "429" || "$code" == 5?? || "$code" == "000" || -z "$code" ]] && (( attempt < MAX_RETRIES )); then
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

# ------------------------------------------------------------
# cookie_works MODEL_ID
#   Asks the metadata API (the one 2_mmf_download_metadata.sh uses) about this model.
#   0 = cookie accepted, 1 = cookie rejected. Cached per model.
# ------------------------------------------------------------
declare -A COOKIE_CHECK=()
cookie_works() {
    local id="$1" out code
    [[ -n "${COOKIE_CHECK[$id]}" ]] && return "${COOKIE_CHECK[$id]}"
    sleep "$DELAY_SECONDS"
    out=$(mktemp)
    code=$(curl --silent --location --compressed --connect-timeout 30 \
        -H "User-Agent: $USER_AGENT" \
        -H "Accept: application/json" \
        -H "Accept-Language: en-US,en;q=0.5" \
        -H "Referer: ${BASE_URL}/api-doc/index.html" \
        -H "Cookie: $COOKIE" \
        -o "$out" -w '%{http_code}' \
        "${BASE_URL}/api/v2/objects/$id")
    if [[ "$code" == "200" && "$(head -c 1 "$out")" == "{" ]]; then
        COOKIE_CHECK[$id]=0
    else
        COOKIE_CHECK[$id]=1
    fi
    rm -f "$out"
    return "${COOKIE_CHECK[$id]}"
}

# ------------------------------------------------------------
# fetch_image URL DEST  (no cookie; the image server is public)
#   0 = downloaded, 1 = failed, 3 = bot check (stop), 4 = not on the server (404)
# ------------------------------------------------------------
fetch_image() {
    local url="$1" dest="$2" tmp="${2}.part" hdr result rc code wait attempt=0 magic
    mkdir -p "$(dirname "$dest")" || { LAST_ERROR="cannot create folder"; return 1; }
    while :; do
        hdr=$(mktemp)
        result=$(curl --silent --location --connect-timeout 30 --max-time 300 \
            -H "User-Agent: $IMAGE_USER_AGENT" -H "Accept: image/*,*/*" \
            -D "$hdr" -o "$tmp" -w '%{http_code}' "$url")
        rc=$?; code="$result"
        local cf; cf=$(grep -i '^cf-mitigated:' "$hdr"); rm -f "$hdr"
        LAST_ERROR="curl exit $rc, HTTP ${code:-none}"
        if (( rc == 0 )) && [[ "$code" == "200" && -s "$tmp" ]]; then
            magic=$(head -c 4 "$tmp" | od -An -tx1 | tr -d ' \n')
            if [[ "$magic" == ffd8ff* || "$magic" == 89504e47* || "$magic" == 47494638* || "$magic" == 52494646* ]]; then
                mv -f "$tmp" "$dest" && return 0
                LAST_ERROR="could not move finished download into place"
            else
                LAST_ERROR="not an image (got: $(head -c 40 "$tmp" | tr -cd '[:print:]'))"
            fi
            rm -f "$tmp"; return 1
        fi
        rm -f "$tmp"
        [[ -n "$cf" ]] && { LAST_ERROR="HTTP $code: blocked by Cloudflare bot check"; return 3; }
        [[ "$code" == "404" || "$code" == "410" ]] && return 4
        (( rc == 3 )) && { LAST_ERROR="malformed image address (curl exit 3)"; return 1; }   # retrying won't help
        if [[ "$code" == "429" || "$code" == 5?? || "$code" == "000" || -z "$code" ]] && (( attempt < MAX_RETRIES )); then
            attempt=$((attempt + 1))
            wait=$(( BACKOFF_SECONDS * (1 << (attempt - 1)) )); (( wait > 900 )) && wait=900
            printf "    ${YELLOW}%s - waiting %ss before retry %s/%s${NC}\n" "$LAST_ERROR" "$wait" "$attempt" "$MAX_RETRIES"
            sleep "$wait"; continue
        fi
        return 1
    done
}

# index_models BASE - remember where the model folders in BASE are: "model_<id>" or "<id>_<name>",
# directly in BASE or one level down in a designer folder (99_mmf_rename_folders_from_json.ps1).
# Read once per run (one folder listing per designer instead of one per model). Only ids with
# a JSON file count; any other folder is taken as a designer folder.
declare -A MODEL_DIRS=() TOP_DIRS=()
index_models() {
    local base="$1" d s n id
    [[ -d "$base" ]] || return 0
    for d in "$base"/*/; do
        d="${d%/}"; n="${d##*/}"; id=""
        [[ -d "$d" ]] || continue
        [[ "$base" == "$DOWNLOAD_DIR" ]] && TOP_DIRS["${n,,}"]="$n"
        if [[ "$n" =~ ^model_([0-9]+)$ || "$n" =~ ^([0-9]+)_ ]] && [[ -n "${have_json[${BASH_REMATCH[1]}]}" ]]; then
            id="${BASH_REMATCH[1]}"; MODEL_DIRS["$base|$id"]+="$d"$'\x1f'; continue
        fi
        for s in "$d"/*/; do
            s="${s%/}"; n="${s##*/}"
            [[ -d "$s" ]] || continue
            if [[ "$n" =~ ^model_([0-9]+)$ || "$n" =~ ^([0-9]+)_ ]] && [[ -n "${have_json[${BASH_REMATCH[1]}]}" ]]; then
                MODEL_DIRS["$base|${BASH_REMATCH[1]}"]+="$s"$'\x1f'
            fi
        done
    done
}

# find_model_dir BASE ID - print the model's folder in BASE (see index_models): "model_<id>", or the
# one "<id>_<name>" folder (if there are several, the only one that isn't empty).
# 0 = found, 1 = none, 2 = several.
find_model_dir() {
    local base="$1" id="$2" d nonempty=() cands=()
    local list="${MODEL_DIRS["$base|$id"]}"
    [[ -z "$list" ]] && return 1
    IFS=$'\x1f' read -r -a cands <<< "${list%$'\x1f'}"
    for d in "${cands[@]}"; do [[ "${d##*/}" == "model_$id" ]] && { printf '%s' "$d"; return 0; }; done
    (( ${#cands[@]} == 1 )) && { printf '%s' "${cands[0]}"; return 0; }
    for d in "${cands[@]}"; do [[ -n "$(ls -A "$d" 2>/dev/null)" ]] && nonempty+=("$d"); done
    (( ${#nonempty[@]} == 1 )) && { printf '%s' "${nonempty[0]}"; return 0; }
    return 2
}

# clean_name NAME - folder name part as 99_mmf_rename_folders_from_json.ps1 makes it
# (characters Windows doesn't allow and spaces -> "_", at most 80 characters)
clean_name() {
    local s="$1"
    s="$(printf '%s' "$s" | tr -d '\000-\037' | sed 's#[<>:"/\\|?*]#_#g; s/[[:space:]]\+/_/g; s/_\+/_/g')"
    s="${s:0:80}"
    s="${s#"${s%%[!_ .]*}"}"; s="${s%"${s##*[!_ .]}"}"
    printf '%s' "$s"
}

images_present=0; images_downloaded=0; images_failed=0; images_absent=0; images_skipped=0; images_stopped=""; first_image=1
folders_created=0; images_listed=0
[[ $IMAGES -eq 1 ]] && : > "$IMAGES_FAILED_FILE"
if [[ $IMAGES -eq 1 && $JPG_TO_BROWSER -eq 1 ]]; then
    : > "$MISSING_IMAGES_FILE"
    printf 'url\tmodel_id\tfolder\tfile\n' > "$MISSING_IMAGES_MAP"
fi

# do_images JSON MODEL_DIR MODEL_ID - download the model's images that aren't there yet
do_images() {
    local json="$1" dir="$2/Images" id="$3" u name n=0 new=0 have=0 absent=0 failed=0 skipped=0 listed=0 r
    local model_existed=0 images_existed=0 parent_existed=0
    [[ -d "$2" ]] && model_existed=1
    [[ -d "${2%/*}" ]] && parent_existed=1   # the designer folder, if a new one
    [[ -d "$dir" ]] && images_existed=1
    local -A used=()
    mapfile -t img_urls < <(jq -r --arg s "$IMAGE_SIZE" \
        '(.images // [])[] | (.[$s].url // .large.url // .original.url // empty)' "$json" 2>/dev/null)
    (( ${#img_urls[@]} )) || return 0
    for u in "${img_urls[@]}"; do
        n=$((n + 1))
        # Older metadata points to dl<N>.myminifactory.com/object-assets/..., which is behind the bot
        # check; the site now serves the same images from assets.myminifactory.com/object-images/...
        [[ "$u" =~ ^https?://dl[0-9]*\.myminifactory\.com/object-assets/(.*)$ ]] && u="https://assets.myminifactory.com/object-images/${BASH_REMATCH[1]}"
        # Name: the file name without the size prefix ("1000X1000-"), %-escapes decoded
        name="${u%%\?*}"; name="${name##*/}"
        name="$(printf '%b' "${name//'%'/'\x'}")"   # quoted: bash 5.2 treats \ in the replacement differently
        name="${name#[0-9]*X[0-9]*-}"
        name="${name//\//_}"; [[ -z "$name" ]] && name="image_$n.jpg"
        [[ -n "${used[$name]}" ]] && name="${n}_$name"
        used[$name]=1
        if [[ -s "$dir/$name" ]]; then ((images_present++)); ((have++)); continue; fi
        if [[ -z "$images_stopped" ]] && (( MAX_IMAGE_DOWNLOADS > 0 && images_downloaded + images_failed >= MAX_IMAGE_DOWNLOADS )); then
            images_stopped="reached MAX_IMAGE_DOWNLOADS ($MAX_IMAGE_DOWNLOADS) for this run"
        fi
        # Upper-case ".JPG": refused to scripts by the bot check - list it for the browser instead
        if [[ $JPG_TO_BROWSER -eq 1 && "${u%%\?*}" == *.JPG ]]; then
            printf '%s\n' "${u// /%20}" >> "$MISSING_IMAGES_FILE"
            printf '%s\t%s\t%s\t%s\n' "${u// /%20}" "$id" "$2" "Images/$name" >> "$MISSING_IMAGES_MAP"
            ((listed++)); ((images_listed++)); continue
        fi
        [[ -n "$images_stopped" ]] && { ((skipped++)); ((images_skipped++)); continue; }
        # Throttle: the same pause before every image request (like step 2)
        (( first_image )) || sleep "$IMAGE_DELAY_SECONDS"
        first_image=0
        fetch_image "${u// /%20}" "$dir/$name"; r=$?
        # Refused by the bot check: stop all image requests for this run - the block lasts a while,
        # and more requests only keep it going
        (( r == 3 )) && images_stopped="$LAST_ERROR - wait a few hours before the next run"
        case $r in
            0) ((images_downloaded++)); ((new++)) ;;
            4) ((images_absent++)); ((absent++)) ;;
            *) ((images_failed++)); ((failed++))
               printf '%s\t%s\t%s\t%s\n' "$id" "$name" "$LAST_ERROR" "$u" >> "$IMAGES_FAILED_FILE" ;;
        esac
    done
    # No image saved: remove the folders this attempt created (never ones that were there before)
    if (( new == 0 )); then
        (( images_existed )) || rmdir "$dir" 2>/dev/null
        (( model_existed )) || rmdir "$2" 2>/dev/null
        (( parent_existed )) || rmdir "${2%/*}" 2>/dev/null
    fi
    printf "  ${BLUE}Images:${NC} %s new, %s already there (%s of %s)" "$new" "$have" "$((new + have))" "${#img_urls[@]}"
    (( absent ))  && printf ", ${YELLOW}%s not on the server${NC}" "$absent"
    (( failed ))  && printf ", ${RED}%s failed${NC}" "$failed"
    (( listed ))  && printf ", ${YELLOW}%s .JPG listed for the browser${NC}" "$listed"
    (( skipped )) && printf ", ${YELLOW}%s skipped - image downloads stopped: %s${NC}" "$skipped" "$images_stopped"
    printf "\n"
}

# Where the model folders are (also inside designer folders) - read once
declare -A have_json=()
for f in "${json_files[@]}"; do f="${f##*/}"; f="${f%.json}"; have_json["${f#model_}"]=1; done
index_models "$DOWNLOAD_DIR"
[[ $IMAGES_ONLY -eq 1 && "$DEFAULT_MODELS_DIR" != "$DOWNLOAD_DIR" ]] && index_models "$DEFAULT_MODELS_DIR"

# HTML table start
echo "<table>" >> "$HTML_TEMP"

for json_file in "${json_files[@]}"; do
    model_id=$(basename "$json_file" .json)
    model_id="${model_id#model_}"
    if [[ -n "${excluded[$model_id]}" ]]; then
        n_excluded=$((n_excluded + 1)); printf "${YELLOW}Model %s: left out (%s)${NC}\n" "$model_id" "$EXCLUDE_FILE"; continue
    fi
    model_dir="${DOWNLOAD_DIR}/model_${model_id}"
    # Renamed by 99_mmf_rename_folders_from_json.ps1 ("<id>_<name>")? Use that folder.
    # In IMAGES_ONLY mode also look in models/ next to this script (models not moved to DOWNLOAD_DIR yet).
    found_dir=""; folder_note=""
    search_dirs=("$DOWNLOAD_DIR")
    [[ $IMAGES_ONLY -eq 1 && "$DEFAULT_MODELS_DIR" != "$DOWNLOAD_DIR" && -d "$DEFAULT_MODELS_DIR" ]] && search_dirs+=("$DEFAULT_MODELS_DIR")
    for base in "${search_dirs[@]}"; do
        found_dir="$(find_model_dir "$base" "$model_id")" && break
        found_dir=""
    done
    [[ -n "$found_dir" ]] && model_dir="$found_dir"

    # Skip files that aren't valid JSON (e.g. saved error pages)
    if ! jq empty "$json_file" 2>/dev/null; then
        printf "${RED}Model %s: invalid JSON, skipping (%s)${NC}\n" "$model_id" "$json_file"
        echo "model_${model_id} | INVALID JSON" >> "$TEMP_FILE"
        echo "" >> "$TEMP_FILE"
        echo "<tr><td colspan='2' class='model-header'>Model ${model_id}</td></tr>" >> "$HTML_TEMP"
        echo "<tr><td colspan='2' class='warning'>Invalid JSON file, skipped</td></tr>" >> "$HTML_TEMP"
        ((invalid_json++))
        INVALID_JSON_FILES+=("$model_id")
        continue
    fi

    model_name=$(jq -r '.name // "UNKNOWN_NAME"' "$json_file")
    model_name_html=$(html_escape "$model_name")

    printf "${BLUE}Model %s — %s:${NC}\n" "$model_id" "$model_name"
    echo "model_${model_id} | \"${model_name}\":" >> "$TEMP_FILE"
    echo "<tr><td colspan='2' class='model-header'>Model ${model_id} — ${model_name_html}</td></tr>" >> "$HTML_TEMP"
    if [[ $IMAGES_ONLY -eq 1 ]]; then
        if [[ -n "$found_dir" ]]; then
            do_images "$json_file" "$model_dir" "$model_id"
            continue
        fi
        find_model_dir "$DOWNLOAD_DIR" "$model_id" >/dev/null; [[ $? -eq 2 ]] && several=1 || several=0
        has_images=$(jq -r '(.images // []) | length' "$json_file" 2>/dev/null)
        if (( IMAGES_CREATE_FOLDERS && ! several && ${has_images:-0} > 0 )); then
            # New "<id>_<name>" folder (the name as the rename script makes it), just for the images,
            # in the designer's folder with FOLDER_STRUCTURE="DESIGNER/ID_NAME"
            cname="$(clean_name "$model_name")"
            model_dir="${DOWNLOAD_DIR}/${model_id}${cname:+_$cname}"
            if [[ "$by_designer" == 1 ]]; then
                if [[ "$AUTHOR_NAME" == "username" ]]; then author=$(jq -r '.designer.username // .designer.name // ""' "$json_file" 2>/dev/null)
                else author=$(jq -r '.designer.name // .designer.username // ""' "$json_file" 2>/dev/null); fi
                author="$(clean_name "$author")"
                [[ -z "$author" ]] && author="$UNKNOWN_AUTHOR"
                [[ "${author^^}" =~ ^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$ ]] && author+="_"
                # a designer folder already there with other upper/lower case is used as it is
                [[ -n "${TOP_DIRS[${author,,}]}" ]] && author="${TOP_DIRS[${author,,}]}"
                TOP_DIRS["${author,,}"]="$author"
                model_dir="${DOWNLOAD_DIR}/${author}/${model_id}${cname:+_$cname}"
            fi
            do_images "$json_file" "$model_dir" "$model_id"
            # The folder only comes into being when its first image is saved
            if [[ -d "$model_dir" ]]; then
                printf "  ${BLUE}New folder:${NC} %s\n" "${model_dir#"$DOWNLOAD_DIR"/}"
                ((folders_created++))
            fi
        elif [[ "${has_images:-0}" == "0" ]]; then
            printf "  ${YELLOW}Skipped:${NC} no images listed for this model\n"
            NO_IMAGES_MODELS+=("$model_id")
        else
            if (( several )); then why="several ${model_id}_* folders with files - not sure which"
            else why="no model_${model_id} or ${model_id}_* folder"; fi
            printf "  ${YELLOW}Skipped:${NC} %s\n" "$why"
            NO_FOLDER_MODELS+=("$model_id")
        fi
        continue
    fi
    [[ $IMAGES -eq 1 ]] && do_images "$json_file" "$model_dir" "$model_id"

    # Only entries that have both a filename and a download URL
    mapfile -t entries < <(jq -r '(.files.items // [])[]
        | select(.download_url != null and .filename != null and .filename != "")
        | "\(.filename)|\(.download_url)"' "$json_file" 2>/dev/null)

    if (( ${#entries[@]} == 0 )); then
        echo -e "  ${YELLOW}No files listed in JSON.${NC}"
        echo "<tr><td colspan='2' class='warning'>No files listed in JSON</td></tr>" >> "$HTML_TEMP"
        echo "" >> "$TEMP_FILE"
        ((no_file_models++))
        NO_FILE_MODELS+=("$model_id")
        continue
    fi

    declare -A seen_files=()

    for entry in "${entries[@]}"; do
        IFS='|' read -r filename url <<< "$entry"
        [[ -z "$filename" ]] && continue
        [[ "$url" == /* ]] && url="${BASE_URL}${url}"   # make relative URLs absolute

        if [[ -n "${seen_files[$filename]}" ]]; then
            printf "  ${YELLOW}⚠ Duplicate ignored:${NC} %s\n" "$filename"
            continue
        fi
        seen_files[$filename]=1

        ((total_expected++))
        # "/" cannot appear in a Linux filename
        file_path="${model_dir}/${filename//\//_}"
        filename_html=$(html_escape "$filename")

        # -s: file exists AND is not empty (catches failed 0-byte downloads)
        if [[ -s "$file_path" ]]; then
            echo "  $filename" >> "$TEMP_FILE"
            printf "  ${GREEN}✓${NC} %s\n" "$filename"
            echo "<tr><td class='present'>OK</td><td class='present'>${filename_html}</td></tr>" >> "$HTML_TEMP"
            continue
        fi

        # ---- Missing: try to download it ----
        if [[ $DOWNLOAD_MISSING -eq 1 && $downloads_stopped -eq 0 ]]; then
            if (( MAX_DOWNLOADS > 0 && download_attempts >= MAX_DOWNLOADS )); then
                downloads_stopped=1
                stop_reason="reached MAX_DOWNLOADS ($MAX_DOWNLOADS) for this run"
                printf "  ${YELLOW}Download limit reached, remaining files will only be checked.${NC}\n"
            else
                # Throttle: pause between downloads
                (( first_download )) || sleep "$DELAY_SECONDS"
                first_download=0
                ((download_attempts++))

                printf "  ${BLUE}↓ Downloading${NC} %s ...\n" "$filename"
                download_file "$url" "$file_path"
                result=$?

                if (( result == 0 )); then
                    auth_fail_streak=0
                    ((total_downloaded++))
                    size=$(du -h "$file_path" 2>/dev/null | cut -f1)
                    echo "  $filename  [DOWNLOADED]" >> "$TEMP_FILE"
                    printf "  ${GREEN}✓ DOWNLOADED${NC} %s (%s)\n" "$filename" "$size"
                    echo "<tr><td class='downloaded'>DOWNLOADED</td><td class='downloaded'>${filename_html}</td></tr>" >> "$HTML_TEMP"
                    continue
                fi

                count_toward_stop=0
                if (( result == 2 )); then
                    # Refused: is it the cookie, or just this file?
                    if cookie_works "$model_id"; then
                        LAST_ERROR="$LAST_ERROR [cookie OK - no access to this file; item may be locked for your account]"
                        auth_fail_streak=0
                    else
                        LAST_ERROR="$LAST_ERROR [cookie also rejected by the API - get a fresh cookie]"
                        count_toward_stop=1
                    fi
                elif (( result == 3 )); then
                    count_toward_stop=1
                else
                    auth_fail_streak=0
                fi

                ((download_failed++))
                printf "  ${RED}✗ Download failed:${NC} %s\n" "$LAST_ERROR"
                printf '%s\t%s\t%s\t%s\n' "$model_id" "$filename" "$LAST_ERROR" "$url" >> "$FAILED_FILE"

                if (( count_toward_stop )); then
                    ((auth_fail_streak++))
                    if (( auth_fail_streak >= AUTH_FAIL_LIMIT )); then
                        downloads_stopped=1
                        stop_reason="$AUTH_FAIL_LIMIT login/bot-check failures in a row - see $FAILED_FILE for the reason"
                        printf "  ${RED}Stopping downloads: %s${NC}\n" "$stop_reason"
                    fi
                fi
            fi
        fi

        # Still missing
        echo "  $filename  [MISSING]" >> "$TEMP_FILE"
        printf "  ${RED}✗ MISSING${NC} %s\n" "$filename"
        echo "$url" >> "$OUTPUT_FILE"
        ((total_missing++))
        MISSING_ENTRIES+=("$filename|$model_id")
        echo "<tr><td class='missing'>MISSING</td><td class='missing'>${filename_html}</td></tr>" >> "$HTML_TEMP"
    done
    unset seen_files
    echo "" >> "$TEMP_FILE"
done

echo "</table>" >> "$HTML_TEMP"

if [[ $IMAGES_ONLY -eq 1 ]]; then
    rm -f "$TEMP_FILE" "$HTML_TEMP"
    echo -e "${YELLOW}================================================${NC}"
    echo -e " Models:                 ${BLUE}${#json_files[@]}${NC}"
    (( n_excluded )) && echo -e " Left out:               ${YELLOW}${n_excluded}${NC} model(s) in ${EXCLUDE_FILE}"
    (( IMAGES_CREATE_FOLDERS )) && echo -e " New folders created:    ${folders_created}"
    (( ${#NO_IMAGES_MODELS[@]} )) && echo -e " No images listed:       ${#NO_IMAGES_MODELS[@]} - $(printf '%s ' "${NO_IMAGES_MODELS[@]:0:30}")"
    (( ${#NO_FOLDER_MODELS[@]} )) && echo -e " Skipped (no folder):    ${YELLOW}${#NO_FOLDER_MODELS[@]}${NC} - $(printf '%s ' "${NO_FOLDER_MODELS[@]:0:30}")"
    echo -e " Images:                 ${GREEN}${images_downloaded}${NC} downloaded, ${images_present} already there, ${images_absent} not on the server, ${RED}${images_failed}${NC} failed, ${images_skipped} skipped"
    echo -e "${YELLOW}================================================${NC}"
    [[ -n "$images_stopped" ]] && echo -e "${YELLOW}Image downloads stopped early: ${images_stopped}${NC}"
    (( images_failed > 0 )) && echo -e "${RED}Image failures saved to:${NC} ${YELLOW}${IMAGES_FAILED_FILE}${NC}"
    (( images_listed > 0 )) && echo -e "${YELLOW}${images_listed} .JPG image(s) for your browser's download manager:${NC} ${MISSING_IMAGES_FILE} (target folders in ${MISSING_IMAGES_MAP})"
    exit 0
fi

# Text summary (optional)
total_present=$((total_expected - total_missing))
timestamp=$(date +"%Y-%m-%d %H:%M:%S")
if [[ $GENERATE_ALLFILES -eq 1 ]]; then
{
    echo "SUMMARY"
    echo "--------"
    echo "Timestamp:            $timestamp"
    echo "Total expected files: $total_expected"
    echo "Present files:        $total_present"
    echo "Downloaded this run:  $total_downloaded"
    echo "Missing files:        $total_missing"
    echo "Models with no files: $no_file_models"
    echo "Invalid JSON files:   $invalid_json"
    echo "----------------------"
    cat "$TEMP_FILE"
} > "$ALL_FILES_OUTPUT"
fi
rm -f "$TEMP_FILE"

if [[ $GENERATE_HTML -eq 1 ]]; then
# HTML report with collapsible sections including all files
{
    echo "<!DOCTYPE html>"
    echo "<html><head><meta charset='utf-8'><title>MMF Download Report</title><style>
        body { font-family: Arial, sans-serif; background: #111; color: #ddd; margin: 20px; }
        h1 { color: #4da3ff; }
        table { width: 100%; border-collapse: collapse; }
        td { padding: 6px 10px; border-bottom: 1px solid #333; }
        .model-header { background: #222; font-weight: bold; color: #4da3ff; padding-top: 20px; }
        .present { color: #4eff4e; }
        .downloaded { color: #7fd8ff; font-weight: bold; }
        .missing { color: #ff5c5c; font-weight: bold; }
        .warning { color: #eb9b34; font-weight: bold; }
        .summary { background: #222; padding: 10px; border: 1px solid #333; margin-bottom: 20px; }
        a { color: #4da3ff; cursor: pointer; }
        .collapsible { background-color: #333; color: #ddd; padding: 10px; cursor: pointer; width: 100%; border: none; text-align: left; outline: none; font-size: 16px; }
        .active, .collapsible:hover { background-color: #444; }
        .content { padding: 0 15px; display: none; overflow: hidden; }
        </style>
    <script>
        function toggleSection(id) {
            var content = document.getElementById(id);
            content.style.display = content.style.display === 'block' ? 'none' : 'block';
        }
    </script>
    </head><body id='top'>"
    echo "<h1>MyMiniFactory Download Verification Report</h1>"
    echo "<div class='summary'><p><strong>Timestamp:</strong> $timestamp</p><p><strong>Total expected files:</strong> $total_expected</p><p><strong>Present files:</strong> $total_present</p><p><strong>Downloaded this run:</strong> $total_downloaded</p><p><strong>Missing files:</strong> <a onclick=\"toggleSection('missing-section')\">$total_missing</a></p><p><strong>Models with no files:</strong> <a onclick=\"toggleSection('nofile-section')\">$no_file_models</a></p><p><strong>Invalid JSON files:</strong> <a onclick=\"toggleSection('invalid-section')\">$invalid_json</a></p><p><strong>All files:</strong> <a onclick=\"toggleSection('allfiles-section')\">View</a></p></div>"

    # Collapsible section for all files
    echo "<button class='collapsible' onclick=\"toggleSection('allfiles-section')\">All Files</button>"
    echo "<div class='content' id='allfiles-section'>"
    cat "$HTML_TEMP"
    echo "<p><a href='#top'>Return to top</a></p></div>"

    # Collapsible section for missing files
    echo "<button class='collapsible' onclick=\"toggleSection('missing-section')\">Missing Files</button>"
    echo "<div class='content' id='missing-section'><ul>"
    for entry in "${MISSING_ENTRIES[@]}"; do
        IFS='|' read -r fname mid <<< "$entry"
        echo "<li>Model $mid — $(html_escape "$fname")</li>"
    done
    echo "</ul><p><a href='#top'>Return to top</a></p></div>"

    # Collapsible section for models with no files
    echo "<button class='collapsible' onclick=\"toggleSection('nofile-section')\">Models With No Files</button>"
    echo "<div class='content' id='nofile-section'><ul>"
    for mid in "${NO_FILE_MODELS[@]}"; do
        echo "<li>Model $mid</li>"
    done
    echo "</ul><p><a href='#top'>Return to top</a></p></div>"

    # Collapsible section for invalid JSON files
    echo "<button class='collapsible' onclick=\"toggleSection('invalid-section')\">Invalid JSON Files</button>"
    echo "<div class='content' id='invalid-section'><ul>"
    for mid in "${INVALID_JSON_FILES[@]}"; do
        echo "<li>Model $mid</li>"
    done
    echo "</ul><p><a href='#top'>Return to top</a></p></div>"

    echo "</body></html>"
} > "$HTML_OUTPUT"
fi # end GENERATE_HTML block
rm -f "$HTML_TEMP"

# Console summary
echo -e "${YELLOW}================================================${NC}"
echo -e " Expected unique files:  ${BLUE}${total_expected}${NC}"
echo -e " Present files:          ${GREEN}${total_present}${NC}"
if [[ $DOWNLOAD_MISSING -eq 1 ]]; then
echo -e "   downloaded this run:  ${GREEN}${total_downloaded}${NC}"
echo -e " Download failures:      ${RED}${download_failed}${NC}"
fi
echo -e " Missing files:          ${RED}${total_missing}${NC}"
echo -e " Models with no files:   ${YELLOW}${no_file_models}${NC}"
echo -e " Invalid JSON files:     ${YELLOW}${invalid_json}${NC}"
(( n_excluded )) && echo -e " Left out:               ${YELLOW}${n_excluded}${NC} model(s) in ${EXCLUDE_FILE}"
if [[ $IMAGES -eq 1 ]]; then
echo -e " Images:                 ${GREEN}${images_downloaded}${NC} downloaded, ${images_present} already there, ${images_absent} not on the server, ${RED}${images_failed}${NC} failed, ${images_skipped} skipped"
fi
echo -e "${YELLOW}================================================${NC}"
[[ -n "$images_stopped" ]] && echo -e "${YELLOW}Image downloads stopped early: ${images_stopped}${NC}"
(( images_failed > 0 )) && echo -e "${RED}Image failures saved to:${NC} ${YELLOW}${IMAGES_FAILED_FILE}${NC}"
(( images_listed > 0 )) && echo -e "${YELLOW}${images_listed} .JPG image(s) for your browser's download manager:${NC} ${MISSING_IMAGES_FILE} (target folders in ${MISSING_IMAGES_MAP})"
[[ -n "$stop_reason" ]] && echo -e "${YELLOW}Downloads stopped early: ${stop_reason}${NC}"
[[ $total_missing -gt 0 ]] && echo -e "${RED}Missing download URLs saved to:${NC} ${YELLOW}${OUTPUT_FILE}${NC}"
[[ $DOWNLOAD_MISSING -eq 1 && $download_failed -gt 0 ]] && echo -e "${RED}Failure details saved to:${NC} ${YELLOW}${FAILED_FILE}${NC}"
if [[ $GENERATE_ALLFILES -eq 1 ]]; then echo -e "${GREEN}Full filename list saved to:${NC} ${YELLOW}${ALL_FILES_OUTPUT}${NC}"; fi
if [[ $GENERATE_HTML -eq 1 ]]; then echo -e "${GREEN}HTML report saved to:${NC} ${YELLOW}${HTML_OUTPUT}${NC}"; fi
