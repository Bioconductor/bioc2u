#!/bin/bash
# Shared helpers for the bioc2u build stack.
# Sourced by the other scripts in this directory; not meant to be run directly.

BIOC2U_SCRIPTS="${BIOC2U_SCRIPTS:-/opt/bioc2u/scripts}"
DEBS_DIR="${DEBS_DIR:-/root/debs}"

log() { printf '[bioc2u] %s\n' "$*" >&2; }
die() { printf '[bioc2u] ERROR: %s\n' "$*" >&2; exit 1; }

# jammy / noble, read from the image rather than passed in, so that the tag and
# the codename used for the apt repository can never drift apart.
ubuntu_codename() {
    local codename="${UBUNTU_CODENAME:-}"
    if [ -z "$codename" ] && [ -r /etc/os-release ]; then
        codename=$(awk -F= '/^VERSION_CODENAME=/ {print $2}' /etc/os-release)
    fi
    echo "${codename:-unknown}"
}

# Bioconductor version the image's BiocManager is pinned to, unless overridden.
bioc_version() {
    if [ -n "${BIOC_VERSION:-}" ]; then
        echo "$BIOC_VERSION"
    else
        Rscript -e 'cat(paste0(BiocManager::version()))'
    fi
}

# 3.22 -> RELEASE_3_22
release_branch() { echo "RELEASE_${1//./_}"; }

# --------------------------------------------------------------- BiocVersion
# BiocVersion is the seed of the whole repository: most other r-bioc-* packages
# depend on the r-api-bioc-<release> virtual package that BiocVersion provides.
#
# Rewrite the control of a built BiocVersion .deb in place: dh-r injects a
# dependency on the previous release's ABI via ${R:Depends} at
# dpkg-buildpackage time, so it can only be fixed on the .deb. $2 is the
# release it defines; $3, if set, an older ABI to also provide.
fix_biocversion_deb() {
    local deb="$1" release="$2" also="${3:-}"
    local tmp ctl provides
    tmp=$(mktemp -d) || return 1
    dpkg-deb -R "$deb" "$tmp" || { rm -rf "$tmp"; return 1; }
    ctl="$tmp/DEBIAN/control"

    provides="r-api-bioc-$release"
    [ -n "$also" ] && [ "$also" != "$provides" ] && provides="$provides, $also"

    # Out of Depends entirely; Provides replaced wholesale so re-running cannot
    # accumulate duplicates.
    sed -i -E "s/, *r-api-bioc-[0-9.]+//g; s/r-api-bioc-[0-9.]+, *//g" "$ctl"
    if grep -q "^Provides:" "$ctl"; then
        sed -i -E "s/^Provides:.*/Provides: $provides/" "$ctl"
    else
        sed -i "/^Depends:/a Provides: $provides" "$ctl"
    fi

    dpkg-deb -b "$tmp" "$deb" >/dev/null || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
}

# Refuse to ship a BiocVersion that would make most r-bioc-* packages
# uninstallable.
assert_biocversion_deb() {
    local deb="$1" release="$2" dep prov
    dep=$(dpkg-deb -f "$deb" Depends 2>/dev/null)
    prov=$(dpkg-deb -f "$deb" Provides 2>/dev/null)
    case "$dep" in
        *r-api-bioc-*) die "BiocVersion still depends on a Bioconductor ABI: $dep" ;;
    esac
    case "$prov" in
        *"r-api-bioc-$release"*) : ;;
        *) die "BiocVersion does not provide r-api-bioc-$release (Provides: ${prov:-none})" ;;
    esac
    log "BiocVersion OK - provides: $prov"
}

# ------------------------------------------------------- version constraints
# R treats "." and "-" as the same version separator; dpkg reads the last "-"
# as the start of the Debian revision, so a dotted constraint on a package
# that versions itself with a hyphen (eg MASS 7.3-66) is unsatisfiable. Fixed
# in DESCRIPTION, not debian/control: dh-r regenerates the runtime Depends
# from DESCRIPTION at dpkg-buildpackage time.

