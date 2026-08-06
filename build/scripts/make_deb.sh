#!/bin/bash
# Build a single Bioconductor package into a .deb.
#
#   make_deb.sh <Package> [<bioc-version>]
#
# Everything happens in $DEBS_DIR: the built .deb stays there for later
# packages, and leftovers are filed in done-<pkg>/ or fail-<pkg>/, which is
# how a re-run knows what to skip.
#
# Not `set -e`: a failing package must reach the bookkeeping at the bottom to
# be recorded as failed rather than retried every pass.

# shellcheck source=lib.sh
source "${BIOC2U_SCRIPTS:-/opt/bioc2u/scripts}/lib.sh"

[ "${BIOC2U_TRACE:-0}" = "1" ] && set -x

PKG="$1"
BIOC_VERSION="${2:-${BIOC_VERSION:-}}"
[ -n "$PKG" ] || die "usage: make_deb.sh <Package> [<bioc-version>]"
[ -n "$BIOC_VERSION" ] || die "no Bioconductor version given"

RELEASE_BRANCH="$(release_branch "$BIOC_VERSION")"
LOG_TAIL="${BIOC2U_LOG_TAIL:-50}"

export DEBIAN_FRONTEND=noninteractive
export DEBEMAIL="${DEBEMAIL:-maintainer@bioconductor.org}"
export DEBFULLNAME="${DEBFULLNAME:-Bioconductor Core Team}"
export LOGNAME=root

cd "$DEBS_DIR" || die "$DEBS_DIR is not available"

# Only build packages that are in the Bioconductor package indexes.
grep -q "^Package: ${PKG}$" PACKAGES.* || exit 0

if [ -d "done-$PKG" ]; then
    # Already built by an earlier run; let the graph move on.
    bash "$BIOC2U_SCRIPTS/mark_done.sh" "$PKG" packages.json
    exit 0
fi
[ -d "fail-$PKG" ] && exit 0

LOG="$DEBS_DIR/$PKG-log"
echo "$PKG starting" >> "$LOG"
log "building $PKG"

PKG_VERSION=$(grep -A3 "^Package: ${PKG}$" PACKAGES.* | grep "Version: " | awk '{print $2}' | head -n 1)
# PACKAGES.bioc -> bioc, PACKAGES.annotation -> data/annotation, ...
PKG_PATH=$(grep -l "^Package: ${PKG}$" PACKAGES.* | head -n 1 | sed 's/^PACKAGES\.//')
[[ "$PKG_PATH" != *"bioc"* ]] && PKG_PATH="data/$PKG_PATH"

PKGSOURCETAR="${PKG}_${PKG_VERSION}.tar.gz"
PKGURL="https://bioconductor.org/packages/${BIOC_VERSION}/${PKG_PATH}/src/contrib/${PKGSOURCETAR}"
echo "$PKGURL" > "$PKG-url"
curl -fsSL -O "$PKGURL" >> "$LOG" 2>&1
tar -xf "$PKGSOURCETAR" >> "$LOG" 2>&1 || true

# Bioconductor dependencies, lowercased to match the r-bioc-* deb names. Every
# package also needs BiocVersion, which is what pulls in r-api-bioc-<version>.
{
    echo 'biocversion'
    sed -n "/^    \"$PKG\"/,/^    \"/p" biocdeps.json |
        grep '^        "' |
        awk -F'"' '{print $2}' |
        tr '[:upper:]' '[:lower:]'
} > "$PKG-deps"

# Install the .debs those dependencies produced earlier in this run. Only pass
# globs that resolved: one unmatched glob makes apt refuse the whole command.
dep_debs=()
missing_deps=()
while read -r dep; do
    [ -z "$dep" ] && continue
    matched=0
    for f in ./r-*-"${dep}"_*.deb; do
        [ -e "$f" ] || continue
        dep_debs+=("$f")
        matched=1
    done
    [ "$matched" = 0 ] && missing_deps+=("$dep")
