#!/bin/bash
# Publish the .debs of one distro to the bioc2u apt repository with deb-s3.
# A separate, explicitly invoked step: the index signature has to be made
# close to the upload, so it is never folded into the build run.
set -euo pipefail

# shellcheck source=lib.sh
source "${BIOC2U_SCRIPTS:-/opt/bioc2u/scripts}/lib.sh"

CODENAME="${DEB_S3_CODENAME:-$(ubuntu_codename)}"
ENDPOINT="${DEB_S3_ENDPOINT:-https://mghp.osn.xsede.org}"
BUCKET="${DEB_S3_BUCKET:-bir190004-bucket01}"
PREFIX="${DEB_S3_PREFIX-bioc2u}"
COMPONENT="${DEB_S3_COMPONENT:-release}"
SIGN_KEY="${GPG_SIGN_KEY:-}"

cd "$DEBS_DIR" || die "$DEBS_DIR is not available"

shopt -s nullglob
debs=(*.deb)
[ ${#debs[@]} -gt 0 ] || die "no .deb files in $DEBS_DIR -- nothing to upload"

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && [ ! -s /root/.aws/config ] && [ ! -s /root/.aws/credentials ]; then
    die "no S3 credentials: mount ~/.aws into the container or set AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY"
fi

# deb-s3 rewrites the index on every upload, so publishing without a key would
# replace a signed index with an unsigned one. Has to be asked for explicitly.
if [ -z "$SIGN_KEY" ]; then
    [ "${BIOC2U_ALLOW_UNSIGNED:-0}" = "1" ] ||
        die "GPG_SIGN_KEY is not set: this would publish an unsigned index. Set it, or BIOC2U_ALLOW_UNSIGNED=1 if that is really what you want."
    log "WARNING: publishing an unsigned repository index"
fi

args=(
    --endpoint="$ENDPOINT"
    --bucket="$BUCKET"
    --force-path-style
    --codename="$CODENAME"
    --component="$COMPONENT"
)
if [ -n "$PREFIX" ]; then
    args+=(--prefix="$PREFIX")
fi
if [ -n "$SIGN_KEY" ]; then
    args+=(--sign="$SIGN_KEY")
fi
if [ -n "${DEB_S3_EXTRA_ARGS:-}" ]; then
    read -r -a extra <<< "$DEB_S3_EXTRA_ARGS"
    args+=("${extra[@]}")
fi

log "uploading ${#debs[@]} deb(s) to $ENDPOINT/$BUCKET/${PREFIX:+$PREFIX/} ($CODENAME/$COMPONENT)"

if [ "${BIOC2U_DRY_RUN:-0}" = "1" ]; then
    log "dry run, would have run:"
    printf 'deb-s3 upload %s ./*.deb\n' "${args[*]}"
    exit 0
fi

ensure_deb_s3

# gpg needs a terminal to ask for the passphrase; `docker compose run` gives one.
if [ -z "${GPG_TTY:-}" ] && [ -t 0 ]; then
    GPG_TTY=$(tty)
    export GPG_TTY
fi

deb-s3 upload "${args[@]}" "${debs[@]}"
