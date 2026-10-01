# Operations

Commands that use `docker compose` or `scripts/` run from `build/`.

## The tagging scheme

Eight tags per image type, in six shapes:

| Shape | Example | Points at |
|---|---|---|
| codename | `jammy` | the latest build |
| codename + R | `jammy-r-4.6.1` | the latest build with that R |
| codename + Bioc | `jammy-bioc-3.23` | the latest build for that release |
| codename + Bioc + R | `jammy-bioc-3.23-r-4.6.1` | the latest build for that release and R |
| OS version | `22.04` | as `jammy` |
| OS version + R / Bioc / both | `22.04-bioc-3.23-r-4.6.1` | as the codename forms |

Each build moves every tag that matches it. The fullest tag is the reproducible
name: when R 4.6.2 arrives, `jammy-bioc-3.23` moves to it and
`jammy-bioc-3.23-r-4.6.1` keeps pointing at the last 4.6.1 build. Rebuilds
within the same versions still replace the image behind that tag, so for an
immutable reference use a digest: `ghcr.io/bioconductor/bioc2u-user@sha256:...`.

## The BiocVersion seed

Most `r-bioc-*` packages depend on `r-api-bioc-<release>`, a virtual package
that only BiocVersion provides; annotation packages and a few others carry no
such dependency. The published BiocVersion must:

- **provide** `r-api-bioc-<release>` for the release it belongs to, and
- **depend on no `r-api-bioc-*`** at all.

If it depends on an ABI that nothing provides, BiocVersion cannot install, and
neither can any package that depends on `r-api-bioc-<release>`, directly or
through another package: nearly the whole repository.

`dh-r` breaks the second rule on its own: it derives a package's Bioconductor
dependency from the BiocVersion installed in the *builder* and injects it via
`${R:Depends}` at `dpkg-buildpackage` time, so the seed inherits the previous
release's ABI. These guards handle it:

| Guard | Where |
|---|---|
| The seed's ABI dependency is stripped from the built `.deb` | `fix_biocversion_deb()` in `build/scripts/lib.sh` |
| The build **stops** if the seed is still wrong or did not build | `assert_biocversion_deb()`, called from `make_deb.sh`, and the check after the seed in `build_all.sh` |
| The published repository is checked from a blank container | `build/scripts/verify_repo.sh` |
| A debs directory belongs to one release | `.bioc-version`, checked by `build_all.sh` |

The last one matters because a run resumes by skipping `done-<pkg>/`: resuming
a previous release's debs directory would carry its packages, with their old
`r-api-bioc-<version>` stamp, into the new release.

To repair an already-built seed without rebuilding anything, run
`repair_biocversion.sh` where the debs are, then publish. In a shell service,
which has the `dpkg-deb` it needs:

```bash
docker compose run --rm -e DEBS=/root noble-shell bash /opt/bioc2u/scripts/repair_biocversion.sh
docker compose run --rm noble-upload
```

That rewrites the control file of one small package, with no R and no
recompilation, and bumps its Debian revision so it supersedes the published
one.

By default BiocVersion is left providing **only** the release it defines, which
is what the virtual package is for: a package built against an older release
must not be satisfied by a newer install. Packages carried over from an older
release stay uninstallable until they are rebuilt.

`KEEP_PREV=1` also provides the older ABI, which makes those packages
installable again. It is a temporary unblock for an existing repository, not a
default: as a habit, BiocVersion accumulates every historical ABI and the
virtual package stops meaning anything.

## Publishing a release build

1. **Check that the builder images for the release exist.** `R_VERSION`
   selects the tag, and `build/` does not build those; the container workflow
   in the repository root does. After an `R_VERSION` bump the new tag does not
   exist until that workflow has run.
   ```bash
   docker manifest inspect ghcr.io/bioconductor/bioc2u-builder:noble-r-4.6.1
   docker compose pull
   ```
2. **Use a fresh debs root.** Do not resume the previous release's. Set it in
   `.env`, so the upload uses the same directory:
   ```bash
   BIOC2U_DEBS_ROOT=/mnt/bioc2u/debs-3.23
   ```
3. **Do not set `BIOC2U_ALSO_PROVIDE_ABI`** for a clean release build. It is a
   migration aid for repairing an existing repository.
4. **Build**. `progress.sh` does not read `.env`, so give it the debs root:
   ```bash
   docker compose up
   BIOC2U_DEBS_ROOT=/mnt/bioc2u/debs-3.23 bash scripts/progress.sh -w 60   # from another terminal
   ```
   Then, in each distro's directory, review `failed-packages.txt`, which lists
   the packages that were tried and failed, and what is left in
   `packages.json`, which also holds the packages that waited on a failed
   dependency:
   ```bash
   python3 -c 'import json; print("\n".join(sorted(json.load(open("packages.json")))))'
   ```
   Remove the build containers, which keep every built package installed:
   `docker compose down`.
5. **Publish**, then **verify from a blank container**: a green upload proves
   nothing, because the build host already has everything installed.
   ```bash
   docker compose run --rm noble-upload
   docker run --rm -e BIOC=3.23 -v "$PWD/scripts/verify_repo.sh:/v.sh:ro" ubuntu:noble bash /v.sh
   ```
   Repeat both for jammy (`jammy-upload`, `ubuntu:jammy`).

## Health checks

