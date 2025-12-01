# WSL Setup

## Why WSL is Essential for Modern Development

Windows Subsystem for Linux (WSL) allows you to run a Linux environment directly on Windows without the overhead of a traditional virtual machine. **WSL is essentially required** for modern development workflows because:

- **Docker Desktop requires WSL2** - Docker Desktop on Windows uses WSL2 as its backend (required for containerized development)
- **Agentic coding tools perform better in WSL** - Tools like OpenAI Codex CLI are recommended to run in WSL over native Windows due to performance and compatibility
- **Cross-platform development** - Test and run Linux-native applications alongside Windows tools
- **Better tooling compatibility** - Many development tools and scripts are optimized for Linux environments

While you can technically do some Windows-native development without WSL, you'll need it for Docker and will get better performance from certain modern AI-assisted coding tools, making it a foundational setup step.

## Official Documentation

- [https://learn.microsoft.com/en-us/windows/wsl/](https://learn.microsoft.com/en-us/windows/wsl/)
- [https://learn.microsoft.com/en-us/windows/wsl/filesystems](https://learn.microsoft.com/en-us/windows/wsl/filesystems)
- [https://learn.microsoft.com/en-us/windows/wsl/tutorials/gui-apps](https://learn.microsoft.com/en-us/windows/wsl/tutorials/gui-apps)
- [https://learn.microsoft.com/en-us/windows/wsl/tutorials/gpu-compute](https://learn.microsoft.com/en-us/windows/wsl/tutorials/gpu-compute)
- [https://learn.microsoft.com/en-us/windows/wsl/networking](https://learn.microsoft.com/en-us/windows/wsl/networking)
- [https://learn.microsoft.com/en-us/windows/wsl/networking#mirrored-mode-networking](https://learn.microsoft.com/en-us/windows/wsl/networking#mirrored-mode-networking)
- [https://learn.microsoft.com/en-us/windows/wsl/basic-commands](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
- [https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro](https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro)
- [https://learn.microsoft.com/en-us/windows/wsl/tutorials/wsl-containers](https://learn.microsoft.com/en-us/windows/wsl/tutorials/wsl-containers)
- [https://learn.microsoft.com/en-us/windows/wsl/tutorials/wsl-vscode](https://learn.microsoft.com/en-us/windows/wsl/tutorials/wsl-vscode)

## Installation

Install WSL with the default Ubuntu distribution:

```powershell
wsl --install
```

**Restart your computer** after installation completes.

## Initial Configuration

On the first launch of your WSL distribution:

1. **Create a user account** - You'll be prompted to create a Linux username and password
2. **Choose a username** - Can mirror your Windows username (Entra ID, Active Directory, etc.)
   - Example: For email `john.smith@example.com`, use `jsmith`
3. **Set a password** - Store this in your password vault
   - Note: WSL passwords can be reset if forgotten, but it's easier to store securely upfront

If you have questions about WSL account setup, reach out to your team.

## Post-Install: First-Time Setup

After creating your user account, **you must update your Ubuntu system**. This is critical for security and compatibility.

### Understanding Linux Package Management

Ubuntu uses **APT** (Advanced Package Tool) to manage software installation and updates. Think of it like Windows Update, but for all your installed programs, not just the operating system.

### Update Your System

Run these two commands in your WSL terminal:

```bash
sudo apt update && sudo apt upgrade -y
```

**What these commands do:**

- `sudo` - Runs the command with administrator privileges (like "Run as Administrator" in Windows)
- `apt update` - Downloads the latest information about available software packages
  - Think of this as "checking for updates"
  - Updates the package list but doesn't install anything yet
  - Fast and safe - just refreshes the catalog
- `apt upgrade` - Actually downloads and installs the updated packages
  - Think of this as "install updates"
  - Only updates packages you already have installed
  - The `-y` flag automatically answers "yes" to installation prompts
- `&&` - Runs the second command only if the first succeeds

**Why this matters:**

- Fresh WSL installations may have outdated packages
- Security patches and bug fixes require updates
- Many tools expect up-to-date system libraries
- Ubuntu uses "phased updates" that roll out gradually for stability

**First-time update can take 5-10 minutes** depending on how many packages need updating. This is normal.

### Additional Cleanup (Optional)

After upgrading, you can clean up old packages:

```bash
sudo apt autoremove -y
```

This removes old package versions that are no longer needed, freeing up disk space.

## Next Steps

After installing and updating WSL, you can:

- **Install Docker Desktop** - See [Docker Setup Windows](../containerization/docker-setup-windows.md)
- **Use VS Code with WSL** - See [Code Editors Windows](../code-editors/code-editors-windows.md) for Remote-WSL integration
- **Install development tools in WSL** - Follow the `-wsl.md` variants in each topic folder (Git, NVM, etc.)
- **Install additional distributions** - Use `wsl --install -d <DistroName>` for other Linux distributions

## Additional Resources

- [Microsoft WSL Documentation](https://learn.microsoft.com/en-us/windows/wsl/)
- [WSL Best Practices](https://learn.microsoft.com/en-us/windows/wsl/setup/environment)

---

## Future Documentation Expansion

TODO: This WSL topic will need significant expansion to support dual-environment workflows (native Windows + WSL). The reality is that developers will need development tooling installed in BOTH environments and must understand when to use each.

### Planned WSL-Specific Setup Guides

The following guides should be created in their respective topic folders, treating WSL as a platform variant (following the `{topic}-wsl.md` naming pattern):

**Lightweight Redirect Files (WSL uses Linux tooling):**

- `docs/version-control/git-setup-wsl.md` - Redirects to `git-setup-linux.md` (installation identical)
- `docs/runtime-environments/nvm-setup-wsl.md` - Redirects to `nvm-setup-linux.md` (installation identical)
- Most `-wsl.md` files will simply redirect to their `-linux.md` siblings, since WSL runs Linux (Ubuntu)

**Full Content Files (when WSL-specific differences exist):**

- `docs/shell-terminal/shell-setup-wsl.md` - May need full content if Windows Terminal integration or file system considerations differ
- `docs/wsl/wsl-workflow-windows.md` - Integration guide: when to use WSL vs native Windows, file system performance, cross-environment workflows

**DRY Principle:** Only create full WSL-specific content when there are actual differences, gotchas, or integration points unique to WSL. Otherwise, redirect to the Linux guide to avoid duplication.

### Key Topics for Dual-Environment Documentation

TODO: Document the following cross-environment concerns:

1. **File System Boundaries**
   - Windows filesystem accessible from WSL (`/mnt/c/`)
   - WSL filesystem accessible from Windows (`\\wsl$\Ubuntu\`)
   - Performance implications (WSL filesystem faster for WSL tools)
   - Where to store projects (WSL filesystem recommended for performance)

2. **Tool Integration**
   - VS Code Remote-WSL extension (already mentioned in code-editors-windows.md)
   - Windows Terminal integration with WSL profiles
   - Git credential sharing between Windows and WSL
   - SSH key management across environments

3. **Dual Installation Strategy**
   - Which tools install in both environments (Git, NVM, etc.)
   - Which tools only in Windows (Docker Desktop, VS Code)
   - Which tools only in WSL (certain AI coding tools like OpenAI Codex CLI)
   - How to keep environments in sync

4. **Workflow Decision Guide**
   - When to run commands in WSL vs Windows
   - When to open projects in WSL vs Windows in VS Code
   - Performance considerations (WSL for file-heavy operations)
   - AI-assisted coding tool recommendations (prefer WSL)

5. **Common Gotchas**
   - Line ending differences (CRLF vs LF)
   - Path separators (backslash vs forward slash)
   - Case sensitivity differences
   - Permission model differences

### Integration with Main Onboarding

TODO: The Windows onboarding hub (windows-onboarding.md) should eventually reference WSL variants of each tool alongside Windows variants. For example:

**Version Control section might include:**

- [Git Setup Windows](version-control/git-setup-windows.md) - Native Windows Git
- [Git Setup WSL](version-control/git-setup-wsl.md) - Git inside WSL environment

This makes it clear developers need both installations and can reference the appropriate guide based on which environment they're configuring.

**Architectural Note:** WSL is treated as a platform variant (like Windows, macOS, Linux) for tool-specific installations. Only WSL installation/configuration guides live in `docs/wsl/`. All tool setups follow the `{topic}-wsl.md` pattern and live in their respective topic folders (vertical slice organization).
