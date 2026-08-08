# bioc2u documentation

Maintainer documentation for bioc2u: Ubuntu binaries for Bioconductor packages,
installable with `apt`.

The top-level [`README.md`](../README.md) is the **user-facing** guide: which
container to pull, how to set up the repository on your own Ubuntu machine, how
to install packages. Everything here is for the people who build, publish and
maintain it.

## Read in this order

| Document | Answers |
|---|---|
| [architecture.md](architecture.md) | What bioc2u is made of, how it relates to r2u, and where the `.deb` packages come from |
| [deployment.md](deployment.md) | Using bioc2u, building the container images, running your own apt repository |
| [troubleshooting.md](troubleshooting.md) | Symptom → cause → fix, for users and for maintainers |
| [security.md](security.md) | The signing key, the apt pin, and what installing from this repository means |

## Repository layout

This repository holds both halves of bioc2u:

- `build/` — the Docker Compose stack that produces the `.deb` packages and
  publishes them. It has [its own README](../build/README.md); the
  documentation here describes how it fits with everything else.
- `apt_setup.sh` — configures a machine to consume them; `uninstall.sh`
  reverses it
- `user.Dockerfile` / `builder.Dockerfile` — the two container images
- `.github/workflows/build_ghcr.yaml` — builds and publishes those images
