#!/bin/bash
# ================================================================
# Loot Studios - re-sort models extracted with earlier layouts of 99_loot_extract_all.sh
#
# The layout now is (like Heroes Infinite):
#   <bundle>/<group>/<Model>/images/                   the model's pictures
#   <bundle>/<group>/<Model>/files/<scale>/<type>/     e.g. ShadowCourt/Enemies/DeathGiant/files/32mm/lychee/
#   <bundle>/<group>/<Model>-FDM/images/ and files/... FDM files, e.g. .../DeathGiant-FDM/files/32mm/3mf/
#
# This script moves what earlier versions made into it:
#   first version:  <Model>-lychee/32mm/ (and -supported, -hollow, -solid, -chitubox,
#                   -unsupported)                     -> <Model>/files/32mm/lychee/
#                   <Model>-3mf/32mm/                 -> <Model>-FDM/files/32mm/3mf/
#                   <Model>-fdm/32mm/                 -> <Model>-FDM/files/32mm/unsupported/
#                   FDM files in <Model>-unsupported ("..._FDM.stl") -> <Model>-FDM/files/32mm/unsupported/
#   second version: <Model>/32mm/lychee/              -> <Model>/files/32mm/lychee/
#   pictures:       <group>/images/ and the downloader's Images/<group>/ -> <Model>/images/,
#                   matched by name ("Bell Head - render resin.png" -> BellHead,
#                   "DeathGiant.png" -> DeathGiant, "... fdm" pictures -> <Model>-FDM if it exists);
#                   pictures that match no model stay in (or go to) <group>/images/
# Nothing is overwritten: a file whose name is already taken by a different file stays where it
# is (and is listed). Running it again is harmless.
#
# Run it with DRY_RUN=1 (the default) first: it only shows what it would move.
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;94m'
NC='\033[0m'

# ==============================
# SETTINGS
# ==============================
# Where the Loot Studios bundles are (same as LOOT_DIR in 99_loot_extract_all.sh).
# Empty = the folder this script is in.
LOOT_DIR=""
DRY_RUN=1                # 1 = only show what would be moved; 0 = move
PROBLEMS_FILE="loot_fix_extracted_problems.txt"
# ==============================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "$LOOT_DIR" ]] && LOOT_DIR="$script_dir"
[[ "$LOOT_DIR" != /* ]] && LOOT_DIR="$script_dir/$LOOT_DIR"
LOOT_DIR="${LOOT_DIR%/}"

echo -e "${BLUE}Loot Studios - re-sort extracted models into <Model>/images/ and <Model>/files/<scale>/<type>/${NC}"
printf "Folder:  ${YELLOW}%s${NC}\n" "$LOOT_DIR"
[[ -d "$LOOT_DIR" ]] || { echo -e "${RED}Folder not found: $LOOT_DIR${NC}"; exit 1; }
(( DRY_RUN )) && printf "         ${YELLOW}DRY RUN - nothing is changed (set DRY_RUN=0 to do it)${NC}\n"
echo ""

shopt -s dotglob nullglob
OLD_RE='^(.+)-(lychee|supported|hollow|solid|unsupported|chitubox|fdm|3mf)$'
SCALE_RE='^([0-9]+mm|bust|prop|epicscale|statue)$'
FDM_FILE_RE='(^|[_ .(-])fdm([_ .)-]|$)'
IMAGE_RE='\.(png|jpe?g|gif|webp)$'
rel() { printf '%s' "${1#"$LOOT_DIR/"}"; }
norm() { NORM="${1,,}"; NORM="${NORM//[^a-z0-9]/}"; }
group_key() {   # same as in 99_loot_extract_all.sh: case, plural and "Enviroment" don't matter
    norm "$1"; GKEY="$NORM"
    [[ "$GKEY" == enviroment* ]] && GKEY="environment${GKEY#enviroment}"
    (( ${#GKEY} > 3 )) && GKEY="${GKEY%s}"
}

moved=0; same=0; kept=0; v1=0; v2=0; n_files=0; pics=0; pics_model=0
(( DRY_RUN )) || : > "$PROBLEMS_FILE"
problem() { kept=$((kept + 1)); (( DRY_RUN )) || printf '%s\t%s\n' "$1" "$2" >> "$PROBLEMS_FILE"; }

# place FILE DESTDIR - move FILE into DESTDIR without overwriting (identical copy there: drop FILE)
place() {
    local f="$1" dst="$2" b="${1##*/}"
    if [[ -e "$dst/$b" ]]; then
        if cmp -s -- "$f" "$dst/$b"; then rm -f -- "$f"; same=$((same + 1))
        else problem "$(rel "$f")" "a different file is already at $(rel "$dst")/$b"; fi
        return
    fi
    mkdir -p -- "$dst" && mv -- "$f" "$dst/$b" && moved=$((moved + 1))
}

