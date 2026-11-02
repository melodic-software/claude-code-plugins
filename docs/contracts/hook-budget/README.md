# Hook budget: the always-on cost ceiling

Owner doc for the marketplace's always-on hook cost budget, adopted in
[#1809](https://github.com/melodic-software/claude-code-plugins/issues/1809). Every plugin accounts
for its own hook cost honestly where it accounts at all; nobody summed them, and the aggregate is
what a consumer experiences: a multi-second stall per tool call that no single plugin reviewed.
This doc states the ceiling the sum must fit inside. The
[hook-precision](../hook-precision/README.md) convention owns *what* a hook fires on; this one owns
*what the always-on set may cost*. Where a check runs (Claude Code hook, git hook or CI) and the
duration budgets for each placement are owned by [check-placement](../check-placement/README.md);
spawn counts and their CI ratchets stay here.

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

CI enforces counts, never durations. For settings hooks it does so in two places:

1. **`.performance/ratchets.json`**, checked by the check-plugins step "Check performance counter
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

### Mods: a third enforcement form

A mod's hooks run as functions inside Claude Code, so a fire starts no process unless the mod calls
`$.process.run`, and neither list above can see it. A mod hook on `tool.call` or `prompt.submit` is
always-on. Its budget is k = 0 on the steady path: a fire that writes nothing spawns no process.
A fire that writes a contract file costs one process, the snapshot helper that renames it into
place. When the consumer sets `HOOK_TELEMETRY_SINK`, context-guard's mod also starts that sink,
fire-and-forget, once per fire that acts: lines sent to Claude, an operator-mode suggestion shown,
or a gated call denied. A fire that changes nothing starts no sink. The plugin's own
`claude plugin test` cases enforce both by stubbing `$.process.run` and
counting the calls per scenario: context-guard's
`hooks/context-guard.test.ts` ("budget: no process on calls that write nothing, one per write,
none for the gate") and rate-limit-guard's `hooks/rate-limit-guard.test.ts` ("budget: no
process on events that write nothing, one per write"). A new always-on mod hook adds such a case.
Claude Code also skips a hook that runs past its own time limit.

- **Pointer**: for the time limit, see
  [reference: limits](https://code.claude.com/docs/en/plugins/mods/reference#limits); for stubbing
  `$` calls in a test, see
  [test: Stub what Claude Code would answer](https://code.claude.com/docs/en/plugins/mods/test#stub-what-claude-code-would-answer).
- **As of**: 2026-10-03, Claude Code 2.1.288; test anchor 2026-10-11
- **Recheck trigger**: the limits table changes a hook's own time limit, or `claude plugin test`
  stops letting a test stub `$.process.run`.

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
then scanned each edit; it now reports at commit time), so these figures remain the reference accounting until
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
READMEs carry the paired before-and-after figures for each change (guardrails, typos-format,
eol-normalizer, markdown-format). context-guard's and rate-limit-guard's figures retired with the
shell hooks and status-line tee they measured; their mods' budget is under
[Mods](#mods-a-third-enforcement-form). The run's transcript, the
installed versions and shas, the per-file cache compare and every `hooks.json` entry measured are
recorded in the hook-performance program's DEVIATIONS log.

## Exec-form fleet sweep

Every shipped hook row, except the shell-form rows named under "Scope", is exec form ([#3686](https://github.com/melodic-software/claude-code-plugins/issues/3686)) with `"command": "node"`. A row whose script is bash runs `hooks/exec-bash.mjs` (canonical copy [`lib/exec-bash.mjs`](../../../lib/exec-bash.mjs)) and then the script; a row whose script is Node names that script directly. The bullets state what the sweep costs and what it needs.

- **What shipped.** Every row in `plugins/*/hooks/hooks.json` and in the skill-frontmatter hooks of
  `disk-hygiene:clean` and `repo-hygiene:clean`, except the shell-form rows named under "Scope",
  carries `args` and `"command": "node"`. Option gates
  that used to be shell tests are launcher flags (`--require-true`, `--run-if-unset-or-true`).
  Another flag skips the bash start on a row whose script would exit at once:
  `--skip-unless-stdin-contains TEXT` buffers stdin and skips a payload without TEXT (the testing
  `Bash` row). It is advisory-only and must never gate a blocking
  guard row: a stdin stall past the idle bound exits 0 without running the script, so a guard
  behind it would fail open. The flag list is in the header of
  [`lib/exec-bash.mjs`](../../../lib/exec-bash.mjs). Two
  scripts check the spelling. `scripts/check-exec-form-windows-probe.sh` rejects a `.sh` path, a
  `.cmd`/`.bat` shim, or bare `bash` as `command`; a non-Windows skip of its spawn half does not show
  that [anthropics/claude-code#90495](https://github.com/anthropics/claude-code/issues/90495) is
  absent, and if that spawn reports args dropped, the script exits 1. `scripts/check-hook-exec-form.sh`
  rejects bare `bash` with the script in `args`. The four-part record is
  [Windows exec-form probe](../../plugin-philosophy.md#windows-exec-form-probe).
- **Cost.** The table's exec-form k of 1 applies to a row that runs the program itself, such as a
  Node script named in `args`. A bash-scripted row behind the launcher is k = 2 (node, then bash),
  plus 1 per program the script starts. That is the shell-form line's "a script is at least 2", so
  the sweep is not a spawn saving. A fire whose launcher gate is closed is k = 1 (see
  [Gated Stop rows at the exec-form floor](#gated-stop-rows-at-the-exec-form-floor)).
- **Prerequisite.** Node on PATH is now required for every exec-form hook (`command` is `node`). The launcher
  cannot detect a missing node, because the launcher is a node process; a failed launch is
  non-blocking, so the guard then enforces nothing (the
  [philosophy Hooks row](../../plugin-philosophy.md#component-stances)), unless the row sets
  `"onFailure": "block"` on Claude Code 2.1.295 or later
  ([`onFailure` probes](#onfailure-probes-melo-desk-001-2026-10-29); the rows that set it are under
  [Which rows set `onFailure: "block"`](#which-rows-set-onfailure-block)). With node present and bash
  unresolvable, the launcher exits 1: a non-blocking hook error and not a guard block, and the guard
  script does not run (the header of
  [`lib/exec-bash.mjs`](../../../lib/exec-bash.mjs)).
- **Scope.** The fleet's one `SessionStart` node-notice row, in `harness-ops` (the [prerequisites convention](../prerequisites/README.md#hook-notices)), and the `hook-failure-audit` Stop row in `harness-ops` stay shell form so they can report a missing `node`.
  Neither check script inspects a shell-form row; `scripts/node-notice-rows.test.sh` pins the node-notice
  row (and the matcher that skips it on compaction) and the hook test of `harness-ops` pins its Stop row, so a sweep back to `node` fails them. A plugin hook config carries no
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

### `onFailure` probes (melo-desk-001, 2026-10-29)

These probes answer [#6755](https://github.com/melodic-software/claude-code-plugins/issues/6755)'s
older-client question and its missing-interpreter question
([#9967](https://github.com/melodic-software/claude-code-plugins/issues/9967)). Two throwaway
plugins each carry one PreToolUse `Bash` row, `node ${CLAUDE_PLUGIN_ROOT}/hooks/h.mjs`, whose
script exits 1. The `block` fixture sets `"onFailure": "block"` and the control fixture omits it.
Each session (`claude -p --plugin-dir <fixture> --permission-mode auto`) asks for one Bash
`touch` of a marker file, so a marker on disk shows the call ran. Host: WSL2 Linux, Node 24.21.0.

| Probe | Client | Command | Observed |
| --- | --- | --- | --- |
| Older client, validator | 2.1.294 | `plugin validate --json <fixture>` | `success: true`, exit 0, no error or warning on `onFailure`; output matches the control's apart from names |
| CI's validator (`package.json` pin) | 2.1.312 | same | Same as 2.1.294: accepted silently |
| Older client, session | 2.1.294 | session, `block` fixture | No load error. The hook ran and failed, and the Bash call ran: the key is ignored |
| Older client, session control | 2.1.294 | session, control fixture | Hook ran and failed, and the Bash call ran |
| Current client, session | 2.1.314 | session, `block` fixture | Bash call denied: `failed; blocking because onFailure is "block"` |
| Missing interpreter, `onFailure` set | 2.1.314 | session, `block` fixture, no `node` on PATH | Bash call denied: `Executable not found in $PATH: "node"`, then the same blocking message |
| Missing interpreter, control | 2.1.314 | session, control fixture, no `node` on PATH | Bash call ran, and no hook error reached the model |

So `plugin validate` gives no signal on `onFailure` in either version, and a pre-2.1.295 client
loads the row and ignores the key, so a row that relies on `"block"` fails open there. On a current
client, `"block"` also closes the missing-`node` gap the **Prerequisite** bullet names: the matched
call is denied instead of running unguarded. Each session made one matched call.

## Which rows set `onFailure: "block"`

Only a named security guard sets `"onFailure": "block"`: a `PreToolUse` row whose job is to deny a
call, where a hook that could not judge the call must deny it rather than let it run unguarded.
Every other row leaves the key unset and keeps the default, under which the action goes ahead when
the hook fails. The owner chose this scope on 2026-10-18
([#6755](https://github.com/melodic-software/claude-code-plugins/issues/6755), D17).

On a `command` hook, these count as failures: a hook that cannot start, an exit code other than 0
or 2, a hook that reaches its `timeout`, or JSON output that does not parse or fails validation.
With `"block"` set, a failure does what exit 2 does on that event, and on `PreToolUse` that blocks
the call. Exit 2 blocks either way. The key needs Claude Code 2.1.295 or later; an older client
loads the row and ignores it ([`onFailure` probes](#onfailure-probes-melo-desk-001-2026-10-29)).

- **Pointer:** [hooks: Block the action when a hook fails](https://code.claude.com/docs/en/hooks#block-the-action-when-a-hook-fails).
- **As of:** 2026-10-30.
- **Recheck trigger:** that section changes what counts as a failure, or which hooks ignore the
  key.

These rows set `block`. `git grep -n '"onFailure"' -- 'plugins/*/hooks/hooks.json'` lists exactly
them, and `plugins/guardrails/hooks/onfailure-rows.test.sh` fails when a row gains or loses the key:

| Plugin | Row | Why `block` |
| --- | --- | --- |
| guardrails | `PreToolUse` `Write\|Edit\|NotebookEdit`; the GitHub MCP file-write row; the MCP merge row; the GitHub MCP comment row; `Bash\|PowerShell` | Each row runs the launcher with `--fail-closed --require-verdict`, which denies when the dispatcher's bash dies by a signal, exits with a status other than 0 or 2, or ends without a verdict. The launcher still exits 1 when no bash resolves, and it cannot act at all when `node` is missing or the hook times out. `block` denies in those three cases too |
| disk-hygiene | `PreToolUse` `Bash(*hygiene.py*)` and `PowerShell(*hygiene.py*)` | The command names the clean engine. With no Python, the launcher already denies such a call. `block` also denies it when `node` or bash is missing, when the guard crashes, and on a timeout |
| discovery | `PreToolUse` `Bash`, the docs-fetcher gate | If the gate fails, `discovery:docs-fetcher`, the agent that reads untrusted pages, gets a `Bash` with no gate on it |
| multi-agent | `PreToolUse` `Bash`, the docs-fetcher gate; `PreToolUse` `WebFetch`, the drift-checker gate | The same holds for `multi-agent:docs-fetcher`. If the fetch gate fails, the drift checker can fetch any URL |

The docs-fetcher and drift-checker gates match every `Bash` or `WebFetch` call in every session,
and outside their agent they allow every call. With `block`, a gate that cannot start or times out
(10 s) denies the main thread's call too. A host with no `node` loses its guardrails `Bash` the
same way. With harness-ops enabled, its `SessionStart` node notice says `node` is missing and names
`/harness-ops:check`. The check skill's own `Bash` call is denied too, and the denial names the missing
`node`.

These rows do not set `block`:

| Row | Why not |
| --- | --- |
| Every `SessionStart` row, the shell-form node-notice row included | `SessionStart` cannot block: exit 2 only shows stderr to the user, so the key changes nothing. The node-notice row has to stay a notice so that it can report a missing `node` |
| `Stop` rows, such as disk-hygiene's guard-launch monitor and the gated end-of-turn checks, and rows with `async` or `asyncRewake`, such as harness-ops' hook-failure audit | The hooks page lists `Stop`, `SubagentStop`, `TaskCompleted`, `TeammateIdle` and background hooks as ignoring the key |
| Advisory rows: guardrails `Workflow`, discovery's `PostToolUse` `WebFetch` truncation note, disk-hygiene's `PreToolUse` `Skill` marker row, and disk-hygiene's `UserPromptExpansion` engine-context row | These rows judge nothing. With `block`, a row that only adds context or writes a marker would deny the call or expansion it was meant to annotate. The `Skill` row matches every Skill call. The engine-context row hands the skill its interpreter, and the `hygiene.py` rows above deny the engine call |
| disk-hygiene `PreToolUse` `PowerShell(*python*$*)` and `PowerShell(*& $*)` | These rows match commands that do not name the engine. With no Python, the launcher lets such a call go ahead with a notice, because denying every `& $` call on a host without Python stops work (the header of `plugins/disk-hygiene/hooks/run-python-hook.sh`). `block` would deny them on every launch failure |
| The `disk-hygiene:clean` skill-frontmatter belt | It is not a `hooks.json` row, and no probe has run a skill-frontmatter hook with the key set |
| Every row in a plugin not named above | The owner's decision covers only the named guards. A row gets `block` only by a change to this section |

Launcher paths:

- **A closed option gate** (`--require-true`, `--run-if-unset-or-true`, `--run-if-any-set`,
  `--run-if-settings-mention`) exits 0. That is not a failure, so a `block` row whose gate is off
  still lets the call through.
- **`--skip-unless-stdin-contains`** exits 0 when stdin stalls. That fails open even under
  `block`, so the flag never gates a `block` row.
- **A launcher exit 1** (no bash or a usage error, and on a row without `--fail-closed` also a
  spawn error or a child killed by a signal) counts as a failure, so under `block` it denies.
- **A guard's own abort boundary** turns every status it did not choose into 0 or 2 on exit
  (`plugins/guardrails/hooks/abort-boundary.sh`). `block` does not change that choice. Every
  guardrails guard declares `open`, so a guard's crash still lets its call through, with a notice.

`block-root-delete-target`, the root-delete guard, bounds its own work: 25 s for the judgment and
50 s for its whole run, inside the shared 60 s timeout. Where `timeout` exists, its git and
path-resolving calls run under it too. It refuses when a bound runs out, so the denial names the
guard's reason. `block` is the backstop for a hook cancelled at the timeout, such as one whose git
call stalled on a host without `timeout` (stock macOS). Its false positives
([#6625](https://github.com/melodic-software/claude-code-plugins/issues/6625),
[#6626](https://github.com/melodic-software/claude-code-plugins/issues/6626),
[#6627](https://github.com/melodic-software/claude-code-plugins/issues/6627)) are exit-2 denials,
which `onFailure` does not affect.

### Adopted-row probes (melo-desk-001, 2026-10-31)

These probes check each row above against its shipped `hooks.json`
([#9989](https://github.com/melodic-software/claude-code-plugins/issues/9989)). Each session runs
Claude Code 2.1.316 on WSL2 Linux as `claude -p --plugin-dir <plugin> --permission-mode dontAsk
--allowedTools <the probed tools> --strict-mcp-config`, with the installed copies of the four
plugins turned off through `--settings` `enabledPlugins`. The session's init event lists only the
probed copy of the four. The `block` arm runs with `PATH=/usr/bin:/bin`, which has no `node`. The
control arm keeps `node` (for guardrails and disk-hygiene, the session's whole `PATH`, `jq`
included) but has no `gh`, so the merge guard makes no GitHub read.
The GitHub MCP rows are matched by a stdio stand-in server named `github` that exposes
`push_files`, `merge_pull_request` and `add_issue_comment`, does nothing, and touches a marker per
call. A control call counts as run when its marker or its tool output appears.

| Plugin | Row | Matched call | No `node` | Control |
| --- | --- | --- | --- | --- |
| guardrails | `Write\|Edit\|NotebookEdit` | `Write` | Denied: `failed; blocking because onFailure is "block"` | File written |
| guardrails | GitHub MCP file-write | `mcp__github__push_files` | Denied, same message | Ran |
| guardrails | MCP merge | `mcp__github__merge_pull_request` | Denied, same message | Ran |
| guardrails | GitHub MCP comment | `mcp__github__add_issue_comment` | Denied, same message | Ran |
| guardrails | `Bash\|PowerShell` | `Bash` `touch` | Denied, same message | Marker written |
| disk-hygiene | `Bash(*hygiene.py*)` | engine `inventory` of an empty directory | Denied, same message | Ran, report returned |
| disk-hygiene | `PowerShell(*hygiene.py*)` | not probed | WSL sessions have no `PowerShell` tool | not probed |
| discovery | `Bash`, docs-fetcher gate | `Bash` `touch` | Denied: `Executable not found in $PATH: "node"`, then the blocking message | Marker written |
| multi-agent | `Bash`, docs-fetcher gate | `Bash` `touch` | Denied, same message | Marker written |
| multi-agent | `WebFetch`, drift-checker gate | `WebFetch` of `example.com` | Denied, same message | Page fetched |

Each adopted row probed denies its matched call when `node` is missing, and with `node` present it
lets a normal call through. The disk-hygiene `PowerShell` row still needs a probe on a Windows host.
A control environment with no `jq` is not a normal call: there the guardrails dispatcher denies
with its own `jq is not on PATH` verdict, and that is a guard's choice, not an `onFailure` block.

## Gated Stop rows at the exec-form floor

A Stop row whose launcher gate is closed sits at its shape's floor, k = 1: `node` starts,
`exec-bash.mjs` finds the gate closed and exits 0 before it reads stdin or starts bash. One process
is the fewest such a row can cost, so it has no overage for Rule 2 to hold against it. Two gate
shapes cover the Stop rows this applies to:

- the default-off end-of-turn checks of actionlint, bash-format, biome-format, go-format,
  powershell-format, ruff-format and typos-format (`--require-true <PLUGIN>_END_OF_TURN`,
  manifest default false), and markdown-format's once its option is `false`
  (`--run-if-unset-or-true MARKDOWN_FORMAT_END_OF_TURN`; unset, its default, runs the check);
- autonomy's lane-stop gate (`--run-if-any-set` or `--run-if-settings-mention`, one any-of gate).

These rows stay synchronous Stop hooks. Stop has no matcher support and a hook with `if` set on a
non-tool event never runs, so neither field can skip them. A shared dispatcher would cross plugin
boundaries, since each plugin registers its own `hooks.json`. `async: true` would take an enabled
check's findings off the turn they belong to.

- **Basis:** "When an event fires, its matching hooks run in parallel"
  ([hooks docs](https://code.claude.com/docs/en/hooks)), so a closed-gate row adds one node start
  that runs beside the other Stop hooks, not after them. A 2026-10-20 `/performance:go-faster` run
  on a loaded Windows host (5 to 10 concurrent sessions) timed 104 Stop samples per hook: these
  rows cost 283 to 378 ms p50 and 991 to 1,472 ms p95 each, which is a node cold start under
  contention. The run captured no S, so these figures have no S conversion. The same run's 125
  Stops measured the wall at p50 576 ms and p95 2,072 ms. The run attributes the p95 to two rows
  that did real work, disk-hygiene's destructive-guard audit
  ([#8771](https://github.com/melodic-software/claude-code-plugins/issues/8771)) and harness-ops'
  hook-failure audit, which has run with `async: true` since
  [#8772](https://github.com/melodic-software/claude-code-plugins/issues/8772). It recorded no
  per-Stop breakdown, so a gated row's tail may still set the wall on some Stops. That tail is the
  shared cost of concurrent node cold starts on a loaded host, which no change to one row below
  its floor removes.
- **Scope:** a row only while its gate is closed. A consumer who enables an end-of-turn option
  pays that check's own work on every Stop, and Rule 1 applies to that work.
- **Recheck trigger:** the hooks docs stop running an event's matching hooks in parallel, or a
  gated Stop row starts a process before its gate, or a per-Stop breakdown shows gated rows
  setting the wall.

## Rules

1. **A plugin adding or widening an always-on hook states its k and its measured cost in S** in its
   README, and adds the hook to one of the two enforced lists above, or, for a mod, adds a
   `claude plugin test` case that counts its processes.
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
