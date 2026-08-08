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
