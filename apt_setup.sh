#!/bin/bash
export UBUNTU_CODENAME=$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2)
curl -O https://raw.githubusercontent.com/eddelbuettel/r2u/master/inst/scripts/add_cranapt_$UBUNTU_CODENAME.sh
bash add_cranapt_$UBUNTU_CODENAME.sh
rm add_cranapt_$UBUNTU_CODENAME.sh
echo "deb [trusted=yes] https://js2.jetstream-cloud.org:8001/swift/v1/bioc2u/ $UBUNTU_CODENAME release" | tee -a /etc/apt/sources.list.d/bioc2u.list > /dev/null
apt update -qq
DEBIAN_FRONTEND=noninteractive apt install -y r-cran-biocmanager
