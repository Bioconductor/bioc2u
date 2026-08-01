ARG BASE_IMAGE=ghcr.io/bioconductor/r2u
ARG UBUNTU_TAG=jammy
# R comes from the r2u base image, which publishes <codename>-r-<version> tags.
# Pinned rather than floating, so a build is reproducible and an upstream R
# release does not change the image until this is bumped.
ARG R_VERSION=4.6.1
FROM ${BASE_IMAGE}:${UBUNTU_TAG}-r-${R_VERSION} AS base
ARG BIOC_VERSION=3.23
RUN apt update -qq &&\
    apt install -y git-all build-essential binutils lintian dh-make devscripts curl vim &&\
    curl -O https://raw.githubusercontent.com/Bioconductor/bioconductor_docker/devel/bioc_scripts/install_bioc_sysdeps.sh &&\
    sed -i 's/install.packages("BiocManager"/bspm::disable(); install.packages("BiocManager"/g' install_bioc_sysdeps.sh &&\
    sed -i 's/BiocManager::install(version=/bspm::disable(); BiocManager::install(version=/g' install_bioc_sysdeps.sh &&\
    bash install_bioc_sysdeps.sh $BIOC_VERSION || ( sed -i 's/--break-system-packages//g' install_bioc_sysdeps.sh && bash install_bioc_sysdeps.sh $BIOC_VERSION ) &&\
    apt update -qq && apt install -y debhelper dh-r
