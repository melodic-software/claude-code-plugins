# Hook-log budget figures

The four rows [#3757](https://github.com/melodic-software/claude-code-plugins/issues/3757) asks
for, measured through the registered launcher (`node hooks/exec-bash.mjs --require-true
SESSION_EVENT_LOG_ENABLED hooks/session-event-log.sh`). This file is where a Windows Git Bash
capture lands.

## Decision

- **Claim:** Windows Git Bash figures are produced only by `hooks/measure-hook-log-budget.sh` on that host. Until a capture here contains `host: windows-git-bash`, the Windows column is unmeasured. A Linux run of the harness is a Linux capture. It is not copied into the Windows column. The per-session event log stays off by default until that Windows capture is pasted over the placeholder.
- **Basis:** `hooks/hooks.json` registers every event-log row as `node exec-bash.mjs --require-true SESSION_EVENT_LOG_ENABLED session-event-log.sh`, and the harness runs that command. The [hook-budget convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/hook-budget/README.md) counts the unit S (`bash -c :`) on the host running the hook, and the Windows measurements there put S between 18 ms and 80 ms. #3757 names the four probes.
- **As of:** 2026-09-29.
- **Recheck:** a Windows Git Bash run of the harness (`OSTYPE` `msys` or `cygwin`) whose capture begins `host: windows-git-bash`, pasted into the table below in place of `windows-git-bash: unmeasured`; or a change to the event-log rows' `command` or `args` in `hooks/hooks.json`.

## Placeholder

| Probe | Windows Git Bash |
|---|---|
| kill-switch off, median ms, and the parallel wall of 30 events with logging off and on | windows-git-bash: unmeasured |
| append of 33 lines at 4 KB and at 16 KB, corrupt line count | windows-git-bash: unmeasured |
| `ls -t` order of two files touched in the same second | windows-git-bash: unmeasured |
| late-EOF held-open pipe, elapsed ms | windows-git-bash: unmeasured |

## How to capture

On the host, with `node` on PATH:

```bash
bash plugins/claude-ops/hooks/measure-hook-log-budget.sh --samples 10 --record /tmp/hook-log-budget.txt
```

Paste that capture under this heading. Replace the four `windows-git-bash: unmeasured` cells only when the capture's `host:` line is `windows-git-bash`.

`measure-hook-log-budget.sh --check-doc plugins/claude-ops/reference/hook-log-budget.md` exits 0 while the placeholder remains, and exits 0 after a stamped Windows capture replaces it. It exits 1 when the placeholder is gone and no `host: windows-git-bash` line is present.