| Check | Expect |
|---|---|
| `curl -fsS https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/dists/noble/Release \| grep '^Date:'` | The date of the last publish, for each of `jammy` and `noble` |
| `verify_repo.sh` from a blank container (see [above](#publishing-a-release-build)) | `PASS` |
| Packages per ABI stamp (below) | All but a few on the current release |
| `gh run list --repo Bioconductor/bioc2u --workflow build_ghcr.yaml --limit 5` | A successful run within the last two days |
| `gh run list --repo Bioconductor/bioc2u --workflow build_ghcr.yaml --event schedule --limit 1` | A scheduled run within the last two days |
| `gh api repos/Bioconductor/bioc2u/actions/workflows/build_ghcr.yaml --jq .state` | `active` |
| `gh api repos/Bioconductor/r2u/actions/workflows/build_ghcr.yaml --jq .state` | `active`: this workflow publishes the builder base image, including the tag for a new R |
| `docker manifest inspect ghcr.io/bioconductor/bioc2u-user:noble-bioc-3.23-r-4.6.1` | A manifest list with `amd64` and `arm64` |

Packages per ABI stamp, for one distro:

```bash
curl -fsS https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/dists/noble/release/binary-amd64/Packages.gz |
  gzip -dc | grep '^Depends:' | grep -oE 'r-api-bioc-[0-9.]+' | sort | uniq -c
```

BiocVersion provides only the current release's ABI, so every package counted
under an older one is uninstallable; see
[Removing packages the current release does not build](#removing-packages-the-current-release-does-not-build).
Packages without a stamp, mostly annotation packages, are not counted.

GitHub turns off a public repository's scheduled workflows after 60 days
without repository activity (state `disabled_inactivity`), and a workflow can
read `active` while its schedule does not run. For both, see
[troubleshooting.md](troubleshooting.md#the-images-have-not-been-rebuilt-for-days).

## Removing packages the current release does not build

`deb-s3 upload` adds and replaces packages but never removes one. A package
the new release did not build (it failed, or it left Bioconductor) keeps its
previous build in the index. If that build carries an older
`r-api-bioc-<version>` stamp, which the current BiocVersion does not provide,
apt reports it as not installable; if it carries none, as most annotation
packages do, it still installs at its old version. Removing it makes apt report
it as missing, and `BiocManager::install()` then builds it from source.

List them for one distro. First the packages stamped for an older release:

```bash
curl -fsS https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/dists/noble/release/binary-amd64/Packages.gz |
  gzip -dc |
  awk -v cur='r-api-bioc-3.23' '/^Package:/ {p=$2} /^Depends:/ && /r-api-bioc-/ && index($0, cur) == 0 {print p}'
```

Then the packages the release does not have at all, stamped or not:

```bash
rel=3.23
for p in bioc data/annotation data/experiment; do
  curl -fsS "https://bioconductor.org/packages/$rel/$p/src/contrib/PACKAGES"
done | awk '/^Package:/ {print "r-bioc-" tolower($2)}' | sort -u > release.txt
curl -fsS https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/dists/noble/release/binary-amd64/Packages.gz |
  gzip -dc | awk '/^Package: r-bioc-/ {print $2}' | sort -u | comm -23 - release.txt
```

Remove them with `deb-s3 delete <package> --arch=all`, passing the same
endpoint, bucket, prefix, codename, component and `--sign` flags as the upload
(`BIOC2U_DRY_RUN=1 docker compose run --rm noble-upload` prints them). In the
upload service:

```bash
docker compose run --rm noble-upload bash -c \
  'export GPG_TTY=$(tty); source /opt/bioc2u/scripts/lib.sh && ensure_deb_s3 &&
   deb-s3 delete <package> --arch=all <flags>'
```

`deb-s3 clean` with the same flags then deletes the files the index does not
reference.

## Backups and restore

| State | Lives in | Restore from |
|---|---|---|
| The published repository: index and pool | The OSN bucket, under `bioc2u/` | The debs directories: re-upload each distro with `docker compose run --rm <codename>-upload` |
| Built packages and build state | `BIOC2U_DEBS_ROOT` on the build host | A rebuild, which takes hours. Keep the previous release's directory until the new release is verified |
| The secret signing key | The keyrings of the operators who publish | An offline, encrypted export: `gpg --export-secret-keys --armor <key id>` |
| The public key | `bioc2u/bioc2u_key.asc` in the bucket | `gpg --export --armor <key id>`, uploaded to the same path |
| Container images | GHCR | A run of the container workflow |

Without the secret key, the repository has to move to a new key: generate one,
replace `bioc2u/bioc2u_key.asc`, and publish; the upload signs the index with
the new key. Every configured machine then has to fetch the new public key, the
same way `apt_setup.sh` does:

```bash
sudo curl -o /etc/apt/trusted.gpg.d/bioc2u_key.asc \
  https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/bioc2u_key.asc
```

To roll the repository back to the previous release, re-upload that release's
debs directory: without `--preserve-versions`, `deb-s3` replaces each package's
index entry with the uploaded version. Machines that already upgraded keep the
newer packages; apt does not downgrade on its own.

## Known gaps

**Failed packages are invisible after the fact.** `make_deb.sh` files a package
that does not build into `fail-<pkg>/` and the run carries on, so the published
repository can be missing packages without anything having looked wrong.
`failed-packages.txt` is written at the end of a run but is not published
anywhere, and nothing compares one release's package count against the last.
A user meets it as "package not found", with no way to tell whether that
package was never built or never existed.

**Nothing monitors the apt repository.** If it stopped updating, the containers
would keep building and the failure would surface as "package not found" reported
by a user. The Bioconductor status page (dev.status.bioconductor.org) already
checks other paths in the same OSN bucket and could carry a bioc2u check.

**No test that a published image works.** The workflow verifies the image builds
and extracts its R version; nothing installs a Bioconductor package and loads it.
A smoke test — `apt install -y r-bioc-biocgenerics && Rscript -e 'library(BiocGenerics)'`
— would catch a repository that built but is not usable.

**`apt_setup.sh` has no error handling.** No `set -e`, so a failed curl or a
failed `apt install` continues to the next line and leaves a half-configured
machine. The exit status reflects only the last command, so such a run can
still report success.
