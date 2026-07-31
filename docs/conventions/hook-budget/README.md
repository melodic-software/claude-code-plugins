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

## Rules

1. **A plugin adding or widening an always-on hook states its measured share** (method above) in
   its README, and the change's review weighs that share against the headroom left in the budget.
2. **The budget never relaxes to absorb an overage.** The current per-Bash-call set exceeds the
   ceiling several times over; that overage is per-plugin remediation work (e.g. guardrails
   spawn-reduction, #1403), not grounds to move the ceiling.
3. **Interpreter choice is a budget decision.** Every always-on hook pays its interpreter's startup
   on every fire; a Python `Stop` hook spends a third of the whole per-turn budget before its first
   statement on the reference host.
