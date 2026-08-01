# Troubleshooting

## Users

### `E: Unable to locate package r-bioc-...`

In order of likelihood:

1. **Name wrong.** The convention is `r-bioc-` plus the package name
   **lowercased**: `GenomicRanges` → `r-bioc-genomicranges`.
2. **Setup did not complete.** `apt_setup.sh` has no `set -e`, so a failed step
   partway through leaves a half-configured machine and can still exit 0.
   Check:
   ```bash
   apt-cache policy | grep mghp.osn.xsede.org
   ```
   Nothing there means re-run the setup and watch the output.
3. **Package not built.** Not every Bioconductor package has a `.deb`. Falling
   back to `BiocManager::install()` works; it compiles from source.
4. **Unsupported codename.** Jammy and Noble only.

### Nothing installs at all: `r-api-bioc-X but it is not installable`

```
r-bioc-biocversion : Depends: r-api-bioc-<older release> but it is not installable
E: Unable to correct problems, you have held broken packages.
```

The seed is broken. Every package that depends on `r-api-bioc-<release>`,
directly or through another package, pulls `BiocVersion`, so this blocks nearly
the whole repository, not only the package you asked for. Check
the candidate specifically, not `apt-cache show`, which prints every version
and lets you read `Depends` from one stanza and `Provides` from another:

```bash
cand=$(apt-cache policy r-bioc-biocversion | awk '/Candidate:/{print $2}')
apt-cache show "r-bioc-biocversion=$cand" | grep -E '^(Version|Depends|Provides)'
```

