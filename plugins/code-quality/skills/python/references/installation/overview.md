# Python Installation

Last Verified: 2025-11-25
Applies to: Windows, macOS, Linux
Python versions: 3.13 (required), 3.13 (current stable), 3.14 (development, optional)

This guide standardizes how we install Python and the `uv` package manager across platforms.
Use this file for shared concepts and the OS-specific docs for concrete commands:

- [Windows Installation](windows.md)
- [macOS Installation](macos.md)
- [Linux Installation](linux.md)

## Table of Contents

- [Why we require Python 3.13 (and also mention 3.13 and 3.14)](#why-we-require-python-313-and-also-mention-313-and-314)
- [Using uv for Python projects](#using-uv-for-python-projects)
- [Next steps by platform](#next-steps-by-platform)
- [References](#references)

## Why we require Python 3.13 (and also mention 3.13 and 3.14)

We support three key Python versions:

- **Python 3.13 (required baseline)**
  - ✅ Fully supported by spaCy and many other core ecosystem libraries (spaCy currently supports up to Python 3.13).
  - ✅ Pre-built wheels are available for most platforms → no C/C++ toolchain required for common packages.
  - ✅ Stable and widely used → best compatibility with data/NLP/scientific libraries.
  - ✅ **Required baseline** for any tooling or projects that depend on spaCy or similar libraries.

- **Python 3.13 (current stable)**
  - ✅ Current stable release with performance improvements.
  - ✅ Experimental Free Threading (no-GIL) support available.
  - ✅ Experimental JIT compiler for performance optimization.
  - ⚠️ Some ecosystem packages may not yet have full support.
  - 💡 Good choice for new projects that don't require spaCy.

- **Python 3.14 (development, optional)**
  - ✅ Latest language features and performance improvements.
  - ⚠️ Not yet supported by some ecosystem packages (including spaCy) as of November 2025.
  - ⚠️ Often lacks pre-built wheels → may require a compiler toolchain and building from source.
  - 💡 Recommended only for experimentation or if you're comfortable compiling native extensions.

**Policy:**

- Install **Python 3.13** on every dev machine (required baseline).
- Consider **Python 3.13** for new projects without spaCy dependencies.
- Optionally install **Python 3.14** side-by-side for experimentation and future-proofing.
- When in doubt, use **3.13** for project work, especially if it might touch NLP or data tooling.

### Installing multiple versions side-by-side

All platforms can have Python 3.13 and 3.14 installed in parallel:

- You install **3.13** and/or **3.14** using your platform's package manager or the official Python installers.
- The **"default"** `python` / `python3` / `py` command depends on:
  - PATH order (Windows, macOS, Linux).
  - Platform-specific tools like the Windows **Python Launcher** (`py`), Homebrew links/symlinks, or `update-alternatives` on Debian/Ubuntu.
- You can always call a specific version explicitly:
  - Windows: `py -3.13`, `py -3.13`, `py -3.14`
  - macOS/Linux: `python3.13`, `python3.13`, `python3.14`

See the OS-specific docs for exact commands:

- [Windows Installation](windows.md)
- [macOS Installation](macos.md)
- [Linux Installation](linux.md)

### High-level installation flow

Across all platforms we follow the same high-level steps:

1. **Check existing Python versions**
   - Determine whether Python is already installed and which versions you have.
2. **Install Python 3.13 (required)**
   - Use the recommended package manager or the official installer for your OS.
3. **Optionally install Python 3.13 (current stable)**
   - Recommended for new projects without spaCy dependencies.
4. **Optionally install Python 3.14 (development)**
   - For experimentation with latest features.
5. **Verify installation**
   - Confirm that Python 3.13 (and optionally 3.14) are available and that `pip` works.
6. **(Optional) Set a default**
   - If you frequently run `python` / `python3`, consider making 3.13 your default interpreter.

Each platform doc provides commands for these steps.

## Using uv for Python projects

[`uv`](https://docs.astral.sh/uv/) is a fast Python package and project manager from Astral.
We use `uv` to manage Python environments and dependencies instead of raw `pip` + `venv` in most new workflows.

### Why uv

From the official uv docs:

- uv provides **standalone installers** and **package manager** integrations for all major platforms.
- uv can:
  - Install and manage Python versions.
  - Create and manage virtual environments.
  - Install and lock dependencies.
  - Run scripts and tools in isolated environments.

See:

- [uv installation docs](https://docs.astral.sh/uv/getting-started/installation/)
- [uv main documentation](https://docs.astral.sh/uv/)

### Our usage guidelines

- Use **Python 3.13** as the primary interpreter version for uv-managed projects.
- Prefer **uv** over raw `pip` + `python -m venv` when starting new work.
- Keep `pip`/`venv` knowledge in mind for troubleshooting or legacy projects.

The platform-specific pages contain the exact installation commands for uv and basic "first steps" examples.

### Common uv tool commands

uv can manage "tools" (like global CLIs) alongside project dependencies. Helpful commands:

```bash
# List installed uv tools
uv tool list

# Upgrade a specific tool
uv tool upgrade <tool-name>

# Uninstall a tool
uv tool uninstall <tool-name>
```

See the uv documentation for more on tool management and workflows: <https://docs.astral.sh/uv/>.

## Next steps by platform

- **Windows**: see [Windows Installation](windows.md) for:
  - Installing Python 3.13 and 3.14 (winget and manual).
  - Installing uv via WinGet and verifying `uv` / `uvx`.
- **macOS**: see [macOS Installation](macos.md) for:
  - Installing Python 3.13 and 3.14 via Homebrew or official installers.
  - Installing uv with Homebrew or the standalone installer.
- **Linux**: see [Linux Installation](linux.md) for:
  - Installing Python 3.13 and 3.14 via apt/dnf/pacman or from source.
  - Installing uv with the standalone installer and verifying it.

All three platform docs share the same goals:
**Get Python 3.13 installed and verified, optionally add 3.14, and install uv as the default package manager.**

## References

- Official Python downloads: <https://www.python.org/downloads/>
- Python 3.12 release notes: <https://docs.python.org/3.12/whatsnew/3.12.html>
- Python 3.13 release notes: <https://docs.python.org/3.13/whatsnew/3.13.html>
- Python 3.14 release notes: <https://docs.python.org/3.14/whatsnew/3.14.html>
- uv installation docs: <https://docs.astral.sh/uv/getting-started/installation/>
- uv documentation: <https://docs.astral.sh/uv/>
