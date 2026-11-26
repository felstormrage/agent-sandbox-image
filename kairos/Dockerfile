# syntax=docker/dockerfile:1

# Kairos host image for the homelab k3s node. The application repositories
# remain responsible for Kubernetes workloads; this image owns the immutable OS,
# k3s provider, and host runtime prerequisites required by those workloads.

ARG KAIROS_INIT_VERSION=v4.5.0
FROM quay.io/kairos/kairos-init:${KAIROS_INIT_VERSION} AS kairos-init

FROM alpine:3.22 AS runtime-assets

ARG TARGETARCH
ARG GVISOR_VERSION=20261123.1
ARG KATA_VERSION=4.4.0

# Keep release archives out of the final image layers after extracting them into
# /runtime-root. All downloads are verified with upstream release digests.
RUN set -eux; \
    apk add --no-cache ca-certificates curl tar zstd; \
    case "${TARGETARCH}" in \
        amd64) \
            gvisor_arch=x86_64; \
            gvisor_sha=b8bcf8ebda5a0e3aa43026f26128759c3f74abc94d3f53839963fad01d152b8ec1c2c01cc0c84e8820aa5fb04fbc50df60332911f58884113a7984287737313a; \
            kata_arch=amd64; \
            kata_sha=ccbc0cbc591089d0c57012b78da64b23ef43e0bac0f869dc7bfebe8588c33986; \
            ;; \
        arm64) \
            gvisor_arch=aarch64; \
            gvisor_sha=930967c01eaa8c91a90903ba866070dd165c580d3197287747bb1444ee11dab7350db11d8f90bf00efb2cdcfb2318602d3f329c522c9e9436a86fe6a93c7b7fc; \
            kata_arch=arm64; \
            kata_sha=9dd4407d4b756858fe9ce33322a605f5a932743839a8ec47108e8513dcc3aaa3; \
            ;; \
        *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    mkdir -p /download /runtime-root/usr/local/bin; \
    curl --fail --location --retry 3 \
        "https://storage.googleapis.com/gvisor/releases/release/${GVISOR_VERSION}/${gvisor_arch}/gvisor.tar.bz2" \
        --output /download/gvisor.tar.bz2; \
    printf '%s  %s\n' "${gvisor_sha}" /download/gvisor.tar.bz2 | sha512sum -c -; \
    tar -xjf /download/gvisor.tar.bz2 -C /runtime-root/usr/local/bin; \
    curl --fail --location --retry 3 \
        "https://github.com/kata-containers/kata-containers/releases/download/${KATA_VERSION}/kata-static-${KATA_VERSION}-${kata_arch}.tar.zst" \
        --output /download/kata-static.tar.zst; \
    printf '%s  %s\n' "${kata_sha}" /download/kata-static.tar.zst | sha256sum -c -; \
    tar --zstd -xf /download/kata-static.tar.zst -C /runtime-root; \
    test -x /runtime-root/usr/local/bin/runsc; \
    test -x /runtime-root/usr/local/bin/containerd-shim-runsc-v1; \
    test -x /runtime-root/opt/kata/runtime-rs/bin/containerd-shim-kata-v2

FROM ubuntu:24.04

ARG VERSION=0.1.0
ARG K3S_VERSION=v1.34.11+k3s1
ARG MODEL=generic
ARG TRUSTED_BOOT=false

LABEL org.opencontainers.image.title="kairos-homelab-k3s" \
      org.opencontainers.image.description="Kairos k3s host image with gVisor and Kata Containers runtime prerequisites" \
      org.opencontainers.image.version="${VERSION}"

# Host-side dependencies not supplied by the pinned runtime archives. runc and
# containerd are deliberately not installed here: the Kairos k3s provider owns
# them, so the image uses k3s's embedded containerd 2.x configuration model.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends \
        ca-certificates \
        curl \
        iproute2 \
        iptables \
        kmod \
        libseccomp2 \
        socat \
        util-linux; \
    rm -rf /var/lib/apt/lists/*

# Install the Kairos OS, k3s provider, kernel, boot support, and immutable-system
# services. The init phase is intentionally delayed until after the custom files
# and runtime assets below have been added.
RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l info -s install \
      --model "${MODEL}" \
      --trusted "${TRUSTED_BOOT}" \
      --provider k3s \
      --provider-k3s-version "${K3S_VERSION}" \
      --version "${VERSION}"

COPY --from=runtime-assets /runtime-root/ /
COPY kairos/rootfs/ /

RUN set -eux; \
    chmod 0755 /usr/local/sbin/load-homelab-modules; \
    ln -sf /opt/kata/runtime-rs/bin/containerd-shim-kata-v2 \
        /usr/local/bin/containerd-shim-kata-v2; \
    systemctl enable homelab-runtime-modules.service; \
    test -x /usr/local/bin/containerd-shim-runsc-v1; \
    test -x /usr/local/bin/containerd-shim-kata-v2; \
    test -f /opt/kata/share/defaults/kata-containers/runtime-rs/configuration-qemu-runtime-rs.toml; \
    /usr/local/bin/runsc --version; \
    /usr/local/bin/containerd-shim-kata-v2 --version

# Finalize boot metadata and generate the initrd after KVM and runtime-related
# modules/configuration are present in the root filesystem.
RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l info -s init \
      --model "${MODEL}" \
      --trusted "${TRUSTED_BOOT}" \
      --provider k3s \
      --provider-k3s-version "${K3S_VERSION}" \
      --version "${VERSION}"
