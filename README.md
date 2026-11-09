# agent-sandbox-image

Minimal [OpenCode](https://opencode.ai) sandbox image built on
[Chainguard's Wolfi base](https://images.chainguard.dev/directory/image/wolfi-base/overview).

The image contains `opencode` plus the tools it expects at runtime: `bash`,
`git`, `curl`, `ripgrep`, CA certificates, `libgcc`, and `libstdc++`. It does
not include Node.js, compilers, or language runtimes; extend it if your
projects need those.

## Pull

```sh
docker pull ghcr.io/felstormrage/agent-sandbox-image:latest
```

## Build

```sh
docker build -f minimal.Dockerfile -t opencode-sandbox .

# Install a different OpenCode release
docker build -f minimal.Dockerfile \
  --build-arg OPENCODE_VERSION=2.2.6 \
  -t opencode-sandbox .
```

Multi-arch build:

```sh
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f minimal.Dockerfile \
  -t opencode-sandbox .
```

The OpenCode version is pinned by `ARG OPENCODE_VERSION` in
`minimal.Dockerfile`. Bump it to upgrade.

To pin the Chainguard base by digest for a reproducible build, override
`WOLFI_BASE`:

```sh
docker build -f minimal.Dockerfile \
  --build-arg WOLFI_BASE=cgr.dev/chainguard/wolfi-base@sha256:<digest> \
  -t opencode-sandbox .
```

## Run

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

`.github/workflows/build.yml` builds `linux/amd64` and `linux/arm64` images and
pushes them to GHCR on pushes to `main`, version tags, manual runs, and a weekly
schedule. Pull requests build without pushing. Images are tagged with `latest`
(on the default branch), the branch name, semver tags, `opencode-<version>`, and
the commit SHA.

If the GHCR package is private after the first publish, change its visibility in
the package settings if you want anonymous pulls.

### Base image note

Chainguard's `wolfi-base` points `apk` at `apk.cgr.dev/chainguard`, which
requires Chainguard credentials. `minimal.Dockerfile` switches the repository to
the public `https://packages.wolfi.dev/os` so CI builds work without secrets.
