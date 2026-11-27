# agent-sandbox-image

This repository builds three image families:

- **OpenCode sandbox containers** (`latest` and `cms-latest`) for disposable
  application workspaces.
- **Kairos full sandbox host** (`kairos-latest`), a Fedora-based Kairos BYOI
  image with Podman, gVisor, Firecracker, Homebrew, and SSH key sync.
- **Fedora bootc sandbox host** (`fedora-minimal-latest`), the CLI/Homebrew/SSH
  tooling on the standard Fedora bootc base, without gVisor and Firecracker.

The two host images are separate from the OpenCode containers and each lives in
its own folder. Both are rebuilt weekly with buildable qcow2 artifacts. See
[`kairos/README.md`](kairos/README.md) and
[`fedora-minimal/README.md`](fedora-minimal/README.md) for build, boot, and
credential details.

## Repository layout

- `.github/workflows/build.yml` builds, publishes, and packages all three image
  families.
- `opencode/` contains the minimal and CMS sandbox Dockerfiles.
- `kairos/` contains the full Kairos host image and its cloud config.
- `fedora-minimal/` contains the Fedora bootc host image and its
  `bootc-image-builder` config.
- `scripts/smoke-test-qcow2.sh` boots a host qcow2 under QEMU and checks the
  basic host contract in CI.
- `renovate.json` tracks the pinned base images and GitHub Actions.

## OpenCode sandbox image

