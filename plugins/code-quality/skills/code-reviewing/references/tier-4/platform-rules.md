# Platform-Specific File Rules

Validation rules for platform-specific documentation files (*-windows.md,*-macos.md, *-linux.md,*-wsl.md).

## Platform Separation

- [ ] **Never mix OS-specific content in a single file**
  - Each platform gets its own file
  - No conditional sections like "On Windows: ... On macOS: ..."
  - Rationale: Separation of concerns, maintainability

- [ ] **Platform suffix must match target OS**
  - `-windows.md` for Windows-specific content
  - `-macos.md` for macOS-specific content
  - `-linux.md` for Linux-specific content
  - `-wsl.md` for WSL-specific content
  - Rationale: Consistent naming enables discovery

## WSL as Fourth Platform

- [ ] **WSL is treated as separate platform, not Linux variant**
  - WSL has unique characteristics (Windows filesystem, interop)
  - Gets dedicated `-wsl.md` files when content differs from Linux
  - Rationale: WSL-specific patterns deserve explicit treatment

## WSL-to-Linux Redirect Pattern

- [ ] **Use DRY redirect for identical WSL/Linux content**
  - Pattern: "WSL setup is identical to Linux. See [tool-name-linux.md](tool-name-linux.md)"
  - Only when content is truly identical (>95% same)
  - Rationale: Avoid duplication while acknowledging WSL as platform

**Detection Pattern:**

```markdown
<!-- GOOD: Redirect for identical content -->
# Tool Setup WSL
WSL setup is identical to Linux. See [tool-setup-linux.md](tool-setup-linux.md)

<!-- BAD: Mixing platforms -->
# Tool Setup
On Windows: ...
On macOS: ...
On Linux/WSL: ...
```

## Shared Cross-Platform Documentation

- [ ] **80% rule: Create shared doc when content >80% identical**
  - Single `tool-name.md` with minimal platform notes
  - Platform-specific supplements only when needed
  - Example: `ai-tooling.md` (just links, same everywhere)
  - Rationale: Balance DRY with platform-specific clarity

- [ ] **Shared docs may omit platform suffix from title**
  - Filename: `ai-tooling-windows.md`
  - Title: `# AI Tooling` (no platform suffix)
  - Valid exception to title-filename consistency rule
  - Rationale: Content is platform-agnostic, suffix is organizational

## Title-Filename Consistency

- [ ] **Platform file titles match filename (with spaces)**
  - `git-setup-windows.md` → `# Git Setup Windows`
  - `nodejs-setup-macos.md` → `# Nodejs Setup Macos`
  - `docker-setup-linux.md` → `# Docker Setup Linux`
  - Exception: Shared docs may omit platform suffix from title
  - Rationale: Predictable mapping, easier navigation

## Hub Document Organization

- [ ] **Platform-specific hubs link to correct variants**
  - `docs/windows-onboarding.md` links to `*-windows.md` files
  - `docs/macos-onboarding.md` links to `*-macos.md` files
  - `docs/linux-onboarding.md` links to `*-linux.md` files
  - Never cross-link (Windows hub to macOS content)
  - Rationale: Clear separation, no platform confusion

## Platform Variants Completeness

- [ ] **All platforms must have equivalent content**
  - If `git-setup-windows.md` exists, need macOS/Linux/WSL variants
  - Content structure should be parallel across platforms
  - Missing variants indicate incomplete documentation
  - Rationale: Equal support for all platforms

**Detection Pattern:**

```bash
# Check for missing platform variants
ls docs/*-windows.md | sed 's/-windows/-macos/' | xargs -I {} test -f {} || echo "Missing macOS variant"
```

## Platform-Specific Commands

- [ ] **Commands must be valid for target platform**
  - Windows: PowerShell, cmd, winget
  - macOS: bash, zsh, brew
  - Linux: bash, apt/yum/pacman
  - WSL: bash, apt (Ubuntu default)
  - Rationale: Broken commands harm user trust

**Detection Pattern:**

```markdown
<!-- BAD: Wrong package manager for platform -->
File: git-setup-macos.md
Content: "Install via: winget install Git.Git"

<!-- GOOD: Correct package manager -->
File: git-setup-macos.md
Content: "Install via: brew install git"
```

## Cross-Platform Links

- [ ] **Internal links should point to same-platform variant**
  - From `git-setup-windows.md`, link to `nodejs-setup-windows.md`
  - Never link Windows docs to macOS variants
  - Exception: WSL may link to Linux docs (with explanation)
  - Rationale: User stays in consistent platform context

## Last Verified Dates

- [ ] **Platform variants may have different verification dates**
  - Each platform file tracks its own "Last Verified" date
  - Dates can diverge (updated Windows docs but not macOS yet)
  - Missing "Last Verified" indicates stale or unverified content
  - Rationale: Independent verification cycles per platform

---

**Tier:** 4 (CLAUDE.md-specific)
**Applies To:** docs/*-{windows,macos,linux,wsl}.md files
**Last Updated:** 2025-11-28
