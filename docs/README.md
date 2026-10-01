# bioc2u documentation

Maintainer documentation for bioc2u: Ubuntu binaries for Bioconductor packages,
installable with `apt`.

The top-level [`README.md`](../README.md) is the **user-facing** guide: which
container to pull, how to set up the repository on your own Ubuntu machine, how
to install packages. Everything here is for the people who build, publish and
maintain it.

## Quick facts

| | |
|---|---|
| apt repository | `https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/`: suites `jammy` and `noble`, component `release`, `amd64` and architecture-independent packages |
| Signing key | `https://mghp.osn.xsede.org/bir190004-bucket01/bioc2u/bioc2u_key.asc` |
| Container images | `ghcr.io/bioconductor/bioc2u-user`, `ghcr.io/bioconductor/bioc2u-builder`; jammy amd64, noble amd64 and arm64 |
| Current release | Bioconductor 3.23 on R 4.6.1 |
| Image builds | GitHub Actions, `.github/workflows/build_ghcr.yaml`, on a schedule and on demand |
| Package builds | `build/`, Docker Compose on an operator's host; publishing is manual and signed |
| Hosting | An Open Storage Network (OSN) S3 bucket for the repository, GHCR for the images |
| Depends on | r2u (CRAN binaries and its setup scripts), `ghcr.io/bioconductor/r2u` (builder base, from Bioconductor/r2u), `install_bioc_sysdeps.sh` from Bioconductor/bioconductor_docker |

## Read in this order

| Document | Answers |
|---|---|
| [architecture.md](architecture.md) | What bioc2u is made of, how it relates to r2u, and where the `.deb` packages come from |
| [deployment.md](deployment.md) | Using bioc2u, building the container images, running your own apt repository |
| [operations.md](operations.md) | Publishing a build, the BiocVersion seed, the tagging scheme, health checks, backups |
| [updating.md](updating.md) | Bioconductor and R releases, Ubuntu codenames, base images, GitHub Actions: cadence, procedure, checks, rollback |
| [troubleshooting.md](troubleshooting.md) | Symptom → cause → fix, for users and for maintainers |
| [security.md](security.md) | The signing key, the apt pin, and what installing from this repository means |
| [examples/](examples/) | Worked setups: CI, a Dockerfile, a bare Ubuntu machine, pinning, a release build host |

## Repository layout

This repository holds both halves of bioc2u:

- `build/` — the Docker Compose stack that produces the `.deb` packages and
  publishes them. It has [its own README](../build/README.md); the
  documentation here describes how it fits with everything else.
- `apt_setup.sh` — configures a machine to consume them; `uninstall.sh`
  reverses it
- `user.Dockerfile` / `builder.Dockerfile` — the two container images
- `.github/workflows/build_ghcr.yaml` — builds and publishes those images
