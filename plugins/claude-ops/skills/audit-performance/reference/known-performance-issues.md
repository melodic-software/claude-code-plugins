# Known Claude Code performance issues and fixes

Distilled evidence base for the four-suspect model this skill's report is read against.
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

## Fan-out layer mechanisms (suspect 4)

The layer a slowness audit most often clears every other suspect and then fails to reach. What
follows is measured behavior from one full manual audit on a 24-core Windows 11 workstation
running 10 to 13 concurrent sessions, plus the documented product behavior it rests on. Treat the
absolute numbers as one machine's readings and the SHAPES as the transferable part.

### Per-spawn cost is the denominator, and it moves with load

The same commands, on the same machine, drained and then under a storm of concurrent sessions:

| probe | drained | under storm |
|---|---|---|
| `bash -c 'exit 0'` | 123 ms | 1,144 ms |
| full statusline render | 657 ms | 18,445 to 41,818 ms |
| one `PreToolUse` hook | not sampled | 5,891 to 33,381 ms |

The floors move by roughly an order of magnitude. Any single-state measurement is therefore
misleading, and the wrong conclusion is easy to reach from storm-state numbers alone. The
bimodal signature, a fast mode around 120 to 430 ms alternating with a slow mode around 950 to
1,200 ms across identical no-op spawns, is itself the contention diagnosis rather than noise
around a mean. This is why `fan_out.spawn_cost` reports min, median, and max with the concurrent
process count at sample time, and never a single number.

### Hooks fire in parallel, so their cost is not additive

Eight `PreToolUse` hooks matching `Bash|PowerShell` fired on every Bash or PowerShell tool call,
each invoked as a 3-deep bash chain worth about 24 spawns per tool call. One measured 5,891 to
33,381 ms. Because hooks on an event run in parallel, 51 to 64 were alive simultaneously and
wall-clock cost was roughly the slowest hook plus contention, which matched the observed 60 to
70 s stalls. A naive 8 x 24 s sum predicts about 200 s and is wrong by a factor of three, which
is worse than useless: it fails to match the symptom and discredits the report.

Two invocation shapes cost extra process creations before the hook's own work begins, and both
are detected by `invocation_shape`:

- `Git\bin\bash.exe -c "bash script.sh"`. The `Git\bin\bash.exe` launcher re-execs
  `Git\usr\bin\bash.exe`, so pointing at `usr\bin\bash.exe` directly removes one spawn per hook.
- Any command line naming two shells. De-forking the hook chain on the audited machine moved the
  median from 10,850 ms to 2,777 ms, roughly 4x, measured back to back at the same load.

Per-turn hooks (`Stop`, `SubagentStop`, `UserPromptSubmit`, `Notification`) deserve separate
attention from per-tool-call hooks: 5 of 15 configured hooks were per-turn on the audited
machine, and per-turn cost is what makes a long conversation degrade rather than a single tool
call stall.

### Configuration on disk is not configuration in force

Plugin enablement is read AT STARTUP. On the audited machine a plugin was disabled in
`settings.json` at 13:53:02 while the newest of 13 running sessions had started at 13:44:59, so
no running session had picked the toggle up and 51 of that plugin's hook processes were still
live. Reading config off disk and describing it as the running state produces a confidently
incorrect report, in this case "that plugin is disabled, so it is not the cause" while it was
exactly the cause. This generalizes to every settings change, which is why `fan_out.config_liveness`
compares the settings mtime against each session process's start time and says plainly when a
restart is required.

### Concurrency ceilings multiply