Minimal [OpenCode](https://opencode.ai) sandbox image built on
[Chainguard's Wolfi base](https://images.chainguard.dev/directory/image/wolfi-base/overview).

The image contains `opencode` plus the tools it expects at runtime: `bash`,
`git`, `curl`, `ripgrep`, CA certificates, `libgcc`, and `libstdc++`. It does
not include Node.js, compilers, or language runtimes; extend it if your
projects need those.

`opencode/cms.Dockerfile` is a variant that extends the minimal image with Chromium's
runtime libraries, [Playwright](https://playwright.dev), and
[cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/).
(The Playwright package brings in Node.js.)

## Pull

```sh
docker pull ghcr.io/felstormrage/agent-sandbox-image:latest

# CMS variant (Chromium, Playwright, cloudflared)
docker pull ghcr.io/felstormrage/agent-sandbox-image:cms-latest

# Full Kairos sandbox host
docker pull ghcr.io/felstormrage/agent-sandbox-image:kairos-latest

# Minimal Fedora bootc sandbox host
docker pull ghcr.io/felstormrage/agent-sandbox-image:fedora-minimal-latest
```

## Build the OpenCode sandbox

```sh
docker build -f opencode/minimal.Dockerfile -t opencode-sandbox .

# Install a different OpenCode release
docker build -f opencode/minimal.Dockerfile \
  --build-arg OPENCODE_VERSION=2.2.6 \
  -t opencode-sandbox .
```

Multi-arch build:

```sh
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f opencode/minimal.Dockerfile \
  -t opencode-sandbox .
```

The OpenCode version is pinned by `ARG OPENCODE_VERSION` in
`opencode/minimal.Dockerfile`. Bump it to upgrade.

To pin the Chainguard base by digest for a reproducible build, override
`WOLFI_BASE`:

```sh
docker build -f opencode/minimal.Dockerfile \
  --build-arg WOLFI_BASE=cgr.dev/chainguard/wolfi-base@sha256:<digest> \
  -t opencode-sandbox .
```

### CMS variant

`opencode/cms.Dockerfile` builds on the minimal image. To use a local minimal build,
build it first and pass it as `BASE_IMAGE` (the default is the published
minimal image):

```sh
docker build -f opencode/minimal.Dockerfile -t opencode-sandbox .
docker build -f opencode/cms.Dockerfile \
  --build-arg BASE_IMAGE=opencode-sandbox:latest \
  -t opencode-cms .
```

Or build against the published minimal image without a local base:

```sh
docker build -f opencode/cms.Dockerfile -t opencode-cms .
```

Chromium is baked into the CMS image at `/opt/playwright-browsers`, which is the
default `PLAYWRIGHT_BROWSERS_PATH`, so Playwright works out of the box:

```sh
docker run --rm -it \
  -v "$PWD:/workspace" \
  opencode-cms
```

If your project pins a different Playwright version, you can instead point it at
a project-managed browser directory:

```sh
docker run --rm -it \
  -v "$PWD:/workspace" \
  -e PLAYWRIGHT_BROWSERS_PATH=/workspace/.playwright-browsers \
  opencode-cms
```

Or install the project's browser in the container with
`playwright install chromium`.

## Host images

The host images are bootable OS artifacts, not container workspaces. Build
their source OCI images locally with:

```sh
# Full Kairos host (Fedora + Kairos BYOI)
docker build --platform linux/amd64 \
  -f kairos/Containerfile \
  --build-arg VERSION=0.1.0 \
  -t agent-sandbox-kairos .

# Fedora bootc host
docker build --platform linux/amd64 \
  -f fedora-minimal/Containerfile \
  --build-arg VERSION=0.1.0 \
  -t agent-sandbox-fedora-minimal .
```

Both images create a `nithin` user in `wheel` with passwordless sudo and inject
an SSH public key for key-only login. The first boot installs Homebrew into
`/home/linuxbrew` and installs the SSH key sync helper. The Kairos image also
includes gVisor and Firecracker plus the container-networking stack. The Fedora
image keeps the standard bootc base, including Podman and Skopeo, and adds the
CLI tooling without the gVisor/Firecracker stack.

SSH is key-only on both hosts; the password in `credentials.txt` is for the
serial console only. The `nithin` user has passwordless sudo, so treat SSH
access as root access and keep these hosts on a trusted network or behind a
VPN/firewall.

Each host folder documents its qcow2 artifact, boot settings, and update path:

- [`kairos/README.md`](kairos/README.md)
- [`fedora-minimal/README.md`](fedora-minimal/README.md)

## Run the OpenCode sandbox

```sh
docker run --rm -it \
  -v "$PWD:/workspace" \
  -e OPENCODE_API_KEY \
  opencode-sandbox
```

The image's entrypoint is `opencode` and its working directory is `/workspace`.
Like the original `box` sandbox, it runs as root; treat the VM as disposable.

## Use with microsandbox

The old `box` script bootstrapped Debian on every launch. With this image that
is no longer needed: the packages and OpenCode binary are already baked in.

```sh
msb run -t --name "$project_name" --replace \
  --cpus 2 --memory 2G --root-disk 4G \
  --mount-dir ./:/workspace:rw \
  --workdir /workspace \
  --mount-dir "$HOME/.agents/skills:/root/.agents/skills:ro" \
  --mount-named "opencode-config:/root/.config/opencode" \
  --mount-named "${project_name}-data:/root/.local/share/opencode" \
  --mount-named "${project_name}-state:/root/.local/state/opencode" \
  --mount-named "${project_name}-cache:/root/.cache/opencode" \
  --secret "OPENCODE_API_KEY@opencode.ai" \
  --secret-violation-action block \
  ghcr.io/felstormrage/agent-sandbox-image:latest
```

For a shell instead of the TUI:

```sh
msb run -t --name "$project_name" --replace \
  --mount-dir ./:/workspace:rw \
  --workdir /workspace \
  --secret "OPENCODE_API_KEY@opencode.ai" \
  --secret-violation-action block \
  --entrypoint /bin/bash \
  ghcr.io/felstormrage/agent-sandbox-image:latest
```

## CI

`.github/workflows/build.yml` builds all three image families and pushes them to
GHCR on pushes to `main`, version tags, manual runs, and a weekly schedule. Pull
requests build without pushing or creating disk artifacts.

The `build` job produces the minimal multi-arch OpenCode sandbox; the
`build-cms` job then layers `opencode/cms.Dockerfile` on that run's
`opencode-<version>` tag (or `:latest` for pull requests). Minimal sandbox images
are tagged with `latest` (on the default branch), the branch name, semver tags,
`opencode-<version>`, and the commit SHA. CMS images mirror those tags with a
`-cms` suffix, plus `cms-latest` on the default branch.

The independent host jobs build amd64 OCI images and, on non-PR runs, upload a
pre-installed qcow2 disk for Proxmox or another hypervisor:

- `build-kairos` publishes `kairos-<version>`, branch/PR, and commit tags, uses
  AuroraBoot and `qemu-img` to create `kairos-<version>-amd64.qcow2`, boot-tests
  the disk, and only then promotes `kairos-latest`.
- `build-fedora-minimal` publishes `fedora-minimal-<version>`, branch/PR, and
  commit tags, builds and boot-tests a qcow2, promotes `fedora-minimal-latest`
  on the default branch, then builds and boot-tests the published
  `fedora-minimal-<version>-amd64.qcow2` from that channel.

Both host images are signed with keyless cosign from the build workflow. The
Kairos updater verifies that signature and the exact image digest before
upgrading.

Each artifact ZIP contains the qcow2, `SHA256SUMS`, and a `credentials.txt` for
the `nithin` console login. Set the repository secret `HOST_SSH_PUBLIC_KEY` to
the public key authorized for key-only SSH; it is required. Set
`HOST_PASSWORD` to use a fixed console password; otherwise each run generates a
random one. See
[`kairos/README.md`](kairos/README.md#weekly-qcow2-artifact) and
[`fedora-minimal/README.md`](fedora-minimal/README.md#weekly-qcow2-artifact) for
the download, boot, and update flow.

If the GHCR package is private after the first publish, change its visibility in
the package settings if you want anonymous pulls.

### Base image note

Chainguard's `wolfi-base` points `apk` at `apk.cgr.dev/chainguard`, which
requires Chainguard credentials. `opencode/minimal.Dockerfile` switches the repository to
the public `https://packages.wolfi.dev/os` so CI builds work without secrets.
