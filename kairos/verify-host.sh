#!/usr/bin/env bash
set -euo pipefail

for command in k3s kubectl runsc containerd-shim-runsc-v1 containerd-shim-kata-v2; do
  command -v "${command}" >/dev/null || {
    printf 'Missing required command: %s\n' "${command}" >&2
    exit 1
  }
done

test -e /dev/kvm || { echo 'Missing /dev/kvm; enable virtualization in firmware' >&2; exit 1; }
test -S /run/k3s/containerd/containerd.sock || {
  echo 'k3s containerd socket is not ready' >&2
  exit 1
}

grep -q 'runtimes.runsc' /var/lib/rancher/k3s/agent/etc/containerd/config.toml
grep -q 'runtimes.kata-qemu' /var/lib/rancher/k3s/agent/etc/containerd/config.toml

runsc --version
containerd-shim-kata-v2 --version
k3s kubectl get nodes -o wide

printf 'Kairos host runtime prerequisites are present.\n'
