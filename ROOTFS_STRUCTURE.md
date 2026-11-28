# rootfs Directory Structure Guide

This document explains the rootfs directory structure used in this repository to maintain consistency and reduce duplication.

## Quick Reference

```
agent-sandbox-image/
├── rootfs/                    # Shared across all images
│   ├── etc/sudoers.d/sudoers
│   ├── usr/bin/install-{homebrew,ssh-sync}
│   ├── usr/lib/systemd/journald.conf.d/size.conf
│   ├── usr/lib/tmpfiles.d/homebrew.conf
│   ├── usr/share/fish/vendor_conf.d/*.fish
│   └── README.md
├── kairos/
│   ├── Containerfile          # Uses: COPY rootfs/ / && COPY kairos/rootfs/ /
│   └── rootfs/                # Kairos-specific: systemd units, kairos scripts
├── fedora-minimal/
│   ├── Containerfile          # Uses: COPY rootfs/ / && COPY fedora-minimal/rootfs/ /
│   └── rootfs/                # Fedora-specific: fail2ban, bootc overrides
└── ...
```

## Shared vs Image-Specific

### Shared (/rootfs/)
Files used by **all** sandbox images:
- Installer scripts (must have identical SHA256 hashes)
- Common systemd journald config
- Common tmpfiles.d definitions
- Common shell integration files
- Parameterized configuration (${USERNAME})

### Image-Specific ({image}/rootfs/)
Files unique to one image:
- **kairos/rootfs/**: Kairos services (auto-update, healthcheck), gVisor/Firecracker configs
- **fedora-minimal/rootfs/**: Fedora bootc-specific (kargs, fail2ban), bootc timers

## File Naming & Parameterization

### Variable Substitution
Files that contain `${USERNAME}` are parameterized:
- `rootfs/etc/sudoers.d/sudoers`
- `rootfs/usr/lib/tmpfiles.d/homebrew.conf`
- `kairos/rootfs/usr/lib/systemd/system/brew-firstboot.service`
- `kairos/rootfs/usr/lib/systemd/system/ssh-sync-firstboot.service`
- `fedora-minimal/rootfs/usr/lib/systemd/system/brew-firstboot.service`
- `fedora-minimal/rootfs/usr/lib/systemd/system/ssh-sync-firstboot.service`

Containerfiles substitute at build time:
```dockerfile
ARG USERNAME=nithin
sed -i "s/\${USERNAME}/${USERNAME}/g" /etc/sudoers.d/sudoers
```

### Pinned Hashes
Installer scripts must include SHA256 verification:
- `install-homebrew`: `34090c61925f5d5c4caca7f1f7089efac33056b1603b4d62b4671d8d22f28fb3`
- `install-ssh-sync`: `ff802f3256eab6ae0ca0dae2daab53168f236b00f05c56387750f06a11a6edc1`

**When updating these, update hash + script together and test both images.**

## Containerfile Pattern

### Standard COPY Pattern
```dockerfile
ARG VERSION=0.1.0
ARG USERNAME=nithin

# Copy shared files first
COPY rootfs/ /

# Copy image-specific files (overrides shared if names conflict)
COPY {image-name}/rootfs/ /

# Substitute variables in all config files
RUN sed -i "s/\${USERNAME}/${USERNAME}/g" /etc/sudoers.d/sudoers
```

### Variable Substitution
Use a find-based sed for all files in directories:
```dockerfile
RUN find /usr/lib/systemd/system -name "*.service" \
    -exec sed -i "s/\${USERNAME}/${USERNAME}/g" {} \;
```

## Layer Efficiency

This structure keeps image layers minimal:
- `COPY rootfs/ /` - Single layer for all shared files
- `COPY {image}/rootfs/ /` - Single layer for image-specific files
- One final `RUN` for variable substitution and permissions

**Don't create separate RUN commands for each file!**

## Adding New Files

### To Shared (/rootfs/)
1. Place file in appropriate `/rootfs/usr/lib/...` hierarchy
2. If parameterized, use `${USERNAME}` placeholder
3. If installer script, include SHA256 verification
4. Test that **both** images build correctly
5. Update rootfs/README.md if needed

### To Image-Specific ({image}/rootfs/)
1. Place file in `{image}/rootfs/...` hierarchy
2. Files here override shared ones if paths match
3. Use `${USERNAME}` if appropriate
4. Test only the specific image

## Maintenance Checklist

When updating installer scripts:
- [ ] Update both hash AND script together
- [ ] Test fedora-minimal build
- [ ] Test kairos build
- [ ] Verify service startup works
- [ ] Check git diff (should show actual changes, not layer bloat)

When adding new configs:
- [ ] Determine: shared or image-specific?
- [ ] Add to correct rootfs directory
- [ ] Use `${USERNAME}` if username-dependent
- [ ] Add sed substitution if parameterized
- [ ] Test affected image builds
- [ ] Document in rootfs/README.md

## Why This Matters

This structure prevents:
- ❌ Maintaining install-homebrew in 2+ places
- ❌ Accidental divergence between images
- ❌ Large inline heredocs (hard to maintain)
- ❌ Lost syntax highlighting during review
- ❌ Difficult git diffs

This enables:
- ✓ Single source of truth for shared scripts
- ✓ Clear separation of image-specific vs shared
- ✓ Full syntax highlighting in repo
- ✓ Reviewable git diffs
- ✓ Easier updates and testing

## References

- See [rootfs/README.md](./rootfs/README.md) for detailed file descriptions
- See [kairos/Containerfile](./kairos/Containerfile) for kairos pattern example
- See [fedora-minimal/Containerfile](./fedora-minimal/Containerfile) for minimal pattern example
