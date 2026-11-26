# syntax=docker/dockerfile:1

# Minimal OpenCode sandbox image.
#
# Chainguard's wolfi-base is a small glibc-based image with apk and a shell.
# Its default /etc/apk/repositories points at Chainguard's authenticated
# repository, which cannot be used by anonymous builds, so switch apk to the
# public Wolfi repository.
ARG WOLFI_BASE=cgr.dev/chainguard/wolfi-base:latest
FROM ${WOLFI_BASE}

# OpenCode release to install. The build workflow reads this value and tags
# the resulting image with it. Bump it to upgrade OpenCode.
ARG OPENCODE_VERSION=2.2.6

# Automatic platform arguments, redeclared so they can be used in RUN.
ARG TARGETARCH
ARG BUILDPLATFORM
ARG TARGETPLATFORM

LABEL org.opencontainers.image.title="opencode-sandbox" \
      org.opencontainers.image.description="Minimal OpenCode sandbox based on Chainguard Wolfi"

# Runtime dependencies: bash for the shell tool and entrypoint, git/ripgrep
# for the agent, curl + CA certificates for HTTPS, and the GCC runtime for the
# Bun-compiled OpenCode binary.
# Wolfi is a rolling distribution, so package versions are intentionally not
# pinned; rebuilding refreshes them along with the base image.
# hadolint ignore=DL3018
RUN set -eux; \
    printf '%s\n' 'https://packages.wolfi.dev/os' > /etc/apk/repositories; \
    apk add --no-cache \
        bash \
        ca-certificates-bundle \
        curl \
        git \
        gzip \
        libgcc \
        libstdc++ \
        ripgrep; \
    rm -rf /var/cache/apk/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# OpenCode ships a self-contained native binary in per-platform npm packages.
# Download it directly instead of piping a remote installer to bash. On amd64
# use the baseline build (matching OpenCode's official image) so it also runs
# on CPUs without AVX2. The opencode2 symlink keeps the legacy command name.
RUN set -eux; \
    arch="${TARGETARCH:-$(apk --print-arch)}"; \
    case "$arch" in \
        amd64|x86_64) oc_arch="x64-baseline" ;; \
        arm64|aarch64) oc_arch="arm64" ;; \
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    pkg="cli-linux-${oc_arch}"; \
    tmp="$(mktemp -d)"; \
    curl -fsSL "https://registry.npmjs.org/@opencode/${pkg}/-/${pkg}-${OPENCODE_VERSION}.tgz" -o "${tmp}/opencode.tgz"; \
    tar -xzf "${tmp}/opencode.tgz" -C "${tmp}"; \
    mkdir -p /usr/local/bin; \
    install -m 0755 "${tmp}/package/bin/opencode" /usr/local/bin/opencode; \
    ln -sf opencode /usr/local/bin/opencode2; \
    rm -rf "${tmp}"; \
    if [ "${BUILDPLATFORM:-}" = "${TARGETPLATFORM:-}" ]; then \
        smoke_home="$(mktemp -d)"; \
        HOME="${smoke_home}" opencode --version; \
        rm -rf "${smoke_home}" /tmp/opencode /tmp/.bun-*; \
    fi

ENV HOME=/root \
    SHELL=/bin/bash \
    BUN_RUNTIME_TRANSPILER_CACHE_PATH=0

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/opencode"]
# Clear the inherited /bin/sh default command so no argument is passed to opencode.
CMD []
