ARG BASE_IMAGE=ghcr.io/bioconductor/r2u
ARG UBUNTU_TAG=jammy
FROM ${BASE_IMAGE}:${UBUNTU_TAG} AS base
ARG BIOC_VERSION=3.18
RUN apt update -qq && apt install git-all build-essential binutils lintian debhelper dh-make devscripts curl vim dh-r -y && curl -O https://raw.githubusercontent.com/Bioconductor/bioconductor_docker/devel/bioc_scripts/install_bioc_sysdeps.sh && bash install_bioc_sysdeps.sh $BIOC_VERSION 
