#!/usr/bin/env bash
# Writes ~/.config/fleet/FLEET.md, the manifest the reach skill reads first, for two
# made-up hosts: desk-01 (the desktop, where the run is) and lap-01 (the laptop).
# The runner sets HOME to the run's temporary home for a scaffold script
# (https://code.claude.com/docs/en/plugin-evals, "Seed the workspace or
# conversation"). The guard does not trust that alone: it refuses the account's
# real home from the password database, and it never overwrites a file.
set -euo pipefail

refuse() {
  echo "refusing: $1" >&2
  exit 1
}

[[ -n "${HOME:-}" && -d "$HOME" ]] || refuse "HOME is unset or not a directory"
user=$(id -un)
if command -v getent >/dev/null 2>&1; then
  real_home=$(getent passwd "$user" | cut -d: -f6)
elif command -v dscl >/dev/null 2>&1; then
  real_home=$(dscl . -read "/Users/$user" NFSHomeDirectory | awk '{print $2}')
else
  refuse "cannot look up the account's real home to compare against"
fi
[[ -n "$real_home" ]] || refuse "the account's real home did not resolve"
[[ "$(cd "$HOME" && pwd -P)" != "$(cd "$real_home" && pwd -P)" ]] || refuse "HOME is the account's real home: $HOME"

d="$HOME/.config/fleet"
f="$d/FLEET.md"
[[ ! -e "$f" ]] || refuse "$f already exists"
mkdir -p "$d"
cat >"$f" <<'MD'
# Fleet

Rendered for desk-01. Machines are addressed by hostname over the tailnet.

## desk-01 (desktop, this machine)

| Lane | Role | ssh alias | Port | Account | Shell |
|---|---|---|---|---|---|
| WSL (distro `Ubuntu`) | wsl-shell | `desk-wsl` | 2222 | `evaluser` | `/bin/bash` |
| Windows | windows-shell | `desk-win` | 22 | `ssh-admin` | `pwsh` |

- Windows console user: `EvalUser`
- `claude.exe`: `/mnt/c/Users/EvalUser/.local/bin/claude.exe`
- Windows scratch directory: `/mnt/c/Users/EvalUser/scratch`

## lap-01 (laptop)

| Lane | Role | ssh alias | Port | Account | Shell |
|---|---|---|---|---|---|
| WSL (distro `Ubuntu`) | wsl-shell | `laptop-wsl` | 2222 | `evaluser` | `/bin/bash` |
| Windows | windows-shell | `laptop-win` | 22 | `ssh-admin` | `pwsh` |

- Windows console user: `EvalUser`
- `claude.exe`: `/mnt/c/Users/EvalUser/.local/bin/claude.exe`
- Windows scratch directory: `/mnt/c/Users/EvalUser/scratch`

## Reach from desk-01

| To | Command |
|---|---|
| lap-01 WSL | `/mnt/c/Windows/System32/OpenSSH/ssh.exe laptop-wsl 'claude -p "<prompt>" < /dev/null'` |
| lap-01 Windows | `/mnt/c/Windows/System32/OpenSSH/ssh.exe laptop-wsl 'cd /mnt/c/Users/EvalUser/scratch && /mnt/c/Users/EvalUser/.local/bin/claude.exe -p "<prompt>" < /dev/null'` |

From the Windows lane, use `ssh.exe` in place of the full path.
MD