# move_dir SRC DEST - move folder SRC to DEST (all at once if DEST doesn't exist yet, else file
# by file without overwriting). With SPLIT_FDM set, files named "..._FDM..." go to SPLIT_FDM.
move_dir() {
    local src="$1" dst="$2" f r d nf
    if [[ ! -e "$dst" && -z "$SPLIT_FDM" ]]; then
        nf=$(find "$src" -type f | wc -l); n_files=$((n_files + nf))
        (( DRY_RUN )) && return
        mkdir -p -- "${dst%/*}" && mv -- "$src" "$dst" && moved=$((moved + nf))
        return
    fi
    while IFS= read -r -d '' f; do
        r="${f#"$src/"}"; d="${r%/*}"; [[ "$d" == "$r" ]] && d=""
        n_files=$((n_files + 1))
        (( DRY_RUN )) && continue
        shopt -s nocasematch
        if [[ -n "$SPLIT_FDM" && "${f##*/}" =~ $FDM_FILE_RE ]]; then shopt -u nocasematch; place "$f" "$SPLIT_FDM${d:+/$d}"
        else shopt -u nocasematch; place "$f" "$dst${d:+/$d}"; fi
    done < <(find "$src" -type f -print0)
    (( DRY_RUN )) || find "$src" -depth -type d -empty -delete 2>/dev/null
}

show() { printf "  ${BLUE}->${NC} %s  =>  %s/\n" "$(rel "$1")" "$(rel "$2")"; }

