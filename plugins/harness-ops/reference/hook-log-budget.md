# Hook-log budget figures

The four rows [#3757](https://github.com/melodic-software/claude-code-plugins/issues/3757) asks
for, measured through the registered launcher (`node hooks/exec-bash.mjs --require-true
SESSION_EVENT_LOG_ENABLED hooks/session-event-log.sh`). This file is where a Windows Git Bash
capture lands.

## Decision

- **Claim:** The Windows Git Bash capture is recorded below, and the per-session event log stays off by default: no figure argues against it. Windows figures come only from `hooks/measure-hook-log-budget.sh` run on that host. A Linux run of the harness is a Linux capture and is not copied into the Windows column.
- **Basis:** the harness runs `node exec-bash.mjs --require-true SESSION_EVENT_LOG_ENABLED session-event-log.sh`, the command the settings rows registered until the log moved into the hooks module ([ADR 0057](../../../docs/adr/0057-move-the-harness-ops-session-event-log-into-a-mod.md)). The module runs the same launcher and script, without the gate, only while the log is on, so the enabled figures are its per-event cost; with the log off it starts no process, and the kill-switch-off figures describe the retired rows. The [hook-budget convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/hook-budget/README.md) counts the unit S (`bash -c :`) on the host running the hook, and the Windows measurements there put S between 18 ms and 80 ms. #3757 names the four probes.
- **As of:** 2026-09-30.
- **Recheck:** a new Windows Git Bash run of the harness (the stamp accepts `OSTYPE` `msys` and `cygwin`; Git for Windows 2.55.0's bash 5.3.15 reports `cygwin`) whose capture begins `host: windows-git-bash`, pasted over the capture below; or a change to the command the hooks module (`hooks/register.ts`) runs, or to the bash `hooks/exec-bash.mjs` resolves.

## Windows Git Bash figures

| Probe | Windows Git Bash |
|---|---|
| kill-switch off, median ms, and the parallel wall of 30 events with logging off and on | kill-switch off median 60 ms (bash spawn floor S 33 ms through the launcher's bash, 20 ms on the PATH bash; node spawn floor 49 ms); parallel wall of 30 events 406 ms off, 466 ms on |
| append of 33 lines at 4 KB and at 16 KB, corrupt line count | 33 lines at 4 KB, 0 corrupt; 33 lines at 16 KB, 0 corrupt |
| `ls -t` order of two files touched in the same second | listed `first second` at same-second resolution: mtime resolution ties at one second, so the order is not guaranteed |
| late-EOF held-open pipe, elapsed ms | 358 ms |

## Which bash

Captured 2026-09-30 on melo-desk-001 from Git for Windows 2.55.0's own bash (`MSYSTEM=MINGW64`,
`uname -s` `MINGW64_NT-10.0-26200`), which reports `OSTYPE=cygwin`. The host has no Cygwin install
(`C:\cygwin64` and `C:\cygwin` are absent), so `cygwin` here is what Git Bash reports, not a second
shell.

Two Git binaries are involved, and the capture records both paths:

- The `bash` on PATH inside Git Bash is `C:/Program Files/Git/usr/bin/bash.exe`
  (`invoking_bash_*`). The harness, the append probe and the `ls -t` probe run in it.
- `exec-bash.mjs` resolves `C:/Program Files/Git/bin/bash.exe` first (`launcher_bash_path`), a 47 KB
  wrapper that starts the real bash. Every enabled hook row spawns it, so S is timed through it: 33 ms,
  against 20 ms for the PATH bash. Only the enabled parallel wall and late-EOF spawn bash; the
  kill-switch-off row and the off wall exit in node before bash is resolved.

With `CLAUDE_CODE_GIT_BASH_PATH` set to `C:/Program Files/Git/usr/bin/bash.exe`, a second run gave S
20 ms, kill-switch off 60 ms, parallel wall 391 ms off and 441 ms on, late-EOF 350 ms. The wrapper is
about 13 ms of S. The table above is the default resolution, which is what a hook runs.

## Wide-payload read cost

A measurement, not a gate: CI holds the hook to its spawn count, never to a duration.

- **Claim:** reading effort and the allowlisted top-level keys out of a payload at the 64 KB read
  cap adds work that does not grow with the session, and adds no process. On Linux the enabled row
  on a 60 KB `tool_input` payload with every allowlisted key absent took 11.87 ms more than on a
  small payload (`wide_payload_extra_ms`, median of 10 per-sample differences), beside S 1.01 ms
  (`S_ms`, `bash -c :` timed in the same loop). About 4 ms of that is the top-level read; the rest
  is the read loop and lookups the hook already did.
- **Basis:** `hooks/measure-hook-log-budget.sh --samples 10` on a Linux (WSL2) host, the
  `wide_payload_extra_ms` and `S_ms` lines of its capture; the hook-budget convention's unit S.
- **As of:** 2026-10-02.
- **Recheck:** a Windows Git Bash run of the harness, whose `wide_payload_extra_ms` and `S_ms`
  lines are added here beside the Linux pair (Windows is unmeasured for this probe); or a change to
  the payload parsing in `hooks/session-event-log.sh`.

| Host | `wide_payload_extra_ms` | `S_ms` | Date |
|---|---|---|---|
| linux | 11.87 | 1.01 | 2026-10-02 |
| windows-git-bash | unmeasured | unmeasured | |

## How to capture

On the host, with `node` on PATH:

```bash
bash plugins/harness-ops/hooks/measure-hook-log-budget.sh --samples 10 --record /tmp/hook-log-budget.txt
```

Paste that capture under this heading.

```text
host: windows-git-bash
ostype: cygwin
uname_s: MINGW64_NT-10.0-26200
date: 2026-09-30T16:32:40Z
samples: 10
invoking_bash_path: /usr/bin/bash
invoking_bash_native_path: C:/Program Files/Git/usr/bin/bash.exe
launcher_bash_path: C:/Program Files/Git/bin/bash.exe
node_spawn_floor_median_ms: 49
bash_spawn_floor_median_ms: 33
invoking_bash_spawn_floor_median_ms: 20
kill_switch_off_median_ms: 60
parallel_wall_off_ms: 406
parallel_wall_on_ms: 466
append_4kb_lines: 33
append_4kb_corrupt: 0
append_16kb_lines: 33
append_16kb_corrupt: 0
ls_t_order: first second
ls_t_resolution: same-second
late_eof_ms: 358
```

`measure-hook-log-budget.sh --check-doc plugins/harness-ops/reference/hook-log-budget.md` exits 0 when a `host: windows-git-bash` line is present. It also exits 0 for a doc whose Windows cells still hold the unmeasured placeholder, and exits 1 when neither is present.
