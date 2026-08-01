## Bioc2u (beta): Ubuntu Binaries for Bioconductor packages

This project aims to extend [r2u][r2u],
in hopes of providing a repository of Ubuntu binaries via `apt` for all Bioconductor packages.

**Bioc2u is currently available for Ubuntu Jammy (22.04) and Noble (24.04) and is still in beta development.**

### Container Images

We provide two types of container images for different use cases:

- **User containers** (`bioc2u-user`): Minimal environment built on `ubuntu:jammy` or `ubuntu:noble` with R, BiocManager, and bioc2u/r2u repositories pre-configured
- **Builder containers** (`bioc2u-builder`): Extended environment based on [r2u][r2u] containers with additional build tools for package development

#### Available Tags

Container images are available with multiple tagging formats:

- **Ubuntu version**: `jammy`, `noble`
- **Ubuntu version with R**: `jammy-r-4.6.1`, `noble-r-4.6.1`
- **Ubuntu version with Bioconductor**: `jammy-bioc-3.23`, `noble-bioc-3.23`
- **Full version**: `jammy-bioc-3.23-r-4.6.1`, `noble-bioc-3.23-r-4.6.1`
- **OS version**: `22.04`, `24.04` (corresponding to Ubuntu versions)
- **OS version with R/Bioc**: eg `22.04-r-4.6.1`, `24.04-bioc-3.23`, `24.04-bioc-3.23-r-4.6.1`

#### Version Strategy and Backward Compatibility

This design allows for old versions to remain accessible by default, under the full tags. For example: when R 4.6.2 comes out, the containers tagged simply `jammy-bioc-3.23` become `jammy-bioc-3.23-r-4.6.2` but the previous container remains accessible under `jammy-bioc-3.23-r-4.6.1`. When containers get rebuilt within the same version, old containers can still be used via their hash in the `ghcr.io/bioconductor/bioc2u-user@sha256:[hash]` format.

This ensures reproducibility by allowing users to pin to specific versions or use the latest versions through the shorter tag names.

The two image types pick up a new R differently. The user containers install R from the CRAN `apt` repository at build time, so they follow it automatically. The builder containers are built on a pinned [r2u][r2u] base image (`R_VERSION` in `builder.Dockerfile`, passed from the workflow matrix), so they only move to a new R when that is bumped.

### Getting started

#### Using Docker containers

For a minimal R environment with bioc2u pre-configured:
```bash
# Ubuntu Jammy (22.04) - latest versions
docker run --rm -it ghcr.io/bioconductor/bioc2u-user:jammy

# Ubuntu Noble (24.04) - latest versions
docker run --rm -it ghcr.io/bioconductor/bioc2u-user:noble

# Specific Bioconductor/R versions for reproducibility
docker run --rm -it ghcr.io/bioconductor/bioc2u-user:jammy-bioc-3.23-r-4.6.1
```

For package development with build tools:
```bash
# Builder container with development tools
docker run --rm -it ghcr.io/bioconductor/bioc2u-builder:jammy
```

#### Local installation

In an Ubuntu environment (eg in containers based on `ubuntu:jammy` and `ubuntu:noble`), you may use the [`apt_setup.sh`](https://github.com/Bioconductor/bioc2u/blob/devel/apt_setup.sh)
script which will set up the Bioc2u `apt` repository and install R, and basic packages such as BiocManager. This script leverages the [r2u][r2u] setup scripts from the [r2u repository](https://github.com/eddelbuettel/r2u/blob/master/inst/scripts/) to configure the CRAN apt repository.

```bash
# Install curl if missing
apt update -qq
apt install -y --no-install-recommends curl ca-certificates
# Run apt script with specific Bioconductor version
curl https://raw.githubusercontent.com/Bioconductor/bioc2u/devel/apt_setup.sh | sudo bash -s 3.23
```

After the initial setup, you may use `apt` or `install.packages()` freely. Installing packages through `apt` can be done in any shell session, by using the
`r-bioc-` prefix and the all-lowercase name of the package, eg `apt install -y r-bioc-genomicranges`. You may alternatively continue to use R traditionally, as you would in any other environment, and observe the speedup resulting from R using the `apt` package manager under the hood.

### Automated Builds

Container images are automatically built every 2 days and pushed to GitHub Container Registry (GHCR). The build process:

- Builds both user and builder containers for Ubuntu Jammy and Noble
- Supports linux/amd64 platform
- Automatically extracts R and OS version information for comprehensive tagging
- Creates multi-platform manifests with various tag combinations

### Acknowledgments

This project builds upon and extends the [r2u][r2u] project. Our `apt_setup.sh` script directly uses the [r2u setup scripts](https://github.com/eddelbuettel/r2u/blob/master/inst/scripts/) to configure the CRAN apt repository, and our builder containers are based on the [r2u][r2u] containers.

[r2u]: https://eddelbuettel.github.io/r2u
