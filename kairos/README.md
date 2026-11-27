# Kairos sandbox host image

This is a Fedora-based Kairos **BYOI** (bring your own image) host. Kairos
manages the immutable root filesystem, bootloader, initramfs, A/B updates, and
the `kairos-agent`. The image adds the sandbox tooling without installing a
second immutable-OS framework such as `bootc`.

Included:

- Kairos `kairos-init` v4.7.0 on Fedora
- Podman, `containernetworking-plugins`, `nftables`, and IPv4 forwarding
- gVisor `runsc` and its containerd shim, registered as a Podman runtime
- Firecracker and Jailer
- `fish`, `tmux`, Neovim, ripgrep, `fd`, `bat`, `eza`, `zoxide`, `btop`, and
  related CLI tools
- Homebrew installed on first boot into `/home/linuxbrew`
- SSH key sync installed on first boot
- Automatic updates from the published `kairos-latest` image
- Serial console on `ttyS0` and root SSH login disabled

Kairos updates are managed separately from the OpenCode container images. The
host checks the published `kairos-latest` image automatically (see
[Automatic updates](#automatic-updates)); to update immediately:

```sh
sudo kairos-agent upgrade \
  --source oci:ghcr.io/felstormrage/agent-sandbox-image:kairos-latest
```

## Build

```sh
docker build --platform linux/amd64 \
  -f kairos/Containerfile \
  --build-arg VERSION=0.1.0 \
  -t ghcr.io/felstormrage/agent-sandbox-image:kairos-0.1.0 \
  .
```

The image is amd64-only because gVisor and Firecracker are selected with
`uname -m` during the build.

## Weekly qcow2 artifact

On non-pull-request runs, the `Build Kairos image` GitHub Actions job:

1. Builds and pushes the OCI image with `kairos-<version>`, `kairos-latest`, and
   branch/PR/commit tags.
2. Runs AuroraBoot against that image to create a pre-installed EFI raw disk.
3. Converts the raw disk to qcow2 and uploads it as
   `kairos-<version>-amd64-qcow2`.

The artifact ZIP contains:

- `kairos-<version>-amd64.qcow2`
- `SHA256SUMS`
- `credentials.txt` with the `nithin` password for this run

Set the repository secret `HOST_PASSWORD` to use a fixed password. If it is not
set, each run generates a random password and records it in `credentials.txt`.
To change the user or groups, edit `cloud-config.yaml`; CI replaces
`__PASSWORD_HASH__` before booting AuroraBoot.

## Automatic updates

The image ships a `kairos-auto-update.timer`. It checks once a day at 06:00 UTC
with up to one hour of random delay and catches up after downtime. The weekly
image build means an update normally appears on Monday, but the daily check also
picks up a late or re-run build without waiting another week. The timer reads the
`org.opencontainers.image.version` label from
`ghcr.io/felstormrage/agent-sandbox-image:kairos-latest` with `skopeo` and
compares it with `KAIROS_VERSION` in `/etc/kairos-release`.

- If the versions match, the check exits without downloading or rebooting.
- If the remote version is newer, it verifies the image's keyless cosign
  signature, resolves the remote digest, then runs
  `kairos-agent upgrade --source oci:...@sha256:...` and reboots into that exact
  image. The digest pin also closes the race where `kairos-latest` moves between
  the version check and the upgrade.
- If the installed version is newer, the check leaves it alone. This prevents a
  tagged release from being downgraded to a `main` build.
- The timer is skipped when the system is booted into recovery mode.
- Only the active system is upgraded. The recovery partition stays at the
  version installed with the qcow2 unless you upgrade it manually with
  `kairos-agent upgrade --recovery`.
- The host reboots to activate the new image, so running containers and VMs are
  interrupted.

The check assumes the GHCR package is publicly readable. For a private package,
configure registry credentials for both `skopeo` and `kairos-agent`, or the
check and upgrade will fail.

To run the version, digest, and signature checks without upgrading:

```sh
sudo /usr/bin/kairos-auto-update --check
```

To inspect a failed run:

```sh
sudo journalctl -u kairos-auto-update.service
```

Because the timer is baked into the image, a node installed from an older qcow2
needs one manual upgrade before automatic updates begin:

```sh
sudo kairos-agent upgrade \
  --source oci:ghcr.io/felstormrage/agent-sandbox-image:kairos-latest
```

Disable or reschedule the timer with:

```sh
sudo systemctl disable --now kairos-auto-update.timer
sudo systemctl edit kairos-auto-update.timer
```

## Boot in Proxmox

1. Extract the downloaded artifact ZIP.
2. Import the qcow2 disk with `qm importdisk`, or attach it as a SATA/SCSI disk.
3. Use OVMF/UEFI, CPU type `host`, and a serial console on `ttyS0`.
4. Give the VM at least 4 GB of RAM and 20 GB of disk. Firecracker needs
   `/dev/kvm`, so enable nested virtualization on the Proxmox host if the VM
   runs inside another VM.
5. Log in as `nithin` with the password from `credentials.txt`. The first boot
   installs Homebrew and the SSH key sync service.

The qcow2 is already installed. The `install:` block in `cloud-config.yaml` is
commented out; uncomment it only if you want to use the same configuration to
build an unattended installer ISO instead.
