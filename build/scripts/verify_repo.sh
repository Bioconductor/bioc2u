#!/usr/bin/env bash
# Check that the published bioc2u repository installs on a clean machine.
#
# Run in a blank Ubuntu container - it must not inherit anything from a build
# host, since the failure this catches only shows on a clean machine:
#
#   docker run --rm -v "$PWD/scripts/verify_repo.sh:/v.sh:ro" ubuntu:noble bash /v.sh
#
# BIOC     release to set up (default 3.23)
# NEW_PKG  a package stamped with the current ABI
# OLD_PKG  a package carried over from the previous release, if any
set -uo pipefail

BIOC=${BIOC:-3.23}
NEW_PKG=${NEW_PKG:-r-bioc-deseq2}
OLD_PKG=${OLD_PKG:-}
SETUP_URL=${SETUP_URL:-https://raw.githubusercontent.com/Bioconductor/bioc2u/devel/apt_setup.sh}

fail=0
ok()  { echo "  [ ok ] $*"; }
bad() { echo "  [FAIL] $*"; fail=1; }

apt-get update -qq >/dev/null 2>&1
apt-get install -y --no-install-recommends curl ca-certificates >/dev/null 2>&1
curl -fsSL -o /tmp/apt_setup.sh "$SETUP_URL" || { echo "cannot fetch apt_setup.sh"; exit 2; }
bash /tmp/apt_setup.sh "$BIOC" >/tmp/setup.log 2>&1 || bad "apt_setup.sh exited non-zero"

echo "== 1. the BiocVersion apt will pick"
# apt-cache show prints every version; pin to the candidate so Depends and
# Provides come from the same stanza.
cand=$(apt-cache policy r-bioc-biocversion 2>/dev/null | awk '/Candidate:/{print $2}')
if [ -z "$cand" ] || [ "$cand" = "(none)" ]; then
    bad "no BiocVersion candidate - is the repository configured?"
else
    stanza=$(apt-cache show "r-bioc-biocversion=$cand" 2>/dev/null)
    dep=$(awk '/^Depends:/{print substr($0,10); exit}'  <<<"$stanza")
    prov=$(awk '/^Provides:/{print substr($0,11); exit}' <<<"$stanza")
    echo "     candidate $cand"
    echo "     Depends:  $dep"
    echo "     Provides: $prov"
    case "$dep"  in *r-api-bioc-*) bad "BiocVersion depends on an ABI" ;;
                    *) ok "no r-api-bioc in Depends" ;; esac
    case "$prov" in *"r-api-bioc-$BIOC"*) ok "provides r-api-bioc-$BIOC" ;;
                    *) bad "does not provide r-api-bioc-$BIOC" ;; esac
fi

echo "== 2. does apt resolve?"
for p in $NEW_PKG $OLD_PKG; do
    n=$(apt-get install -s --no-install-recommends "$p" 2>/dev/null | grep -c '^Inst ')
    if [ "$n" -gt 0 ]; then ok "$p -> $n packages"
    else
        bad "$p -> unresolvable"
        apt-get install -s --no-install-recommends "$p" 2>&1 |
            grep -E 'Depends:|^E:' | head -2 | sed 's/^/       /'
    fi
done

echo "== 3. does it install and load for real?"   # dpkg enforces deps; apt -s does not
if apt-get install -y --no-install-recommends "$NEW_PKG" >/tmp/inst.log 2>&1; then
    # Deb names are lowercased; library() needs the R package's own name.
    lib=$(dpkg -L "$NEW_PKG" 2>/dev/null | sed -n 's#.*/site-library/\([^/]*\)/DESCRIPTION$#\1#p' | head -n 1)
    lib=${lib:-${NEW_PKG#r-bioc-}}
    v=$(Rscript -e "suppressMessages(library($lib)); cat(as.character(packageVersion('$lib')))" 2>&1 | tail -1)
    case "$v" in [0-9]*) ok "library($lib) works, version $v" ;;
                 *) bad "installed but will not load: $v" ;; esac
else
    bad "apt install failed"
    tail -3 /tmp/inst.log | sed 's/^/       /'
fi

echo
[ "$fail" = 0 ] && echo "PASS" || echo "FAIL"
exit "$fail"
