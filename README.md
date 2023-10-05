## Bioc2u (alpha): Ubuntu Binaries for Bioconductor packages

This project aims to extend [r2u](https://github.com/eddelbuettel/r2u),
in hopes of providing a repository of Ubuntu binaries via `apt` for all Bioconductor packages.

**Bioc2u is current only available for Ubuntu Jammy and is still in alpha development.**

### Getting started

If you wish to get started in a minimal environment, a relatively small docker container is provided, built on `ubuntu:jammy`, and providing the initial `apt`
and `R` setup to get you started. You may use this container via `docker run --rm -it ghcr.io/bioconductor/bioc2u-user:jammy`. Alternatively, if you are on
an Ubuntu machine, you may set up the `bioc2u` and `r2u` repositories for your local system's `apt` by using the provided script!

In an Ubuntu environment (tested in `ubuntu:jammy` container), you may use the [`apt_setup.sh`](https://github.com/Bioconductor/bioc2u/blob/devel/apt_setup.sh)
script which will set up the Bioc2u `apt` repository and install R, and basic packages such as BiocManager.
```bash
# Install curl if missing
apt update -qq
apt install -y --no-install-recommends curl ca-certificates
# Run apt script
curl https://raw.githubusercontent.com/Bioconductor/bioc2u/devel/apt_setup.sh | sudo bash
```
After the initial setup, you may use `apt` or `install.packages()` freely. Installing packages through `apt` can be done in any shell session, by using the
`r-bioc-` prefix and the all-lowercase name of the package, eg `apt install -y r-bioc-biocmanager`. You may alternatively continue to use R traditionally.

By default, the `r-core-base` installation (provided by the r2u project), uses the [`bspm`](https://cran.r-project.org/web/packages/bspm/index.html) package to enable the usage of the package manager
when installing packages from within R via `install.packages()` or `BiocManager::install()`. You may thus continue to use R as you would outside of this
environment, and observe the speedup resulting from R using the `apt` package manager under the hood.

### Status / TODOs (alpha)
- 1800+ packages built for ubuntu jammy
  - TODO: Build for ubuntu focal
  - TODO: Collect failure logs, then address common errors and missing build-dependencies
- Repository public without signed key (TODO: gpg key and update repository)
- Repository hosted on JS2 (TODO: host on OSN)
