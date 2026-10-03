#!/bin/bash

# MyMiniFactory Model Metadata Downloader
# Downloads JSON metadata for a list of model IDs from the MyMiniFactory API

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;94m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ==============================
# CONFIG
# ==============================
# Where the JSON metadata is saved. Empty = the "downloads" folder next to this
# script. To use another folder, put its full path here, e.g. "/mnt/nas/MyMiniFactory/downloads".
JSON_OUTPUT_DIR=""

# Cookie: leave empty to use cookie.txt next to this script (same file as
# 3_mmf_check_and_download.sh), or set the MMF_COOKIE environment variable. Never share it.
COOKIE=''
COOKIE_FILE="cookie.txt"

# User agent: MUST match the browser the cookie came from (run navigator.userAgent
# in its console). Leave empty to use user_agent.txt next to this script, or set
# the MMF_USER_AGENT environment variable.
USER_AGENT=''
USER_AGENT_FILE="user_agent.txt"

DELAY_SECONDS=3

# Models to leave out: one ID per line ("# ..." = comment), in the current folder or next to
# this script. Also used by 3_mmf_check_and_download.sh.
EXCLUDE_FILE="exclude_models.txt"
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "$JSON_OUTPUT_DIR" ]] && JSON_OUTPUT_DIR="$script_dir/downloads"

# Look for cookie and user agent: script setting, then environment variable, then file
[[ -z "$COOKIE" && -n "$MMF_COOKIE" ]] && COOKIE="$MMF_COOKIE"
[[ -z "$COOKIE" && -f "$script_dir/$COOKIE_FILE" ]] && COOKIE="$(tr -d '\r\n' < "$script_dir/$COOKIE_FILE")"
[[ -z "$USER_AGENT" && -n "$MMF_USER_AGENT" ]] && USER_AGENT="$MMF_USER_AGENT"
[[ -z "$USER_AGENT" && -f "$script_dir/$USER_AGENT_FILE" ]] && USER_AGENT="$(tr -d '\r\n' < "$script_dir/$USER_AGENT_FILE")"
USER_AGENT="${USER_AGENT#\"}"; USER_AGENT="${USER_AGENT%\"}"   # strip quotes copied from the console

if [[ -z "$COOKIE" ]]; then
    echo -e "${RED}Error: no cookie set (COOKIE, $COOKIE_FILE, or MMF_COOKIE).${NC}"
    exit 1
fi
if [[ -z "$USER_AGENT" ]]; then
    echo -e "${RED}Error: no user agent set (USER_AGENT, $USER_AGENT_FILE, or MMF_USER_AGENT). Run navigator.userAgent in your browser console.${NC}"
    exit 1
fi
ids_file="model_ids.txt"   # in the current folder, or next to this script
[[ ! -f "$ids_file" && -f "$script_dir/$ids_file" ]] && ids_file="$script_dir/$ids_file"
if [[ ! -f "$ids_file" ]]; then
    echo -e "${RED}Error: model_ids.txt not found!${NC}"
    echo "Create a file with one model ID per line."
    exit 1
fi

# Read IDs robustly: handles a missing final newline, Windows line endings,
# a UTF-8 BOM (Notepad), stray spaces, and non-numeric lines.
ids=()
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    line="${line#$'\xEF\xBB\xBF'}"
    line="${line//[[:space:]]/}"
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^[0-9]+$ ]]; then
        ids+=("$line")
    else
        echo -e "${YELLOW}Skipping invalid line: '$line'${NC}"
    fi
done < "$ids_file"

