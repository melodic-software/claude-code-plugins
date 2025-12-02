# Python Installation macOS

Last Verified: 2025-11-25
Python versions: 3.13 (required), 3.13 (current stable), 3.14 (development, optional)
uv: latest via Homebrew or standalone installer

This guide installs **Python 3.12** (required), optionally **Python 3.13** and **Python 3.14**, and the **uv** package manager on macOS.

- Shared concepts (why 3.12 vs 3.13/3.14, uv overview): [Installation Overview](overview.md)
- [Windows Installation](windows.md)
- [Linux Installation](linux.md)

---

## Table of Contents

- [1. Check existing Python installation](#1-check-existing-python-installation)
- [2. Install Python 3.13 (required)](#2-install-python-313-required)
- [3. Install Python 3.13 (optional)](#3-install-python-313-optional)
- [4. Install Python 3.14 (optional)](#4-install-python-314-optional)
- [5. Working with multiple versions on macOS](#5-working-with-multiple-versions-on-macos)
- [6. Verify Python and pip](#6-verify-python-and-pip)
- [7. Install uv on macOS](#7-install-uv-on-macos)
- [8. First steps with uv (macOS)](#8-first-steps-with-uv-macos)
- [9. Troubleshooting (macOS)](#9-troubleshooting-macos)
- [References](#references)

## 1. Check existing Python installation

Run these in **Terminal**:

```bash
# Check default Python 3
python3 --version

# See where Python 3 is located
which python3
```

**Interpretation:**

- If you see **Python 3.12.x** → you already have the required version.
- If you only see **Python 3.14.x** → you still need **3.12** for spaCy and some tooling.
- If `python3` is missing or points to an old system Python → install the recommended versions below.

---

## 2. Install Python 3.13 (required)

### 2.1 Install with Homebrew (recommended)

If you don't have Homebrew yet, see the macOS onboarding docs, then run:

```bash
# Install Python 3.12
brew install python@3.13

# Verify installation
python3.13 --version
```

You should see:

```text
Python 3.12.x
```

### 2.2 Manual install from python.org

1. Download the macOS **Python 3.12** installer (.pkg):
   - Specific 3.12.0 release: <https://www.python.org/downloads/release/python-3120/>
   - Or latest 3.12.x: <https://www.python.org/downloads/>
2. Run the installer and follow the prompts.
3. Verify:

```bash
python3 --version
python3.13 --version
```

If you installed only 3.12, `python3` should point to 3.12.x.

---

## 3. Install Python 3.13 (optional)

Python 3.13 is the current stable release with experimental Free Threading (no-GIL) and JIT compiler support.

### 3.1 Install with Homebrew

```bash
brew install python@3.13

# Verify installation
python3.13 --version
python3.13 --version
```

Homebrew installs each version side-by-side.

### 3.2 Manual install

1. Download the **Python 3.13** macOS installer (.pkg): <https://www.python.org/downloads/>
2. Run the installer.
3. Verify:

```bash
python3.13 --version
```

---

## 4. Install Python 3.14 (optional)

Only install Python 3.14 if you explicitly need the latest language features and are comfortable with development releases.

### 4.1 Install with Homebrew

```bash
brew install python@3.14

# Verify all versions
python3.13 --version
python3.13 --version
python3.14 --version
```

### 4.2 Manual install

1. Download the latest Python 3.14 macOS installer (.pkg): <https://www.python.org/downloads/>
2. Run the installer.
3. Verify:

```bash
python3.14 --version
```

Depending on your PATH and symlinks, `python3` may point to 3.12, 3.13, or 3.14.

---

## 5. Working with multiple versions on macOS

When you have both 3.12 and 3.14 installed:

```bash
# Use a specific version explicitly
python3.13 --version
python3.14 --version

# Run pip for each version
python3.13 -m pip --version
python3.14 -m pip --version

# Check which python3 is used by default
which python3
python3 --version
```

### Optional: prefer Python 3.12

You can make 3.12 your default `python3` in a few ways:

```bash
# In your shell profile (~/.zshrc or ~/.bash_profile)
alias python3='python3.13'
alias pip3='python3.13 -m pip'
```

If you use Homebrew:

```bash
# Ensure python@3.13 is linked
brew unlink python@3.14  # if 3.14 is linked
brew link --overwrite python@3.13
```

---

## 6. Verify Python and pip

After installing Python 3.13 (and optionally 3.14), verify:

```bash
# Required version
python3.13 --version
python3.13 -m pip --version

# Optional latest version
python3.14 --version  # if installed
python3.14 -m pip --version

# Where Python is located
which python3
which python3.13
```

---

## 7. Install uv on macOS

We use **uv** as the default package/project manager for new Python work.
Installation options here are based on the official uv docs
([installation](https://docs.astral.sh/uv/getting-started/installation/),
[overview](https://docs.astral.sh/uv/)).

### 7.1 Install uv with Homebrew (recommended)

```bash
brew install uv

# Verify
uv --version
uvx --version
```

### 7.2 Install uv via standalone installer (alternative)

If you prefer the official standalone installer, use:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

You can inspect the script before running it:

```bash
curl -LsSf https://astral.sh/uv/install.sh | less
```

> Commands adapted from the uv installation guide:
> [Installing uv](https://docs.astral.sh/uv/getting-started/installation/)

After installation, ensure `~/.local/bin` (where uv is commonly installed) is on your PATH, then restart your shell.

---

## 8. First steps with uv (macOS)

Once Python 3.13 and uv are installed:

```bash
# Check uv
uv --version

# Create a new project in the current directory
uv init

# Install a package into the project environment
uv add requests

# Run a Python file using uv's environment
uv run python main.py
```

Tool-style usage:

```bash
uvx black --version
```

See the uv docs for more examples: <https://docs.astral.sh/uv/>.

---

## 9. Troubleshooting (macOS)

### "python3: command not found"

- Verify that Python is installed:

```bash
ls /usr/local/bin/python3* /opt/homebrew/bin/python3* 2>/dev/null
```

- Ensure your PATH includes Homebrew's `bin` directory (Intel vs Apple Silicon may differ).

### "python3.13: command not found"

- Confirm 3.12 is installed:

```bash
python3.13 --version
```

- If not found, reinstall `python@3.13` via Homebrew or python.org and ensure PATH is updated.

### uv command not found

- Check that uv is installed:

```bash
which uv
```

- If you used the standalone installer, add `~/.local/bin` to your PATH and restart your shell.

---

## References

- Python downloads: <https://www.python.org/downloads/>
- Python 3.12 release notes: <https://docs.python.org/3.12/whatsnew/3.12.html>
- Python 3.13 release notes: <https://docs.python.org/3.13/whatsnew/3.13.html>
- Python 3.14 release notes: <https://docs.python.org/3.14/whatsnew/3.14.html>
- Homebrew and Python: <https://docs.brew.sh/Homebrew-and-Python>
- uv installation: <https://docs.astral.sh/uv/getting-started/installation/>
- uv documentation: <https://docs.astral.sh/uv/>
