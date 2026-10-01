# Updating

What changes in bioc2u, how often, how to update it, how to check the update
worked, and how to undo it. Commands that use `docker compose` or `scripts/`
run from `build/`; the others run from the repository root.

The procedures need `gh`, logged in with write access to Bioconductor/bioc2u
and Bioconductor/r2u, and Docker with Buildx.

## Cadence

| What | When | Section |
|---|---|---|
| Bioconductor release | Twice a year: spring (April or May) and autumn (October or November) | [Bioconductor release](#bioconductor-release) |
| R | `x.y.0` each April, with the spring Bioconductor release; patch releases during the year | [R release](#r-release) |
| Ubuntu LTS | A new LTS every two years in April; each gets five years of standard support | [Ubuntu LTS](#ubuntu-lts) |
| Base images and the build stack | Every container workflow run, and before every package build | [Base images and the build stack](#base-images-and-the-build-stack) |
| GitHub Actions | Twice a year, with the Bioconductor release, and when a run shows deprecation warnings | [GitHub Actions](#github-actions) |
| Upstream scripts | Before each release build | [Upstream scripts](#upstream-scripts) |

## Bioconductor release

Bioconductor publishes the release and its R version in
[config.yaml](https://bioconductor.org/config.yaml) (`release_version`,
`r_ver_for_bioc_ver`). The spring release moves to a new R minor version; the
autumn release keeps the spring release's R.

### Procedure

The release is bumped in two parts. Every workflow run builds both image types
from their own matrix entries, so if the `user` entries move with the
`builder` entries, that run and every scheduled run after it move the user
tags (`jammy`, `noble`, `*-bioc-<release>`) to images set up for a release
whose packages are not published yet.

1. **Bump the builder side**:

   | File | What |
   |---|---|
   | `.github/workflows/build_ghcr.yaml` | `biocversion` in the three `type: builder` entries |
   | `builder.Dockerfile` | the `BIOC_VERSION` ARG default |
   | `build/.env.example` | the `BIOC_VERSION` and `BIOC2U_ALSO_PROVIDE_ABI` examples |

   For a spring release, do the [R release](#r-release) bump in the same change.
2. **Build the builder images** for the new release: merge the bump, then run
   the workflow and wait for it to finish. Until step 5, this run and the
   scheduled ones rebuild the user images for the previous release.
   ```bash
   gh workflow run build_ghcr.yaml --repo Bioconductor/bioc2u --ref devel
   gh run watch --repo Bioconductor/bioc2u
   ```
3. **Check the builder** is pinned to the new release:
   ```bash
   docker run --rm ghcr.io/bioconductor/bioc2u-builder:noble-bioc-<release>-r-<R> \
     Rscript -e 'cat(as.character(BiocManager::version()))'
   ```
4. **Build and publish the packages** in a fresh debs root; see
   [operations.md](operations.md#publishing-a-release-build). Keep the previous
   release's debs directory until step 6 passes.
5. **Bump the user side** once the packages are published, merge it, and run
   the workflow again:

   | File | What |
   |---|---|
   | `.github/workflows/build_ghcr.yaml` | `biocversion` in the three `type: user` entries |
   | `user.Dockerfile` | the `BIOC_VERSION` ARG default |
   | `apt_setup.sh` | the `BIOC_VERSION` default |
   | `build/scripts/verify_repo.sh` | the `BIOC` default |
   | `README.md`, `docs/` | example tags and commands |

   Then check what still names the release being replaced, `<previous>`:
   ```bash
   git grep -n -F '<previous>'
   ```
   The `BIOC2U_ALSO_PROVIDE_ABI` example in `build/.env.example` names
   `r-api-bioc-<previous>`; any other hit is a missed bump.
   The ARG defaults are overridden by the workflow, so a missed one does not
   break CI; it breaks anyone who builds a Dockerfile by hand.
6. **Verify**, for jammy and noble:
   ```bash
   docker run --rm -e BIOC=<release> -v "$PWD/scripts/verify_repo.sh:/v.sh:ro" ubuntu:noble bash /v.sh
   docker run --rm ghcr.io/bioconductor/bioc2u-user:noble-bioc-<release>-r-<R> \
     Rscript -e 'BiocManager::version(); BiocManager::valid()'
   ```
   and check the packages per ABI stamp
   ([operations.md](operations.md#health-checks)).
7. **Remove the packages the release did not build**; see
   [operations.md](operations.md#removing-packages-the-current-release-does-not-build).

### Rollback

- **Images**: the previous release's full tags
  (`<codename>-bioc-<previous>-r-<R>`) stay on GHCR. Revert the bump and run
  the workflow; the short tags move back. To move them back without a
  rebuild, see [Rolling back a published image](#rolling-back-a-published-image).
- **Repository**: re-upload the previous release's debs directory; see
  [operations.md](operations.md#backups-and-restore).

## R release

`bioc2u-user` installs R from CRAN's apt repository at build time, so a
rebuild picks up a new R without any change here. `bioc2u-builder` is built
`FROM ghcr.io/bioconductor/r2u:<codename>-r-<R>` and only moves when
`R_VERSION` is bumped.

Packages built against R `x.y.z` depend on `r-api-4.0` and, on jammy,
`r-base-core (>= x.y.z)`; a later patch release satisfies both, so it does not
require rebuilding the packages. A new minor version arrives with the spring
Bioconductor release, which rebuilds them.

### Procedure

1. **Wait for the r2u base image** for the new R. Bumping first makes every
   builder build fail on a missing base image. The image comes from the
   `build_ghcr.yaml` workflow in
   [Bioconductor/r2u](https://github.com/Bioconductor/r2u), which runs every
   two days only while it is enabled; GitHub turns it off after 60 days without
   activity in that repository. Check its state, enable it if it reads
   `disabled_inactivity`, start a run, and check the tags:
   ```bash
   gh api repos/Bioconductor/r2u/actions/workflows/build_ghcr.yaml --jq .state
   gh workflow enable build_ghcr.yaml --repo Bioconductor/r2u
   gh workflow run build_ghcr.yaml --repo Bioconductor/r2u --ref devel
   docker manifest inspect ghcr.io/bioconductor/r2u:noble-r-<R>
   docker manifest inspect ghcr.io/bioconductor/r2u:jammy-r-<R>
   ```
2. **Bump R**:

   | File | What |
   |---|---|
   | `.github/workflows/build_ghcr.yaml` | `rversion` in every matrix entry (six) |
   | `builder.Dockerfile` | the `R_VERSION` ARG default |
   | `build/.env.example` | `R_VERSION`, and the tag in the `docker manifest inspect` comment |
   | `build/docker-compose.yml` | the `R_VERSION` default in all six `image:` lines |
   | `build/README.md`, `README.md`, `docs/` | example tags |

   Then check what still names the R version being replaced:
   ```bash
   git grep -n -F '<previous R>'
   ```
3. **Run the workflow**, then confirm the builder and user images are on the
   same R:
   ```bash
   for t in builder user; do
     docker run --rm --pull always ghcr.io/bioconductor/bioc2u-$t:noble Rscript -e 'cat(R.version.string, "\n")'
   done
   ```

Between an R release and the bump, the user images are on the new R and the
builder images on the old one, and the tags show it. Keep the window short.

### Rollback

Revert the bump and run the workflow. The previous `-r-<R>` tags stay on GHCR.

## Ubuntu LTS

bioc2u builds jammy (22.04) and noble (24.04). Canonical's standard support
ends in May 2027 for jammy and May 2029 for noble. Ubuntu 26.04 (resolute),
released in April 2026, is the next codename to add.

### Adding a codename

Each item below is needed before the codename works end to end:

1. **r2u supports it.** `apt_setup.sh` runs r2u's setup script for the codename:
   ```bash
   curl -fsI https://raw.githubusercontent.com/eddelbuettel/r2u/master/inst/scripts/add_cranapt_<codename>.sh
   ```
2. **The r2u base image exists.** `ghcr.io/bioconductor/r2u` is built from
   [Bioconductor/r2u](https://github.com/Bioconductor/r2u), a fork of
   [rocker-org/r2u](https://github.com/rocker-org/r2u) with a directory per
   codename and matrix entries per codename and platform. Bring the
   codename's directory over from upstream, add it to that repository's
   workflow, and check:
   ```bash
   docker manifest inspect ghcr.io/bioconductor/r2u:<codename>-r-<R>
   ```
3. **The images build.** Add `builder` and `user` matrix entries for the
   codename to `build_ghcr.yaml` and add it to the `ubuntu` list of the
   `merge` job. An `arm64` pair is optional; it also needs the codename in the
   condition on the merge job's arm64 digest download.
   `install_bioc_sysdeps.sh` installs a fixed list of system packages, so a
   package renamed in the new release fails the builder build there.
4. **The build stack knows it.** `build/docker-compose.yml` defines the build,
   shell and upload services per codename; copy the noble ones.
5. **The repository carries it.** Build and publish the codename's packages;
   the first upload creates `dists/<codename>/`. The containers build against a
   repository without it and look fine, so check:
   ```bash
   curl -fsI https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/dists/<codename>/Release
   ```
6. **Uninstalling works.** `uninstall.sh --all` removes the files r2u's setup
   scripts create, listed by name. Compare that list with what the new
   codename's r2u script writes. Resolute's writes
   `/etc/apt/trusted.gpg.d/eddelbuettel.asc` and `rutter.asc`, which the list
   does not include.
7. **Verify** with `verify_repo.sh` in `ubuntu:<codename>`, and update
   `README.md` and `docs/`.

### Retiring a codename

Remove its matrix entries, its `merge` list entry and its compose services.
Published images and the repository's `dists/<codename>/` stay available but
stop receiving updates; say so in the README.

## Base images and the build stack

| Image or tool | Pinned by | Moves when |
|---|---|---|
| `ghcr.io/bioconductor/r2u:<codename>-r-<R>` (builder base) | `R_VERSION` | Bioconductor/r2u's `build_ghcr.yaml` rebuilds the tag every two days while that workflow is enabled; each builder build pulls the current one |
| `ubuntu:<codename>` (user base) | `UBUNTU_TAG` | Every user build pulls the current one |
| `install_bioc_sysdeps.sh` | nothing (`bioconductor_docker@devel`) | Every builder build |
| `ghcr.io/bioconductor/bioc2u-builder:<codename>-r-<R>` (build stack) | `R_VERSION` in `.env` | Every container workflow run |
| `deb-s3` | nothing (latest gem) | Installed by each upload |
| `dh-r`, `debhelper`, `devscripts` | the builder image | Every builder build |

Nothing here needs a version bump. Before every package build:

```bash
docker compose pull
docker compose run --rm noble bash -c 'Rscript -e "BiocManager::version()"; dpkg -l dh-r | tail -1'
```

The first command picks up the current builder image; the second shows what
the build will run with. Record the digest of the image a good build used
before pulling a new one:

```bash
docker image inspect --format '{{index .RepoDigests 0}}' ghcr.io/bioconductor/bioc2u-builder:noble-r-<R>
```

To roll the build stack back to it, pull that digest, `docker tag` it as the
tag compose uses, and run without `docker compose pull`.

To upload with a known-good `deb-s3`, install that version in the upload
container first; `ensure_deb_s3` then skips the install:

```bash
docker compose run --rm noble-upload bash -c \
  'apt-get update -qq && apt-get install -y --no-install-recommends rubygems >/dev/null &&
   gem install deb-s3 -v <deb-s3 version> && bash /opt/bioc2u/scripts/upload.sh'
```

### Rolling back a published image

A scheduled run rebuilds every tag of both images from their current inputs
(`ubuntu:<codename>`, the r2u base image, r2u's setup script,
`install_bioc_sysdeps.sh`), so a bad upstream change reaches the short and full
tags within two days. To put the tags back on the last good image:

1. Stop the schedule, so the next run does not undo the rollback:
   ```bash
   gh workflow disable build_ghcr.yaml --repo Bioconductor/bioc2u
   ```
2. Find the last good image index. GHCR keeps the images a tag pointed at
   before, untagged; listing them needs a `gh` token with `read:packages`:
   ```bash
   gh api '/orgs/Bioconductor/packages/container/bioc2u-user/versions?per_page=30' \
     --jq '.[] | [.created_at, .name, (.metadata.container.tags | join(" "))] | @tsv'
   docker buildx imagetools inspect ghcr.io/bioconductor/bioc2u-user@sha256:<digest>
   ```
   An index lists every platform; a per-platform image lists one.
3. Point each tag the bad run moved at it, logged in to `ghcr.io` with a token
   that can write the organization's packages. The
   [tagging scheme](operations.md#the-tagging-scheme) lists the tags:
   ```bash
   docker buildx imagetools create -t ghcr.io/bioconductor/bioc2u-user:noble \
     ghcr.io/bioconductor/bioc2u-user@sha256:<digest>
   ```
   Repeat for `bioc2u-builder` if it is affected.
4. Check that the tag carries that digest, on the `Digest:` line:
   ```bash
   docker buildx imagetools inspect ghcr.io/bioconductor/bioc2u-user:noble
   ```
5. Fix or pin the cause (see [Upstream scripts](#upstream-scripts)), then
   enable the workflow and run it:
   ```bash
   gh workflow enable build_ghcr.yaml --repo Bioconductor/bioc2u
   gh workflow run build_ghcr.yaml --repo Bioconductor/bioc2u --ref devel
   ```

## GitHub Actions

`build_ghcr.yaml` pins each action to a major version:

| Action | Pinned |
|---|---|
| `actions/checkout` | `v4` |
| `docker/metadata-action` | `v5` |
| `docker/setup-buildx-action` | `v3` |
| `docker/login-action` | `v3` |
| `docker/build-push-action` | `v6` |
| `actions/upload-artifact` | `v4` |
| `actions/download-artifact` | `v4` |

### Procedure

1. List the latest release of each:
   ```bash
   for a in actions/checkout docker/metadata-action docker/setup-buildx-action \
            docker/login-action docker/build-push-action \
            actions/upload-artifact actions/download-artifact; do
     printf '%-28s %s\n' "$a" "$(gh api repos/$a/releases/latest --jq .tag_name)"
   done
   ```
2. Read the release notes of every major version in between. The artifact
   actions carry the digests from the build jobs to the `merge` job, so a
   change in how they name or unpack artifacts breaks tagging.
3. Bump and run the workflow **in a fork**: it publishes the same tags from
   any branch it runs on. Set the fork up as in
   [deployment.md](deployment.md#in-ci): GHCR write for Actions, and a runner
   for the arm64 label, GitHub's `ubuntu-24.04-arm`, or no arm64 entries.
   Otherwise the arm64 jobs stay queued and the merge jobs do not start.
4. Check that every build leg and the four merge jobs pass, and that the tags
   moved:
   ```bash
   gh run list --repo <fork> --workflow build_ghcr.yaml --limit 1
   docker manifest inspect ghcr.io/<fork owner>/bioc2u-user:noble
   ```

Pinning each action to a full commit SHA, with the version as a comment, is
safer than a major tag; see [security.md](security.md#recommended-changes).
With SHA pins, step 3 replaces the SHA and the comment.

The runner labels need the same review: `ubuntu-latest` moves to new Ubuntu
releases on GitHub's schedule, and `ubuntu-latest-arm64` is an organization
runner label (see [deployment.md](deployment.md#in-ci)).

### Rollback

Revert the bump and run the workflow.

## Upstream scripts

Two scripts are fetched at build or setup time rather than pinned, and both
can break bioc2u without any change here:

- **r2u's `add_cranapt_<codename>.sh`**, from `master`. Any change lands
  immediately in every `apt_setup.sh` run.
- **`install_bioc_sysdeps.sh`** from `bioconductor_docker@devel`, which
  `builder.Dockerfile` then patches with `sed`. If it is reformatted so the
  patterns do not match, **the `sed` succeeds having changed nothing** and
  the build fails later somewhere unrelated-looking.

Before each release build, check that the patterns still match:

```bash
curl -fsSL https://raw.githubusercontent.com/Bioconductor/bioconductor_docker/devel/bioc_scripts/install_bioc_sysdeps.sh |
  grep -c -e 'install.packages("BiocManager"' -e 'BiocManager::install(version='   # expect 2
```

### Rollback

Pin the fetch to the last good commit until upstream is fixed, then run the
workflow. To restore the images before that, see
[Rolling back a published image](#rolling-back-a-published-image).

- **r2u's script**: in `apt_setup.sh`, replace `master` in the `add_cranapt_`
  URL with a commit SHA. The change reaches every `apt_setup.sh` run at once.
- **`install_bioc_sysdeps.sh`**: in `builder.Dockerfile`, replace `devel` in its
  URL with a commit SHA.

```bash
gh api 'repos/eddelbuettel/r2u/commits?path=inst/scripts/add_cranapt_noble.sh&per_page=5' \
  --jq '.[] | [.sha, .commit.committer.date] | @tsv'
gh api 'repos/Bioconductor/bioconductor_docker/commits?path=bioc_scripts/install_bioc_sysdeps.sh&per_page=5' \
  --jq '.[] | [.sha, .commit.committer.date] | @tsv'
```
