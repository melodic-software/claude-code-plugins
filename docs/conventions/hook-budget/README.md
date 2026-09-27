# Hook budget: the always-on cost ceiling

Owner doc for the marketplace's always-on hook cost budget, adopted in
[#1809](https://github.com/melodic-software/claude-code-plugins/issues/1809). Every plugin accounts
for its own hook cost honestly where it accounts at all; nobody summed them, and the aggregate is
what a consumer experiences: a multi-second stall per tool call that no single plugin reviewed.
This doc states the ceiling the sum must fit inside. The
[hook-precision](../hook-precision/README.md) convention owns *what* a hook fires on; this one owns
*what the always-on set may cost*.

## The unit: S

S is the wall time of one no-op process spawn (`bash -c :`) on the host running the hook, measured
in the same run as the hook. Budgets are stated in multiples of S because a millisecond figure does
not survive a change of host: the Windows measurements below put S anywhere from 18 ms to 80 ms.

## The budget

Each hook's budget is k × S, where k is the fewest processes one fire can cost for its shape:

| Hook shape | k | Basis ([hooks docs](https://code.claude.com/docs/en/hooks)) |
| --- | --- | --- |
| Shell form (no `args`) | 1 for the shell, plus 1 per program it starts; a script is at least 2 | "The `command` string is passed to a shell: `sh -c` on macOS and Linux, Git Bash on Windows, or PowerShell when Git Bash isn't installed." |
| Exec form (`args` set) | 1 | "Claude Code resolves `command` as an executable on `PATH` and spawns it directly with `args` as the argument vector. There is no shell" |
| `if` that does not match | 0 | "the `if` check would fail and `block-rm.sh` would never run, avoiding the process spawn overhead" |
| `async: true` | 0 on the turn's path | "By default, hooks block Claude's execution until they complete." An async hook "runs in the background without blocking." |

- **Ideal:** k × S.
- **Realistic:** k × S plus the hook's measured work. That work must not grow with the session: a
  per-turn hook reads what the turn appended, never the whole transcript.

"All matching hooks run in parallel", so a surface costs its slowest hook under spawn contention,
not the sum of its hooks.

"Always-on" means the hook fires regardless of whether the plugin's feature is in use: an
unconditional matcher like `Bash|PowerShell` or `Write|Edit`, or a per-turn event (`Stop`,
`SubagentStop`, `PostToolBatch`, `UserPromptSubmit`). A hook that fires only inside its plugin's own
workflow is not in this budget.

## What enforces it

CI enforces counts, never durations, in two places:

1. **`.performance/ratchets.json`**, checked by the test-linux step "Check performance counter
   ceilings" (`ratchet.py check`). Hook counters run through `scripts/hook-census.sh`, which fires
   the command exactly as `hooks.json` registers it, under strace, from a scratch repository:
   - `spawns` counts process creations plus successful execs, the hook's own shell included;
   - `growth` counts transcript bytes read on a warm fire at 10 MiB minus at 50 KiB, ceiling 0.
     strace follows the descriptor, so a builtin read such as `mapfile <"$t"` counts too.

   A ceiling is the value measured on the CI runner. A change that lowers a count lowers the
   ceiling in the same pull request (`ratchet.py propose-tighten --write`).
2. **Per-hook strace budget tests** in the hook's own suite. `grep -l strace plugins/*/hooks/*.test.sh`
   lists them. A row a budget test already covers gets no `spawns` entry in the ratchets file.

A new always-on hook adds itself to one of the two.

## Wall-clock measurement (Windows)

Wall-clock (`EPOCHREALTIME`) around direct hook invocation with a benign representative payload, on
a representative dev host; singles averaged over ≥ 10 runs, sets launched concurrently (`&` +
`wait`) to approximate the harness's parallel dispatch. Windows numbers are the reference ones for
wall time: process spawn is most expensive there, and the fleet's reference measurements
(2026-07-31, Windows 11 + Git Bash, at the pre-#1809 baseline `d5d02a2d`) are `bash -c :` ≈ 80 ms,
`python3 -c pass` ≈ 160 ms. The per-Bash-call always-on set (six guardrails classifiers + the
disk-hygiene engine gate) measures ≈ 5.9 s parallel wall and the per-Write set (two formatters +
three guardrails verifiers) ≈ 1.9 s. #1809's single-writer change removes per-Write work only in
repos without a markdownlint config; in an opted-in repo the per-Write set is unchanged (typos-format
still scans in report-only mode), so these figures remain the reference accounting until
re-measured.

## Reference figures (2026-09-02, after the hook-performance program)

The fleet's reference wall-time measurement is now the dotfiles fan-out harness, run on a Windows
11 + Git Bash host (`common/measure-claude-hook-fanout.sh`, sha256
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
| PreToolUse `Edit` (in-repo `.md`), slowest hook | 34.8 | 114.6 (2,062 ms) | about 9.2 s |
| PostToolUse `Edit` (in-repo `.md`), slowest hook | 41.6 (out-of-repo sample; the in-repo pre-program figure is 17,192 ms, about 520 S) | 169.3 (3,048 ms) | about 13.5 s |
| PostToolBatch (per turn) | 38.0 | 15.7 (282 ms) | about 1.3 s |
| UserPromptSubmit (per turn) | 29.5 | 16.5 (297 ms) | about 1.3 s |
| Stop, slowest of four (per turn) | 11.4 | 22.8 (410 ms) | about 1.8 s |
| SessionStart `startup`, slowest | 2.7 | 3.3 (60 ms) | about 0.26 s |

In the "after" column the slowest hook on each per-tool-call surface costs 76 to 169 S, and on
each per-turn surface 16 to 23 S. The per-tool-call cost is the guardrails dispatcher, 1,360 to
3,048 ms per fire on the Windows measuring host across the Write, Edit and Bash rows (eight guards per Bash
call and three per Write or Edit), followed by markdown-format's `markdownlint-cli2` Node process.
The "after" spawn-equivalents read higher than "before" on the Write and Edit rows because the
before run's samples lived outside the repository, so every Write and verifier guard early-exited
and measured a no-op; the harness now writes its samples under the measured cwd. Per-plugin
READMEs carry the paired before-and-after figures for each change (guardrails, context-guard,
rate-limit-guard, typos-format, eol-normalizer, markdown-format). The run's transcript, the
installed versions and shas, the per-file cache compare and every `hooks.json` entry measured are
recorded in the hook-performance program's DEVIATIONS log.

## Rules

1. **A plugin adding or widening an always-on hook states its k and its measured cost in S** in its
   README, and adds the hook to one of the two enforced lists above.
2. **The budget never relaxes to absorb an overage.** The per-tool-call set exceeds k × S many
   times over; that overage is per-plugin remediation work (guardrails spawn reduction, #1403 and
   #4390), not grounds to raise a ceiling.
3. **Interpreter choice is a budget decision.** Every always-on hook pays its interpreter's startup
   on every fire. On the Windows reference host `python3 -c pass` measured about 160 ms against
   80 ms for `bash -c :`, so a Python hook costs about 2 S before its first statement.
