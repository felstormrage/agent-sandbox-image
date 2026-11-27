# Fedora minimal sandbox host image

A minimal Fedora `bootc` host. It keeps the immutable bootc update path, the
serial console, `fish`, Homebrew, and SSH key sync, but deliberately omits
Podman, gVisor, Firecracker, and the container-networking stack.

Included:

- Fedora `bootc` with `bootc-fetch-apply-updates.timer` moved to 04:00 daily
- `fish`, `tmux`, Neovim, ripgrep, `fd`, `bat`, `eza`, `zoxide`, `btop`, and
  related CLI tools
- Homebrew installed on first boot into `/home/linuxbrew`
- SSH key sync installed on first boot
- Serial console on `ttyS0` and root SSH login disabled
- 200 MB journald cap

Updates are applied by bootc:

```sh
sudo bootc update
systemctl list-timers bootc-fetch-apply-updates.timer
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

Set the repository secret `HOST_PASSWORD` to use a fixed password. If it is not
set, each run generates a random password and records it in `credentials.txt`.
To change the user or groups, edit `config.toml`; CI replaces
`__PASSWORD_HASH__` with a SHA-512 password hash before invoking
`bootc-image-builder`.

## Boot in Proxmox

1. Extract the downloaded artifact ZIP.
2. Import the qcow2 disk with `qm importdisk`, or attach it as a SATA/SCSI disk.
3. Use OVMF/UEFI, CPU type `host`, and a serial console on `ttyS0`.
4. Give the VM at least 2 GB of RAM and 10 GB of disk.
5. Log in as `nithin` with the password from `credentials.txt`. The first boot
   installs Homebrew and the SSH key sync service.

This image does not include Podman, gVisor, or Firecracker and does not require
KVM; use the Kairos image when you need those.
