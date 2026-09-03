# Hook budget — the always-on cost ceiling

Owner doc for the marketplace's always-on hook cost budget, adopted in
[#1809](https://github.com/melodic-software/claude-code-plugins/issues/1809). Every plugin accounts
for its own hook cost honestly where it accounts at all; nobody summed them, and the aggregate is
what a consumer experiences — a multi-second stall per tool call that no single plugin reviewed.
This doc states the ceiling the sum must fit inside. The
[hook-precision](../hook-precision/README.md) convention owns *what* a hook fires on; this one owns
*what the always-on set may cost*.

## The budget

Fleet-wide aggregate across every always-on hook a consumer install fires, measured as parallel
wall time (Claude Code runs matching hooks in parallel, so the wall is the max of the set under
spawn contention, not the sum):

| Surface | Budget |
| --- | --- |
| Per tool call (`PreToolUse` + `PostToolUse` for one matcher) | ≤ 1 s typical, ≤ 2 s worst-case |
| Per turn (`Stop` / notification-shaped hooks) | ≤ 500 ms |

"Always-on" means the hook fires regardless of whether the plugin's feature is in use — an
unconditional matcher like `Bash|PowerShell` or `Write|Edit`. A hook that fires only inside its
plugin's own workflow is not in this budget.

## Measurement method

Wall-clock (`EPOCHREALTIME`) around direct hook invocation with a benign representative payload, on
a representative dev host; singles averaged over ≥ 10 runs, sets launched concurrently (`&` +
`wait`) to approximate the harness's parallel dispatch. Windows numbers are the binding ones:
process spawn is most expensive there, and the fleet's reference measurements
(2026-07-31, Windows 11 + Git Bash, at the pre-#1809 baseline `d5d02a2d`) are `bash -c :` ≈ 80 ms,
`python3 -c pass` ≈ 160 ms — with the per-Bash-call always-on set (six guardrails classifiers + the
disk-hygiene engine gate) measuring ≈ 5.9 s parallel wall and the per-Write set (two formatters +
three guardrails verifiers) ≈ 1.9 s. #1809's single-writer change removes per-Write work only in
repos without a markdownlint config; in an opted-in repo the per-Write set is unchanged (typos-format
still scans in report-only mode), so these figures remain the binding accounting until re-measured.

## Reference figures (2026-09-02, after the hook-performance program)

The fleet's binding measurement is now the dotfiles fan-out harness
(`common/measure-claude-hook-fanout.sh`, sha256
`5a254b50a67a9e1b158ce9ff7bd3c7c53f7eade80e55a1b2f8c5075026067178`), which samples 22 events
against the installed plugin cache, times each hook process in-process with `EPOCHREALTIME`, and
interleaves a `bash -c :` spawn floor S with every sample. A run is valid at S at or below 160 ms;
figures below are spawn-equivalents (hook wall divided by the same-run S), which is the number that
survives a change of host, with the reference-host conversion at S = 80 ms beside it. Every hook
stays `type: command` in its plugin's `hooks/hooks.json`; the program removed no check, added no
`async` row, and narrowed no matcher. The eight guardrails per-Bash-call guards and the three
per-Write verifier guards run through one dispatcher process per event; the six formatter plugins
carry one `if: Edit(*.ext)` row per extension so a Write to any other file spawns nothing.

| Surface (benign payload) | Before (`main` 2026-09-02 morning, S = 33 ms) | After (`main` at `9f07fb5fc`, S = 26 ms, phase 4b not yet installed) | Reference host at S = 80 ms |
| --- | --- | --- | --- |
| PreToolUse `Bash` (`git status --short`), slowest hook | 75.0 | 91.5 | about 7.3 s |
| PreToolUse `Write` (in-repo `.md`), slowest hook | 23.4 | 78.0 | about 6.2 s |
| PostToolUse `Write` (in-repo `.md`), slowest hook | 36.7 (out-of-repo sample; the in-repo pre-program figure is 13,225 ms, about 400 S) | 163.5 | about 13 s |
| PostToolBatch (per turn) | 38.0 | 8.2 | about 0.65 s |
| UserPromptSubmit (per turn) | 29.5 | 6.7 | about 0.54 s |
| Stop, slowest of four (per turn) | 11.4 | 27.2 | about 2.2 s |
| SessionStart `startup`, slowest | 2.7 | 2.9 | about 0.23 s |

The per-turn rows meet the budget table above; the per-tool-call rows do not, and the "after"
column is worse than "before" on those rows for two stated reasons: the before run's Write samples
lived outside the repository, so every Write and verifier guard early-exited and measured a no-op
(the harness now writes its samples under the measured cwd), and the after run shared its host with
the phase 4b worker's suites (S rose from 18 ms to 26 ms during it). The remaining per-tool-call
cost sits in the guardrails dispatcher, which pays the shared library's telemetry envelope (two
`jq` per guard when `HOOK_TELEMETRY_SINK` is set) and payload reader on every fire; the builtin
versions of both land with the 4b sync and the final run in the program's DEVIATIONS log is the
figure of record for that column. Per-plugin READMEs carry the paired before-and-after figures
for each change (guardrails, context-guard, rate-limit-guard, typos-format, eol-normalizer,
markdown-format).

## Rules

1. **A plugin adding or widening an always-on hook states its measured share** (method above) in
   its README, and the change's review weighs that share against the headroom left in the budget.
2. **The budget never relaxes to absorb an overage.** The current per-Bash-call set exceeds the
   ceiling several times over; that overage is per-plugin remediation work (e.g. guardrails
   spawn-reduction, #1403), not grounds to move the ceiling.
3. **Interpreter choice is a budget decision.** Every always-on hook pays its interpreter's startup
   on every fire; a Python `Stop` hook spends a third of the whole per-turn budget before its first
   statement on the reference host.
