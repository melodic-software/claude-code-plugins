#!/usr/bin/env bash
# Writes .config/fleet/FLEET.md in the workspace, the manifest the reach skill reads
# first, for two made-up hosts: desk-01 (the desktop, where the run is) and lap-01
# (the laptop). It sits in the workspace, not under $HOME, because the agent never
# sees $HOME: it expands ~ from the /home/<user> prefix of the absolute paths in its
# context and the run denies that read. Each case's prompt names this location.
# The runner sets HOME to the run's temporary home and runs a scaffold script in the
# workspace (https://code.claude.com/docs/en/plugin-evals, "Seed the workspace or
# conversation"). The guard does not trust that alone: it looks up the account's
# real home in the password database and refuses when either HOME or the working
# directory is that home, and it never overwrites a file.
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
real_home=$(cd "$real_home" && pwd -P)
[[ "$(cd "$HOME" && pwd -P)" != "$real_home" ]] || refuse "HOME is the account's real home: $HOME"
[[ "$(pwd -P)" != "$real_home" ]] || refuse "the working directory is the account's real home: $PWD"

d="$PWD/.config/fleet"
f="$d/FLEET.md"
[[ ! -e "$f" ]] || refuse "$f already exists"
mkdir -p "$d"
cat >"$f" <<'MD'
# Fleet

Rendered for desk-01. Machines are addressed by hostname over the tailnet.

The paths under `/mnt/c` named below exist on the machines but cannot be read with this session's file tools; commands that use them still run there.

## desk-01 (desktop, this machine)

| Lane | Role | ssh alias | Port | Account | Shell |
|---|---|---|---|---|---|
| WSL (distro `Ubuntu`) | wsl-shell | `desk-wsl` | 2222 | `evaluser` | `/bin/bash` |
| Windows | windows-shell | `desk-win` | 22 | `ssh-admin` | `pwsh` |

- Windows console user: `EvalUser`
- `claude.exe`: `/mnt/c/Users/EvalUser/.local/bin/claude.exe`
- Windows scratch directory: `/mnt/c/Users/EvalUser/scratch`
- `ssh-admin` is key-only and has no DPAPI. Anything needing `EvalUser`'s Windows credentials
  runs through an on-demand task, which runs as `EvalUser`: `eval-sync`, `eval-backup`. Start
  one over port 22 with `Start-ScheduledTask <name>` and read its log.

## lap-01 (laptop)

| Lane | Role | ssh alias | Port | Account | Shell |
|---|---|---|---|---|---|
| WSL (distro `Ubuntu`) | wsl-shell | `laptop-wsl` | 2222 | `evaluser` | `/bin/bash` |
| Windows | windows-shell | `laptop-win` | 22 | `ssh-admin` | `pwsh` |

- Windows console user: `EvalUser`
- `claude.exe`: `/mnt/c/Users/EvalUser/.local/bin/claude.exe`
- Windows scratch directory: `/mnt/c/Users/EvalUser/scratch`
- `ssh-admin` is key-only and has no DPAPI. Anything needing `EvalUser`'s Windows credentials
  runs through an on-demand task, which runs as `EvalUser`: `eval-sync`, `eval-backup`. Start
  one over port 22 with `Start-ScheduledTask <name>` and read its log.

## Reach from desk-01

| To | Command |
|---|---|
| lap-01 WSL | `printf '%s\n' '<prompt>' \| /mnt/c/Windows/System32/OpenSSH/ssh.exe laptop-wsl claude -p` |
| lap-01 Windows | `printf '%s\n' '<prompt>' \| /mnt/c/Windows/System32/OpenSSH/ssh.exe laptop-wsl 'cd /mnt/c/Users/EvalUser/scratch && /mnt/c/Users/EvalUser/.local/bin/claude.exe -p'` |

From the Windows lane, use `ssh.exe` in place of the full path.
MD
