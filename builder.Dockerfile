ARG BASE_IMAGE=ghcr.io/bioconductor/r2u
ARG UBUNTU_TAG=jammy
FROM ${BASE_IMAGE}:${UBUNTU_TAG} AS base

RUN apt update -qq && apt install git-all build-essential binutils lintian debhelper dh-make devscripts curl vim dh-r -y