# Leave out the models listed in exclude_models.txt (an ID, a model URL or a "<id>_<name>"
# folder name per line; "# ..." = comment)
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
if (( ${#excluded[@]} )); then
    kept=()
    for id in "${ids[@]}"; do
        if [[ -n "${excluded[$id]}" ]]; then n_excluded=$((n_excluded + 1)); else kept+=("$id"); fi
    done
    ids=("${kept[@]}")
    (( n_excluded )) && echo -e "${YELLOW}Leaving out $n_excluded model(s) listed in $EXCLUDE_FILE${NC}"
fi

total=${#ids[@]}
if (( total == 0 )); then
    echo -e "${RED}No valid IDs found in model_ids.txt${NC}"
    exit 1
fi

# Private models (made private by the creator, or taken off sale) are still in your library,
# but the API answers 404 for them, and MyMiniFactory's bot check blocks scripts from the
# library's own API. browser/99_mmf_private_models.js reads their file lists in your browser
# and you save them as private_models.json (next to model_ids.txt); they're taken from there.
private_file="private_models.json"
[[ ! -f "$private_file" && -f "$script_dir/$private_file" ]] && private_file="$script_dir/$private_file"
if [[ -f "$private_file" ]]; then
    private_file="$(cd "$(dirname "$private_file")" && pwd)/$(basename "$private_file")"
    if jq -e 'type == "object"' "$private_file" >/dev/null 2>&1; then
        echo "Private models: using $(jq 'length' "$private_file") file list(s) from private_models.json"
    else
        echo -e "${YELLOW}private_models.json is not valid JSON - ignored (save it again from the browser snippet).${NC}"
        private_file=""
    fi
else
    private_file=""
fi

mkdir -p "$JSON_OUTPUT_DIR"
cd "$JSON_OUTPUT_DIR" || exit 1
: > failed_ids.txt

echo -e "${BLUE}Starting download of $total model metadata files...${NC}"
echo "JSON files will be saved in: '$JSON_OUTPUT_DIR'"
echo "Waiting ${DELAY_SECONDS}s between requests"
echo ""

current=0
ok=0
fail=0
from_library=0
not_public=0

# Write model_<id>.json from private_models.json. Returns 0 if it had a file list for this ID.
from_private_file() {
    [[ -n "$private_file" ]] || return 1
    jq -e --arg id "$1" '.[$id] | select(.files.total_count > 0)' "$private_file" > "model_$1.json.tmp" 2>/dev/null \
        && mv -f "model_$1.json.tmp" "model_$1.json" && return 0
    rm -f "model_$1.json.tmp"; return 1
}

for id in "${ids[@]}"; do
    current=$((current + 1))
    echo -e "${BLUE}[$current/$total] Model $id...${NC}"

    # Already in private_models.json: no need to ask the API (it would answer 404)
    if from_private_file "$id"; then
        rm -f "error_${id}.txt"
        echo -e "${GREEN}  OK${NC} (private model - file list from private_models.json)"
        ok=$((ok + 1)); from_library=$((from_library + 1))
        continue
    fi

    # Note: no hand-written Accept-Encoding header. --compressed requests only
    # the encodings this curl build can decode (many Windows builds lack br/zstd).
    http_code=$(curl --silent --show-error --location --compressed \
        -H "User-Agent: $USER_AGENT" \
        -H "Accept: application/json" \
        -H "Accept-Language: en-US,en;q=0.5" \
        -H "Referer: https://www.myminifactory.com/api-doc/index.html" \
        -H "Cookie: $COOKIE" \
        -o "model_${id}.json" \
        -w "%{http_code}" \
        "https://www.myminifactory.com/api/v2/objects/$id")
    curl_exit=$?

    first_char=$(head -c 1 "model_${id}.json" 2>/dev/null)

    if [[ $curl_exit -eq 0 && "$http_code" == "200" && "$first_char" == "{" ]]; then
        echo -e "${GREEN}  OK${NC}"
        ok=$((ok + 1))
    else
        fail=$((fail + 1))
        echo "$id" >> failed_ids.txt
        if [[ $curl_exit -eq 0 && "$http_code" == "404" ]]; then
            # The usual reason: the model is private now (or was removed) - see private_models.json
            not_public=$((not_public + 1))
            echo -e "${RED}  FAILED (HTTP 404 - private or removed model)${NC}"
            mv -f "model_${id}.json" "error_${id}.txt" 2>/dev/null
            if (( current < total )); then sleep "$DELAY_SECONDS"; fi
            continue
        fi
        echo -e "${RED}  FAILED (curl exit $curl_exit, HTTP $http_code)${NC}"
        if [[ -s "model_${id}.json" ]]; then
            mv "model_${id}.json" "error_${id}.txt"
            echo "  Response starts with:"
            head -c 200 "error_${id}.txt" | tr -d '\r' | sed 's/^/    /'
            echo ""
        else
            rm -f "model_${id}.json"
        fi
    fi

    if (( current < total )); then
        sleep "$DELAY_SECONDS"
    fi
done

echo ""
echo -e "${GREEN}Done. $ok succeeded, $fail failed.${NC}"
(( n_excluded > 0 )) && echo "$n_excluded model(s) left out (listed in $EXCLUDE_FILE)."
(( from_library > 0 )) && echo "$from_library of them are private models; their file lists came from private_models.json."
if (( fail > 0 )); then
    echo "Failed IDs are listed in '$JSON_OUTPUT_DIR/failed_ids.txt'."
    echo "Server responses for failures are saved as error_<id>.txt."
fi
if (( not_public > 0 )); then
    echo ""
    echo -e "${YELLOW}$not_public model(s) answered HTTP 404: usually models the creator has made private (they're still in your library).${NC}"
    echo "To get them: paste the IDs from failed_ids.txt into browser/99_mmf_private_models.js, run it in the"
    echo "Console on myminifactory.com/library, save the result as private_models.json next to model_ids.txt,"
    echo "and run this script again (with failed_ids.txt as model_ids.txt)."
fi
echo -e "${BLUE}Next step: run 3_mmf_check_and_download.sh to find the missing files.${NC}"
