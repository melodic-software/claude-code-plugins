---
name: onboarding
description: Developer environment setup guides for Windows, macOS, Linux, and WSL. Use when setting up development machines, installing tools, configuring environments, or following platform-specific setup guides. Covers package management, shell/terminal, code editors, AI tooling, containerization, databases, and more.
allowed-tools: Read, Glob, Grep, Bash
---

# Developer Onboarding

Complete developer environment setup guides across all major platforms.

## Overview

This skill provides step-by-step onboarding documentation for setting up:

- **Package managers** (winget, Homebrew, apt, pacman)
- **Runtime environments** (NVM for Node.js)
- **Shell & terminal** (PowerShell, Zsh, Bash customization)
- **Code editors** (VS Code, JetBrains, Neovim)
- **AI tooling** (Claude Code, Cursor, LM Studio, Gemini CLI)
- **Containerization** (Docker setup)
- **Cloud platforms** (Azure CLI)
- **Database tools** (DBeaver, Azure Data Studio)
- **Security tools** (GPG, SSH, Windows Sandbox)
- **Productivity tools** (Figma, various utilities)

## When to Use This Skill

Use this skill when:

- Setting up a new development machine
- Onboarding new developers to a team
- Finding platform-specific installation instructions
- Configuring developer tools across Windows, macOS, Linux, or WSL
- Looking for best practices in environment setup
- Troubleshooting developer tool installations

## Quick Start by Platform

### Windows

Main Guide: [references/windows-onboarding.md](references/windows-onboarding.md)

Follow the ordered steps covering WSL, package management, Git (via git skills), runtime environments, shell configuration, and development tools.

### macOS

Main Guide: [references/macos-onboarding.md](references/macos-onboarding.md)

Follow the ordered steps covering Homebrew, Git (via git skills), runtime environments, shell configuration, and development tools.

### Linux

Main Guide: [references/linux-onboarding.md](references/linux-onboarding.md)

Follow the ordered steps covering package management, Git (via git skills), runtime environments, shell configuration, and development tools.

## Topics Index

| Topic | Windows | macOS | Linux | WSL |
|-------|---------|-------|-------|-----|
| Package Management | [link](references/package-management/package-managers-windows.md) | [link](references/package-management/package-managers-macos.md) | [link](references/package-management/package-managers-linux.md) | - |
| WSL Setup | [link](references/wsl/wsl-setup-windows.md) | - | - | - |
| Linux Fundamentals | - | - | [link](references/linux-fundamentals/common-commands-linux.md) | [link](references/linux-fundamentals/common-commands-wsl.md) |
| Runtime Environments | [link](references/runtime-environments/nvm-setup-windows.md) | [link](references/runtime-environments/nvm-setup-macos.md) | [link](references/runtime-environments/nvm-setup-linux.md) | - |
| PowerShell | [link](references/shell-terminal/powershell-setup-windows.md) | [link](references/shell-terminal/powershell-setup-macos.md) | [link](references/shell-terminal/powershell-setup-linux.md) | - |
| Shell Customization | [link](references/shell-terminal/shell-customization-windows.md) | [link](references/shell-terminal/shell-customization-macos.md) | [link](references/shell-terminal/shell-customization-linux.md) | - |
| Alternative Shells | [link](references/shell-terminal/alternative-shells-windows.md) | [link](references/shell-terminal/alternative-shells-macos.md) | [link](references/shell-terminal/alternative-shells-linux.md) | - |
| Code Editors | [link](references/code-editors/code-editors-windows.md) | [link](references/code-editors/code-editors-macos.md) | [link](references/code-editors/code-editors-linux.md) | - |
| AI Tooling | [link](references/ai-tooling/ai-tooling-windows.md) | [link](references/ai-tooling/ai-tooling-macos.md) | [link](references/ai-tooling/ai-tooling-linux.md) | - |
| Docker | [link](references/containerization/docker-setup-windows.md) | [link](references/containerization/docker-setup-macos.md) | [link](references/containerization/docker-setup-linux.md) | - |
| API Tools | [link](references/api-development/api-tools-windows.md) | [link](references/api-development/api-tools-macos.md) | [link](references/api-development/api-tools-linux.md) | [link](references/api-development/api-tools-wsl.md) |
| Web Browsers | [link](references/web-browsers/browsers-windows.md) | [link](references/web-browsers/browsers-macos.md) | [link](references/web-browsers/browsers-linux.md) | - |
| Azure CLI | [link](references/cloud-platforms/azure-cli-setup-windows.md) | [link](references/cloud-platforms/azure-cli-setup-macos.md) | [link](references/cloud-platforms/azure-cli-setup-linux.md) | - |
| Database Tools | [link](references/database-tools/database-tools-windows.md) | [link](references/database-tools/database-tools-macos.md) | [link](references/database-tools/database-tools-linux.md) | - |
| Productivity | [link](references/productivity/productivity-tools-windows.md) | [link](references/productivity/productivity-tools-macos.md) | [link](references/productivity/productivity-tools-linux.md) | - |
| Figma | [link](references/productivity/figma-setup-windows.md) | [link](references/productivity/figma-setup-macos.md) | [link](references/productivity/figma-setup-linux.md) | - |
| Security Tools | [link](references/security/security-tools-windows.md) | [link](references/security/security-tools-macos.md) | [link](references/security/security-tools-linux.md) | - |
| Windows Sandbox | [link](references/security/windows-sandbox.md) | - | - | - |
| System Utilities | [link](references/system-tools/system-utilities-windows.md) | [link](references/system-tools/system-utilities-macos.md) | [link](references/system-tools/system-utilities-linux.md) | - |
| Other | [link](references/other/other-windows.md) | [link](references/other/other-macos.md) | [link](references/other/other-linux.md) | - |

## Cross-Platform Content

- [Database Tools Overview](references/database-tools/database-tools.md) - Platform-agnostic database tools guide
- [GitHub Spec Kit](references/ai-tooling/github-spec-kit.md) - AI-assisted specification development

## Git and Version Control

Git documentation has been consolidated into dedicated Claude Code skills for better maintainability:

- **git-setup** skill: Git installation and basic configuration
- **git-line-endings** skill: Cross-platform line ending configuration
- **git-gui-tools** skill: Git GUI client recommendations
- **git-config** skill: Comprehensive Git configuration
- **git-gpg-signing** skill: Commit signing setup

Invoke these skills directly for Git-related guidance.

## Platform Detection

When helping users, detect their platform via:

- **Windows**: `$env:OS` contains "Windows", PowerShell, `winget`
- **macOS**: `uname -s` returns "Darwin", `brew`
- **Linux**: `uname -s` returns "Linux", `apt`/`dnf`/`pacman`
- **WSL**: Linux kernel + `/mnt/c/` paths

## Reference Loading Guide

All references are **conditionally loaded** based on detected platform:

1. Load `references/{platform}-onboarding.md` for platform entry point
2. Load topic-specific references as needed from `references/{topic}/`
3. Cross-reference with git skills for version control setup

**Token efficiency**: Entry point + 2-3 topic references is typical load (~200-400 lines)

---

**Last Updated:** 2025-12-01
