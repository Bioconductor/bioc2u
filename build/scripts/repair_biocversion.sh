#!/usr/bin/env bash
# Repair an already-built BiocVersion .deb, without rebuilding anything.
#
#   DEBS=debs bash scripts/repair_biocversion.sh
#
# For a BiocVersion deb built without the correction make_deb.sh applies.
# Control-file surgery only; bumps the Debian revision so the result
# supersedes what is published. Safe to re-run: a deb with no ABI dependency
# is left alone.
#
# By default BiocVersion provides only the release it defines. KEEP_PREV=1
# also provides the ABI the deb wrongly depended on, a temporary unblock that
# keeps carried-over packages installable. See ../../docs/operations.md.
set -euo pipefail
shopt -s nullglob

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

DEBS=${DEBS:-debs}
KEEP_PREV=${KEEP_PREV:-0}

found=0
for deb in "$DEBS"/*/r-bioc-biocversion_*_all.deb; do
    found=1
    echo "== $deb"
    prev=$(dpkg-deb -f "$deb" Depends | sed -n 's/.*\(r-api-bioc-[0-9.]\+\).*/\1/p')
    if [ -z "$prev" ]; then
        echo "   already correct, skipping"
        continue
    fi

    ver=$(dpkg-deb -f "$deb" Version)
    release=$(cut -d. -f1,2 <<<"$ver")
    new="${ver%-*}-$(( ${ver##*-} + 1 ))"
    also=""
    [ "$KEEP_PREV" = 1 ] && [ "$prev" != "r-api-bioc-$release" ] && also="$prev"

    out="${deb%/*}/r-bioc-biocversion_${new}_all.deb"
    cp "$deb" "$out"
    fix_biocversion_deb "$out" "$release" "$also" || die "could not rewrite $out"

    tmp=$(mktemp -d); dpkg-deb -R "$out" "$tmp"
    sed -i "s/^Version: ${ver}\$/Version: ${new}/" "$tmp/DEBIAN/control"
    dpkg-deb -b "$tmp" "$out" >/dev/null; rm -rf "$tmp"

    assert_biocversion_deb "$out" "$release"
    rm -f "$deb"
    dpkg-deb -f "$out" Version Depends Provides | sed 's/^/   /'
done

[ "$found" = 1 ] || die "no r-bioc-biocversion_*_all.deb under $DEBS/*/"
echo
echo "Re-upload so the index is regenerated:  docker compose run --rm <codename>-upload"
