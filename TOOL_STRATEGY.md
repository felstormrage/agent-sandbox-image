# Tool Installation Strategy: Bootc Layer vs Homebrew

## Executive Summary

**Yes, it makes sense to move developer tools like `bat` to Homebrew.** This aligns with the principle of separating immutable OS layers from mutable development environments and is recommended for your sandbox images.

## Quick Answer

| Aspect | Current | Recommended |
|--------|---------|-------------|
| **Image Size** | ~1.5GB (Kairos), ~850MB (Fedora) | ~1.3GB, ~700MB (~15% smaller) |
| **First Boot** | Ready immediately | +2-3 min for tool install |
| **Tool Updates** | Requires full rebuild | `brew upgrade` (minutes) |
| **Customization** | Fixed in image | User choice |
| **Offline** | Works without network | Needs network for first boot |

## Recommended Changes

### Move to Homebrew (8 tools):
```
✓ bat              - syntax-highlighted cat replacement
✓ ripgrep (rg)     - fast grep alternative
✓ fd                - friendly find alternative
✓ du-dust           - disk usage analyzer
✓ eza               - modern ls replacement
✓ zoxide            - smart cd assistant
✓ btop              - beautiful system monitor
✓ neovim (nvim)     - extensible editor
```

### Keep in Bootc Layer:
```
Essential System:
  - qemu-guest-agent, podman, ssh, fish, tmux, sudo
  - curl, wget, tar, zstd
  - jq, skopeo (container ecosystem)

Build Tools (for Homebrew compilation):
  - gcc, make, patch, zlib-devel
  - git (consider for consistency)

Utilities:
  - procps-ng, file, which, unzip, bzip2
  - conntrack-tools, nftables, iproute*
  - container-selinux
```

## Why This Makes Sense

### For Your Use Case (Developer Sandbox)
1. **Sandbox images are developer-focused**, not strict minimal systems
2. **Customization flexibility** - users want their preferred tools
3. **Faster iteration** - tool version changes don't require OS rebuilds
4. **Smaller CI artifacts** - faster builds and deployments
5. **Industry standard** - immutable base + mutable app layer is the pattern

### Trade-offs
| Benefit | Cost |
|---------|------|
| 15-20% smaller images | First boot takes 2-3 min |
| Faster rebuilds | Requires network for tools |
| User customization | Slight complexity for first-boot |
| Independent tool updates | Not useful if offline sandbox needed |

## Implementation Plan

### Phase 1: Setup
1. Create `/rootfs/etc/homebrew-tools.txt` with the 8 tools
2. Update `rootfs/usr/bin/install-homebrew` to install tools after Homebrew setup
3. Document in README

### Phase 2: Update Containerfiles
1. Remove 8 dev tools from kairos/Containerfile dnf install (line ~38)
2. Remove 8 dev tools from fedora-minimal/Containerfile dnf install (line ~27)
3. Keep all build tools (gcc, make, patch, zlib-devel, git)

### Phase 3: Validation
```bash
# Build test image
docker build -t test-kairos kairos/
# Boot it
docker run -it test-kairos bash
# Verify tools installed on first boot
bat --version  # should work after systemd brings up network
```

## File Changes Overview

```
NEW FILES:
├── rootfs/etc/homebrew-tools.txt
│   └── List of 8 tools to install via brew

MODIFIED FILES:
├── kairos/Containerfile
│   └── Remove 8 tools from dnf install line
├── fedora-minimal/Containerfile
│   └── Remove 8 tools from dnf install line
└── rootfs/usr/bin/install-homebrew
    └── Add: brew install $(cat /etc/homebrew-tools.txt) || true
```

## Questions to Address

1. **Should git be in Homebrew too?**
   - Recommendation: **Keep in layer** for consistency/reliability
   - Alternative: Move to Homebrew if users prefer latest git

2. **What about offline sandbox scenarios?**
   - Current: Would fail to install tools
   - Solution: Pre-cache tools or fall back to system tools

3. **First-boot timeout concerns?**
   - Current timeout: 30 minutes (see brew-firstboot.service)
   - Expected: 2-3 minutes total
   - Safe margin: Good

4. **What if Homebrew is down?**
   - Service has retry logic (Restart=on-failure, RestartSec=2min)
   - User can manually run `brew install -v` after boot
   - Consider adding logging/monitoring

## Expected Outcomes

### Image Size Reduction
```
Kairos:
  Before: ~1.5GB
  After: ~1.3GB
  Savings: ~200MB (13%)

Fedora-minimal:
  Before: ~850MB
  After: ~700MB
  Savings: ~150MB (18%)
```

### Build Time Impact
```
CI Builds:
  - Layer compression: Slightly faster (~5-10%)
  - Push time: Faster due to smaller images (~10-15%)

First-Boot (one-time):
  - Homebrew install: ~1-2 min
  - Tool compilation/install: ~1-2 min
  - Total: ~2-3 min

Subsequent Rebuilds:
  - Layer reuse: Better caching
  - Faster iteration on sandbox internals
```

### User Experience
```
Before first-boot: Image boots, needs to wait for network tools
After boot: All tools ready
Tool updates: `brew upgrade <tool>` instead of full image rebuild
Customization: `brew install <my-tool>` or `brew remove <unwanted-tool>`
```

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|-----------|
| First-boot network failure | Low | Retry logic + manual recovery |
| Homebrew formula removed | Very Low | Pin versions if needed |
| Tool performance issues | Low | Same tools, same environment |
| Boot time SLA violation | Low | 2-3 min is acceptable for sandbox |
| User confusion | Medium | Document clearly in README |

## Alternative Approaches

### Option A: Current Approach (All in Layer)
- ✓ Ready immediately on boot
- ✓ No network dependency
- ✗ Larger images (~15% bigger)
- ✗ Tool updates require rebuild
- ✗ No user customization

### Option B: Recommended (Essentials in layer, tools via Homebrew)
- ✓ Smaller images (~15% smaller)
- ✓ Faster tool updates
- ✓ User customization
- ✗ 2-3 min first-boot
- ✗ Network required for tools

### Option C: Hybrid (Pre-cache tools in layer with Homebrew override)
- ✓ Fast boot if offline
- ✓ Tools ready immediately
- ✓ Users can still customize
- ✗ More complexity
- ✗ No real size savings

## Recommendation

**Implement Option B** (move to Homebrew) because:

1. ✅ Aligns with immutable OS + mutable app layer pattern
2. ✅ Significantly smaller images (better for CI/CD)
3. ✅ Faster rebuilds of core sandbox (gcc, podman, etc.)
4. ✅ Users get customization flexibility
5. ✅ Industry standard approach
6. ✅ 2-3 min first-boot is acceptable for sandbox use
7. ✅ Tools are well-maintained in Homebrew

## Next Steps

1. Review this strategy with team
2. If approved, implement Phase 1 (setup)
3. Create PR with Phase 2 (Containerfile changes)
4. Test locally and in CI
5. Document in README

---

**Document Purpose**: Decision record for tool installation strategy
**Last Updated**: 2026-11-28
**Status**: Ready for Implementation
