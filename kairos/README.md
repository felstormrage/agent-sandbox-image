# Kairos host image

This OCI image is a Kairos-managed Ubuntu 24.04 host for the homelab k3s node.
It contains the host-owned prerequisites for Sandbox Pair without taking
ownership of Kubernetes workloads or shared cluster resources.

Pinned components:

- Kairos `kairos-init` v4.5.0
- k3s `v1.34.11+k3s1` (including containerd 2.x and Kubernetes 1.34)
- gVisor `20261123.1`
- Kata Containers `4.4.0`, using the runtime-rs QEMU configuration

The image registers the k3s containerd handlers `runsc` and `kata-qemu`. The
platform Alchemy stack must separately own the `RuntimeClass` objects. Cilium,
certificates, ingress, storage, Agent Sandbox, application namespaces, and app
workloads are intentionally not baked into this OS image.

## Build

The amd64 build is the expected mini-PC path:

```sh
docker build \
  --platform linux/amd64 \
  -f kairos/Dockerfile \
  --build-arg VERSION=0.1.0 \
  -t ghcr.io/felstormrage/agent-sandbox-image:kairos-0.1.0 \
  .
```

The Dockerfile also selects the matching arm64 gVisor and Kata archives when
built natively on arm64, or with BuildKit emulation:

```sh
docker build --platform linux/arm64 -f kairos/Dockerfile -t kairos-homelab:arm64 .
```

Kata's static archive is roughly 1 GB compressed, so allow several GB of free
space for a build and its cache.

## Publish

```sh
docker push ghcr.io/felstormrage/agent-sandbox-image:kairos-0.1.0
```

GitHub Actions publishes `kairos-latest`, a versioned `kairos-<version>` tag,
and commit-specific tags. A semver Git tag becomes the exact Kairos image
version. Branch, scheduled, and manual builds advance the patch component of
`ARG VERSION` with the monotonic workflow run number and append the commit,
ensuring Kairos sees each rebuild as a distinct, increasing upgrade artifact.

## Install in Proxmox

Each non-PR GitHub Actions build publishes a bootable `amd64` ISO artifact named
`kairos-<version>-amd64-iso`. Download it from the run's **Artifacts** section
and extract the `.zip`; the ZIP contains the ISO and `SHA256SUMS`. Upload the
extracted ISO to the Proxmox ISO library, attach it to a VM, enable CPU
virtualization passthrough for Kata, and select
**kairos (interactive install)** at boot.

The ISO is deliberately a generic live installer and does not contain SSH keys,
passwords, cluster tokens, or production-specific settings. Use the interactive
installer or the Proxmox console to provide your node configuration. To verify
the downloaded artifact before uploading it:

```sh
sha256sum -c SHA256SUMS
```

`cloud-config.example.yaml` shows the expected single-node k3s flags. Copy it to
the platform repository, replace the SSH key, set any LAN/VPN and storage
configuration there, and do not commit cluster tokens or kubeconfigs. The
example disables Flannel and k3s's bundled Traefik/ServiceLB because Cilium and
the shared ingress/load-balancer responsibilities belong to the platform
Alchemy stack.

## Build a custom ISO locally

The OCI image is not itself an ISO. To create an unattended installer with
site-specific configuration embedded, pass a completed cloud config to
AuroraBoot. Keep node-specific configuration outside this repository (especially
in the platform repository):

```sh
docker run --rm -ti \
  -v "$PWD/build:/tmp/auroraboot" \
  -v "$PWD/cloud-config.yaml:/cloud-config.yaml:ro" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  quay.io/kairos/auroraboot:v4.7.0 \
  --set "container_image=oci:ghcr.io/felstormrage/agent-sandbox-image:kairos-latest" \
  --set disable_http_server=true \
  --set disable_netboot=true \
  --cloud-config /cloud-config.yaml \
  --set state_dir=/tmp/auroraboot
```

## Host prerequisites

Enable Intel VT-x/AMD-V in firmware before boot. `/dev/kvm` must exist for Kata;
Kata cannot fall back to gVisor or `runc`. The image loads the KVM and vhost
modules, configures host forwarding, and bakes the k3s containerd v3 template at
`/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl`.

After boot, copy and run `kairos/verify-host.sh` as a privileged user. It checks
that both binaries and generated containerd handlers exist, but live sandbox
execution should still be verified by the platform and Sandbox Pair stacks.
