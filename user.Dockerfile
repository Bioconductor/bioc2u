ARG BASE_IMAGE=ubuntu
ARG UBUNTU_TAG=jammy
FROM ${BASE_IMAGE}:${UBUNTU_TAG} AS base

USER root
COPY apt_setup.sh /bioc_scripts/apt_setup.sh
RUN bash /bioc_scripts/apt_setup.sh
