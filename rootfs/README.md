# rootfs/ - Shared Configuration and Scripts

This directory contains files shared across all sandbox image variants (fedora-minimal, kairos, etc.).

## Structure

```
rootfs/
├── etc/sudoers.d/sudoers                 # Passwordless sudo for ${USERNAME}
├── usr/bin/
│   ├── install-homebrew                  # Pinned Homebrew installer
│   └── install-ssh-sync                  # Pinned SSH sync installer
├── usr/lib/systemd/journald.conf.d/
│   └── size.conf                         # Cap journald at 200M
├── usr/lib/tmpfiles.d/
│   └── homebrew.conf                     # tmpfiles.d to create Homebrew dir
└── usr/share/fish/vendor_conf.d/
    ├── brew.fish                         # Fish shell integration for Homebrew
    └── zoxide.fish                       # Fish shell integration for zoxide
```

## Shared Files

### Scripts (Pinned & Verified)
- **install-homebrew**: Pinned to specific release via SHA256 hash
  - Used by both fedora-minimal and kairos as first-boot service
  - Hash: `34090c61925f5d5c4caca7f1f7089efac33056b1603b4d62b4671d8d22f28fb3`
  
- **install-ssh-sync**: Pinned to specific release via SHA256 hash
  - Used by both fedora-minimal and kairos as first-boot service
  - Hash: `ff802f3256eab6ae0ca0dae2daab53168f236b00f05c56387750f06a11a6edc1`

### Configuration Files
- **sudoers/sudoers**: Passwordless sudo for `${USERNAME}` (parameterized)
- **journald.conf.d/size.conf**: Cap journald logs at 200M
- **tmpfiles.d/homebrew.conf**: Create Homebrew directory with correct ownership
- **fish/vendor_conf.d/*.fish**: Shell integration files

## Usage in Containerfiles

### For fedora-minimal:
```dockerfile
ARG USERNAME=nithin
COPY rootfs/ /
COPY fedora-minimal/rootfs/ /
RUN sed -i "s/\${USERNAME}/${USERNAME}/g" /etc/sudoers.d/sudoers /usr/lib/tmpfiles.d/homebrew.conf /usr/lib/systemd/system/*/service
```

### For kairos:
```dockerfile
ARG USERNAME=nithin
COPY rootfs/ /
COPY kairos/rootfs/ /
RUN sed -i "s/\${USERNAME}/${USERNAME}/g" /etc/sudoers.d/sudoers /usr/lib/systemd/system/*/service
```

## Why Shared?

These files are shared because:
1. **Identical pinned versions** - both images use the same Homebrew and SSH sync releases
2. **Same hash verification** - same SHAs for consistency
3. **Reduce duplication** - avoid maintaining the same script in multiple places
4. **Easier updates** - update once, all images get the fix
5. **Consistent behavior** - same installers produce same results

## Notes

- Uses `/var/tmp` (not `/tmp`) because Kairos mounts `/tmp` with `noexec`
- Hashes must be updated together when upgrading installer versions
- Variable substitution (`${USERNAME}`) happens per-image in respective Containerfiles
- Fish configuration files persist across image upgrades (under `/usr/share`)
- Each image can override these by placing files in its own `{image}/rootfs/` directory
