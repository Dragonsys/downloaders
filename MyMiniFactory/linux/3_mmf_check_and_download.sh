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
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "$JSON_DIR" ]] && JSON_DIR="$script_dir/downloads"
[[ -z "$DOWNLOAD_DIR" ]] && DOWNLOAD_DIR="$script_dir/models"

# Remove trailing slashes so paths don't contain "//"
JSON_DIR="${JSON_DIR%/}"
DOWNLOAD_DIR="${DOWNLOAD_DIR%/}"

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

# Download setup
if [[ $DOWNLOAD_MISSING -eq 1 ]]; then
    command -v curl &> /dev/null || { echo -e "${RED}Error: curl not installed.${NC}"; exit 1; }
    [[ -z "$COOKIE" && -n "$MMF_COOKIE" ]] && COOKIE="$MMF_COOKIE"
    [[ -z "$COOKIE" && -f "$script_dir/$COOKIE_FILE" ]] && COOKIE="$(tr -d '\r\n' < "$script_dir/$COOKIE_FILE")"
    [[ -z "$COOKIE" ]] && { echo -e "${RED}Error: no cookie set (COOKIE, $COOKIE_FILE, or MMF_COOKIE).${NC}"; exit 1; }
    [[ -z "$USER_AGENT" && -n "$MMF_USER_AGENT" ]] && USER_AGENT="$MMF_USER_AGENT"
    [[ -z "$USER_AGENT" && -f "$script_dir/$USER_AGENT_FILE" ]] && USER_AGENT="$(tr -d '\r\n' < "$script_dir/$USER_AGENT_FILE")"
    USER_AGENT="${USER_AGENT#\"}"; USER_AGENT="${USER_AGENT%\"}"   # strip quotes copied from the console
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

> "$OUTPUT_FILE"
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

# HTML table start
echo "<table>" >> "$HTML_TEMP"

for json_file in "${json_files[@]}"; do
    model_id=$(basename "$json_file" .json)
    model_id="${model_id#model_}"
    model_dir="${DOWNLOAD_DIR}/model_${model_id}"

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
echo -e "${YELLOW}================================================${NC}"
[[ -n "$stop_reason" ]] && echo -e "${YELLOW}Downloads stopped early: ${stop_reason}${NC}"
[[ $total_missing -gt 0 ]] && echo -e "${RED}Missing download URLs saved to:${NC} ${YELLOW}${OUTPUT_FILE}${NC}"
[[ $DOWNLOAD_MISSING -eq 1 && $download_failed -gt 0 ]] && echo -e "${RED}Failure details saved to:${NC} ${YELLOW}${FAILED_FILE}${NC}"
if [[ $GENERATE_ALLFILES -eq 1 ]]; then echo -e "${GREEN}Full filename list saved to:${NC} ${YELLOW}${ALL_FILES_OUTPUT}${NC}"; fi
if [[ $GENERATE_HTML -eq 1 ]]; then echo -e "${GREEN}HTML report saved to:${NC} ${YELLOW}${HTML_OUTPUT}${NC}"; fi
