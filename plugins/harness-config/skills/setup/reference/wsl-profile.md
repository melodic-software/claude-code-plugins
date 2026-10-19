# WSL hardening profile

An opt-in settings profile for Claude Code running inside WSL on a Windows machine. It closes four
gaps with settings, not hooks. `/harness-config:setup wsl-profile` prints it for the current host and
writes nothing.

## Detect a WSL host

A host is WSL when `WSL_DISTRO_NAME` is set, or `/proc/version` names Microsoft or WSL. The profile
applies only there; on any other host the action says so and prints nothing.

## The profile

All path rules are `Read(//...)` or `Edit(//...)`, absolute from the filesystem root. Every path is
derived from the running user's `$HOME` and the Windows user directories visible under
`/mnt/<drive>/Users/<user>`; nothing machine-specific ships.

| Setting | Entries | Why |
| - | - | - |
| `permissions.deny` `Read` | `$HOME/.ssh/id_*`, `$HOME/.azure/msal_token_cache*`, `$HOME/.config/gh/hosts.yml`, `$HOME/.gnupg/**`, `$HOME/.microsoft/usersecrets/**` | Linux-side secret stores are readable by default. The locations are the tools' conventions, not verified here; confirm each exists on your host. |
| `permissions.deny` `Edit` | `/mnt/<drive>/Users/<user>/.claude/**`, `/mnt/<drive>/Users/<user>/.claude.json` | The Windows host's Claude config is writable through `/mnt/<drive>/...`. |
| `env.TMPDIR` | `/tmp`, or `$WSL_PROFILE_TMPDIR` when set | Hooks and the shell resolve temp to the same directory. The session's own `$TMPDIR` is not used: inside a sandbox it is a per-session path. Edit the value if you want another. |

Use `Edit(path)`, never `Write(path)`, for the Windows config: Claude Code accepts a `Write` path
rule but never consults it. A single leading `/` anchors at the settings source, not the filesystem
root, so `//` is the only absolute form. Both are stated on the
[permissions page](https://code.claude.com/docs/en/permissions) ("Read and Edit"); as of 2026-10-18,
recheck when that section changes.

`wsl-profile.sh lint <file>` fails on any `Write(path)` rule and on any `Read`/`Edit` path rule
without a `//` prefix, so a profile you edit can be checked.

## Limits

A deny rule is not an OS-level control. Per the same permissions page section (as of 2026-10-18,
recheck when it changes):

- Read and Edit denies cover the built-in file tools, the Bash file commands Claude Code recognizes
  (`cat`, `head`, `tail`, `sed`, `tee`) and redirection targets.
- They do not cover a command that reads files without naming them (`grep -r`), or a subprocess that
  opens files itself, such as a Python or Node script.
- A `Read` deny does not cover NotebookEdit, so add an `Edit` deny for any path no tool may change.

For OS-level enforcement that blocks all processes from a path, enable the
[sandbox](https://code.claude.com/docs/en/sandboxing) and give it matching filesystem rules. The
deny rules here are the first layer, not a replacement.

## Host steps you run

The plugin edits neither of these.

- `appendWindowsPath=false` in `/etc/wsl.conf` (`[interop]` section) keeps Windows paths off the WSL
  `PATH`. It is a WSL setting outside Claude Code. With it set, `/copy` and paste need
  `powershell.exe` reachable: symlink the Windows PowerShell to `~/.local/bin/powershell.exe`
  yourself, from the path it has on your host.
- Restart WSL (`wsl --shutdown` from Windows) after a `wsl.conf` change.
