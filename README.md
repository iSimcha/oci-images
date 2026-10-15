# oci-images

OCI Images

## Base images

`base/` builds two images with the same tool set, one on Debian and one on Alpine, for other images to build on:

| Image                         | Base             |
| ----------------------------- | ---------------- |
| `ghcr.io/isimcha/debian-base` | `debian:13-slim` |
| `ghcr.io/isimcha/alpine-base` | `alpine:3.24`    |

Both run as the non-root user `dev`, who has passwordless `sudo`, with `/home/dev` as the working directory. An image
that builds on one of them switches to `USER root` to install packages.

The tool set is the union of what `iSimcha/devcontainer-features` and `iSimcha/common` install or require:

- Secret scanners, at the versions `devcontainer-features/.github/workflows/check-secrets.yml` runs: Kingfisher,
  TruffleHog, Nosey Parker, Titus.
- The `dev-shell` feature: Nushell with every `nu_plugin_*` it ships, ouch, and each entry of
  `src/dev-shell/packages.json`: ripgrep, uv/uvx, biome, caddy, just, d2, xh, gomplate, yq, bun, fj, yt, fd, starship,
  rage.
- `common/.scripts/packages.json`, which `dev-shell` dropped: deno, watchexec.
- Commands `common.just` requires: ruff, git, plus cspell, Claude Code (`claude`) and prettier as npm globals. `gcloud`
  is deliberately left out; images that need it build on top of these.
- OS: bash, curl, git, jq, openssh client, sudo, Node.js 24 and npm.

### Alpine compatibility

Every tool runs on Alpine. Most release assets are static (Rust musl or Go) and are the same file on both images. Four
tools differ:

| Tool | Debian                                     | Alpine                                    | Why                                                                              |
| ---- | ------------------------------------------ | ----------------------------------------- | -------------------------------------------------------------------------------- |
| bun  | `bun-linux-x64.zip`                        | `bun-linux-x64-musl.zip`                  | The default build links glibc; the musl build needs `libstdc++` and `libgcc`.    |
| deno | release asset v2.7.4                       | Alpine package `deno` (2.7.4 in 3.24)     | glibc only. `gcompat` cannot load it (`__res_init`, `__memcpy_chk` are missing). |
| rage | release asset v0.11.1                      | Alpine package `rage` (0.11.1 in 3.24)    | The release asset links glibc.                                                   |
| node | nodejs.org v24.21.0 (Debian 13 ships 20.x) | Alpine package `nodejs` (24.18.1 in 3.24) | cspell and Claude Code need Node 22 or newer.                                    |

An Alpine package version follows the Alpine 3.24 repository rather than a pin in `config.yml`, so `test.nu` prints the
version each build actually installed.

The Claude Code npm package picks its `linux-x64-musl` binary on Alpine on its own, and that binary links only musl.

### Configuration

`base/config.yml` is the single source for versions. Every release asset carries a `sha256`, either the checksum the
project publishes for the release or, where there is none (ouch), the hash of the download, as noted beside the entry.
The build fails on a mismatch or a missing checksum. To add a tool, add an entry to `binaries` with its `commands`;
`test.nu` checks every command listed there.

### Tags

`<published.version>-<distro>-<distro version>`, one exact tag per build and no `latest`:

```
debian-base:v1.0.0-debian-13
alpine-base:v1.0.0-alpine-3.24
```

Bump `published.version` in `base/config.yml` when anything in `base/` changes.

### Building and testing

```nu
./base/build.nu debian
./base/build.nu alpine
./base/test.nu debian
./base/test.nu alpine
```

`test.nu` runs every command's version check inside the image as `dev`, registers every Nushell plugin, and checks
`sudo`. It prints a PASS/FAIL table and exits non-zero naming each command that failed.

`.github/workflows/build-base.yml` builds and tests both images on pull requests and pushes that touch `base/`, and
pushes them to GHCR only from `main`.
