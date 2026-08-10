#!/bin/bash
# Undo apt_setup.sh.
#
#   sudo bash uninstall.sh                 # remove the bioc2u repository configuration
#   sudo bash uninstall.sh --purge         # also remove installed r-bioc-* packages
#   sudo bash uninstall.sh --all           # also remove the r2u/CRAN apt layer and bspm setup
#
# Flags can be combined. Without --purge, installed packages are kept and keep
# working; they simply stop receiving updates from the removed repositories.
# R itself is never removed by this script (use "apt remove r-base-core" for that).
# Containers need none of this: remove the container and image instead.
set -u

PURGE=0
ALL=0
for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        --all)   ALL=1 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg (try --help)"; exit 2 ;;
    esac
done

if [ "$(id -u)" != 0 ]; then
    echo "this needs root: sudo bash uninstall.sh $*"
    exit 1
fi

drop() {
    for f in "$@"; do
        if [ -e "$f" ]; then
            rm -f "$f" && echo "removed $f"
        fi
    done
    return 0
}

# --- the bioc2u layer, as created by apt_setup.sh ---------------------------
drop /etc/apt/sources.list.d/bioc2u.list \
     /etc/apt/preferences.d/prefbioc2u \
     /etc/apt/trusted.gpg.d/bioc2u_key.asc

# --- installed packages, only on request ------------------------------------
if [ "$PURGE" = 1 ]; then
    if dpkg-query -W -f '${Package}\n' 'r-bioc-*' >/dev/null 2>&1; then
        apt-get remove -y 'r-bioc-*'
    else
        echo "no r-bioc-* packages installed"
    fi
fi

# --- the r2u / CRAN layer, only on request ----------------------------------
# File names differ between the r2u setup scripts for noble and jammy;
# both sets are listed and whichever exists is removed.
if [ "$ALL" = 1 ]; then
    drop /etc/apt/sources.list.d/r2u.sources \
         /etc/apt/sources.list.d/cran.sources \
         /usr/share/keyrings/r2u.gpg \
         /etc/apt/sources.list.d/cranapt.list \
         /etc/apt/sources.list.d/cran_r.list \
         /etc/apt/trusted.gpg.d/cranapt_key.asc \
         /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc \
         /etc/apt/preferences.d/99cranapt
    for rp in /etc/R/Rprofile.site /usr/lib/R/etc/Rprofile.site; do
        [ -e "$rp" ] || continue
        if grep -q 'bspm::enable()' "$rp"; then
            sed -i '/suppressMessages(bspm::enable())/d;/options(bspm.version.check=FALSE)/d' "$rp"
            echo "removed bspm lines from $rp"
        fi
    done
fi

apt-get update -qq

echo "Done."
[ "$PURGE" = 0 ] && echo "Installed R packages were kept; they no longer update from the removed repositories."
[ "$ALL" = 0 ]   && echo "The r2u/CRAN apt layer was kept; rerun with --all to remove it as well."
exit 0
