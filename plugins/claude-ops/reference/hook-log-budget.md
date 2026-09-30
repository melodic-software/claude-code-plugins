# Hook-log budget figures

The four rows [#3757](https://github.com/melodic-software/claude-code-plugins/issues/3757) asks
for, measured through the registered launcher (`node hooks/exec-bash.mjs --require-true
SESSION_EVENT_LOG_ENABLED hooks/session-event-log.sh`). This file is where a Windows Git Bash
capture lands.

## Decision

- **Claim:** The Windows Git Bash capture is recorded below, and the per-session event log stays off by default: no figure argues against it. Windows figures come only from `hooks/measure-hook-log-budget.sh` run on that host. A Linux run of the harness is a Linux capture and is not copied into the Windows column.
- **Basis:** `hooks/hooks.json` registers every event-log row as `node exec-bash.mjs --require-true SESSION_EVENT_LOG_ENABLED session-event-log.sh`, and the harness runs that command. The [hook-budget convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/hook-budget/README.md) counts the unit S (`bash -c :`) on the host running the hook, and the Windows measurements there put S between 18 ms and 80 ms. #3757 names the four probes.
- **As of:** 2026-09-30.
- **Recheck:** a new Windows Git Bash run of the harness (`OSTYPE` `msys` or `cygwin`) whose capture begins `host: windows-git-bash`, pasted over the capture below; or a change to the event-log rows' `command` or `args` in `hooks/hooks.json`.

## Windows Git Bash figures

| Probe | Windows Git Bash |
|---|---|
| kill-switch off, median ms, and the parallel wall of 30 events with logging off and on | kill-switch off median 71 ms (bash spawn floor S 26 ms, node spawn floor 59 ms); parallel wall of 30 events 454 ms off, 622 ms on |
| append of 33 lines at 4 KB and at 16 KB, corrupt line count | 33 lines at 4 KB, 0 corrupt; 33 lines at 16 KB, 0 corrupt |
| `ls -t` order of two files touched in the same second | listed `first second` at same-second resolution: mtime resolution ties at one second, so the order is not guaranteed |
| late-EOF held-open pipe, elapsed ms | 389 ms |

## How to capture

On the host, with `node` on PATH:

```bash
bash plugins/claude-ops/hooks/measure-hook-log-budget.sh --samples 10 --record /tmp/hook-log-budget.txt
```

Paste that capture under this heading.

```text
host: windows-git-bash
ostype: cygwin
date: 2026-09-30T03:57:32Z
samples: 10
node_spawn_floor_median_ms: 59
bash_spawn_floor_median_ms: 26
kill_switch_off_median_ms: 71
parallel_wall_off_ms: 454
parallel_wall_on_ms: 622
append_4kb_lines: 33
append_4kb_corrupt: 0
append_16kb_lines: 33
append_16kb_corrupt: 0
ls_t_order: first second
ls_t_resolution: same-second
late_eof_ms: 389
```

`measure-hook-log-budget.sh --check-doc plugins/claude-ops/reference/hook-log-budget.md` exits 0 when a `host: windows-git-bash` line is present. It also exits 0 for a doc whose Windows cells still hold the unmeasured placeholder, and exits 1 when neither is present.
