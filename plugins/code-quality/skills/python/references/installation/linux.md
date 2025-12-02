# Python Installation Linux

Last Verified: 2025-11-25
Python versions: 3.13 (required), 3.13 (current stable), 3.14 (development, optional)
uv: latest via standalone installer or package manager (where available)

This guide installs **Python 3.12** (required), optionally **Python 3.13** and **Python 3.14**, and the **uv** package manager on Linux.

- Shared concepts (why 3.12 vs 3.13/3.14, uv overview): [Installation Overview](overview.md)
- [Windows Installation](windows.md)
- [macOS Installation](macos.md)

Examples below target common distributions (Debian/Ubuntu, Fedora/RHEL, Arch).
Adjust package names for your specific distro as needed.

---

## Table of Contents

- [1. Check existing Python installation](#1-check-existing-python-installation)
- [2. Install Python 3.13 (required)](#2-install-python-313-required)
- [3. Install Python 3.13 (optional)](#3-install-python-313-optional)
- [4. Install Python 3.14 (optional)](#4-install-python-314-optional)
- [5. Build Python from source (fallback)](#5-build-python-from-source-fallback)
- [6. Working with multiple versions on Linux](#6-working-with-multiple-versions-on-linux)
- [7. Verify Python and pip](#7-verify-python-and-pip)
- [8. Install uv on Linux](#8-install-uv-on-linux)
- [9. First steps with uv (Linux)](#9-first-steps-with-uv-linux)
- [10. Troubleshooting (Linux)](#10-troubleshooting-linux)
- [References](#references)

## 1. Check existing Python installation

Run in your shell:

```bash
# Check default Python 3
python3 --version

# See where Python 3 is located
which python3
```

**Interpretation:**

- If you see **Python 3.12.x** → you already have the required version.
- If you only see **Python 3.14.x** → you still need **3.13** for spaCy and some tooling.
- If `python3` is missing or older than 3.12 → install the versions below.

---

## 2. Install Python 3.13 (required)

### 2.1 Debian/Ubuntu

```bash
sudo apt update

# Install Python 3.12 and common extras
sudo apt install -y python3.13 python3.13-venv python3.13-dev

# Verify
python3.13 --version
```

### 2.2 Fedora/RHEL

```bash
sudo dnf install -y python3.13 python3.13-pip python3.13-devel

# Verify
python3.13 --version
```

### 2.3 Arch Linux

```bash
sudo pacman -S python312

# Verify
python3.13 --version
```

If your distro doesn't provide Python 3.12 packages, see **Section 5** (Build from source).

---

## 3. Install Python 3.13 (optional)

Python 3.13 is the current stable release with experimental Free Threading (no-GIL) and JIT compiler support.

### 3.1 Debian/Ubuntu (may require DeadSnakes PPA)

```bash
sudo add-apt-repository ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.13 python3.13-venv python3.13-dev

# Verify both versions
python3.13 --version
python3.13 --version
```

### 3.2 Fedora/RHEL

```bash
sudo dnf install -y python3.13 python3.13-pip python3.13-devel

# Verify both versions
python3.13 --version
python3.13 --version
```

### 3.3 Arch Linux

```bash
sudo pacman -S python313

# Verify both versions
python3.13 --version
python3.13 --version
```

If 3.13 packages are not yet available for your distro, you can skip this step or build from source (below).

---

## 4. Install Python 3.14 (optional)

Install Python 3.14 only if you explicitly need the latest language features and **do not** depend on spaCy (which currently supports up to 3.13).

### 4.1 Debian/Ubuntu (may require DeadSnakes PPA)

```bash
sudo add-apt-repository ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.14 python3.14-venv python3.14-dev

# Verify all versions
python3.13 --version
python3.13 --version
python3.14 --version
```

### 4.2 Fedora/RHEL

```bash
sudo dnf install -y python3.14 python3.14-pip python3.14-devel

# Verify all versions
python3.13 --version
python3.13 --version
python3.14 --version
```

### 4.3 Arch Linux

```bash
sudo pacman -S python314

# Verify all versions
python3.13 --version
python3.13 --version
python3.14 --version
```

If 3.14 packages are not yet available for your distro, you can skip this step or build from source (below).

---

## 5. Build Python from source (fallback)

Use this only if your distribution does not offer Python 3.12/3.14 packages.

### 5.1 Install build prerequisites

```bash
# Debian/Ubuntu
sudo apt install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
  libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev

# Fedora/RHEL
sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y zlib-devel bzip2-devel openssl-devel ncurses-devel \
  sqlite-devel readline-devel tk-devel gdbm-devel libdb-devel libpcap-devel \
  xz-devel libffi-devel

# Arch Linux
sudo pacman -S base-devel zlib xz tk
```

### 5.2 Build and install Python 3.12

```bash
cd /tmp
wget https://www.python.org/ftp/python/3.12.0/Python-3.12.0.tgz
tar -xzf Python-3.12.0.tgz
cd Python-3.12.0

./configure --enable-optimizations --prefix=/usr/local
make -j"$(nproc)"
sudo make altinstall  # Avoid overwriting system python3

python3.13 --version
```

### 5.3 Build and install Python 3.14 (optional)

```bash
cd /tmp
wget https://www.python.org/ftp/python/3.14.0/Python-3.14.0.tgz
tar -xzf Python-3.14.0.tgz
cd Python-3.14.0

./configure --enable-optimizations --prefix=/usr/local
make -j"$(nproc)"
sudo make altinstall

python3.14 --version
```

---

## 6. Working with multiple versions on Linux

When you have both 3.12 and 3.14 installed:

```bash
# Use a specific version explicitly
python3.13 --version
python3.14 --version

# Pip for each version
python3.13 -m pip --version
python3.14 -m pip --version

# Check default
python3 --version
which python3
```

### Optional: prefer Python 3.12

On Debian/Ubuntu you can use `update-alternatives`:

```bash
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 1
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.14 2
sudo update-alternatives --config python3  # interactive selection
```

Or use shell aliases in `~/.bashrc` or `~/.zshrc`:

```bash
alias python3='python3.13'
alias pip3='python3.13 -m pip'
```

---

## 7. Verify Python and pip

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

## 8. Install uv on Linux

We use **uv** as the default package/project manager for new Python work.
The commands below follow the official uv installation docs
([installation](https://docs.astral.sh/uv/getting-started/installation/),
[overview](https://docs.astral.sh/uv/)).

### 8.1 Install uv via standalone installer (recommended)

Using `curl`:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

If you prefer `wget`:

```bash
wget -qO- https://astral.sh/uv/install.sh | sh
```

Inspect the script before running it:

```bash
curl -LsSf https://astral.sh/uv/install.sh | less
```

After installation, ensure `~/.local/bin` is on your PATH and restart your shell.

### 8.2 Verify uv

```bash
uv --version
uvx --version
```

If your distribution offers a uv package (e.g., via your package manager), you can use that instead, but the official installer is the most consistent option.

---

## 9. First steps with uv (Linux)

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

## 10. Troubleshooting (Linux)

### "python3.13: command not found"

- Confirm whether 3.12 is installed via your package manager or `/usr/local/bin`:

```bash
ls /usr/bin/python3* /usr/local/bin/python3* 2>/dev/null
```

- If missing, reinstall via package manager or rebuild from source.

### "pip: command not found"

- Use `python3.13 -m pip` instead of `pip` directly.
- Install pip if needed via your package manager (e.g., `python3.13-pip`).

### uv command not found

- Ensure `~/.local/bin` is in your PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

- Verify:

```bash
uv --version
```

---

## References

- Python downloads: <https://www.python.org/downloads/>
- Python 3.12 release notes: <https://docs.python.org/3.12/whatsnew/3.12.html>
- Python 3.13 release notes: <https://docs.python.org/3.13/whatsnew/3.13.html>
- Python 3.14 release notes: <https://docs.python.org/3.14/whatsnew/3.14.html>
- DeadSnakes PPA: <https://launchpad.net/~deadsnakes/+archive/ubuntu/ppa>
- uv installation: <https://docs.astral.sh/uv/getting-started/installation/>
- uv documentation: <https://docs.astral.sh/uv/>
