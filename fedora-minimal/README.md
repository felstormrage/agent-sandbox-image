# Fedora minimal sandbox host image

A Fedora `bootc` host with a minimal sandbox tool set. It keeps the immutable
bootc update path, the serial console, `fish`, Homebrew, and SSH key sync. It
does not add gVisor, Firecracker, or the Kairos container-networking stack, but
the standard `fedora-bootc` base already includes Podman, Skopeo, rpm-ostree,
toolbox, and common server tooling.

Included:

- Fedora `bootc` with `bootc-fetch-apply-updates.timer` moved to 04:00 daily
- Standard `fedora-bootc` base packages, including Podman, Skopeo, rpm-ostree,
  toolbox, chrony, and nftables
- `fish`, `tmux`, Neovim, ripgrep, `fd`, `bat`, `eza`, `zoxide`, `btop`, and
  related CLI tools
- Homebrew installed on first boot into `/home/linuxbrew`
- SSH key sync installed on first boot
- Key-only SSH, root SSH login disabled, and firewalld allowing only SSH
- Serial console on `ttyS0`
- 200 MB journald cap
- auditd, fail2ban, and zram defaults
- kdump disabled for small VMs

Updates are applied by bootc. The timer checks daily at 04:00 with a randomized
delay and catches up after downtime; bootc reboots after applying an update.

```sh
sudo bootc status
sudo bootc update
systemctl list-timers bootc-fetch-apply-updates.timer
```

To return to the previous deployment:

```sh
sudo bootc rollback
sudo reboot
```

## Build

```sh
docker build --platform linux/amd64 \
  -f fedora-minimal/Containerfile \
  --build-arg VERSION=0.1.0 \
  -t ghcr.io/felstormrage/agent-sandbox-image:fedora-minimal-0.1.0 \
  .
```

The disk artifact is amd64-only. The OCI image can be rebuilt for arm64 later,
but the serial-console kernel arguments are currently scoped to x86_64.

## Weekly qcow2 artifact

On non-pull-request runs, the `Build Fedora minimal image` GitHub Actions job:

1. Builds and pushes the OCI image with `fedora-minimal-<version>`,
   `fedora-minimal-latest`, and branch/PR/commit tags.
2. Uses `bootc-image-builder` to create a qcow2 disk from the image. On `main`
   it builds from `fedora-minimal-latest` so the installed system tracks future
   weekly upgrades.
3. Uploads the artifact as
   `fedora-minimal-<version>-amd64-qcow2`.

The artifact ZIP contains:

- `fedora-minimal-<version>-amd64.qcow2`
- `SHA256SUMS`
- `credentials.txt` with the `nithin` password for this run

Set the repository secret `HOST_PASSWORD` to use a fixed console password. If it
is not set, each run generates a random password and records it in
`credentials.txt`. SSH is key-only: set the repository secret
`HOST_SSH_PUBLIC_KEY` to the public key that should be authorized for `nithin`.
CI replaces `__PASSWORD_HASH__` and `__SSH_PUBLIC_KEY__` before invoking
`bootc-image-builder`. To change the user or groups, edit `config.toml`.

## Boot in Proxmox

1. Extract the downloaded artifact ZIP.
2. Import the qcow2 disk with `qm importdisk`, or attach it as a SATA/SCSI disk.
3. Use OVMF/UEFI, CPU type `host`, and a serial console on `ttyS0`.
4. Give the VM at least 2 GB of RAM and 10 GB of disk.
5. Log in at the serial console as `nithin` with the password from
   `credentials.txt`, or over SSH with the key configured in
   `HOST_SSH_PUBLIC_KEY`. The first boot installs Homebrew and the SSH key sync
   service.

This image does not include gVisor or Firecracker and does not require KVM. It
does include the standard bootc/Podman tooling from the base image; use the
Kairos image when you need the full container and virtualization stack.