| variable | documented default | note |
|---|---|---|
| [`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`](https://code.claude.com/docs/en/sub-agents#concurrent-subagent-limit) | 20 per session | at 10 sessions that is a 200-subagent ceiling, each carrying the same statusline and hook fan-out |
| [`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`](https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents) | 3 | depth multiplies against the concurrency ceiling |
| `CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS` | undocumented | absent from [env-vars.md](https://code.claude.com/docs/en/env-vars) but present in the shipped binary, gating background observer agents and a per-subagent observer fan-out |

**The truthiness trap.** These flags are gated by a JavaScript truthiness test on the raw string
(`if (!process.env.CLAUDE_CODE_...) return false`), and in JavaScript the string `"0"` is TRUTHY.
Setting one to `0` reads like a disable in a settings file and is a silent no-op; only removing
the variable disables it. Any advisory that says "set it to 0" is actively wrong. Re-verify the
gating shape against the shipped binary before resting a conclusion on it.

The engine reports these three against their documented defaults and flags one that is set but
undocumented upstream. It deliberately does NOT cross-check env keys against a strings scan of
the shipped binary: that capability lives in `/claude-ops:inventory`'s extractor, and reaching
into another skill's private surface to borrow it would breach the encapsulation convention. An
operator who wants that check runs that skill.

### Orphan attribution needs parent liveness, not age

Of 14 `conhost.exe` processes over 24 h old on the audited machine, 12 had LIVE parents (device
managers, a console host chain, a monitoring service); killing them would have broken running
software. Exactly one was a true orphan, alongside one 6.2-day `bash.exe` still running a
statusline script from a plugin version that had since been replaced. Age alone would have
convicted all 14.

Population trend matters as much as population size, and needs two samples: `conhost` went 34 to
44 to 49 (mild accumulation) while `bash` went 153 to 137 to 93 to 134 to 112, which is CHURN,
not accumulation. A single sample cannot tell the two apart, and the first reading of that bash
series was written up as accumulation and had to be retracted.

## Tested and cleared (record the negatives)

A plausible cause ruled out by measurement is a finding. All four of these looked right on the
audited machine and all four were wrong; without the record, the next operator re-derives them.

- **Antivirus.** The `WdFilter` minifilter was Stopped, `WinDefend` and `Sense` were stopped,
  `MsMpEng` was not running, and `DisableAntiVirus` was 1. The Windows Defender guidance this
  skill emits would have pointed at a cause that did not exist. Note that `Get-MpComputerStatus`
  throwing *Provider load failure* is a symptom of Defender being DISABLED, not evidence of it
  scanning.
- **Third-party EDR.** None present; only stock minifilters (`bindflt`, `CldFlt`, `FileInfo`,
  `luafv`, `storqosflt`, `wcifs`).
- **Filesystem.** The repository volume was ReFS on a VHDX and measured FASTER per file than the
  NTFS system drive (`git status` floor 1,955 ms over 7,238 files versus 1,105 ms over 2,055;
  enumeration 50 ms versus 57 ms). This was asserted as a cause before it was tested, and the
  test refuted it.
- **MSYS and Git Bash.** `bash.exe` floored at 123 ms, faster than `cmd.exe` at 206 ms and
  `pwsh.exe` at 267 ms. Another hypothesis that looked right and was false.

## Measurement method

1. **Use a monotonic in-process clock.** The engine's `perf_counter` is correct. Do NOT shell out
   to `date` around a command: `s=$(date +%s%N); cmd; e=$(date +%s%N)` puts a fork INSIDE the
   measured interval and inflated readings by 1 to 3 s on the loaded machine.
2. **Bracket, never single-sample.** Report min, median, and max with the concurrent process load
   at sample time.
3. **Verify config is live before attributing cost to it.**
4. **Rule out by test, then record the negative.**
5. **Prove a fix with a before and after under identical load.**

## Surface scope: CLI versus desktop

On the audited machine the four heavy sessions were all `WindowsTerminal.exe` to `pwsh.exe`,
which is the CLI, at 595 to 686 MB working set and 155 to 338 s CPU. The eight `sihost.exe` to
`claude.exe` desktop-app children were near idle at 0 to 5 s CPU and 28 to 118 MB.
`settings.json`, hooks, statusline, and the env vars are a SHARED config surface, so those
findings apply to both. **Every timing number in this section is CLI-only**, and desktop coverage
is unmeasured until someone takes readings there. See [desktop.md](https://code.claude.com/docs/en/desktop).

## Reference links

- [statusline](https://code.claude.com/docs/en/statusline): `refreshInterval` is in SECONDS
  (minimum 1), renders are debounced 300 ms, and an in-flight render is cancelled on a new trigger
- [sub-agents](https://code.claude.com/docs/en/sub-agents): concurrency limit and spawn depth
- [agent-teams](https://code.claude.com/docs/en/agent-teams)
- [env-vars](https://code.claude.com/docs/en/env-vars)
- [hooks](https://code.claude.com/docs/en/hooks)
- [debug-your-config](https://code.claude.com/docs/en/debug-your-config): `/doctor`, `/hooks`,
  `/context`, the cheap first pass worth taking before this engine
- [desktop](https://code.claude.com/docs/en/desktop)
- [llms.txt](https://code.claude.com/docs/llms.txt): the index; resolve doc URLs from here rather
  than guessing them

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
