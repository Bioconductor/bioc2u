#!/bin/bash
BIOC_VERSION=${1:-"3.18"}
export UBUNTU_CODENAME=$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2)
apt update -qq
apt install -y --no-install-recommends curl ca-certificates
curl -O https://raw.githubusercontent.com/eddelbuettel/r2u/master/inst/scripts/add_cranapt_$UBUNTU_CODENAME.sh
bash add_cranapt_$UBUNTU_CODENAME.sh
rm add_cranapt_$UBUNTU_CODENAME.sh
curl -o /etc/apt/trusted.gpg.d/bioc2u_key.asc https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/bioc2u_key.asc
echo "deb https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/ $UBUNTU_CODENAME release" | tee -a /etc/apt/sources.list.d/bioc2u.list > /dev/null
echo "Package: *" > /etc/apt/preferences.d/prefbioc2u
echo "Pin: origin mghp.osn.xsede.org" >> /etc/apt/preferences.d/prefbioc2u
echo "Pin-Priority: 800"  >> /etc/apt/preferences.d/prefbioc2u
apt update -qq
DEBIAN_FRONTEND=noninteractive apt install -y r-base-core r-cran-biocmanager r-cran-bspm
Rscript -e "BiocManager::install(version='$BIOC_VERSION', update=TRUE, ask=FALSE)"
Rscript -e "BiocManager::install(c('devtools'))"
