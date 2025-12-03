# Windows Onboarding

Complete developer environment setup for Windows (includes WSL for Docker and modern development tooling).

Follow these guides in order for the smoothest onboarding experience.

---

## Core Development Tools

> **Note on Dual-Environment Setup:** After installing WSL (step 2), you'll be working across two environments: native Windows and WSL (Linux). Currently, these guides cover native Windows installation. As you progress in your development work, you may also need to install many of these same tools (Git, NVM, etc.) inside your WSL environment for optimal performance with certain tools. See [WSL Setup Windows](wsl/wsl-setup-windows.md) for future expansion plans and dual-environment considerations.

TODO: Future expansion will add WSL-specific installation guides and clarify which steps happen in Windows vs WSL. For now, follow the guides below for native Windows setup.

### 1. Package Management

Install system-level package managers first - they make installing everything else easier.

- [Package Managers Windows](package-management/package-managers-windows.md)

### 2. Windows Subsystem for Linux

**Essential foundation** - Required for Docker and recommended for modern development tools (better performance with specific AI-assisted coding tools).

- [WSL Setup Windows](wsl/wsl-setup-windows.md)

### 3. Linux Fundamentals

Learn essential Linux commands for working in your WSL environment.

- [Common Commands WSL](linux-fundamentals/common-commands-wsl.md)

### 4. Version Control

Set up Git before anything else - you'll need it for all development work.

> **Skills Available:** Git documentation has been consolidated into Claude Code skills for better maintainability. Invoke these skills directly:

- **git:setup** skill: Git installation and basic configuration (Windows-specific guidance)
- **git:line-endings** skill: Cross-platform line ending configuration (important for Windows)
- **git:gui-tools** skill: Git GUI clients (GitKraken, Sourcetree, GitHub Desktop)
- **git:config** skill: Comprehensive configuration (aliases, performance tuning, credentials)
- **git:gpg-signing** skill: Commit signing setup and troubleshooting

### 5. Runtime Environments

Install language runtimes and version managers.

- [NVM Setup Windows](runtime-environments/nvm-setup-windows.md)

### 6. Shell & Terminal

Configure your command-line environment.

- [PowerShell Setup Windows](shell-terminal/powershell-setup-windows.md)
- [Shell Customization Windows](shell-terminal/shell-customization-windows.md) (optional)
- [Alternative Shells Windows](shell-terminal/alternative-shells-windows.md) (optional)

### 7. Code Editors

Install and configure your text editor or IDE.

- [Code Editors Windows](code-editors/code-editors-windows.md)

### 8. AI Tooling

AI-assisted development tools for enhanced productivity.

- [AI Tooling Windows](ai-tooling/ai-tooling-windows.md)

### 9. Containerization

Set up Docker for container-based development (requires WSL2).

- [Docker Setup Windows](containerization/docker-setup-windows.md)

### 10. API Development

Tools for testing and debugging APIs.

- [API Tools Windows](api-development/api-tools-windows.md)

### 11. Web Browsers

Install browsers and developer tools for web development.

- [Browsers Windows](web-browsers/browsers-windows.md)

---

## Optional Enhancements

Install these as needed for your specific projects.

### Cloud Platforms

- [Azure CLI Setup Windows](cloud-platforms/azure-cli-setup-windows.md)

### Database Tools

- [Database Tools Windows](database-tools/database-tools-windows.md)

### Productivity

- [Productivity Tools Windows](productivity/productivity-tools-windows.md)
- [Figma Setup Windows](productivity/figma-setup-windows.md) (optional)

### Security

- [Security Tools Windows](security/security-tools-windows.md)
- [Windows Sandbox](security/windows-sandbox.md)

### System Tools

- [System Utilities Windows](system-tools/system-utilities-windows.md)
