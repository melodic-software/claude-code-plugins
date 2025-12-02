# Python Installation Windows

Last Verified: 2025-11-25
Python versions: 3.13 (required), 3.13 (current stable), 3.14 (development, optional)
uv: latest via WinGet or standalone installer

This guide installs **Python 3.12** (required), optionally **Python 3.13** and **Python 3.14**, and the **uv** package manager on Windows.

- Shared concepts (why 3.12 vs 3.13/3.14, uv overview): [Installation Overview](overview.md)
- [macOS Installation](macos.md)
- [Linux Installation](linux.md)

---

## Table of Contents

- [1. Check existing Python installation](#1-check-existing-python-installation)
- [2. Install Python 3.13 (required)](#2-install-python-313-required)
- [3. Install Python 3.13 (optional)](#3-install-python-313-optional)
- [4. Install Python 3.14 (optional)](#4-install-python-314-optional)
- [5. Working with multiple versions on Windows](#5-working-with-multiple-versions-on-windows)
- [6. Verify Python and pip](#6-verify-python-and-pip)
- [7. Install uv on Windows](#7-install-uv-on-windows)
- [8. First steps with uv (Windows)](#8-first-steps-with-uv-windows)
- [9. Troubleshooting (Windows)](#9-troubleshooting-windows)
- [References](#references)

## 1. Check existing Python installation

Run these in **PowerShell**:

```powershell
# Check default Python
python --version

# List all installed Python versions (Windows launcher)
py --list

# See where Python is installed
where python
```

**Interpretation:**

- If you see **Python 3.12.x** → you already have the required version.
- If you only see **Python 3.14.x** → you still need **3.12** for spaCy and some tooling.
- If you get "not recognized" → Python is not installed or not on PATH.

---

## 2. Install Python 3.13 (required)

### 2.1 Quick install with WinGet (recommended)

```powershell
# Install Python 3.12
winget install --id Python.Python.3.12 -e --source winget

# Verify installation
py -3.13 --version
```

You should see output like:

```text
Python 3.12.x
```

### 2.2 Manual install from python.org

1. Download the **Python 3.12** Windows installer:
   - Specific 3.12.0 release: <https://www.python.org/downloads/release/python-3120/>
   - Or latest 3.12.x: <https://www.python.org/downloads/>
2. Run the installer:
   - ✅ **Important:** Check **"Add Python to PATH"** on the first screen.
   - Choose **"Install Now"** or customize the installation location.
3. Verify:

```powershell
python --version
py -3.13 --version
```

---

## 3. Install Python 3.13 (optional)

Python 3.13 is the current stable release with experimental Free Threading (no-GIL) and JIT compiler support.

### 3.1 Install with WinGet

```powershell
winget install --id Python.Python.3.13 -e --source winget

# Verify installation
py --list
py -3.13 --version
```

You should see both 3.12 and 3.13 listed by `py --list`.

### 3.2 Manual install

1. Download the **Python 3.13** Windows installer: <https://www.python.org/downloads/>
2. Run the installer:
   - ✅ **Important:** Check **"Add Python to PATH"**.
3. Verify:

```powershell
py -3.13 --version
```

---

## 4. Install Python 3.14 (optional)

Only install Python 3.14 if you explicitly need the latest language features and are comfortable with development releases.

### 4.1 Install with WinGet

```powershell
winget install --id Python.Python.3.14 -e --source winget

# Verify all versions
py --list
py -3.14 --version
```

You should see 3.13 and 3.14 listed by `py --list`.

### 4.2 Manual install

1. Download the latest Python 3.14 release: <https://www.python.org/downloads/>
2. Run the installer:
   - ✅ **Important:** Check **"Add Python to PATH"**.
3. Verify:

```powershell
py -3.14 --version
```

---

## 5. Working with multiple versions on Windows

Windows provides the **Python Launcher** (`py`) to manage multiple versions:

```powershell
# List installed versions
py --list

# Use a specific version
py -3.13 --version
py -3.14 --version

# Run pip for a specific version
py -3.13 -m pip --version
py -3.14 -m pip --version
```

### Optional: set 3.12 as the default

To prefer Python 3.12 when a script does not specify a version:

```powershell
# Current PowerShell session only
$env:PY_PYTHON = "3.12"
```

For a system-wide default, set the `PY_PYTHON` environment variable to `3.12` in **System Properties → Environment Variables**.

---

## 6. Verify Python and pip

After installing Python 3.13 (and optionally 3.14), verify:

```powershell
# Required version
py -3.13 --version
py -3.13 -m pip --version

# Optional latest version
py -3.14 --version
py -3.14 -m pip --version

# Where Python is located
where python
where py
```

---

## 7. Install uv on Windows

We use **uv** as the default package/project manager for new Python work.
Installation options below are based on the official uv installation docs
([installation](https://docs.astral.sh/uv/getting-started/installation/),
[overview](https://docs.astral.sh/uv/)).

### 7.1 Install uv with WinGet (preferred)

From PowerShell:

```powershell
winget install --id astral-sh.uv -e --source winget
```

This installs the `uv`, `uvx`, and (where applicable) `uvw` binaries.

Verify:

```powershell
uv --version
uvx --version
```

### 7.2 Install uv via standalone PowerShell installer (alternative)

If WinGet is not available, you can use the standalone installer from Astral:

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

You can inspect the script before running it:

```powershell
powershell -c "irm https://astral.sh/uv/install.ps1 | more"
```

> Based on the uv installation guide:
> [Installing uv](https://docs.astral.sh/uv/getting-started/installation/)

---

## 8. First steps with uv (Windows)

Once Python 3.13 and uv are installed:

```powershell
# Check uv
uv --version

# Create a new project in the current directory
uv init

# Install a package into the project environment
uv add requests

# Run a Python file using uv's environment
uv run python main.py
```

For tool-style usage:

```powershell
# Run a tool once without adding it to the project
uvx black --version
```

See the uv docs for more patterns and advanced usage: <https://docs.astral.sh/uv/>.

---

## 9. Troubleshooting (Windows)

### "python is not recognized"

- Python is not on PATH.
- Reinstall Python and ensure **"Add Python to PATH"** is checked, or use `py -3.13` instead of `python`.

### "pip is not recognized"

- Use `py -3.13 -m pip` instead of `pip` directly:

```powershell
py -3.13 -m pip --version
py -3.13 -m pip install package-name
```

### uv command not found

- Confirm that `uv` is installed:

```powershell
where uv
```

- If using the standalone installer, restart your shell so PATH changes take effect.

---

## References

- Python downloads: <https://www.python.org/downloads/>
- Python 3.12 release notes: <https://docs.python.org/3.12/whatsnew/3.12.html>
- Python 3.13 release notes: <https://docs.python.org/3.13/whatsnew/3.13.html>
- Python 3.14 release notes: <https://docs.python.org/3.14/whatsnew/3.14.html>
- Windows Python launcher: <https://docs.python.org/3/using/windows.html#launcher>
- uv installation: <https://docs.astral.sh/uv/getting-started/installation/>
- uv documentation: <https://docs.astral.sh/uv/>