`BiocVersion` must **provide** `r-api-bioc-<release>` and depend on no ABI at
all. If it depends on one, repair it without rebuilding; see
[operations.md](operations.md#the-biocversion-seed).

### A package exists in the index but will not install

If the error names an *older* ABI than the release you set up, the package was
not rebuilt for the current release, and the repository still carries its
previous build with the old `r-api-bioc-<version>` stamp. Install it from
source instead:

```bash
Rscript -e 'bspm::disable(); BiocManager::install("<Package>")'
```

Maintainers: rebuild it, or remove it from the index
([operations.md](operations.md)).

### apt installs a package from r2u or Ubuntu instead of bioc2u

The pin is missing or wrong. `apt_setup.sh` writes
`/etc/apt/preferences.d/prefbioc2u` giving `origin mghp.osn.xsede.org` priority
800. r2u pins its own repository to 700 and carries some `r-bioc-*` packages
with higher version strings, so without the pin r2u's build wins.

```bash
cat /etc/apt/preferences.d/prefbioc2u
apt-cache policy r-bioc-biobase      # the candidate should be the version from mghp.osn.xsede.org
```

### `install.packages()` still compiles from source

bspm is not active, or the package has no binary.

```bash
Rscript -e 'packageVersion("bspm")'
grep -r bspm /etc/R/Rprofile.site
Rscript -e 'bspm::enable()'
```

`r-cran-bspm` is installed by the setup script; r2u's `add_cranapt_*` script
enables it system-wide in `Rprofile.site`. If the lines are missing, the CRAN
setup step failed; re-run the setup and watch the output.

### `NO_PUBKEY` / `The following signatures couldn't be verified`

The signing key is missing from `/etc/apt/trusted.gpg.d/bioc2u_key.asc`:

```bash
sudo curl -o /etc/apt/trusted.gpg.d/bioc2u_key.asc \
  https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/bioc2u_key.asc
sudo apt update -qq
```

Do not work around this with `--allow-unauthenticated` or `[trusted=yes]`. The
signature is what stands between apt and anything served from that host. See
[security.md](security.md).

### A package installs but will not load

Usually an R version mismatch: a package built against one R, loaded under
another. Check which R is installed and where it came from, and where the
package came from:

```bash
R --version
apt-cache policy r-base-core
apt-cache policy r-bioc-<package>
```

R should come from CRAN's Ubuntu repository (`cloud.r-project.org`) and the
package from bioc2u (see the pin, above). A `bioc2u-builder` and a
`bioc2u-user` image can be on different R versions; their tags show which.

## Maintainers

### Builder image fails somewhere inside `install_bioc_sysdeps`

`builder.Dockerfile` fetches that script from `bioconductor_docker@devel` and
patches it with `sed` before running:

```dockerfile
sed -i 's/install.packages("BiocManager"/bspm::disable(); install.packages("BiocManager"/g'
sed -i 's/BiocManager::install(version=/bspm::disable(); BiocManager::install(version=/g'
```

**If upstream reformats those lines, `sed` matches nothing, succeeds, and the
build fails later somewhere that looks unrelated.**

Check the patch applies:

```bash
curl -sO https://raw.githubusercontent.com/Bioconductor/bioconductor_docker/devel/bioc_scripts/install_bioc_sysdeps.sh
grep -c 'install.packages("BiocManager"' install_bioc_sysdeps.sh   # expect >= 1
grep -c 'BiocManager::install(version=' install_bioc_sysdeps.sh    # expect >= 1
```

Zero means upstream changed.

### Builder fails on `--break-system-packages`

The Dockerfile retries with the flag stripped:

```dockerfile
bash install_bioc_sysdeps.sh $BIOC_VERSION \
  || ( sed -i 's/--break-system-packages//g' install_bioc_sysdeps.sh && bash install_bioc_sysdeps.sh $BIOC_VERSION )
```

The flag is PEP 668 and only exists on newer pip. Jammy's rejects it, Noble's
requires it. The upstream line that carries it is commented out. If **both**
attempts fail, the cause is something else: read above the pip error.

### Builder fails on a missing base image

```
ghcr.io/bioconductor/r2u:<codename>-r-<version>: not found
```

`R_VERSION` was bumped before that r2u tag was published. The tag comes from
the `build_ghcr.yaml` workflow in
[Bioconductor/r2u](https://github.com/Bioconductor/r2u), which runs every two
days only while it is enabled; GitHub turns it off after 60 days without
activity in that repository. Check the tag and the workflow:

```bash
docker manifest inspect ghcr.io/bioconductor/r2u:<codename>-r-<version>
gh api repos/Bioconductor/r2u/actions/workflows/build_ghcr.yaml --jq .state
```

If the state is `disabled_inactivity`, enable it. Then start a run, or pin
`R_VERSION` back:

```bash
gh workflow enable build_ghcr.yaml --repo Bioconductor/r2u
gh workflow run build_ghcr.yaml --repo Bioconductor/r2u --ref devel
```

### The merge job cannot find digests

The `merge` job downloads artifacts named
`bioc2udigests-<ubuntu>-<type>-<platform>-<run_id>` and fails if the amd64 one
is missing, meaning that build leg failed. Fix the leg; the merge is a
symptom.

The arm64 download is `continue-on-error: true`, so an arm64 failure degrades to
an amd64-only manifest rather than failing the run.

### Images pushed but not tagged

Expected when a build fails partway. Images are pushed **by digest** first and
tagged by the `merge` job, so a failure between the two leaves images reachable
only by hash. Re-running the workflow tags a new build. It also explains a
registry that looks emptier than the build log suggests.

### The R version in the tag is not what was expected

`bioc2u-user` installs whatever R CRAN's apt repository has at build time, and
the tag is derived from the built image rather than from the matrix, so the tag
reports the R that is in the image.

`bioc2u-builder` is different: its R comes from the pinned r2u base. The two can
differ.

### Everything builds but users report missing packages

The container build does not check that the apt repository has anything new in
it. A repository that has stopped updating produces good containers that
install stale packages.

```bash
curl -s https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/dists/jammy/release/binary-amd64/Packages \
  | grep -c '^Package:'
```

Nothing monitors this; see [operations.md](operations.md#known-gaps).
