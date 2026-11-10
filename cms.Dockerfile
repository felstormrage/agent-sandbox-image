# syntax=docker/dockerfile:1

# CMS OpenCode sandbox image.
#
# Extends the minimal OpenCode sandbox with the shared libraries Chromium needs
# at runtime, plus Playwright and cloudflared. Build the minimal image first:
#
#   docker build -f minimal.Dockerfile -t opencode-sandbox .
#   docker build -f cms.Dockerfile \
#     --build-arg BASE_IMAGE=opencode-sandbox:latest -t opencode-cms .
#
# The default base is the published minimal image, so cms.Dockerfile also
# builds on its own:
#
#   docker build -f cms.Dockerfile -t opencode-cms .
ARG BASE_IMAGE=ghcr.io/felstormrage/agent-sandbox-image:latest
FROM ${BASE_IMAGE}

# Automatic platform arguments, redeclared so they can be used in RUN.
ARG BUILDPLATFORM
ARG TARGETPLATFORM

LABEL org.opencontainers.image.title="opencode-cms-sandbox" \
      org.opencontainers.image.description="OpenCode CMS sandbox with Chromium runtime libraries, Playwright, and cloudflared"

ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers

# Chromium/Playwright runtime dependencies. Wolfi splits NSS into libnss (which
# provides libnss3.so) and a metadata-only nss package, so install libnss only.
# libatk-bridge-2.0 is a separate package rather than a dependency of
# libatk-1.0. binutils is intentionally omitted: it was only needed to inspect
# missing libraries with readelf and is not a runtime dependency.
#
# Playwright browser binaries are not downloaded here. Use an existing
# .playwright-browsers directory (set PLAYWRIGHT_BROWSERS_PATH), or run
# `playwright install chromium` inside the container.
#
# The install below bakes the project-matched Chromium browser into
# /opt/playwright-browsers. Do not use --with-deps: Wolfi has no apt, so
# Playwright's system dependency installer cannot run here.
#
# Wolfi is a rolling distribution, so package versions are intentionally not
# pinned; rebuilding refreshes them along with the base image.
# hadolint ignore=DL3018
RUN set -eux; \
    apk add --no-cache --no-progress \
        alsa-lib \
        at-spi2-core \
        cairo \
        cloudflared \
        cups \
        dbus-libs \
        expat \
        fontconfig \
        freetype \
        glib \
        libatk-1.0 \
        libatk-bridge-2.0 \
        libdrm \
        libnspr \
        libnss \
        libx11 \
        libxcb \
        libxcomposite \
        libxdamage \
        libxext \
        libxfixes \
        libxkbcommon \
        libxrandr \
        libxrender \
        libxshmfence \
        mesa \
        nodejs-24 \
        npm \
        pango \
        playwright \
        wayland-libs-client \
        ttf-dejavu; \
    rm -rf /var/cache/apk/*; \
    npm exec --yes --package=playwright@1.63.0 -- playwright install --no-shell chromium; \
    if [ "${BUILDPLATFORM:-}" = "${TARGETPLATFORM:-}" ]; then \
        cloudflared --version; \
        playwright --version; \
        node --version; \
        npm --version; \
    fi
