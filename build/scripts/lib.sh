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
