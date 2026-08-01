#!/bin/bash
# Entrypoint for every service in the build stack: prepares the packaging
# environment inside the container, then runs the requested command.
set -euo pipefail

# shellcheck source=lib.sh
source "${BIOC2U_SCRIPTS:-/opt/bioc2u/scripts}/lib.sh"

export DEBIAN_FRONTEND=noninteractive
export DEBEMAIL="${DEBEMAIL:-maintainer@bioconductor.org}"
export DEBFULLNAME="${DEBFULLNAME:-Bioconductor Core Team}"
export LOGNAME=root
UBUNTU_CODENAME="$(ubuntu_codename)"
export UBUNTU_CODENAME

mkdir -p "$DEBS_DIR"

# Keep a Debian archive's own r-bioc-* packages out of the build.
cat > /etc/apt/preferences.d/ignore-r-bioc <<'EOF'
Package: r-bioc-*
Pin: release o=Debian
Pin-Priority: -1
EOF

apt-get update -qq
# These come from the builder image, but dh-r can be autoremoved mid-run;
# re-assert the packaging tools. Recommends stay on.
apt-get install -y \
    curl ca-certificates python3 devscripts equivs debhelper dh-make dh-r >/dev/null

exec "$@"