# Highest version of $1 apt can put in place - installed or candidate,
# whichever is greater. Empty (status 1) if apt does not know the package.
apt_best_version() {
    local pol inst cand best
    pol=$(apt-cache policy "$1" 2>/dev/null) || return 1
    inst=$(printf '%s\n' "$pol" | awk '/Installed:/ {print $2; exit}')
    cand=$(printf '%s\n' "$pol" | awk '/Candidate:/ {print $2; exit}')
    [ "$inst" = "(none)" ] && inst=""
    [ "$cand" = "(none)" ] && cand=""
    best="$cand"
    if [ -n "$inst" ] && { [ -z "$best" ] || dpkg --compare-versions "$inst" gt "$best"; }; then
        best="$inst"
    fi
    [ -n "$best" ] || return 1
    printf '%s' "$best"
}

# R package name -> the deb providing it, if apt knows one. CRAN first: the
# r-cran-* namespace is much larger and a name collision is not plausible.
r_deb_name() {
    local lower cand
    lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    for cand in "r-cran-$lower" "r-bioc-$lower"; do
        if apt-cache show "$cand" >/dev/null 2>&1; then
            printf '%s' "$cand"
            return 0
        fi
    done
    return 1
}

# Rewrite unsatisfiable X.Y.Z constraints in DESCRIPTION to X.Y-Z, in place.
# Only touches a constraint that is unsatisfiable as written and satisfiable
# hyphenated, so a dependency that is too old still fails.
normalise_r_version_constraints() {
    local desc="${1:-DESCRIPTION}"
    [ -r "$desc" ] || return 0

    local unfolded fields rpkg ver hyph deb have esc_p esc_v n=0

    # Continuation lines are indented; join them so a field is one line.
    unfolded=$(sed -E ':a;N;$!ba;s/\n[[:space:]]+/ /g' "$desc")
    fields=$(printf '%s\n' "$unfolded" | grep -E '^(Depends|Imports|LinkingTo):')
    [ -n "$fields" ] || return 0

    while IFS='|' read -r rpkg ver; do
        [ -n "$rpkg" ] || continue

        hyph=$(printf '%s' "$ver" | sed -E 's/^([0-9]+\.[0-9]+)\.([0-9]+)$/\1-\2/')
        [ "$hyph" != "$ver" ] || continue          # not a rewritable shape

        deb=$(r_deb_name "$rpkg") || continue
        have=$(apt_best_version "$deb") || continue

        dpkg --compare-versions "$have" ge "$ver"  && continue   # already fine
        dpkg --compare-versions "$have" ge "$hyph" || continue   # hyphen no better

        # "#" as the s/// delimiter: the pattern itself contains "|", and a
        # package name or version can never contain "#".
        esc_p=$(printf '%s' "$rpkg" | sed -E 's#[][\.*^$(){}?+|/]#\\&#g')
        esc_v=$(printf '%s' "$ver"  | sed -E 's#[][\.*^$(){}?+|/]#\\&#g')
        sed -i -E \
            "s#(^|[,[:space:]])${esc_p}[[:space:]]*\([[:space:]]*>=[[:space:]]*${esc_v}[[:space:]]*\)#\1${rpkg} (>= ${hyph})#g" \
            "$desc"
        log "  $rpkg (>= $ver) -> (>= $hyph)   [$deb is $have]"
        n=$((n + 1))
    done < <(printf '%s\n' "$fields" |
        grep -oE '[A-Za-z][A-Za-z0-9._]*[[:space:]]*\([[:space:]]*>=[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*\)' |
        sed -E 's/^([A-Za-z][A-Za-z0-9._]*)[[:space:]]*\([[:space:]]*>=[[:space:]]*([0-9.]+)[[:space:]]*\)$/\1|\2/' |
        sort -u)

    [ "$n" -gt 0 ] && log "normalised $n unsatisfiable version constraint(s) in $desc"
    return 0
}

# deb-s3 is only needed for uploads, so it is installed on demand rather than
# baked into every build container.
ensure_deb_s3() {
    if command -v deb-s3 >/dev/null 2>&1; then
        return 0
    fi
    log "installing deb-s3"
    apt-get update -qq
    apt-get install -y --no-install-recommends rubygems >/dev/null
    gem install deb-s3
}
