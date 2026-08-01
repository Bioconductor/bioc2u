#!/bin/bash
# Report on a build directory. Works on the host as well as in a container:
#
#   bash scripts/progress.sh              # every distro under ./debs
#   bash scripts/progress.sh debs/jammy
#   bash scripts/progress.sh -w 60        # refresh every 60 seconds
# No `set -u`: empty globs are the normal case here, and this one also has to
# run on the older bash that ships with macOS.
set -o pipefail
shopt -s nullglob

WATCH=0
dirs=()
while [ $# -gt 0 ]; do
    case "$1" in
        -w|--watch) WATCH="${2:-30}"; shift; [ $# -gt 0 ] && shift ;;
        -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
        *) dirs+=("$1"); shift ;;
    esac
done

if [ ${#dirs[@]} -eq 0 ]; then
    root="${BIOC2U_DEBS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/debs}"
    for d in "$root"/*/; do dirs+=("$d"); done
    [ ${#dirs[@]} -eq 0 ] && { echo "no build directories under $root"; exit 0; }
fi

summarize() {
    local dir="${1%/}"
    if [ ! -d "$dir" ]; then
        printf '\n%s: no such directory\n' "$dir"
        return
    fi

    local all=("$dir"/*.deb)
    local bioc=("$dir"/r-bioc-*.deb)
    local done_dirs=("$dir"/done-*/)
    local fail_dirs=("$dir"/fail-*/)

    local others=() f
    for f in "${all[@]}"; do
        case "${f##*/}" in r-bioc-*) ;; *) others+=("${f##*/}") ;; esac
    done

    printf '\n%s\n' "$dir"
    printf '  debs total      : %d\n' "${#all[@]}"
    printf '  r-bioc-* debs   : %d\n' "${#bioc[@]}"
    printf '  built (done-*)  : %d\n' "${#done_dirs[@]}"
    printf '  failed (fail-*) : %d\n' "${#fail_dirs[@]}"

    if [ -s "$dir/packages.json" ] && command -v python3 >/dev/null 2>&1; then
        printf '  left in graph   : %s\n' \
            "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' \
                "$dir/packages.json" 2>/dev/null || echo '?')"
    fi

    if [ ${#others[@]} -gt 0 ]; then
        printf '  other debs      : %s\n' "${others[*]}"
    fi

    if [ ${#fail_dirs[@]} -gt 0 ]; then
        local names=()
        for f in "${fail_dirs[@]}"; do
            f="${f%/}"
            names+=("${f##*/fail-}")
        done
        if [ ${#names[@]} -gt 20 ]; then
            printf '  failures        : %s ... (+%d more)\n' \
                "${names[*]:0:20}" "$((${#names[@]} - 20))"
        else
            printf '  failures        : %s\n' "${names[*]}"
        fi
    fi
}

while :; do
    [ "$WATCH" != "0" ] && printf '\033[2J\033[H%s\n' "$(date)"
    for d in "${dirs[@]}"; do summarize "$d"; done
    echo
    [ "$WATCH" = "0" ] && break
    sleep "$WATCH"
done
