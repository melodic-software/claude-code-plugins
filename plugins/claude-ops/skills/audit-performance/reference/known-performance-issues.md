# Known Claude Code performance issues and fixes

Distilled evidence base for the three-suspect model this skill's report is read against.
Compiled 2026-08-12 from the upstream issue tracker, release notes, and a source-level analysis
of Claude Code v2.1.228. Per the upstream-drift convention: re-verify a row against the linked
source before resting a conclusion on it — the platform moves, and absence from this file is not
evidence of absence. `/claude-ops:known-issues` is the live-search complement.

## Version regressions fixed in 2.1.2xx (suspect 2)

An installation running a version below these carries known, fixed slowness. Capture the version
before any reinstall.

| Fixed in | What it fixed | Why it matters |
|---|---|---|
| v2.1.216 (2026-07-20) | Message-normalization cost grew **quadratically** with conversation turns — multi-second stalls in long sessions, slow resumes | The single strongest alternative explanation for "it got slower over weeks" |
| v2.1.208 (2026-07-14) | Per-tool-call CPU with many MCP tools (up to 7x), transcript size (up to 79x in edit-heavy sessions), unbounded file-edit read cache (now 16 MB) | Couples suspect 2 to suspect 3: big fleets hurt far more on older versions |
| v2.1.207 (2026-07-11) | Terminal freezing / keystroke lag while streaming long output; Windows process creation via kernel32 instead of PowerShell | Direct keystroke-lag fix; also removed a per-spawn security-tool trigger on Windows |
| v2.1.203 (2026-07-07) | Per-turn CPU/memory regression (context indicator re-analyzed the whole transcript every turn) | — |
| v2.1.221 (2026-08-10) | Fewer event-loop stalls; Windows startup improvement | — |

## Accumulated-state mechanisms confirmed at source level, v2.1.228 (suspect 1)

- **Retention sweep cost is a daily stat-walk of the whole tree.** Fires ~5 s after the first
  launch of the day (24 h sentinel: `.last-cleanup`; defers 10 min while the user was active in
  the last 60 s), then runs ~30 sequential sub-sweeps doing a stat (and past the window, an
  unlink) per file. Async and yielding, so the harm mode is sustained background I/O — amplified
  per-operation by antivirus filter drivers — not a blocked event loop.
- **An unparsable `settings.json` silently pauses the entire sweep.** Nothing is cleaned for as
  long as the error persists; the only surfaces are `/doctor`, `/status`, and this skill's
  `sweep_health`. The tree then grows without bound while looking normal.
- **Never swept, grow forever:** `history.jsonl` (every prompt ever typed) and the home-root
  `~/.claude.json`. The supported shrink lever for the latter is `claude project purge <path>`;
  a community report (Medium, 2026-07) confirmed surgically pruning one project's metadata from
  `~/.claude.json` fully cured an input-lag case.
- **`cleanupPeriodDays` default 30** (minimum 1). Raising it far preserves transcripts by growing
  the live tree — the wrong lever for preservation.
- **Resumed mega-sessions:** `--continue`/`--resume` loads the full transcript with no cap, and
  Windows builds force a full-viewport repaint per frame, so per-keystroke render cost scales
  with mounted transcript size. Session hygiene (fresh sessions, `/clear`) bounds it.

## The "nuke ~/.claude" folk remedy — evidence status

Weakly supported. The strongest public testimonial actually pruned `~/.claude.json`, not the
directory; the one tracker report of deleting `projects/` got partial, temporary relief
(anthropics/claude-code#50713). A delete-and-reinstall additionally crosses the version fixes
above, permanently confounding what fixed what. This skill exists so the next incident produces
evidence instead of a ritual.

## Windows-specific amplifiers

- Defender real-time scanning taxes every stat/unlink/spawn under the tree; the sweep and
  file-history churn pay it per file (handle-hold EPERM during plugin install:
  anthropics/claude-code#54053; installer false positive: #36796). Exclusions are hidden from
  non-elevated `Get-MpPreference` on Windows 11 — an empty non-admin read proves nothing.
- Every running session polls `~/.claude.json` at 1 Hz (cheap stat; a full main-thread re-parse
  only when another process writes it), and concurrent sessions multiply all watcher/poll load.
- Claude **Desktop** (Electron) has its own distinct lag bugs (unbounded LocalStorage sync,
  #55149; idle disk-write churn, #58799) — do not import Desktop evidence into a CLI diagnosis
  or vice versa; say which surface the symptom was observed on.
