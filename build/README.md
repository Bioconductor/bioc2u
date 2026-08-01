# bioc2u build stack

Builds a `.deb` for every Bioconductor package and publishes them to the bioc2u
`apt` repository. This is the producer side of the project: the packages that
end up here are what `apt_setup.sh` and the `bioc2u-user` containers install.

Everything runs inside the `bioc2u-builder` containers, driven by Docker
Compose, so the only things needed on the host are Docker (Compose v2) and disk
space.

## Quick start

> **The builder image for the release must exist first.** `R_VERSION` selects
> the tag (`noble-r-4.6.1`), and those images are published by the container
> workflow in the repository root, not by anything here. Check before you
> start a multi-hour run:
>
> ```bash
> docker manifest inspect ghcr.io/bioconductor/bioc2u-builder:noble-r-${R_VERSION:-4.6.1}
> ```
>
> A build also refuses to run if `BIOC_VERSION` disagrees with the BiocManager
> pinned inside the image, because that combination builds one release's
> sources in another release's environment.

```bash
cd build
cp .env.example .env      # optional, the defaults work
docker compose up         # builds jammy and noble side by side
```

That is a multi-hour run that needs several hundred GB of disk (see
[Disk](#disk)), producing the `.deb` files under `debs/jammy` and
`debs/noble`. The exited containers keep every built package installed;
remove them once the run has finished:

```bash
docker compose down
```

To build one distro at a time and watch it:

```bash
docker compose run --rm jammy
```

Progress can be checked at any time from the host, while the build runs.
`progress.sh` looks under `./debs`, or under `BIOC2U_DEBS_ROOT` from the
environment; it does not read `.env`:

```bash
bash scripts/progress.sh          # both distros
bash scripts/progress.sh -w 60    # refresh every minute
BIOC2U_DEBS_ROOT=/mnt/bioc2u/debs bash scripts/progress.sh   # the debs root set in .env
```

Publishing is a separate, manual step, because the repository index is signed
and the signature has to be made close to the upload:

```bash
docker compose run --rm jammy-upload
```

That reads S3 credentials from `~/.aws` and the signing key from `~/.gnupg` on
the host (`AWS_DIR` / `GNUPG_DIR` to point elsewhere), and asks for the key's
passphrase in the terminal. Set `BIOC2U_DRY_RUN=1` to see the `deb-s3` command
without uploading anything. The upload and shell services sit behind Compose
profiles, so a plain `docker compose up` only ever builds.

To work on a build by hand, use the shell services, which land in `/root/debs`
with the same environment the build loop uses:

```bash
docker compose run --rm jammy-shell
```

### After publishing

A successful upload does not show that the repository installs: the build host
already has every package installed. Check from a blank container:

```bash
docker run --rm -v "$PWD/scripts/verify_repo.sh:/v.sh:ro" ubuntu:noble bash /v.sh
```

It checks the BiocVersion apt would pick (the *candidate*, not whichever stanza
comes first), that packages resolve, and that one installs and loads under R.
`BIOC` sets the release (default `3.23`), `NEW_PKG` the package to install
(default `r-bioc-deseq2`); use `ubuntu:jammy` for jammy. Non-zero exit on
failure, so it is usable in CI.

## Configuration

All of it goes in `.env`; see [`.env.example`](.env.example) for the full list.
The ones that matter most:

| Variable | Default | Meaning |
| --- | --- | --- |
| `R_VERSION` | `4.6.1` | Picks the builder image tag, eg `jammy-r-4.6.1` |
| `BIOC2U_DEBS_ROOT` | `./debs` | Where `.debs` and build state are written |
| `BIOC_VERSION` | image's `BiocManager` | Bioconductor release to build |
| `BIOC2U_REFRESH_DEPS` | `0` | Re-resolve the dependency graph instead of resuming |
| `GPG_SIGN_KEY` | unset | Key the published index is signed with |
| `BIOC2U_ALSO_PROVIDE_ABI` | unset | Extra ABI for BiocVersion to provide (migration aid) |
| `BIOC2U_ALLOW_RELEASE_CHANGE` | `0` | Continue a debs dir from a different release |

The container workflow rebuilds the builder image tags in place, so a local
copy can be older than the tag suggests. `docker compose pull` before starting
a fresh run.

### Disk

A Bioconductor 3.23 build needs, per distro:

| Where | What | Size |
| --- | --- | --- |
| `BIOC2U_DEBS_ROOT/<codename>/` | The `.deb` files | About 130 GB |
| `BIOC2U_DEBS_ROOT/<codename>/done-*/` | The source tarballs | About as much again |
| Docker's data-root | The build container's writable layer, where every built package is installed | About 180 GB |

`docker compose up` builds both distros at once, which doubles each figure.
Point `BIOC2U_DEBS_ROOT` at a large volume, and put Docker's data-root
(`/var/lib/docker` unless `data-root` is set in `/etc/docker/daemon.json`) on
one as well. The source tarballs are not needed once a run has finished:

```bash
rm <debs root>/<codename>/done-*/*.tar.gz
```

## How the build works

1. **Dependency graph** — `deps_json.R` asks Bioconductor for every software,
   annotation and experiment package and their strong dependencies, keeps the
   Bioconductor ones (CRAN packages already come from [r2u][r2u]), and writes
   `biocdeps.json`.
2. **Working copy** — `packages.json` starts as a copy of that graph and is the
   state of the run.
3. **Seed** — `BiocVersion` is built first; it provides the
   `r-api-bioc-<version>` virtual package that most other packages depend on.
   Its control is corrected on the built `.deb`, not in `debian/control`:
   `dh-r` injects a Bioconductor dependency through `${R:Depends}` derived from
   the BiocVersion installed in the *builder*, so the seed inherits a
   dependency on the previous release's ABI. `make_deb.sh` strips it and
   checks the result, and the run stops if the seed did not build correctly.
4. **Loop** — every package whose dependency list is empty gets dispatched to
   `make_deb.sh`, which downloads the source tarball, runs `dh-make-R` /
   `dh-update-R` / `dpkg-buildpackage`, installs the resulting `.deb` so the
   packages built after it can link against it, and files the leftovers in
   `done-<pkg>/`. `mark_done.sh` then removes it from the other packages'
   dependency lists, which is what makes the next batch buildable. A package
   that does not produce a `.deb` lands in `fail-<pkg>/` instead and is not
   retried.
5. **Repeat** until a full pass leaves `packages.json` unchanged. Whatever is
   still in the graph at that point was not built. `failed-packages.txt` lists
   only the packages that were tried and failed; the packages that waited on a
   failed dependency are only in `packages.json`, which `progress.sh` counts as
   "left in graph".

The builder image has no bioc2u repository configured, so a run never installs
`r-bioc-*` packages from an earlier publish. Each package's Bioconductor
dependencies are installed from the `.deb` files already built in the same
debs directory, with `--allow-downgrades`, so they replace any `r-bioc-*`
package that r2u supplied as a dependency of a CRAN package. `entrypoint.sh` pins `r-bioc-*`
from a Debian archive to priority -1.

### Changing release

A debs directory records the release it belongs to in `.bioc-version`, and a
build refuses to continue one that belongs to a different release. Resuming
across a release would carry every already-built package into the new
repository with the *old* ABI stamp.

Build a new release in a fresh directory (`BIOC2U_DEBS_ROOT`). To reuse one in
place, clear the state first and say so explicitly:

```bash
rm -rf debs/noble/done-* debs/noble/fail-* debs/noble/packages.json
BIOC2U_REFRESH_DEPS=1 BIOC2U_ALLOW_RELEASE_CHANGE=1 docker compose run --rm noble
```

`BIOC2U_ALSO_PROVIDE_ABI=r-api-bioc-<older>` makes BiocVersion also provide an
older ABI, so packages carried over from that release stay installable. It is a
migration aid for an existing repository, not something to set for a clean
release build.

### Resuming

State lives in the `debs` directory, not in the container, so an interrupted
run picks up where it stopped: re-run the same command. `done-<pkg>/` and
`fail-<pkg>/` are what a re-run skips: delete a `fail-<pkg>` directory to give
that package another try, and set `BIOC2U_REFRESH_DEPS=1` to pull a fresh
dependency graph (this restarts the graph walk, but already-built packages are
still skipped).

## Files

| File | Role |
| --- | --- |
| `docker-compose.yml` | The services: build, shell and upload, per distro |
| `scripts/entrypoint.sh` | Per-container setup: apt pinning, packaging tools |
| `scripts/build_all.sh` | The build loop |
| `scripts/make_deb.sh` | Builds one package into a `.deb` |
| `scripts/deps_json.R` | Resolves the Bioconductor dependency graph |
| `scripts/mark_done.sh` | Removes a finished package from the graph |
| `scripts/upload.sh` | `deb-s3` publish, signed |
| `scripts/progress.sh` | Build progress, runs on the host too |
| `scripts/repair_biocversion.sh` | Repair an already-built BiocVersion deb, no rebuild |
| `scripts/verify_repo.sh` | Check the published repository is installable |
| `scripts/lib.sh` | Shared helpers |

The scripts are bind-mounted into the containers, so editing one takes effect
on the next `docker compose run` without rebuilding or pulling anything.

[r2u]: https://eddelbuettel.github.io/r2u
