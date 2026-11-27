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
- Serial console on `ttyS0` and root SSH login disabled

Kairos upgrades are managed separately from the OpenCode container images:

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
