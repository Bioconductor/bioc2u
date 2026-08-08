# Deployment

Three different things get called "deploying bioc2u":

| | Covered |
|---|---|
| **Using it** — configure a machine or pull an image | [Using bioc2u](#using-bioc2u), and the top-level README |
| **Building the images** — the container build | [Running the container build](#running-the-container-build) |
| **Running an apt repository** — building and publishing the packages | [Running your own apt repository](#running-your-own-apt-repository) |

## Using bioc2u

### Containers

> A full tag exists only once the container workflow has run for that version,
> so check a tag before pinning it:
>
> ```bash
> docker manifest inspect ghcr.io/bioconductor/bioc2u-user:jammy-bioc-3.23-r-4.6.1
> ```

```bash
docker run --rm -it ghcr.io/bioconductor/bioc2u-user:jammy
docker run --rm -it ghcr.io/bioconductor/bioc2u-user:jammy-bioc-3.23-r-4.6.1   # pinned
docker run --rm -it ghcr.io/bioconductor/bioc2u-builder:jammy                  # build tooling
```

Pin the full tag for anything reproducible. See
[operations.md](operations.md#the-tagging-scheme).

### On an existing Ubuntu machine

```bash
sudo apt update -qq
sudo apt install -y --no-install-recommends curl ca-certificates
curl https://raw.githubusercontent.com/Bioconductor/bioc2u/devel/apt_setup.sh | sudo bash -s 3.23
```

Jammy (22.04) and Noble (24.04) only. In a container based on `ubuntu:jammy`
or `ubuntu:noble`, which runs as root and has no `sudo`, run the same commands
without `sudo`.

Before running it as root on a machine you care about, know that it:

- **Adds a signing key** to `/etc/apt/trusted.gpg.d/`, trusted for the whole
  system.
- **Pins `origin mghp.osn.xsede.org` to priority 800**, so it outranks Ubuntu's
  own archive and r2u.
- **Runs r2u's CRAN setup script**, fetched from `master` at run time.

See [security.md](security.md) for what each of those means. On a shared or
long-lived machine, read the script first rather than piping it to `sudo bash`.

### Verifying

```bash
apt-cache policy | grep -A2 mghp.osn.xsede.org      # repository present, priority 800
sudo apt install -y r-bioc-biocgenerics             # a binary install
Rscript -e 'library(BiocGenerics); BiocManager::version()'
Rscript -e 'packageVersion("bspm")'                 # bspm present
grep -r bspm /etc/R/Rprofile.site                    # ...and enabled system-wide
```

## Running the container build

To build the images yourself, for example for a fork:

```bash
git clone https://github.com/Bioconductor/bioc2u
cd bioc2u

docker build -f user.Dockerfile \
  --build-arg UBUNTU_TAG=jammy \
  --build-arg BIOC_VERSION=3.23 \
  -t bioc2u-user:jammy .

docker build -f builder.Dockerfile \
  --build-arg UBUNTU_TAG=jammy \
  --build-arg BIOC_VERSION=3.23 \
  --build-arg R_VERSION=4.6.1 \
  -t bioc2u-builder:jammy .
```

The builder needs `ghcr.io/bioconductor/r2u:jammy-r-4.6.1` to exist. If the
`R_VERSION` you pass has no r2u tag, the build fails immediately on the base
image.

### In CI

`.github/workflows/build_ghcr.yaml` runs on a schedule and on demand. It also
declares a push trigger for Dockerfile changes, but that filter does not match
this repository's Dockerfiles; see
[architecture.md](architecture.md#the-build-workflow). To run it in a fork:

- **No secrets to add.** It uses `secrets.GITHUB_TOKEN` and pushes to
  `ghcr.io/<owner>/<repo>-user` and `-builder`, derived from
  `github.repository`.
- **Enable GHCR write** for Actions: repository → Settings → Actions → Workflow
  permissions → Read and write. That setting gives `GITHUB_TOKEN` write access
  to every scope, including contents, issues and pull requests, in every
  workflow of the repository; [security.md](security.md#recommended-changes)
  describes a narrower `permissions:` block.
- **`ubuntu-latest-arm64` must exist.** The two arm64 legs target that runner
  label, which is not a GitHub-hosted label; on a fork without a runner of
  that name those jobs wait in the queue. Remove those matrix entries, provide
  the runner, or use GitHub's hosted `ubuntu-24.04-arm`. The `merge` job
  tolerates their absence (`continue-on-error` on the arm64 digest download),
  so the amd64 manifests still publish.
- **Every branch publishes.** The workflow pushes the same tags whichever
  branch it runs on, so test workflow changes in a fork.

Understand the two-phase build before changing it: images are pushed **by
digest**, the R version is then extracted from the built image, and a `merge`
job creates the tags. The R version cannot be known ahead of time because
`bioc2u-user` installs whatever CRAN's apt repository has that day. See
[architecture.md](architecture.md#the-build-workflow).

## Running your own apt repository

Everything needed is in [`build/`](../build/); [its README](../build/README.md)
is the reference.

What a host needs:

- Docker with Compose v2.
- Disk: several hundred GB, for the debs root and for Docker's data-root; see
  [build/README.md](../build/README.md#disk). Put both on a large volume
  rather than a small root disk.
- For publishing: write access to an S3-compatible bucket (`~/.aws`, or
  `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) and the secret signing key in
  a GnuPG keyring (`~/.gnupg`). Both stay on the host and are mounted into the
  upload container, which runs the builder image; nothing is baked into an
  image or a workflow. See [security.md](security.md#the-signing-key).

Steps:

1. Configure. The upload settings default to the Bioconductor bucket; to
   publish elsewhere, set `DEB_S3_ENDPOINT`, `DEB_S3_BUCKET`, `DEB_S3_PREFIX`
   and `GPG_SIGN_KEY` for your bucket and signing key:
   ```bash
   cd build
   cp .env.example .env      # R_VERSION, BIOC2U_DEBS_ROOT, GPG_SIGN_KEY, DEB_S3_*
   ```
2. Check the builder image for `R_VERSION` exists, and pull it. The tags are
   rebuilt in place, so a local copy can be older than its tag suggests:
   ```bash
   docker manifest inspect ghcr.io/bioconductor/bioc2u-builder:noble-r-<R_VERSION>
   docker compose pull
   ```
3. Build. A multi-hour run writing to `<debs root>/jammy` and
   `<debs root>/noble`, where `<debs root>` is `BIOC2U_DEBS_ROOT` from `.env`
   (`build/debs` when unset). `progress.sh` does not read `.env`, so give it
   the debs root:
   ```bash
   docker compose up                                            # jammy and noble side by side
   BIOC2U_DEBS_ROOT=<debs root> bash scripts/progress.sh -w 60  # from another terminal
   ```
   When the run has finished, remove the build containers, which keep every
   built package installed:
   ```bash
   docker compose down
   ```
4. Publish, one distro at a time. The index is signed at upload, and the
   passphrase is asked for in the terminal:
   ```bash
   BIOC2U_DRY_RUN=1 docker compose run --rm jammy-upload   # print the deb-s3 command only
   docker compose run --rm jammy-upload
   docker compose run --rm noble-upload
   ```
5. Verify from a blank container; see
   [operations.md](operations.md#publishing-a-release-build).

**Publishing elsewhere** also needs the armored public key at
`<endpoint>/<bucket>/<prefix>/bioc2u_key.asc`, and a fork of `apt_setup.sh`
with three edits: the `deb` line, the key URL, and the `Pin: origin` line,
which must name your endpoint's host. With the Bioconductor host left in the
pin, your repository gets apt's default priority, 500, and r2u's builds of
the `r-bioc-*` packages it also carries, pinned at 700, win. To verify, pass
`-e SETUP_URL=<URL of your apt_setup.sh>` to the `docker run` that runs
`verify_repo.sh`; without it, the script fetches the upstream `apt_setup.sh`.

See [architecture.md](architecture.md#the-producer-side-build) for how the
build relates to the rest of the repository.
