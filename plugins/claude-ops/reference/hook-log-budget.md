# Hook-log budget figures

The four rows #3757 asks for. Linux serial figures already in the README
(2.42 ms disabled against a 2.08 ms spawn floor) stay the published Linux
baseline. This file is where a Windows Git Bash capture lands.

## Decision

- **Claim:** Windows Git Bash figures are produced only by `hooks/measure-hook-log-budget.sh` on that host. Until a capture here contains `host: windows-git-bash`, the Windows column is unmeasured. A Linux run of the harness is a Linux capture. It is not copied into the Windows column. The per-session event log stays off by default until that Windows capture is pasted over the placeholder.
- **Basis:** [Hooks](https://code.claude.com/docs/en/hooks), fetched 2026-09-28: shell form "is passed to a shell: `sh -c` on macOS and Linux, Git Bash on Windows, or PowerShell when Git Bash isn't installed." The hook-budget convention binds wall-clock to Windows Git Bash. #3757 names the four probes.
- **As of:** 2026-09-28.
- **Recheck:** a Windows Git Bash run of the harness (`OSTYPE` `msys` or `cygwin`) whose capture begins `host: windows-git-bash`, pasted into the table below in place of `windows-git-bash: unmeasured`.

## Placeholder

| Probe | Windows Git Bash |
|---|---|
| kill-switch off, median ms, and the parallel wall of 30 events with logging off and on | windows-git-bash: unmeasured |
| append of 33 lines at 4 KB and at 16 KB, corrupt line count | windows-git-bash: unmeasured |
| `ls -t` order of two files touched in the same second | windows-git-bash: unmeasured |
| late-EOF held-open pipe, elapsed ms | windows-git-bash: unmeasured |

## How to capture

On the host:

```bash
bash plugins/claude-ops/hooks/measure-hook-log-budget.sh --samples 10 --record /tmp/hook-log-budget.txt
```

Paste that capture under this heading. Replace the four `windows-git-bash: unmeasured` cells only when the capture's `host:` line is `windows-git-bash`.

CI writes the same capture to the Windows lane's step summary (`.github/workflows/test-windows.yml`, "Capture hook-log budget figures"). That summary is the path that records a figure without a commit from the runner. Copy it here when it is a Windows capture.

`measure-hook-log-budget.sh --check-doc plugins/claude-ops/reference/hook-log-budget.md` exits 0 while the placeholder remains, and exits 0 after a stamped Windows capture replaces it. It exits 1 when the placeholder is gone and no `host: windows-git-bash` line is present.