for b in "$LOOT_DIR"/*/; do
    b="${b%/}"; [[ "${b##*/}" == .* ]] && continue

    # ---------- first version: <Model>-<type>/<scale>/ ----------
    for o in "$b"/*/ "$b"/*/*/; do
        o="${o%/}"; [[ -d "$o" ]] || continue
        name="${o##*/}"
        [[ "$name" =~ $OLD_RE ]] || continue
        model="${BASH_REMATCH[1]}"; type="${BASH_REMATCH[2]}"
        parent="${o%/*}"
        [[ "${parent##*/}" =~ $OLD_RE ]] && continue
        v1=$((v1 + 1))
        newtype="$type"; fdm=0
        case "$type" in 3mf) fdm=1 ;; fdm) fdm=1; newtype=unsupported ;; esac
        if (( fdm )); then base="$parent/$model-FDM"; else base="$parent/$model"; fi
        orig="$o"
        # work from a temporary name: on network shares that ignore case, the new "<Model>-FDM"
        # is the same folder as the old "<Model>-fdm"
        if (( ! DRY_RUN )); then
            hold="$parent/.fixing_${v1}_$$"
            mv -- "$o" "$hold" || { printf "  ${RED}could not rename %s - skipped${NC}\n" "$(rel "$o")"; continue; }
            o="$hold"
        fi
        for c in "$o"/*; do
            cn="${c##*/}"
            if [[ -d "$c" && "${cn,,}" =~ $SCALE_RE ]]; then
                dst="$base/files/$cn/$newtype"; fdmdst="$parent/$model-FDM/files/$cn/unsupported"
            else
                dst="$base/files/$newtype"; fdmdst="$parent/$model-FDM/files/unsupported"
                [[ -d "$c" ]] && { dst="$dst/$cn"; fdmdst="$fdmdst/$cn"; }
            fi
            SPLIT_FDM=""; [[ "$type" == unsupported ]] && SPLIT_FDM="$fdmdst"
            printf "  ${BLUE}->${NC} %s  =>  %s/\n" "$(rel "$orig")/$cn" "$(rel "$dst")"
            if [[ -d "$c" ]]; then move_dir "$c" "$dst"
            else
                n_files=$((n_files + 1))
                if (( ! DRY_RUN )); then
                    shopt -s nocasematch
                    if [[ -n "$SPLIT_FDM" && "$cn" =~ $FDM_FILE_RE ]]; then shopt -u nocasematch; place "$c" "$SPLIT_FDM"
                    else shopt -u nocasematch; place "$c" "$dst"; fi
                fi
            fi
        done
        SPLIT_FDM=""
        if (( ! DRY_RUN )); then
            find "$o" -depth -type d -empty -delete 2>/dev/null
            if [[ -d "$o" ]]; then        # files that couldn't be moved: back under the old name
                back="$orig"; [[ -e "$back" ]] && back="$orig (left over)"
                mv -- "$o" "$back"
            fi
        fi
    done

    # ---------- second version: <Model>/<scale>/<type>/ ----------
    for m in "$b"/*/ "$b"/*/*/; do
        m="${m%/}"; [[ -d "$m" ]] || continue
        mn="${m##*/}"
        [[ "$mn" == .* || "${mn,,}" == images || "${mn,,}" == files || "${mn,,}" =~ $SCALE_RE || "$mn" =~ $OLD_RE ]] && continue
        found=0
        for s in "$m"/*/; do
            s="${s%/}"; sn="${s##*/}"
            [[ "${sn,,}" =~ $SCALE_RE ]] || continue
            (( found )) || { v2=$((v2 + 1)); found=1; }
            show "$s" "$m/files/$sn"
            SPLIT_FDM=""; move_dir "$s" "$m/files/$sn"
        done
    done

    # ---------- pictures -> <Model>/images/ ----------
    # model folders (holding files/) of this bundle: normalized name -> "<group>/<Model>|..."
    declare -A MODEL_AT=()
    for d in "$b"/*/files/ "$b"/*/*/files/; do
        d="${d%/files/}"; d="${d#"$b/"}"; norm "${d##*/}"
        MODEL_AT[$NORM]="${MODEL_AT[$NORM]:+${MODEL_AT[$NORM]}|}$d"
    done
    if (( DRY_RUN )); then
        # in a dry run nothing was moved: count the models of the earlier layouts too
        for d in "$b"/*/*/ "$b"/*/; do
            d="${d%/}"; n="${d##*/}"
            if [[ "$n" =~ $OLD_RE ]]; then n="${BASH_REMATCH[1]}"; [[ "${BASH_REMATCH[2]}" == 3mf || "${BASH_REMATCH[2]}" == fdm ]] && n="$n-FDM"
            else local_has=0; for s in "$d"/*/; do s="${s%/}"; [[ "${s##*/}" =~ $SCALE_RE ]] && { local_has=1; break; }; done; (( local_has )) || continue; fi
            p="${d%/*}"; p="${p#"$b"}"; p="${p#/}"
            norm "$n"; [[ "|${MODEL_AT[$NORM]}|" == *"|${p:+$p/}$n|"* ]] && continue
            MODEL_AT[$NORM]="${MODEL_AT[$NORM]:+${MODEL_AT[$NORM]}|}${p:+$p/}$n"
        done
    fi
    for f in "$b"/*/images/* "$b"/images/* "$b"/Images/*/*; do
        [[ -f "$f" && "${f,,}" =~ $IMAGE_RE ]] || continue
        fr="${f#"$b/"}"
        if [[ "$fr" == Images/* ]]; then g="${fr#Images/}"; g="${g%%/*}"
        elif [[ "$fr" == */images/* ]]; then g="${fr%%/*}"
        else g=""; fi
        # which model? (same rules as 99_loot_extract_all.sh)
        s="${f##*/}"; s="${s%.*}"; mat=""; PM=""
        while [[ "$s" =~ ^(.*)\&#[0-9]+\;(.*)$ ]]; do s="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
        if [[ "$s" =~ ^(.+)[[:space:]]-[[:space:]](render|painted)[[:space:]](resin|fdm)$ ]]; then s="${BASH_REMATCH[1]}"; mat="${BASH_REMATCH[3]}"; fi
        [[ "$s" =~ ^(.+)_[0-9]+$ ]] && s="${BASH_REMATCH[1]}"
        norm "$s"; k="$NORM"
        cands="$k"; [[ "$k" == *bust ]] && cands+=" ${k%bust}"
        [[ "$mat" == fdm ]] && { fc=""; for c in $cands; do fc+="${c}fdm "; done; cands="$fc$cands"; }
        group_key "$g"; gk="$GKEY"
        for c in $cands; do
            [[ -n "$k" && -n "${MODEL_AT[$c]}" ]] || continue
            if [[ "${MODEL_AT[$c]}" != *"|"* ]]; then PM="${MODEL_AT[$c]}"; break; fi
            IFS='|' read -r -a cand <<< "${MODEL_AT[$c]}"
            for x in "${cand[@]}"; do group_key "${x%%/*}"; [[ "$GKEY" == "$gk" ]] && { PM="$x"; break; }; done
            break
        done
        if [[ -n "$PM" ]]; then dst="$b/$PM/images"; pics_model=$((pics_model + 1))
        elif [[ "$fr" == Images/* ]]; then dst="$b/$g/images"       # downloader picture, no model: the group's images/
        else continue; fi                                            # already in a group's images/: leave it
        pics=$((pics + 1))
        (( DRY_RUN )) && continue
        place "$f" "$dst"
    done
    if (( ! DRY_RUN )) && [[ -d "$b/Images" ]]; then
        find "$b/Images" -depth -mindepth 1 -type d -empty -delete 2>/dev/null
        rmdir -- "$b/Images" 2>/dev/null
        for d in "$b"/*/images/; do rmdir -- "${d%/}" 2>/dev/null; done   # emptied group images/
    fi
    unset MODEL_AT
done

echo ""
echo -e "${YELLOW}================================================${NC}"
echo -e " First-version folders:  ${BLUE}${v1}${NC} (<Model>-<type>/)"
echo -e " Second-version models:  ${BLUE}${v2}${NC} (<Model>/<scale>/)"
echo -e " Pictures to sort:       ${BLUE}${pics}${NC} (${pics_model} into their model's images/)"
if (( DRY_RUN )); then
    echo -e " Files to move:          ${GREEN}${n_files}${NC}"
else
    echo -e " Files moved:            ${GREEN}$((moved))${NC}"
    (( same )) && echo -e " Duplicates dropped:     ${same} (identical file already in the new place)"
    echo -e " Left in place:          ${RED}${kept}${NC}$( (( kept )) && echo " - a different file with the same name was already there; see $PROBLEMS_FILE")"
fi
echo -e "${YELLOW}================================================${NC}"
if (( DRY_RUN )); then echo -e "${YELLOW}Dry run - nothing was changed.${NC} If this looks right, set DRY_RUN=0 and run it again."
elif (( ! kept )); then rm -f "$PROBLEMS_FILE"; fi
