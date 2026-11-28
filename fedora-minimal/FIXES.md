# Fedora Minimal Fixes

This document outlines the bugs and improvements made to the fedora-minimal Containerfile.

## Critical Bugs Fixed

### 1. ✅ `Type=oneshot` + `Restart=on-failure` Conflict
**Issue:** Systemd rejects `Restart=` on `Type=oneshot` units, causing the services to fail to load or ignore the restart policy silently.

**Files affected:**
- `brew-firstboot.service`
- `ssh-sync-firstboot.service`

**Fix:** Changed `Type=oneshot` → `Type=exec` in both units. This allows `Restart=on-failure` and `RestartSec=2min` to work correctly if the network isn't ready on first boot.

### 2. ✅ Removed Unnecessary `sudo` from ExecStartPre
**Issue:** `brew-firstboot.service` used `ExecStartPre=/usr/bin/sudo /usr/bin/install -d -o nithin -g nithin /home/linuxbrew`. This is non-idiomatic for bootc and unnecessarily invokes `sudo` inside a systemd unit.

**Fix:** Replaced with native bootc pattern using `/usr/lib/tmpfiles.d/homebrew.conf`:
```
d /var/home/linuxbrew 0755 ${USERNAME} ${USERNAME} -
```
This guarantees the directory exists with correct ownership at boot without invoking `sudo`.

### 3. ✅ Explicit `fail2ban-firewalld` Dependency
**Issue:** Fedora's `fail2ban` package usually pulls `fail2ban-firewalld` via weak dependencies, but if the base image has `install_weak_deps=False`, fail2ban won't integrate with firewalld.

**Fix:** Explicitly added `fail2ban-firewalld` to the `dnf install` line. Removes guesswork and ensures proper firewall integration.

## Code Quality Improvements

### 4. ✅ Moved Inline Heredocs to `rootfs/` Tree
**Before:** ~15 separate `RUN cat <<'EOF'` layers (massive layer bloat and poor git diffs)

**After:** Single `COPY rootfs/ /` with organized directory structure:
```
rootfs/
├── etc/
│   ├── fail2ban/jail.d/sshd.local
│   └── sudoers.d/sudoers
├── usr/
│   ├── bin/
│   │   ├── install-homebrew
│   │   ├── install-ssh-sync
│   │   └── fedora-minimal-legacy-cleanup
│   ├── lib/
│   │   ├── bootc/kargs.d/00-console.toml
│   │   ├── systemd/system/
│   │   │   ├── brew-firstboot.service
│   │   │   ├── ssh-sync-firstboot.service
│   │   │   └── fedora-minimal-legacy-cleanup.service
│   │   ├── systemd/system/bootc-fetch-apply-updates.timer.d/override.conf
│   │   ├── systemd/journald.conf.d/size.conf
│   │   ├── systemd/system/fail2ban.service.d/after-firewalld.conf
│   │   ├── tmpfiles.d/homebrew.conf
│   │   └── systemd/system/fail2ban.service.d/after-firewalld.conf
│   └── share/fish/vendor_conf.d/
│       ├── brew.fish
│       └── zoxide.fish
```

**Benefits:**
- Single layer instead of 15 layers
- Proper syntax highlighting in editor
- Cleaner git diffs
- Easier to review and test individual files

### 5. ✅ Parameterized Username
**Added:** `ARG USERNAME=nithin`

**Updated in:**
- `brew-firstboot.service` (User, Environment vars)
- `ssh-sync-firstboot.service` (ExecStart script)
- `tmpfiles.d/homebrew.conf` (directory ownership)
- `sudoers.d/sudoers` (permissions)

**Benefits:**
- Reusable Containerfile for different usernames
- Supports shared or secondary hosts
- Dynamic substitution via sed during build

### 6. ✅ Automated Variable Substitution
Added build step:
```dockerfile
RUN find /usr/lib/tmpfiles.d /usr/lib/systemd/system /home -type f 2>/dev/null \
    -exec sed -i "s/\${USERNAME}/${USERNAME}/g" {} \;
```
This replaces all `${USERNAME}` placeholders with the actual ARG value at build time.

## Summary of Changes

| Category | Before | After |
|----------|--------|-------|
| Systemd unit layers | 15+ RUN commands | 1 COPY command |
| `brew-firstboot.service` Type | oneshot (broken) | exec (working) |
| ExecStartPre approach | sudo + install -d | tmpfiles.d (idiomatic) |
| fail2ban integration | Weak dependency | Explicit (guaranteed) |
| Reusability | Hardcoded username | Parameterized |
| Git diffs | Difficult to review | File-based, clear |
| Syntax highlighting | None in Containerfile | Full in rootfs/ tree |

## Testing

To build with a custom username:
```bash
buildah build -t fedora-minimal:custom \
  --build-arg USERNAME=myuser \
  ./fedora-minimal
```

To build with defaults:
```bash
buildah build -t fedora-minimal:latest ./fedora-minimal
```
