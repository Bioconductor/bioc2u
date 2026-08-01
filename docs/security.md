# Security considerations

bioc2u distributes compiled binaries that users install as root, and asks them
to trust its repository ahead of Ubuntu's own.

## What a user is trusting

Running `apt_setup.sh` does three security-relevant things:

1. **Installs a signing key** into `/etc/apt/trusted.gpg.d/bioc2u_key.asc`.
   Keys there are trusted for **any** repository apt is configured with, not
   only this one.
2. **Adds a repository** served over HTTPS from OSN.
3. **Pins `origin mghp.osn.xsede.org` to priority 800**, above Ubuntu's default
   500 and r2u's 700.

The pin decides what gets installed. Anything that host publishes wins over
the distribution's and r2u's package of the same name, and the preference
matches `Package: *`, so that holds for **any** package name, not only R
packages:

```
Package: *
Pin: origin mghp.osn.xsede.org
Pin-Priority: 800
```

A package named `openssl` or `sudo` appearing in that repository would take
precedence over Ubuntu's. The repository carries only R packages (`r-bioc-*`,
and a few `r-bioconductor-*` and `r-other-*` on jammy), but the pin does not
restrict itself to those. See [Recommended changes](#recommended-changes).

### Why the pin exists

r2u pins its own repository to 700 and carries some `r-bioc-*` packages, built
as dependencies of CRAN packages, with version strings that sort above
bioc2u's. Ubuntu's archive carries some as well. The pin makes apt install
bioc2u's build of every `r-bioc-*` package, whatever the version strings say.

## `curl | sudo bash`

The documented installation is:

```bash
curl https://raw.githubusercontent.com/Bioconductor/bioc2u/devel/apt_setup.sh | sudo bash -s 3.23
```

The user executes, as root, whatever is on the `devel` branch at that moment.
`apt_setup.sh` then fetches and runs a second script from **r2u's `master`
branch**, also as root:

```bash
curl -O https://raw.githubusercontent.com/eddelbuettel/r2u/master/inst/scripts/add_cranapt_$UBUNTU_CODENAME.sh
bash add_cranapt_$UBUNTU_CODENAME.sh
```

So a user running the one-liner trusts two repositories' current branch state,
not a reviewed release. Neither fetch is pinned to a tag or a checksum. On a
shared or long-lived machine, download the script, read it, then run it.

## `apt_setup.sh` has no error handling

There is no `set -e`. A failed `curl`, a failed `apt install`, or a failed
`BiocManager::install()` does not stop the script: execution carries on to the
next line with the machine in whatever state that failure left it. The exit
status is that of the *last* command, so it reports on the final
`BiocManager::install(c('devtools'))` and nothing else: a run that failed to add
the repository can still exit 0.

The security-relevant case: if the key fetch fails but the sources line is still
written, the machine ends up with a configured repository whose signature cannot
be verified. apt refuses to install from it, which is the right outcome, but
the user sees `NO_PUBKEY` rather than a setup failure, and may reach for
`[trusted=yes]`.

## The signing key

The public key is served from the same bucket as the packages:

```
https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/bioc2u_key.asc
```

Fetched over HTTPS, so the transport is authenticated by the OSN certificate.
Anyone who can write to that bucket can replace both the key and the packages
it signs, which means **bucket write access is equivalent to signing authority**.
The signature protects against a compromised mirror or a network attacker; it
does not protect against a compromised bucket.

**The private key lives on the operator's machine.** The upload services in
`build/docker-compose.yml` mount `~/.gnupg` (or `GNUPG_DIR`) read-write and
`~/.aws` (or `AWS_DIR`) into a `bioc2u-builder` container. `upload.sh` selects
the key with `GPG_SIGN_KEY`, and gpg asks for the passphrase inside that
container.

No CI system holds the key or the bucket credentials, and publishing needs a
person at a terminal. **The upload container is inside the signing trust
boundary**: whatever the builder image contains runs with the whole mounted
keyring, the passphrase and the S3 credentials. That image is the
`<codename>-r-<R>` tag, which the container workflow rebuilds every two days
from unpinned upstream scripts, and which a run on any branch can publish. See
[Recommended changes](#recommended-changes).

The key's availability depends on the operators who hold it: keep an offline,
encrypted backup. Losing it means publishing under a new key that every
configured machine has to fetch again.

## Container images

- Published to GHCR by a workflow using `secrets.GITHUB_TOKEN`. No long-lived
  credential is stored in the repository.
- Images run as **root**: `user.Dockerfile` sets `USER root` explicitly, and
  the builder inherits root from the r2u base. Reasonable for a build
  container; relevant if one is used as a runtime base.
- The builder fetches and `sed`-patches a script from `bioconductor_docker@devel`
  at build time. Same unpinned-upstream concern as above, in a place where the
  result is published for others to use.

## What installing a package means

A `.deb` runs maintainer scripts as root at install time, and an R package can
contain compiled code that runs in-process. Installing from bioc2u is as
trustworthy as Bioconductor's review plus this pipeline, as for any binary
distribution.

## Recommended changes

None of these is applied. The first four change behaviour on machines that are
already configured; the others change how images are built and packages are
published.

1. **Narrow the pin** to R packages, which keeps bioc2u's builds ahead of r2u's
   and Ubuntu's and removes the ability to shadow the base system:
   ```
   Package: r-*
   Pin: origin mghp.osn.xsede.org
   Pin-Priority: 800
   ```
2. **Scope the key to the repository** with `Signed-By`, instead of
   `/etc/apt/trusted.gpg.d/`, which confers system-wide trust:
   ```
   # /etc/apt/sources.list.d/bioc2u.sources
   Types: deb
   URIs: https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/
   Suites: jammy
   Components: release
   Signed-By: /usr/share/keyrings/bioc2u-archive-keyring.asc
   ```
   Combined with the narrowed pin, that closes both broad permissions
   described above.
3. **Fail fast in `apt_setup.sh`** with `set -euo pipefail`.
4. **Pin r2u's setup script** to a commit rather than `master`, or verify a
   checksum of the fetched script.
5. **Give the upload a keyring of its own.** Point `GNUPG_DIR` at a directory
   that holds only the bioc2u signing key, or a signing subkey, rather than a
   personal `~/.gnupg`, and `AWS_DIR` at one that holds only the bucket's
   credentials:
   ```bash
   install -d -m 700 /srv/bioc2u/gnupg
   gpg --export-secret-keys --armor <key id> | gpg --homedir /srv/bioc2u/gnupg --import
   ```
6. **Upload from a pinned image.** Run the upload services from the builder
   image a verified build used, by digest, rather than from a freshly pulled
   tag. Record the digest after the build
   (`docker image inspect --format '{{index .RepoDigests 0}}' <image>`), and do
   not `docker compose pull` between that build and the upload.
7. **Pin `deb-s3`.** `ensure_deb_s3` in `build/scripts/lib.sh` installs the
   latest gem from RubyGems on every upload, in the container that holds the
   key. Install a fixed version (`gem install deb-s3 -v <deb-s3 version>`), or bake
   one into the image the uploads run from.
8. **Narrow the workflow token.** `build_ghcr.yaml` has no `permissions:` block,
   so its `GITHUB_TOKEN` gets the repository's default permissions, and
   publishing needs that default to be "Read and write" for every scope. A
   block in the workflow grants only what it needs, and the default can stay
   read-only:
   ```yaml
   permissions:
     contents: read
     packages: write
   ```
9. **Pin third-party actions to commit SHAs.** The `docker/*` actions run with
   a token that can write packages, and a major tag such as `v6` is moved by
   its owner. Pin each to a full commit SHA, with the version as a comment:
   ```yaml
   uses: docker/build-push-action@<commit sha> # v6.x.y
   ```

## Reporting a vulnerability

Do not open a public issue. Email the Bioconductor core team at
[bioconductorcoreteam@gmail.com](mailto:bioconductorcoreteam@gmail.com), the
contact published on [bioconductor.org/about](https://bioconductor.org/about/).