done < "$PKG-deps"
[ ${#missing_deps[@]} -gt 0 ] && echo "no local deb for: ${missing_deps[*]}" >> "$LOG"
if [ ${#dep_debs[@]} -gt 0 ]; then
    apt-get install -y --allow-downgrades "${dep_debs[@]}" >> "$LOG" 2>&1
fi

if cd "$PKG"; then
    sed -i "s/git_branch: devel/git_branch: $RELEASE_BRANCH/" DESCRIPTION

    # Must run before dh-make-R reads DESCRIPTION; see lib.sh for what this
    # fixes and why it happens there.
    normalise_r_version_constraints DESCRIPTION >> "$LOG" 2>&1

    dh-make-R --repo bioc >> "$LOG" 2>&1
    dh-update-R >> "$LOG" 2>&1

    install_cmd="apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends -y"
    if ! mk-build-deps --install --tool "${install_cmd}" debian/control >> "$LOG" 2>&1; then
        # Not fatal: the builder image often already holds what is needed. But
        # a later in-R failure names the wrong packages, so record the
        # unresolved Build-Depends while the real cause is known.
        {
            echo "BUILD-DEPS UNRESOLVED for $PKG: apt could not satisfy Build-Depends."
            echo "Any 'dependencies ... are not available' error below may name"
            echo "unrelated packages; the cause is in the field printed here."
            awk '/^Build-Depends:/ {p=1; print; next} p && /^[[:space:]]/ {print; next} p {exit}' \
                debian/control
        } >> "$LOG"
    fi

    # The Provides is also set on the built .deb below; dh-r rewrites Depends
    # after this point, so the control file is not the last word.
    [ "$PKG" = "BiocVersion" ] && sed -i "/Suggests:/ a\\Provides: r-api-bioc-$BIOC_VERSION" debian/control
    sed -i "s|Maintainer: Debian R Packages Maintainers <r-pkg-team@alioth-lists.debian.net>|Maintainer: $DEBFULLNAME <$DEBEMAIL>|" debian/control

    apt-get -y build-dep . >> "$LOG" 2>&1
    dpkg-buildpackage -us -uc -d -b >> "$LOG" 2>&1
    cd ..
fi

ls r-*-"$(echo "$PKG" | tr '[:upper:]' '[:lower:]')"_*.deb > "$PKG-debname" 2>/dev/null

if [ -s "$PKG-debname" ]; then
    DEBNAME=$(head -n 1 "$PKG-debname")
    log "DONE $PKG -> $DEBNAME"
    chmod 644 "./$DEBNAME"

    # The seed cannot depend on the ABI it defines; strip the one dh-r
    # inherited from the builder's own BiocVersion. See lib.sh.
    if [ "$PKG" = "BiocVersion" ]; then
        fix_biocversion_deb "./$DEBNAME" "$BIOC_VERSION" "${BIOC2U_ALSO_PROVIDE_ABI:-}" ||
            die "could not rewrite $DEBNAME"
        assert_biocversion_deb "./$DEBNAME" "$BIOC_VERSION"
    fi
    # Install it right away: the packages built after this one need it present.
    apt-get install -y "./$DEBNAME" >> "$LOG" 2>&1
    cp -r "$PKG/debian" "$PKG-debian"
    rm -rf "${DEBS_DIR:?}/$PKG"
    bash "$BIOC2U_SCRIPTS/mark_done.sh" "$PKG" packages.json
    mkdir -p "done-$PKG"
    mv "$PKG"* "done-$PKG"/
else
    log "FAILED $PKG (log: $LOG -> fail-$PKG/$PKG-log)"
    if [ "$LOG_TAIL" != "0" ]; then
        tail -n "$LOG_TAIL" "$LOG" >&2
    fi
    mkdir -p "fail-$PKG"
    mv "$PKG"* "fail-$PKG"/
fi
