# Architecture

## Purpose

Installing a Bioconductor package from source compiles it and every
dependency it pulls in. On a fresh machine that can mean an hour of C++ for a
dependency tree the user did not ask for.

[r2u](https://eddelbuettel.github.io/r2u) provides every CRAN package as a
prebuilt Ubuntu `.deb`, installed with `apt`, with system dependencies resolved
by the package manager. bioc2u does the same for Bioconductor:
`apt install r-bioc-genomicranges` fetches a binary, and its system
dependencies come with it.

With [bspm](https://cran.r-project.org/package=bspm) enabled,
`install.packages()` and `BiocManager::install()` install through apt as well,
so R users keep their usual workflow.

## Components

```
  Bioconductor sources ──► build/ (runs in bioc2u-builder) ──► bioc2u apt repository
                                                                        │
  CRAN ─────────────────► r2u apt repository ──────────────────┐       │
                                                                ▼       ▼
                                          apt_setup.sh ──► Ubuntu system: apt + bspm

  bioc2u-user is an Ubuntu image with apt_setup.sh applied.
  bioc2u-builder is the r2u base image plus the Debian R packaging tools; it
  does not run apt_setup.sh.
```

| Component | Where | What |
|---|---|---|
| The apt repository | `mghp.osn.xsede.org/bir190004-bucket01/bioc2u/` | The `.deb` packages, on an Open Storage Network (OSN) bucket |
| `build/` | this repository | Builds every package and publishes the repository |
| `apt_setup.sh` | this repository | Configures a machine to use r2u and the repository |
| `bioc2u-user` | this repository | `ubuntu:<codename>` + `apt_setup.sh` |
| `bioc2u-builder` | this repository | r2u base + build tooling, for making packages. **Does not run `apt_setup.sh`**, so it has r2u's CRAN repository but not bioc2u's |
| `build_ghcr.yaml` | this repository | Builds and publishes both images |

### `apt_setup.sh`

In order:

1. Read the Ubuntu codename from `/etc/os-release`.
2. Install `curl` and `ca-certificates`.
3. Fetch and run r2u's `add_cranapt_<codename>.sh` from r2u's `master` branch.
   It configures CRAN's Ubuntu repository for R itself and r2u's repository
   for CRAN packages, pins r2u to priority 700, and enables bspm in
   `/etc/R/Rprofile.site`. **CRAN comes from r2u**; bioc2u delegates it.
4. Download the bioc2u signing key to `/etc/apt/trusted.gpg.d/bioc2u_key.asc`.
5. Append the repository to `/etc/apt/sources.list.d/bioc2u.list`.
6. **Pin `origin mghp.osn.xsede.org` to priority 800** in
   `/etc/apt/preferences.d/prefbioc2u`.
7. Install `r-base-core`, `r-cran-biocmanager` and `r-cran-bspm`, run
   `BiocManager::install(version=...)`, and install `devtools`.

Step 6 decides which build of a package apt installs. r2u (pinned to 700) and
Ubuntu's archive (default 500) both carry some `r-bioc-*` packages, and r2u's
version strings carry a suffix (`2.72.0-1.ca2404.1`) that sorts above bioc2u's
(`2.72.0-1`). At 800, apt installs bioc2u's build even when another
repository's version string is higher, though it does not downgrade a package
already installed from elsewhere. The pin matches every package name, so the
repository is trusted ahead of the distribution for anything it publishes. See
[security.md](security.md).

### The two images

They differ in contents and in how they pick up a new R:

| | `bioc2u-user` | `bioc2u-builder` |
|---|---|---|
| Base | `ubuntu:<codename>` | `ghcr.io/bioconductor/r2u:<codename>-r-<version>` |
| For | Using Bioconductor | Building packages |
| Extra | — | `build-essential`, `devscripts`, `dh-make`, `dh-r`, `lintian`, Bioconductor system deps |
| New R | **Automatically**, from CRAN's apt repository at build time | **Only when `R_VERSION` is bumped** in `builder.Dockerfile` / the workflow matrix |

After an R release, a rebuilt `bioc2u-user:jammy` moves to the new R on its
own, while `bioc2u-builder:jammy` stays on the pinned R until `R_VERSION`
changes. The two can be on different R versions at the same time, and their
tags show it.

`ghcr.io/bioconductor/r2u` is built from
[Bioconductor/r2u](https://github.com/Bioconductor/r2u), a fork of
[rocker-org/r2u](https://github.com/rocker-org/r2u).

### `install_bioc_sysdeps.sh` and bspm

`builder.Dockerfile` fetches that script from `bioconductor_docker` and rewrites
it before running:

```dockerfile
sed -i 's/install.packages("BiocManager"/bspm::disable(); install.packages("BiocManager"/g'
sed -i 's/BiocManager::install(version=/bspm::disable(); BiocManager::install(version=/g'
```

The r2u base enables bspm, which routes `install.packages()` through apt.
`bspm::disable()` makes these two calls install from source instead.

There is also a retry:

```dockerfile
bash install_bioc_sysdeps.sh $BIOC_VERSION \
  || ( sed -i 's/--break-system-packages//g' install_bioc_sysdeps.sh && bash install_bioc_sysdeps.sh $BIOC_VERSION )
```

`--break-system-packages` is a `pip` flag that only exists on newer pip
(PEP 668). Jammy's pip predates it and rejects it; Noble's requires it. The
build tries the script as fetched and falls back to stripping the flag. The
upstream line that carries the flag is commented out; the fallback runs only
when it is active.

Both of these are **patches applied to a file fetched from another repository at
build time**. If `install_bioc_sysdeps.sh` upstream is reformatted so the `sed`
patterns do not match, the `sed` silently does nothing and the build fails
later, somewhere confusing. See
[troubleshooting.md](troubleshooting.md#builder-image-fails-somewhere-inside-install_bioc_sysdeps).

### The build workflow

`build_ghcr.yaml` runs on a schedule (`0 0 */2 * *`: midnight UTC on odd days
of the month), on manual dispatch, and on pushes that change a file matching
`**/Dockerfile`. That pattern matches only files named exactly `Dockerfile`, so
changes to `user.Dockerfile` and `builder.Dockerfile` do not start a build;
they wait for the next scheduled or manual run. `*.Dockerfile` would match
them.

Tags are not set at build time. The workflow:

1. builds each `(ubuntu, platform, type)` combination and pushes **by digest**;
2. runs a throwaway build against the pushed image to extract the actual R
   version and OS version from inside it;
3. creates a directory per intended tag, containing a file named for the digest;
4. in a `merge` job, walks those directories and creates a multi-arch manifest
   for each tag from the digests it finds.

Step 2 exists because **for `bioc2u-user` the R version is not known until the
image exists**: it installs whatever R CRAN's apt repository has that day, so
`jammy-r-4.6.1` can only be computed by asking the built image. For
`bioc2u-builder` the R version is pinned by `R_VERSION` and already in the
matrix, but it goes through the same extraction, because the matrix value is
passed only as a build-arg.

A build failing partway leaves images pushed by digest but not tagged:
reachable by hash, invisible by name.

`arm64` is built for Noble only, and its digest download in the merge job is
`continue-on-error: true`, so an arm64 failure degrades to an amd64-only
manifest rather than failing the build. The apt repository publishes `amd64`
and architecture-independent packages only: on arm64, Bioconductor packages
with compiled code are not available from it, and `BiocManager::install()`
compiles them from source.

## The producer side: `build/`

The `.deb` packages come from [`build/`](../build/), a Docker Compose stack
with [its own README](../build/README.md). That README is the reference; this
section covers how it relates to the rest of the repository.

**It runs inside the `bioc2u-builder` image.** `builder.Dockerfile` provides
the environment (`dh-r`, `dh-make`, `devscripts`, `lintian`, the Bioconductor
system dependencies) and `build/` runs the packaging in it.

The shape of a run:

| Stage | Script | What it does |
|---|---|---|
| Resolve | `deps_json.R` | Asks Bioconductor for every software, annotation and experiment package plus strong dependencies, keeps the Bioconductor ones (CRAN already comes from r2u), and writes `biocdeps.json` |
| Seed | `build_all.sh`, `make_deb.sh` | Builds `BiocVersion` first; it provides the `r-api-bioc-<version>` virtual package that most other packages depend on. Its ABI dependency is stripped from the built `.deb` and asserted; see [operations.md](operations.md#the-biocversion-seed) |
| Loop | `make_deb.sh`, `mark_done.sh` | Dispatches every package whose dependency list is empty, installs the resulting `.deb` so later packages link against it, then removes it from the other packages' dependency lists, which is what makes the next batch buildable |
| Repeat | `build_all.sh` | Until a full pass leaves `packages.json` unchanged. What remains was not built: the packages that failed, listed in `failed-packages.txt`, and the packages that waited on them, which stay only in `packages.json` |
| Publish | `upload.sh` | `deb-s3`, signed, a separate manual step |

Properties of a run:

- **It does not install from an earlier publish.** The builder image has no
  bioc2u repository configured; each package is built against the `.deb`
  files already built in the same debs directory.
- **State lives in the `debs` directory, not the container**, so an interrupted
  multi-hour run resumes. `done-<pkg>/` and `fail-<pkg>/` are what a re-run
  skips; deleting a `fail-` directory retries that package.
- **A failed package is not retried and does not stop the run.** It lands in
  `fail-<pkg>/`, so the published repository can be missing packages without
  anything having gone visibly wrong; see
  [operations.md](operations.md#known-gaps).

**Publishing is manual.** The repository index is signed and the signature is
made close to the upload: `upload.sh` reads S3 credentials from `~/.aws` and
the signing key from `~/.gnupg` on the operator's host, and prompts for the
passphrase. No CI job builds or publishes the packages, and nothing in CI holds
the key or the credentials. See [security.md](security.md).

## Relationship to r2u

bioc2u is a companion to r2u, not a fork. It delegates CRAN entirely: the setup
script runs r2u's own configuration script, and the builder image is built on
an r2u container image.

Practical consequences:

- **r2u's supported Ubuntu codenames bound bioc2u's.** r2u publishes
  `add_cranapt_<codename>.sh` for focal, jammy, noble and resolute; bioc2u
  builds jammy and noble.
- **An r2u change can break bioc2u** without anything here changing, since the
  setup script fetches r2u's script from `master` at run time, not a pinned
  revision.
- CRAN dependency resolution is r2u's.
