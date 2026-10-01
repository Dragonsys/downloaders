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
# Root folder for all downloads. Set the PRINTS_DIR environment variable
# (e.g. in ~/.bashrc: export PRINTS_DIR=/mnt/nas/3DPrints) or change the default here.
PRINTS_DIR="${PRINTS_DIR:-$HOME/3DPrints}"
JSON_OUTPUT_DIR="$PRINTS_DIR/.mmf_downloads/downloads"   # where the JSON metadata is saved

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
# ==============================

# Look for cookie and user agent: script setting, then environment variable, then file
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
if [[ ! -f "model_ids.txt" ]]; then
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
done < model_ids.txt

total=${#ids[@]}
if (( total == 0 )); then
    echo -e "${RED}No valid IDs found in model_ids.txt${NC}"
    exit 1
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

for id in "${ids[@]}"; do
    current=$((current + 1))
    echo -e "${BLUE}[$current/$total] Model $id...${NC}"

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
if (( fail > 0 )); then
    echo "Failed IDs are listed in '$JSON_OUTPUT_DIR/failed_ids.txt'."
    echo "Server responses for failures are saved as error_<id>.txt."
fi
echo -e "${BLUE}Next step: run 3_mmf_check_and_download.sh to find the missing files.${NC}"
