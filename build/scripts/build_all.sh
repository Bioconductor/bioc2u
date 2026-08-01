#!/bin/bash
# Build .debs for the whole Bioconductor package graph, in dependency order.
# packages.json is the run's state: a package is dispatched once its
# dependency list is empty, and the run ends when a full pass changes nothing.
#
# Not `set -e`: individual package failures are expected and recorded per
# package by make_deb.sh (see fail-<pkg>/ directories).
set -uo pipefail

# shellcheck source=lib.sh
source "${BIOC2U_SCRIPTS:-/opt/bioc2u/scripts}/lib.sh"

BIOC_VERSION="$(bioc_version)"
export BIOC_VERSION
[ -n "$BIOC_VERSION" ] || die "could not determine the Bioconductor version"

cd "$DEBS_DIR" || die "$DEBS_DIR is not available"

log "Bioconductor $BIOC_VERSION ($(release_branch "$BIOC_VERSION")) on $(ubuntu_codename), building in $DEBS_DIR"
log "R $(Rscript -e 'cat(paste(R.version$major, R.version$minor, sep="."))' 2>/dev/null), BiocManager pinned to $(Rscript -e 'cat(as.character(BiocManager::version()))' 2>/dev/null)"

# ------------------------------------------------------- environment sanity
# Sources from one release in an image pinned to another produce packages
# stamped for the wrong release. Refuse the mismatch.
IMAGE_BIOC="$(Rscript -e 'cat(as.character(BiocManager::version()))' 2>/dev/null)"
if [ -n "$IMAGE_BIOC" ] && [ "$IMAGE_BIOC" != "$BIOC_VERSION" ]; then
    die "BIOC_VERSION=$BIOC_VERSION but this image's BiocManager is $IMAGE_BIOC.
     Use a builder image built for $BIOC_VERSION - the container workflow
     publishes bioc2u-builder:<codename>-r-<R version> once it has run for
     this release - or unset BIOC_VERSION to build $IMAGE_BIOC."
fi

# --------------------------------------------------- release-change guard
# A run resumes by skipping done-<pkg>/; pointed at another release's debs,
# that silently carries every already-built package forward with the old
# ABI stamp. Record and check the release a debs directory belongs to.
STAMP="$DEBS_DIR/.bioc-version"
if [ -s "$STAMP" ]; then
    PREV_RELEASE="$(cat "$STAMP")"
    if [ "$PREV_RELEASE" != "$BIOC_VERSION" ] && [ "${BIOC2U_ALLOW_RELEASE_CHANGE:-0}" != "1" ]; then
        die "$DEBS_DIR holds a Bioconductor $PREV_RELEASE build, but this is $BIOC_VERSION.
     Resuming would carry $PREV_RELEASE packages into the $BIOC_VERSION
     repository with the wrong ABI stamp. Use a fresh directory
     (BIOC2U_DEBS_ROOT), or if you really mean to continue in place:
       rm -rf $DEBS_DIR/done-* $DEBS_DIR/fail-* $DEBS_DIR/packages.json
       BIOC2U_REFRESH_DEPS=1 BIOC2U_ALLOW_RELEASE_CHANGE=1 ..."
    fi
    [ "$PREV_RELEASE" != "$BIOC_VERSION" ] &&
        log "WARNING: continuing a $PREV_RELEASE directory as $BIOC_VERSION (BIOC2U_ALLOW_RELEASE_CHANGE=1)"
fi
printf '%s\n' "$BIOC_VERSION" > "$STAMP"

# ---------------------------------------------------------------- dependencies
# biocdeps.json is the full graph; packages.json is the working copy that
# shrinks as packages build. Both persist so an interrupted run resumes;
# BIOC2U_REFRESH_DEPS=1 pulls a fresh graph (eg after a release).
if [ "${BIOC2U_REFRESH_DEPS:-0}" = "1" ] || [ ! -s biocdeps.json ]; then
    log "resolving the Bioconductor dependency graph (this takes a few minutes)"
    # Via a temporary file: a graph half-written by an interrupted run would
    # otherwise look complete to the next one.
    Rscript "$BIOC2U_SCRIPTS/deps_json.R" biocdeps=biocdeps.json.tmp ||
        die "failed to resolve the dependency graph"
    mv biocdeps.json.tmp biocdeps.json
    rm -f packages.json
else
    log "reusing existing biocdeps.json (BIOC2U_REFRESH_DEPS=1 to regenerate)"
fi
[ -s packages.json ] || cp biocdeps.json packages.json

# ------------------------------------------------------------ package indexes
# Source tarball versions and locations come from these.
for repo in bioc:bioc annotation:data/annotation experiment:data/experiment; do
    name="${repo%%:*}"
    path="${repo#*:}"
    curl -fsSL -o "PACKAGES.$name" \
        "https://bioconductor.org/packages/$BIOC_VERSION/$path/src/contrib/PACKAGES" ||
        die "could not fetch the $name package index for Bioconductor $BIOC_VERSION"
done

# ----------------------------------------------------------------- build loop
ready_packages() {
    python3 -c 'import json, sys
graph = json.load(open(sys.argv[1]))
print("\n".join(pkg for pkg, deps in graph.items() if not deps))' packages.json
}

# BiocVersion seeds the graph: it provides r-api-bioc-<version>, which most
# other r-bioc-* packages depend on, so build it first.
bash "$BIOC2U_SCRIPTS/make_deb.sh" BiocVersion "$BIOC_VERSION" < /dev/null
[ -d done-BiocVersion ] ||
    die "BiocVersion did not build, and every other package is built against it.
     See $DEBS_DIR/BiocVersion-log or $DEBS_DIR/fail-BiocVersion/."

# One round per generation of the graph; when a whole round changes nothing,
# what is left is unbuildable.
round=0
while :; do
    round=$((round + 1))
    cp packages.json old_packages.json
    ready_packages > curlist
    log "round $round: $(grep -c . curlist) package(s) ready to build"
    while read -r pkg; do
        # Close stdin so the build cannot swallow the rest of the list.
        [ -n "$pkg" ] && bash "$BIOC2U_SCRIPTS/make_deb.sh" "$pkg" "$BIOC_VERSION" < /dev/null
    done < curlist
    diff -q packages.json old_packages.json >/dev/null 2>&1 && break
done

# -------------------------------------------------------------------- results
for d in fail-*/; do
    [ -d "$d" ] && basename "$d" | sed 's/^fail-//'
done > failed-packages.txt 2>/dev/null
sort -o failed-packages.txt failed-packages.txt 2>/dev/null

log "build loop finished after $round round(s)"
bash "$BIOC2U_SCRIPTS/progress.sh" "$DEBS_DIR"
log "upload with: docker compose run --rm $(ubuntu_codename)-upload"
