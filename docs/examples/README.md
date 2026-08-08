# Examples

Worked setups. Each is complete enough to copy.

| | |
|---|---|
| [Dockerfile](#a-dockerfile-built-on-bioc2u) | Base an image on bioc2u |
| [GitHub Actions](#github-actions) | Bioconductor CI with binary dependencies |
| [Bare Ubuntu machine](#a-bare-ubuntu-machine) | Configure a VM or workstation |
| [Pinning](#pinning-for-reproducibility) | Make a setup reproducible |

## A Dockerfile built on bioc2u

> A full tag exists only once the container workflow has run for that version,
> so check a tag before pinning it:
>
> ```bash
> docker manifest inspect ghcr.io/bioconductor/bioc2u-user:jammy-bioc-3.23-r-4.6.1
> ```

```dockerfile
# Pin the full tag. `jammy` alone moves with every rebuild.
FROM ghcr.io/bioconductor/bioc2u-user:jammy-bioc-3.23-r-4.6.1

# Binary installs. Package names are r-bioc- plus the lowercased package name.
RUN apt update -qq && apt install -y --no-install-recommends \
      r-bioc-genomicranges \
      r-bioc-summarizedexperiment \
      r-bioc-deseq2 \
 && rm -rf /var/lib/apt/lists/*

# Or install from R - bspm routes this through apt underneath, so it is still
# binary. Useful when a package has no .deb: it falls back to source silently.
RUN Rscript -e 'BiocManager::install(c("edgeR"), ask = FALSE)'

WORKDIR /work
CMD ["R"]
```

Two habits worth keeping:

- **Prefer `apt install` when you know the package has a `.deb`.** It fails
  loudly if the package is missing, where `BiocManager::install()` quietly
  compiles from source instead.
- **`rm -rf /var/lib/apt/lists/*`** after installing, or the image carries the
  package index for nothing.

## GitHub Actions

```yaml
name: Check
on: [push, pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/bioconductor/bioc2u-user:jammy-bioc-3.23-r-4.6.1
    steps:
      - uses: actions/checkout@v7

      - name: Install dependencies
        run: |
          apt update -qq
          apt install -y --no-install-recommends r-base-dev \
            r-bioc-biocgenerics r-bioc-s4vectors r-bioc-iranges

      - name: Check
        run: |
          R CMD build .
          R CMD check --no-manual *.tar.gz
```

The `user` image has the bioc2u repository configured; `r-base-dev` adds the
compilers `R CMD check` needs for packages with compiled code. The `builder`
image has the compilers but not the bioc2u repository.

## A bare Ubuntu machine

```bash
sudo apt update -qq
sudo apt install -y --no-install-recommends curl ca-certificates

# Read it before running it on a machine you care about - it adds a
# system-wide apt key and pins a repository above Ubuntu's own.
curl -O https://raw.githubusercontent.com/Bioconductor/bioc2u/devel/apt_setup.sh
less apt_setup.sh
sudo bash apt_setup.sh 3.23
```

Verify:

```bash
apt-cache policy | grep -A2 mghp.osn.xsede.org   # present, priority 800
sudo apt install -y r-bioc-biocgenerics
Rscript -e 'library(BiocGenerics); BiocManager::version()'
Rscript -e 'packageVersion("bspm")'              # bspm present
grep -r bspm /etc/R/Rprofile.site                 # ...and enabled system-wide
```

Once `bspm` is active, ordinary R workflows use apt underneath:

```r
BiocManager::install("DESeq2")   # binary, seconds
install.packages("data.table")   # binary, via r2u
```

## Pinning for reproducibility

Three levels, weakest to strongest:

```bash
# Moves with every rebuild
ghcr.io/bioconductor/bioc2u-user:jammy

# Fixed Bioconductor and R; still rebuilt for security updates
ghcr.io/bioconductor/bioc2u-user:jammy-bioc-3.23-r-4.6.1

# Immutable
ghcr.io/bioconductor/bioc2u-user@sha256:...
```

For a paper or a released pipeline, use the digest:

```bash
docker pull ghcr.io/bioconductor/bioc2u-user:jammy-bioc-3.23-r-4.6.1
docker inspect --format='{{index .RepoDigests 0}}' \
  ghcr.io/bioconductor/bioc2u-user:jammy-bioc-3.23-r-4.6.1
```

A pinned image does *not* pin what `apt install` inside it resolves: that
still comes from the live repository, so a container built today and one built
next month from the same base can contain different package versions. Pin the
image *and* record the package versions:

```bash
dpkg -l 'r-bioc-*' 'r-cran-*' > package-versions.txt
```
