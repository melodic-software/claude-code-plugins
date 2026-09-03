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

| Surface (benign payload) | Before (`main` 2026-09-02 morning, S = 33 ms) | After (`main` at `5e3d749cb`, 2026-09-03, S = 18 ms, quiet host) | After at S = 80 ms |
| --- | --- | --- | --- |
| PreToolUse `Bash` (`git status --short`), slowest hook | 75.0 | 88.8 (1,599 ms) | about 7.1 s |
| PreToolUse `Write` (in-repo `.md`), slowest hook | 23.4 | 75.6 (1,360 ms) | about 6.0 s |
| PostToolUse `Write` (in-repo `.md`), slowest hook | 36.7 (out-of-repo sample; the in-repo pre-program figure is 13,225 ms, about 400 S) | 108.3 (1,949 ms) | about 8.7 s |
| PostToolBatch (per turn) | 38.0 | 15.7 (282 ms) | about 1.3 s |
| UserPromptSubmit (per turn) | 29.5 | 16.5 (297 ms) | about 1.3 s |
| Stop, slowest of four (per turn) | 11.4 | 22.8 (410 ms) | about 1.8 s |
| SessionStart `startup`, slowest | 2.7 | 3.3 (60 ms) | about 0.26 s |

Read against the budget table above in milliseconds on the measuring host: PostToolBatch,
UserPromptSubmit and Stop meet the 500 ms per-turn ceiling; PreToolUse `Bash`, PreToolUse `Write`
and PostToolUse `Write` sit at 1.4 to 1.9 s against the 1 s typical ceiling and inside the 2 s
worst case, and in the pre-program shape PostToolUse `Write` in a repository was 13.2 s. The
"after" spawn-equivalents read higher than "before" on the Write rows because the before run's
Write samples lived outside the repository, so every Write and verifier guard early-exited and
measured a no-op; the harness now writes its samples under the measured cwd. The remaining
per-tool-call cost is the guardrails dispatcher (1.6 to 3.0 s per fire on this host, eight guards
per Bash call and three per Write, each still sourcing the library and building its telemetry
data), followed by markdown-format's `markdownlint-cli2` Node process. Per-plugin READMEs carry
the paired before-and-after figures for each change (guardrails, context-guard,
rate-limit-guard, typos-format, eol-normalizer, markdown-format). The run's transcript, the
installed versions and shas, the per-file cache compare and every `hooks.json` entry measured are
recorded in the hook-performance program's DEVIATIONS log.

## Rules

1. **A plugin adding or widening an always-on hook states its measured share** (method above) in
   its README, and the change's review weighs that share against the headroom left in the budget.
2. **The budget never relaxes to absorb an overage.** The current per-Bash-call set exceeds the
   ceiling several times over; that overage is per-plugin remediation work (e.g. guardrails
   spawn-reduction, #1403), not grounds to move the ceiling.
3. **Interpreter choice is a budget decision.** Every always-on hook pays its interpreter's startup
   on every fire; a Python `Stop` hook spends a third of the whole per-turn budget before its first
   statement on the reference host.
