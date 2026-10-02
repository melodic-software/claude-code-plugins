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
`async` row, and narrowed no matcher. The guardrails per-Bash-call guards and the per-Write
verifier guards run through one dispatcher process per event; the six formatter plugins
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
3,048 ms per fire on the Windows measuring host across the Write, Edit and Bash rows (eight guards
per Bash call and three per Write or Edit, both at measurement time), followed by markdown-format's
`markdownlint-cli2` Node process.
The "after" spawn-equivalents read higher than "before" on the Write and Edit rows because the
before run's samples lived outside the repository, so every Write and verifier guard early-exited
and measured a no-op; the harness now writes its samples under the measured cwd. Per-plugin
READMEs carry the paired before-and-after figures for each change (guardrails, context-guard,
rate-limit-guard, typos-format, eol-normalizer, markdown-format). The run's transcript, the
installed versions and shas, the per-file cache compare and every `hooks.json` entry measured are
recorded in the hook-performance program's DEVIATIONS log.

## Exec-form fleet sweep

Every shipped hook row, except the shell-form rows named under "Scope", is exec form ([#3686](https://github.com/melodic-software/claude-code-plugins/issues/3686)) with `"command": "node"`. A row whose script is bash runs `hooks/exec-bash.mjs` (canonical copy [`lib/exec-bash.mjs`](../../../lib/exec-bash.mjs)) and then the script; a row whose script is Node names that script directly. The bullets state what the sweep costs and what it needs.

- **What shipped.** Every row in `plugins/*/hooks/hooks.json` and in the skill-frontmatter hooks of
  `disk-hygiene:clean` and `repo-hygiene:clean`, except the shell-form rows named under "Scope",
  carries `args` and `"command": "node"`. Option gates
  that used to be shell tests are launcher flags (`--require-true`, `--run-if-unset-or-true`). Two
  scripts check the spelling. `scripts/check-exec-form-windows-probe.sh` rejects a `.sh` path, a
  `.cmd`/`.bat` shim, or bare `bash` as `command`; a non-Windows skip of its spawn half does not show
  that [anthropics/claude-code#90495](https://github.com/anthropics/claude-code/issues/90495) is
  absent, and if that spawn reports args dropped, the script exits 1. `scripts/check-hook-exec-form.sh`
  rejects bare `bash` with the script in `args`. The four-part record is
  [Windows exec-form probe](../../plugin-philosophy.md#windows-exec-form-probe).
- **Cost.** The table's exec-form k of 1 applies to a row that runs the program itself, such as a
  Node script named in `args`. A bash-scripted row behind the launcher is k = 2 (node, then bash),
  plus 1 per program the script starts. That is the shell-form line's "a script is at least 2", so
  the sweep is not a spawn saving.
- **Prerequisite.** Node on PATH is now required for every exec-form hook (`command` is `node`). The launcher
  cannot detect a missing node, because the launcher is a node process; a failed launch is
  non-blocking, so the guard then enforces nothing (the
  [philosophy Hooks row](../../plugin-philosophy.md#component-stances)). With node present and bash
  unresolvable, the launcher exits 1: a non-blocking hook error and not a guard block, and the guard
  script does not run (the header of
  [`lib/exec-bash.mjs`](../../../lib/exec-bash.mjs)).
- **Scope.** Three rows stay shell form so they can report a missing `node`: the `SessionStart` notice rows in `guardrails` and `disk-hygiene`, and the `hook-failure-audit` Stop row in `harness-ops`.
  Neither check script inspects a shell-form row; each of the three plugins' own hook tests pins its
  row's shell form, so a sweep back to `node` fails that test. A plugin hook config carries no
  `${user_config.*}` token (the [philosophy Hooks row](../../plugin-philosophy.md#component-stances)),
  so no `userConfig` rule requires exec form and exec form fleet-wide is this sweep's choice.
- **Measurement.** The reference figures above (Windows, 2026-07-31 and 2026-09-02) were taken before
  the sweep. The launcher's added time comes from the paired run below
  ([#3686](https://github.com/melodic-software/claude-code-plugins/issues/3686)).

### Launcher A/B (melo-lap-001, 2026-10-01)

Setup:

- **Host:** melo-lap-001 (Windows 11, Git Bash 5.3.15, Node 24.21.0) on AC and idle.
- **Harness:** the dotfiles fan-out harness (sha256
  `e1bbebb90ebf4f49b0d765b98aab69d109b33299245effc58c3872f2290c12b4`) with `--runs 3`, against
  plugins at `b7c8a6221`.
- **Arm A:** each plugin as shipped (`node` plus `exec-bash.mjs`).
- **Arm B:** the same copy with every launcher row rewritten to shell form,
  `bash "${CLAUDE_PLUGIN_ROOT}"/hooks/<script> <same args>` with `"shell": "bash"` and no `args`.
  Only `hooks/hooks.json` differs between the arms.
  - Arm B drops the launcher's option gates. The harness sets no `CLAUDE_PLUGIN_OPTION_*`, so every
    `--run-if-unset-or-true` gate was open in arm A as well.
  - The one `--require-true` row (guardrails `Workflow`) has no harness sample.
- **Runs:** A, B, A, B, A, B per plugin, each with `CLAUDE_CONFIG_DIR` pointing at a config that
  enables only that plugin. All 18 runs were valid.

Each figure is the median of the three run medians, in ms. The S figure in the last column is the
difference divided by the plugin's S, the median over all six runs, shown beside its name. The
guardrails `SessionStart` row is shell form in both arms, so it is the control.

| Plugin (S, ms) | Row | Arm A (`node` launcher) | Arm B (shell form) | A − B, ms (S) |
| --- | --- | ---: | ---: | ---: |
| eol-normalizer (S 21) | PostToolUse `Write` | 292 | 257 | 35 (1.7) |
| | PostToolUse `Edit` | 307 | 251 | 56 (2.7) |
| typos-format (S 21.5) | PostToolUse `Write` | 371 | 326 | 45 (2.1) |
| | PostToolUse `Edit` | 378 | 313 | 65 (3.0) |
| | SessionStart `startup` | 182 | 127 | 55 (2.6) |
| | SessionStart `compact` | 181 | 124 | 57 (2.7) |
| guardrails (S 23) | PreToolUse `Bash` | 166 | 114 | 52 (2.3) |
| | PreToolUse `Bash` (`$(…)` sample) | 164 | 124 | 40 (1.7) |
| | PreToolUse `Write` | 214 | 172 | 42 (1.8) |
| | PreToolUse `Edit` | 209 | 188 | 21 (0.9) |
| | PostToolUse `Write` | 275 | 231 | 44 (1.9) |
| | PostToolUse `Edit` | 311 | 271 | 40 (1.7) |
| | SessionStart `startup` (control, shell form in both arms) | 33 | 37 | −4 (−0.2) |
| | SessionStart `compact` (control) | 37 | 38 | −1 (0.0) |

On every bash-scripted row the launcher took 21 to 65 ms longer per fire than shell form, about
1 to 3 S. The control row moved by at most 4 ms. That fits the **Cost** bullet: the sweep is not
a spawn saving, and on this host each bash-scripted fire costs about 2 S more than it did in shell
form.

The absolute times come from a one-plugin config with the harness's synthetic payloads, so they
cannot be compared with the reference figures above. The difference between the arms is the
measurement.

## Rules

1. **A plugin adding or widening an always-on hook states its k and its measured cost in S** in its
   README, and adds the hook to one of the two enforced lists above.
2. **The budget never relaxes to absorb an overage.** The per-tool-call set exceeds k × S many
   times over; that overage is per-plugin remediation work (guardrails spawn reduction, #1403 and
   #4390), not grounds to raise a ceiling.
3. **Interpreter choice is a budget decision.** Every always-on hook pays its interpreter's startup
   on every fire. On the Windows reference host `python3 -c pass` measured about 160 ms against
   80 ms for `bash -c :`, so a Python hook costs about 2 S before its first statement.

## Windows kernel Token leak

Hook, statusline, and Bash-tool spawns add to a Windows kernel Token-object leak. The leak per
spawn differs by binary and by host, so this doc states no rate. The section "The host-level floor:
a kernel Token-object leak" of
[known-performance-issues.md](../../../plugins/harness-ops/skills/audit-performance/reference/known-performance-issues.md#the-host-level-floor-a-kernel-token-object-leak-suspect-5-windows)
owns the reference host's per-binary measurements, sources, and recheck triggers.
[#4372](https://github.com/melodic-software/claude-code-plugins/issues/4372) holds the melo-lap-001
rows, and [#4373](https://github.com/melodic-software/claude-code-plugins/issues/4373) tracks
per-hook fan-out reduction. The leak does not relax the budget (Rule 2).
