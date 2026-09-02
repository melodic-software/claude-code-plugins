# hook-performance-levers

Draft for orchestrator review. Every phase is `[TODO]`. Branch: `perf/hook-fanout-consolidation`
(four commits ahead of `main` with the guardrails dispatcher, PR #3621, already shipped).

## Brief

### TLDR

Measure and cut every runtime-cost surface this marketplace ships on the binding host (Windows 11,
Git Bash, Claude Code 2.1.258): hook spawn count and critical-path time per event, Windows-only
production no-ops, the skill listing payload, and the statusline. Eight PR-sized phases, each with a
before and after harness run, no check removed, every hook still a `type: command` entry in its
plugin's `hooks/hooks.json`.

### Goal (from the drafted `/goal` condition)

END STATE, proven by harness output pasted in the transcript:

- **(A)** The dotfiles harness samples, beyond its current seven events, a Bash command containing
  `$(...)`, PreToolUse and PostToolUse Edit, SessionStart `source=startup`, PostCompact, PreCompact,
  Notification, PostToolUseFailure, StopFailure, InstructionsLoaded, ConfigChange,
  UserPromptExpansion, WorktreeCreate and the statusline command, and prints per event `fires=`,
  `cpu_sum_ms=`, `max_ms=` (timed in-process with `EPOCHREALTIME`) plus an interleaved `bash -c :`
  spawn baseline S (median ms), and refuses or marks the run invalid when S is above 160 ms.
- **(B)** A valid run with `--runs 3` against the installed cache (`~/.claude/plugins`) carrying the
  changes prints a `=== per event` block where every PreToolUse and PostToolUse line has
  `max_ms <= 8*S` and `cpu_sum_ms <= 12*S`; PostToolBatch `max_ms <= 3*S`; UserPromptSubmit and each
  Stop line `max_ms <= 4*S`; SessionStart `max_ms <= 6*S`; every per-tool-call `max_ms` is also
  under the 1,000 ms hook-budget ceiling in absolute terms; count caps hold: the sum of PreToolUse:Bash,
  PostToolUse:Bash and PostToolBatch is at most 3 on the plain `git status --short` sample, the sum
  of PreToolUse:Write and PostToolUse:Write is at most 8 on the `.md` sample, UserPromptSubmit at
  most 1, Stop at most 4.
- **(C)** `plugins/instruction-placement/hooks/index-drift.sh` emits its stale notice on a Windows
  `C:/...` repo path, shown by a run.
- **(D)** `plugins/skill-quality/scripts/check-listing-budget.sh` runs on the repo with its output
  pasted, reporting the shared listing estimate under the budget it prints and zero over-cap
  entries (its exit code is always 0, so the parsed lines are the check; see phase 6).
- **(E)** Every change is on a PR whose `gh pr checks` output, pasted, shows 0 failing. Merging is the
  operator's call.

STATED CHECK: immediately before the final harness run the transcript shows, read from the installed
cache paths, every `hooks.json` entry the run measures (event, matcher, if, async, timeout, command),
each measured plugin's installed version and `gitCommitSha` from `installed_plugins.json` equal to the
delivered branch HEAD, and the sha256sum of the harness at the commit its dotfiles PR carries.

### Constraints (hard, from the goal and the team lead)

1. **No check removed.** Every hook command present at baseline appears in a transcript table mapping
   it to where it now runs (dispatcher branch, `if`-gated entry, async entry, or moved event), and each
   consolidated, gated, async or moved hook has an actual run with a payload matching its real trigger
   producing the same decision as the baseline hook, pasted.
2. **Every hook stays `type: command`** and stays declared in its plugin's `hooks/hooks.json`.
3. **`if` and matcher never narrowed to dodge a sample**; each gate matches the hook's real trigger
   class.
4. **`async: true` only where the hook emits no decision and rewrites no user file.**
5. **`enabledPlugins` in `~/.claude/settings.json` unchanged**, shown before and after.
6. **Cache delivery** goes through the marketplace clone at
   `~/.claude/plugins/marketplaces/melodic-software`, checked out at the phase branch, then
   `claude plugin update <plugin>@melodic-software`, and the clone is returned to `main` afterward.
   Delivery keys on the plugin version, so a phase that changes a plugin bumps that plugin's version
   in the same PR, and a re-delivery at an unchanged version is a no-op (re-bump before
   re-delivering). Sessions pin their plugin version directory at start, so every probe and
   measurement runs in a fresh session started after the delivery.
7. **Any `hook-utils.sh` change** goes through `scripts/sync-hook-utils.sh` with every carrying
   plugin's version bumped and CI's `hook-utils-sync` lane green.
8. **Exec form and `shell: "powershell"` only after measurement** on this host (open bugs #90495,
   #90077 contradict the docs).
9. **Tool-command guards on this host** block `cat >`, `printf >`, `echo >`, `python -c`, and any
   literal disk-hygiene engine filename inside a Bash command string. Workers write files with the
   Write tool. The hardcoded-path guard also blocks machine-specific paths in written files, so
   this PLAN uses `~/` and `<placeholder>` forms.
10. **Baselines before every change**, stored under `.work/hook-performance-levers/baselines/` (never
    committed); distilled values land in this PLAN.
11. **Changes land only** in `melodic-software/claude-code-plugins` and the dotfiles harness.
12. **PR bodies** follow `.claude/rules/pr-body-contract.md`: a closing-keyword line (or
    `No related issue: <reason>`), then non-empty `## Summary`, `## Fix`, `## Verification`,
    `## Related`.

### Context (verified this session)

- The harness the brief names at `D:/worktrees/dotfiles-perf-hooks` **does not exist**. The script
  lives in the chezmoi source checkout `~/.local/share/chezmoi/common/measure-claude-hook-fanout.sh`
  on dotfiles `main` at `5aceefb` (PR #614). The separate dotfiles clone under the repos root is one
  commit behind at `6058c72`. Phase 1 creates the worktree.
- Existing harness runs: `D:/worktrees/hook-fanout-baseline.tsv` (pre-dispatcher, 46 rows) and
  `hook-fanout-after.tsv` (post-dispatcher, 38 rows). Guardrails README accounting (0.31.0): eight
  per-Bash-call guard processes summing to about 2,450 ms became one process at about 1,220 ms
  inside `RUN_GUARDS_PROFILE=1`; the reference host spawn baseline is about 80 ms, the loaded host
  measured 4,498 ms, so every figure in this plan is reported as spawn-equivalents (hook wall divided
  by the same-trial `bash -c :` median).
- Fleet shape (INVENTORY.md): 20 `hooks.json` files, 16 distinct events, no `async` anywhere,
  every `hooks.json` row already carries an explicit `timeout`. Seventeen plugins carry
  `hooks/hook-utils.sh` (2,139 lines, byte-identical): actionlint, autonomy, bash-format,
  biome-format, claude-ops, context-guard, desktop-notification, eol-normalizer, go-format,
  guardrails, instruction-placement, markdown-format, powershell-format, rate-limit-guard,
  ruff-format, source-control, typos-format.
- Spawn reducers per the research ledger: only `matcher` and `if` stop a process; `if` is exact for
  file tools and best-effort for Bash (a pattern beyond a bare command name spawns anyway on `$()`,
  backticks or `$VAR`, H7); `async` moves cost off the critical path without reducing it (H10 to H14),
  its `systemMessage` is not shown to the operator (H12), and Windows drops some async firings in
  batches (#79230).
- SUITE-FAILURES.md: seven suites fail on this host on `main` and on the branch identically. Three
  are production defects (index-drift no-ops on `C:/` paths; docs-hygiene and claude-config
  `emit-findings.sh` decline every row on Windows path forms). Four are host-only test defects
  (NTFS filename rules, MSYS symlink emulation).
- `scripts/check-silent-skips.sh` scans `plugins/*/hooks/*.sh` and `scripts/*.test.sh` only. The
  plugin skill tests phase 5 annotates are outside its scan today.
- `~/.claude/statusline/entrypoint.sh` wires only the rate-limit-guard tee. The context-guard tee is
  not on this host's render path. `statusline-tee.sh` spawns no `date` or `mktemp`: the temp name
  is `$$.$RANDOM$RANDOM` and `captured_at` comes from jq's `todate` inside its single jq pass.
- `~/.claude/plugins/known_marketplaces.json` has `autoUpdate: true` for the melodic-software
  clone, so a session start may pull the clone mid-phase. `installed_plugins.json` records
  `version` and `gitCommitSha` per plugin (guardrails today: 0.31.0 at `a423e2c`).
- `~/.claude/statusline/entrypoint.sh` and the harness's `now_ms()` both spawn `date | cut` per
  sample today, which inflates S and hook time alike under load.
- 41 hook scripts outside `hook-utils.sh` call the telemetry helpers (`hook::emit_telemetry`,
  `hook::ctx_*`); the git-argv helpers are called only from guardrails guards.
- `scripts/lib/sync-cluster.sh` runs one cluster per `scripts/sync-*.sh`, each with its own CI job
  (`ci.yml` lines 512 to 670); `lib/resolve-convention-pattern.sh` is such a synced source with its
  own `--check-bump` gate.
- The inherited `D:/worktrees/hook-fanout-after.tsv` is mislabeled: it carries zero `run-guards`
  rows, and its delta from the baseline is eight security-guidance rows leaving. The v2 and v3 TSVs
  in the same directory are later runs of unknown provenance.

### Acceptance criteria

The goal's (A) through (E), the STATED CHECK, and every constraint above, each shown by a pasted
command output, not a sentence.

### Out of scope

- Exec form or `shell: "powershell"` adoption (constraint 8) beyond a measurement row.
- Moving any hook out of `hooks.json` into skill frontmatter, settings, or an HTTP hook.
- Relaxing the hook-budget convention (rule 2 of that doc).
- Consumer-side settings (`skillListingBudgetFraction`, `skillOverrides`, `refreshInterval`).
- Changing `enabledPlugins`.

### Deferred questions

Listed under Open questions; each names its arbiter.

## Plan

Scale: Large (cross-cutting, 20 `hooks.json`, 17 library carriers, two repositories). Standards
grounding: `docs/conventions/hook-budget/README.md` (ceiling and measurement method),
`docs/conventions/hook-precision/README.md` (repro-first stay-quiet cases), the
`hook-utils-sync` CI lane and `scripts/sync-hook-utils.sh --check-bump`,
`scripts/affected-tests.sh --run` for every change, `.claude/rules/pr-body-contract.md`,
`.claude/rules/hook-budget.md` (loads on `plugins/*/hooks/**`), and the
`.claude/rules/vendor-docs-are-not-style.md` house style for every README line written.
Provenance: team layer only.

### Phase 0: baseline capture (precondition for every phase) [DONE]

Runs once after phase 1 lands (the first code phase in the spine is 3) and again before each later
phase, always against the installed cache at `main`. Not a PR.

1. Copy the four inherited TSVs from `D:/worktrees/` to `baselines/inherited-*.tsv` with a
   `baselines/README.md` line each: `hook-fanout-baseline.tsv` (pre-dispatcher, 46 rows),
   `hook-fanout-after.tsv` (mislabeled: no `run-guards` rows, its delta is eight security-guidance
   rows leaving, not the dispatcher), `hook-fanout-v2.tsv` and `hook-fanout-v3.tsv` (provenance
   unknown). None is the program baseline; item 3 is.
2. Record `enabledPlugins` before: `jq -S .enabledPlugins ~/.claude/settings.json` saved to
   `baselines/enabled-plugins-before.json`.
3. Run the extended harness `--runs 3 --out baselines/phase1-harness-main.tsv` against the
   unchanged cache at `main` and paste the `=== per event` block into this file under "Baseline
   values". This is the only pre-change baseline the (B) comparison uses.
4. Cache delivery helper: the fetch, checkout, `claude plugin update`, run, return-to-main sequence
   is more than three commands and re-runs per phase, so it is a script, `[FALLBACK]` decision below
   on where it lives. Flow: `--dry-run` prints the plugin list and commands; `--branch <b>` runs
   `git fetch origin <b>` in the marketplace clone, checks it out at `origin/<b>`, updates each named
   plugin, asserts delivery (item 5), runs the harness with `--out`, then checks the clone back out at
   `main` in a trap so an aborted run never leaves it on the branch; rollback is that trap. The
   helper refuses to run while another `claude` process is live (`tasklist`/`pgrep` check) and
   refuses when the harness's S is above 160 ms, because ratio targets get easier under load.
5. Delivery assertion, per plugin: `installed_plugins.json` `.version` equals the branch's
   `plugin.json` version and `.gitCommitSha` equals the delivered branch HEAD. A re-delivery at an
   unchanged version is a no-op, so a phase that re-delivers re-bumps first.
6. Marketplace auto-update: `known_marketplaces.json` has `autoUpdate: true`, so a session start
   during a phase may pull the clone. The helper records `git -C <clone> rev-parse HEAD` before and
   after each run and the assertion in item 5 is what proves the measured cache is the branch, not
   the clone's checkout state.

**Sanity Check:**

- `ls .work/hook-performance-levers/baselines/ | grep -c 'inherited-.*\.tsv'` returns 4 and
  `test -f baselines/phase1-harness-main.tsv` exits 0.
- `git -C ~/.claude/plugins/marketplaces/melodic-software branch --show-current` prints `main` after
  every helper run.
- For each delivered plugin: `jq -r --arg p "<name>@melodic-software" '.plugins[$p] | if type=="array" then .[0] else . end | "\(.version) \(.gitCommitSha)"' ~/.claude/plugins/installed_plugins.json` equals `"$(jq -r .version plugins/<name>/.claude-plugin/plugin.json) $(git rev-parse HEAD)"` on the delivered branch.
- `git check-ignore -q .work` exits 0 (baselines never tracked).

### Phase 1: dotfiles harness extension [DONE]

Repo: `melodic-software/dotfiles`. Worktree `D:/worktrees/dotfiles-perf-hooks` created from
`origin/main` (step 0, run from the dotfiles clone: `git fetch origin && git worktree add <worktrees-root>/dotfiles-perf-hooks -b perf/hook-fanout-samples origin/main`).
One PR.

1. **TSV consumers first.** Before changing the output shape, list every reader of the TSV and the
   summary block: `docs/claude-hook-fanout.md` (documents the columns and pastes a run), the
   `D:/worktrees/hook-fanout-*.tsv` comparisons this plan inherits, `docs/maintenance.md`, and the
   two awk summaries inside the script. Each is updated or shown compatible in the PR.
2. **Samples.** Add to `events()` after the seven existing lines, in this order, each a documented
   payload shape: PreToolUse:Bash with `echo $(git rev-parse HEAD)` (the `$()` sample);
   PreToolUse:Edit and PostToolUse:Edit on the same scratch `.md` (`old_string`/`new_string`);
   SessionStart `source=startup` and SessionStart `source=compact` (session-flow's `observer-arm.sh`
   fires on compact, resume and clear too); PostCompact; PreCompact `trigger=auto`; Notification
   `notification_type=permission_prompt`; PostToolUseFailure tool Bash; StopFailure
   `error_type=rate_limit`; InstructionsLoaded `load_reason=session_start`; ConfigChange
   `source=user_settings`; UserPromptExpansion; WorktreeCreate; and the statusline command read
   from `~/.claude/settings.json` `.statusLine.command` fed a representative statusline payload
   (session_id, model, context_window, rate_limits).
   **Sample identity.** The per-event summary keys on `event:tool`, so the `$()` sample would
   merge into the plain `PreToolUse:Bash` line and the goal's plain-sample cap could not be read.
   Add a ninth TSV column `sample`, empty for the seven legacy rows and `subst` for the `$()`
   sample, and include it in the awk key only when non-empty (`PreToolUse:Bash:subst`). Columns 1
   to 8 and the legacy keys stay byte-identical; the header gains the ninth column name. For
   non-tool events, write the payload's matcher subject into the harness's `tool` field
   (`permission_prompt`, `rate_limit`, `startup`, `compact`, `auto`, `user_settings`,
   `session_start`) so `matcher_hits` evaluates those hooks' matchers instead of skipping every one
   of them on an empty tool; the statusline sample uses `statusline:-`. Every sampled event key is
   emitted in the summary even when no enabled hook matches it: the script writes a placeholder
   `NONE` row per sample so the awk keys cover hookless events with `fires= 0`.
3. **Timing and baseline S.** Replace `now_ms()` (`date | cut`, two spawns per sample) with
   `$EPOCHREALTIME` arithmetic, so a sample costs no spawn of its own. Before each event's hook
   loop, run `bash -c :` `RUNS` times and take the median; print `baseline S=<median> ms` per event
   and one overall median at the top of the summary. A run is valid only when the overall S is at
   most 160 ms (twice the 80 ms reference); otherwise the summary is headed
   `INVALID RUN (S=<n> ms > 160)` and the script exits 3. The per-event line keeps `fires=`,
   `cpu_sum_ms=`, `max_ms=`, and appends `async=<n>`, `cpu_x_s=<n>` and `max_x_s=<n>` (the sum
   and the max divided by the run's overall S, one decimal, so the (B) ratios read directly) while
   `max_ms` stays absolute, so the hook-budget ceilings (1 s typical, 2 s worst per tool call,
   500 ms per turn) can be read beside the ratio.
4. **`if` semantics.** Non-tool events: a hook with `if` set gets status `NEVER_RUNS(if-on-non-tool-event)`
   (distinct from `SKIPPED`). Bash `if`: a pattern that is more than a bare command name
   (anything after the name) spawns when the command contains `$(`, a backtick, or `$` followed by
   an identifier character, status `RAN(best-effort)`; a bare command name pattern still skips.
   Edit rules cover Write, Edit, MultiEdit, NotebookEdit (ledger H9). Path rules follow the
   permissions doc anchors: a bare `**/x` or `dir/**` pattern is cwd-anchored, `~/` anchors to the
   home directory, `//` anchors to the filesystem root; `if_hits` normalizes the payload path and
   the pattern to one form (`/c/...` MSYS form and `C:/...` both map to the same comparison string)
   before globbing, else phase 3's fires count on `~/.claude/settings.json` is misread.
5. **`async` semantics.** An `async: true` hook is run and timed like any other, counted in `fires=`
   and `cpu_sum_ms=`, excluded from `max_ms=` (off the critical path), and its TSV status is
   `RAN(async)`. The status column carries the marker; its own median is still printed on the
   per-hook line so phase 2 can report async rows' cost.
6. **Byte compatibility.** The seven existing `printf` lines in `events()` are not edited; the
   first eight header fields are unchanged.
7. Update the header comment, `README.md` (the line naming the harness), `docs/claude-hook-fanout.md`
   (usage, the column list, the sample list) and the `docs/maintenance.md` row describing what the
   harness runs.

**Sanity Check:**

- `diff <(git show origin/main:common/measure-claude-hook-fanout.sh | grep -n "printf 'PreToolUse%sBash\|printf 'PostToolUse%sBash\|printf 'PreToolUse%sWrite\|printf 'PostToolUse%sWrite\|printf 'PostToolBatch\|printf 'UserPromptSubmit\|printf 'Stop%s" | cut -d: -f2-) <(grep "printf 'PreToolUse%sBash\|printf 'PostToolUse%sBash\|printf 'PreToolUse%sWrite\|printf 'PostToolUse%sWrite\|printf 'PostToolBatch\|printf 'UserPromptSubmit\|printf 'Stop%s" common/measure-claude-hook-fanout.sh | head -7)` prints nothing.
- `bash common/measure-claude-hook-fanout.sh --runs 1 | grep -c '^baseline S='` returns 1;
  `grep -c 'date +%s%N' common/measure-claude-hook-fanout.sh` returns 0 and
  `grep -c 'EPOCHREALTIME' common/measure-claude-hook-fanout.sh` is at least 1.
- With `HOOK_FANOUT_FAKE_S=500` (a test seam that overrides the measured S) the script prints
  `INVALID RUN` and exits 3.
- `if_hits 'Edit(~/.claude/settings.json)' Write "$HOME/.claude/settings.json"` returns 0 and
  `if_hits 'Edit(**/.claude/settings.json)' Write "$HOME/.claude/settings.json"` returns 1 when
  cwd is not `$HOME` (sourced function test in the dotfiles test suite).
- `bash common/measure-claude-hook-fanout.sh --runs 1 | sed -n '/=== per event/,/^$/p' | awk '{print $1}' | sort` prints exactly this key list: `ConfigChange:user_settings`, `InstructionsLoaded:session_start`, `Notification:permission_prompt`, `PostCompact:-`, `PostToolBatch:Read`, `PostToolUse:Bash`, `PostToolUse:Edit`, `PostToolUse:Write`, `PostToolUseFailure:Bash`, `PreCompact:auto`, `PreToolUse:Bash`, `PreToolUse:Bash:subst`, `PreToolUse:Edit`, `PreToolUse:Write`, `SessionStart:compact`, `SessionStart:startup`, `Stop:-`, `StopFailure:rate_limit`, `UserPromptExpansion:-`, `UserPromptSubmit:-`, `WorktreeCreate:-`, `statusline:-` (a key whose event has no enabled hook still prints with `fires= 0`).
- `head -1 "$OUT" | cut -f1-8` equals the legacy header; `cut -f9 "$OUT" | sed -n '2,8p'` (the first seven data rows are legacy samples) prints seven empty lines.
- `grep -c 'NEVER_RUNS(if-on-non-tool-event)\|RAN(best-effort)\|RAN(async)' common/measure-claude-hook-fanout.sh` is at least 3.
- dotfiles `lefthook`/CI shell lint passes; `gh pr checks` shows 0 failing.
- `sha256sum common/measure-claude-hook-fanout.sh` recorded in this PLAN under "Baseline values".

### Phase 2: `async: true` on non-deciding, non-rewriting hooks [DONE: measured, not applied]

Repo: claude-code-plugins. One PR. Runs after phase 3 merges (both edit `claude-ops/hooks/hooks.json`
and `disk-hygiene/hooks/hooks.json`).

Candidates and the evidence each needs before the flag is set:

| Hook | Event | Emits a decision? | Rewrites a user file? | Verdict | Evidence run |
|---|---|---|---|---|---|
| typos-format `typos-format.sh` | PostToolUse Write/Edit/NotebookEdit | No | Only when userConfig `typos_format_write_changes` is true | `async` only if write mode is dropped or split; Open question 3 | benign `.md` payload and a payload with a typo: same output text, same exit code, before and after |
| claude-ops `hook-failure-audit.sh` | Stop | No | No (plugin data only) | `async` changes who sees `systemMessage` (H12); Open question 4 | Stop payload with a seeded failure record: same JSONL row appended |
| disk-hygiene `guard_launch_monitor.py` | Stop | No | No (marker under plugin data) | same visibility question as above | Stop payload with a seeded silent-failure marker: same message text |
| context-guard `zone-crossing-inject.sh` | PostToolBatch only | No (advisory `additionalContext`) | No (hysteresis state under plugin data) | `async` candidate; the live probe must show when the output lands (within the turn of the crossing, or only after the next prompt, where the synchronous UserPromptSubmit row fires anyway and the async row buys nothing); Open question 8 | PostToolBatch payload crossing a zone boundary: same `additionalContext`; live probe records the turn the context arrived in |
| context-guard `zone-crossing-inject.sh` | UserPromptSubmit | No | No | stays synchronous (output must land before the prompt) | none |

Work items:

1. Add `"async": true` to the rows the verdict column and the resolved open questions allow.
2. Bump each touched plugin's version and CHANGELOG (constraint 6).
3. Baseline-equivalence runs: for every hook flagged, one direct run before and after with the
   payload in the table, outputs diffed; and one live `claude --debug-file` session, started fresh
   after delivery, on the installed cache showing the async hook fired on a Write batch of three
   files (#79230 lossiness check: count the firings) while a process-table sample
   (`tasklist` or `ps` every 200 ms during the burst) records the peak concurrent hook process
   count before and after. The same session records the turn in which the PostToolBatch
   `additionalContext` arrived (open question 8).
4. READMEs: one line per flagged hook stating the delivery change (output reaches Claude next turn,
   not the operator) and the Windows storm caveat: async has no dedup, its timeout is unenforced
   once running, and batches may drop firings (#79230), so an async row can worsen a spawn storm
   even as it leaves the critical path.

**Sanity Check:**

- `jq -r '.hooks | to_entries[] | .key as $e | .value[] | .hooks[] | select(.async == true) | "\($e) \(.command)"' plugins/*/hooks/hooks.json` lists exactly the approved rows and no row on UserPromptSubmit or any PreToolUse event.
- `for f in plugins/*/hooks/hooks.json; do jq -e '[.hooks[][] .hooks[] | select(.async == true) | .type] | all(. == "command")' "$f" >/dev/null || { echo "FAIL $f"; exit 1; }; done` exits 0 (per file: a multi-file `jq -e` reports only the last file).
- `diff baselines/phase2-<hook>-before.out baselines/phase2-<hook>-after.out` prints nothing for each flagged hook.
- Harness after: `fires=` and `cpu_sum_ms` on PostToolUse:Write and PostToolBatch lines are within 10 percent of `baselines/phase1-harness-main.tsv` (async reduces neither), `async=` equals the number of flagged rows on each line, and each flagged row's own median on the per-hook list is pasted beside its pre-change median. (`max_ms` dropping is not evidence: async rows are excluded from it by construction.)
- Process-table peak during the three-file Write burst, before and after, pasted; the after value is not higher.
- `scripts/affected-tests.sh --run` exits 0; `gh pr checks` 0 failing.

### Phase 3: `if` gates, matcher scoping, explicit timeouts [DONE]

Repo: claude-code-plugins. One PR.

1. **context-budget `settings-write-ask.mjs`**: replace the single unconditioned row with `if`-gated
   rows under the same matcher, each `type: command`, `command: node`, the same `args`. Path rules
   are cwd-anchored unless they carry an anchor (permissions doc), so `**/.claude/settings.json`
   matches only under the project and never the user-global or managed files. Rows:
   `Edit(**/.claude/settings.json)`, `Edit(**/.claude/settings.local.json)` (project scope),
   `Edit(~/.claude/settings.json)`, `Edit(~/.claude/settings.local.json)` (user scope), and one
   `//`-anchored row per managed-settings location the script checks
   (`Edit(//c/ProgramData/ClaudeCode/managed-settings.json)` and its equivalents for each drive the
   host has, plus the macOS and Linux paths for portability). The script's own scope check stays
   (defence in depth). Live probe required, in a fresh session after delivery: this is the fleet's
   only exec-form hook, and #90495 reports `args` dropped on Windows. The `claude --debug-file`
   session must perform a Write (not only an Edit) to `~/.claude/settings.json` and to a
   managed-settings path, and an Edit to a project `.claude/settings.local.json`, and the log must
   show the hook matched and returned `ask` for each; on any miss that row stays ungated and the
   miss is recorded as the residual. The harness feeds payloads directly and never exercises Claude
   Code's own `if` evaluation, so this probe is the test boundary for the gate, not the harness.
2. **claude-ops InstructionsLoaded**: the event ignores the hook's exit code (hooks doc), so it is spawn
   count only, never critical path. Its JSONL row is documented under
   `docs/conventions/hook-telemetry`. Scope its matcher to the `load_reason` values
   `instructions-loaded-audit.sh` actually distinguishes in its JSONL row. Removing the row is not
   a decision this phase makes: "moved to nothing" is outside the goal's closed destination list
   (dispatcher branch, `if`-gated entry, async entry, moved event), so the row stays unless the
   operator signs off (open question 9), and a sign-off also updates the hook-telemetry convention.
   Same review for PermissionDenied, PreCompact, UserPromptExpansion, PostToolUseFailure: keep,
   with the reason each earns its spawn written into the README.
3. **Explicit timeouts**: assert every always-on row has one (today true), and right-size the two
   60-second rows on context-guard UserPromptSubmit and PostToolBatch, where a stalled hook blocks
   the prompt (H31): `[FALLBACK]` proposes 15 seconds. A shorter timeout buys nothing against a
   stdin-blocked hook (#87289); the real protection is `hook::buffer_stdin` reading to EOF with its
   bounded stall path, which every hook here already uses, plus the explicit timeout as the cap
   for a hook that is running. Gating rows keep their current values; a shorter timeout on a gate
   is fail-open (H20).
4. **Residual note**: `source-control` README lines describing `Bash(gh *)` and `Bash(*worktree*)`
   as "spawned only for" and the `disk-hygiene` README engine-gate description each gain the H7
   caveat: the process still spawns on any command containing `$()`, backticks or `$VAR`; the
   harness's `$()` sample shows it as `RAN(best-effort)`. The goal's count cap applies to the plain
   sample; the `$()` sample's count is recorded as the residual.
5. Bump only the plugins whose `hooks.json` changed (context-budget, claude-ops, context-guard);
   README-only changes in source-control and disk-hygiene need no cache delivery and no bump
   (verified: `.github/workflows/ci.yml` carries `--check-bump` gates only for the lib sync
   clusters and vendored versions, none on `plugins/<name>/**` generally).

**Sanity Check:**

- `jq -e '[.hooks.PreToolUse[] | .hooks[] | select(.if == null)] | length == 0' plugins/context-budget/hooks/hooks.json` exits 0 (no ungated row remains, unless the probe recorded a miss, in which case exactly the missed row is ungated and named in the README), and `jq -r '.hooks.PreToolUse[].hooks[].if' plugins/context-budget/hooks/hooks.json | sort` prints the three `//**/`-anchored rules (`.claude/settings.json`, `.claude/settings.local.json`, `managed-settings.json`), mirroring the script's two path regexes; see DEVIATIONS.md for why the cwd and `~/` scheme was dropped.
- The `--debug-file` log lines for the three probe writes (user-scope Write, managed-settings Write, project-scope Edit), each naming the hook and `ask`, are pasted; the session was started after delivery and its `installed_plugins.json` `gitCommitSha` matches the delivered HEAD.
- `for f in plugins/*/hooks/hooks.json; do jq -e '[.hooks[][] .hooks[] | select(.timeout == null)] | length == 0' "$f" >/dev/null || { echo "FAIL $f"; exit 1; }; done` exits 0.
- `grep -c 'best-effort\|\$()' plugins/source-control/README.md plugins/disk-hygiene/README.md` is at least 1 per file.
- Harness: PreToolUse:Write `fires=` on the `.md` sample is unchanged versus the phase 1 baseline (the context-budget gate was rejected by the live probe; see DEVIATIONS.md), and the context-guard timeout rows show 15.
- `scripts/affected-tests.sh --run` exits 0; `gh pr checks` 0 failing.

### Phase 4a: guard hot path inside the dispatcher [TODO]

Repo: claude-code-plugins. One PR. Sub-topic promotion: **recommended for 4b, not 4a** (see Phase 4b).

1. **Profile.** `RUN_GUARDS_PROFILE=1` per guard, 12 interleaved trials with `bash -c :` between
   each, benign `git status --short` payload and the `$()` payload, on the installed cache. Save
   to `baselines/phase4a-profile-before.tsv`. Also measure the library parse alone:
   `bash -c 'source plugins/guardrails/hooks/hook-utils.sh'` versus `bash -c :`, 12 trials. This
   number is the switch condition for 4b.
2. **block-convention-violation**: it forks `bash "$RESOLVER"` twice (lines 99 and 100) on every
   Bash call. `resolve-convention-pattern.sh` is a synced library (`lib/` source, its own
   `sync-*.sh` and `--check-bump` CI gate), so editing it is outside this phase's fence. Preferred:
   cache the two resolved patterns per repo root in a plugin-data file keyed on the convention
   file's path and mtime, so the fork runs once per convention change instead of once per Bash
   call. Contract test gains a case proving the cached pattern equals the forked form and a case
   proving an mtime change invalidates the cache. If the cache proves insufficient, the fallback
   is a separate PR that adds `lib/resolve-convention-pattern.sh` plus its sync script to the fence.
3. **Benign-path spawns** across the eight Bash guards and three Write guards: replace
   `$(dirname ...)`, `$(basename ...)`, `git rev-parse` re-runs (the dispatcher already primed
   `.cwd`), and per-guard `jq` calls that the primed field cache already answers. Each replacement
   is behind the guard's existing `*.test.sh`; a guard's MUST-fire and MUST-stay-quiet cases stay
   green (hook-precision discipline).
4. **Profile after** and write the per-guard slice table into the guardrails README accounting
   section.
5. Bump guardrails.

**Sanity Check:**

- `grep -c 'bash "\$RESOLVER"' plugins/guardrails/hooks/block-convention-violation.sh` returns at most 1 and that call sits on the cache-miss path only; `git diff --stat main -- lib/resolve-convention-pattern.sh plugins/*/hooks/resolve-convention-pattern.sh` prints nothing.
- `for t in plugins/guardrails/hooks/*.test.sh; do bash "$t" || exit 1; done` exits 0.
- `bash plugins/guardrails/hooks/run-guards.test.sh` exits 0.
- Profile after: the `RUN_GUARDS_PROFILE=1` sum in spawn-equivalents is below the before sum, both
  pasted; the benign `git status --short` PreToolUse:Bash `max_ms` is at or below `8*S`.
- `scripts/affected-tests.sh --run` exits 0; `gh pr checks` 0 failing.

### Phase 4b: hook-utils.sh telemetry hot path (re-scoped; the core-plus-modules split is not needed, parse measured at 4 ms) [TODO]

Re-scope (2026-09-02, see DEVIATIONS.md): the parse measured at about 4 ms, so the lazy-module split is
closed as not needed. What remains in the library is `hook::emit_telemetry`, which on a host with
`HOOK_TELEMETRY_SINK` set spends 2 `jq` + `mktemp` + `rm` per guard, about 1.2 s of the 2.5 s Bash
dispatcher wall. This phase makes that path builtin-only (JSON assembled with `printf` and bash
escaping, an append with `>>` under the existing lock discipline, no temp file), byte-identical JSONL
rows proven by a diff of the sink output before and after on the same payloads, through
`scripts/sync-hook-utils.sh` with every carrying plugin bumped and the `hook-utils-sync` CI lane green.
It also makes `hook::read_file_path` (about 7 execs and 10 forks per hook, identical in every Write
hook, per the phase 4c profile) builtin-only where the payload is small and well-formed, with the jq
path kept as the fallback. It still runs last among the code phases (17-carrier bump). The original sketch below is kept for
reference and is not executed.

Repo: claude-code-plugins. Runs only if 4a's parse measurement clears a threshold the operator
sets; the `[FALLBACK]` default below is one spawn-equivalent (about 80 ms on the reference host)
per hook process, and at that bar this phase most likely closes as "not needed, measured" with the
number pasted. A lower bar (for example a quarter spawn-equivalent, since the parse is paid on
every hook process the fleet spawns) is the operator's call.

Promotion: this phase has more than five work items, a delta above 300 lines, its own sub-phases
(split, sync cluster, tests, fleet bump), and an independent commit boundary. It qualifies on four
of five triggers. Recommend `docs/topics/hook-utils-split/PLAN.md` inheriting this Brief and the
type sketch in `design/design-resolution.md`.

1. **Identify consumers (first).** `grep -l 'hook::emit_telemetry\|hook::ctx_' plugins/*/hooks/*.sh`
   and the same for each git-argv function. Today 41 hook scripts call the telemetry helpers, so
   a telemetry module loads on nearly every fire unless telemetry is disabled; git-argv is called
   only from guardrails guards. Size the saving from this inventory: the parse saved per hook
   process is the module's share of the file only for hooks that never call into it. If the
   telemetry module cannot be kept off the common path (a core stub that returns without loading
   when `hook::telemetry_enabled` is false), the telemetry split is dropped and only git-argv moves.
2. Split `lib/hook-utils.sh` into core plus `lib/hook-utils.d/git-argv.sh` and, if item 1
   allows, `lib/hook-utils.d/telemetry.sh` per the sketch (lazy stubs, `hook::_load`, modules
   resolve relative to core via `${BASH_SOURCE[0]%/*}`, never `$(dirname)` or `$(cd && pwd)`).
   After `hook::_load` the stub checks the module's guard variable and, if the module file was
   absent or failed to define it, emits a skip notice and returns 2 instead of recursing (bash has
   no default `FUNCNEST`, so an unguarded stub loops until the hook timeout and a gate fails open).
3. **Dispatcher eager load.** Inside `run-guards.sh` each guard runs in a `$(source ...)` subshell,
   so a lazy load inside one guard is lost before the next; git-argv would parse up to five times
   per Bash call. The dispatcher loads the shared modules once before fan-out (a `--module` flag
   beside `--lib`), and `run-guards.test.sh` gains a case counting module loads across a run
   (exactly one).
4. **Seed the copies.** `sync-cluster.sh` copies only onto existing files and exits 2 on an empty
   glob, so the 17 by N module files are seeded (committed empty-shell copies) before the sync
   scripts run.
5. Sync scripts: one `scripts/sync-hook-utils-<module>.sh` per module (the shape
   `scripts/lib/sync-cluster.sh` supports is one cluster per script) plus one CI job each in
   `.github/workflows/ci.yml` next to `hook-utils-sync` (lines 512 to 530), each with `--check`
   and `--check-bump`. `scripts/affected-tests.sh` rule R5 discovers a new `scripts/sync-*.sh` from
   its `--print-manifest`, so no change there; each new sync script gets its co-located test.
6. `lib/hook-utils.test.sh`: lazy-load case, no-module-load case, double-load guard case, absent
   module returns 2 with a notice.
7. `plugins/guardrails/hooks/run-guards.test.sh`: `hook::jq_fields` override survives a module
   load; module load count is one per run.
8. Sync to the 17 carriers; bump all 17 versions and CHANGELOGs.
9. Deliver to the cache, run the harness in a fresh session, paste before and after.

**Sanity Check:**

- `for s in scripts/sync-hook-utils*.sh; do "$s" --check && "$s" --check-bump origin/main || exit 1; done` exits 0.
- `ls plugins/*/hooks/hook-utils.d/git-argv.sh | wc -l` returns 17; `grep -c 'sync-hook-utils-' .github/workflows/ci.yml` equals the number of modules.
- `bash -c 'source lib/hook-utils.sh; HOOK_UTILS_DIR=/nonexistent hook::git_resolve_subcommand x; echo rc=$?'` prints `rc=2` within one second (no recursion).
- `grep -c '\$(dirname\|\$(cd ' lib/hook-utils.d/*.sh lib/hook-utils.sh` returns 0 for the module-resolution lines (module dir computed with `${BASH_SOURCE[0]%/*}`).
- `bash lib/hook-utils.test.sh` exits 0.
- `wc -l < lib/hook-utils.sh` is below 1,400.
- `bash -c 'source lib/hook-utils.sh; declare -F hook::git_resolve_subcommand'` prints the name (stub present) and `bash -c 'source lib/hook-utils.sh; [[ -z ${HOOK_UTILS_GIT_ARGV_LOADED:-} ]]'` exits 0 (module not loaded by sourcing core).
- `scripts/affected-tests.sh --run` exits 0; `gh pr checks` shows `hook-utils-sync` passed and 0 failing.

### Phase 4c: per-Write hook hot path [DONE]

Repo: claude-code-plugins. One PR. Owns the (B) `cpu_sum_ms` residual on the `.md` sample that no
other phase touches: typos-format plus eol-normalizer plus markdown-format plus the guardrails
PostToolUse verifier dispatcher measured about 13.7 spawn-equivalents against the 12 times S cap,
and async (phase 2) reduces none of it.

1. Profile each per-Write hook on the `.md` sample with the phase 1 harness per-hook list, 12
   interleaved trials, and list every external spawn on its benign path (a file with nothing to
   fix): `jq` calls the primed payload could answer, `typos` and `markdownlint` invocations that
   run even when the file class is excluded, `git` lookups repeated across hooks, `mktemp`.
2. Cut in place, behind each hook's existing `*.test.sh`: skip the formatter binary when the
   extension is outside the hook's own allowlist before any spawn; read the payload once with one
   `jq`; reuse `hook::repo_root` results instead of re-running `git`; no behaviour change to what
   gets reported or rewritten.
3. If the residual survives the cuts, record it explicitly in this PLAN's Baseline values as the
   (B) `cpu_sum_ms` residual with the per-hook breakdown, and in the hook-budget README.
4. Bump typos-format, eol-normalizer, markdown-format (and guardrails if the verifier dispatcher
   changed).

**Sanity Check:**

- `for t in plugins/{typos-format,eol-normalizer,markdown-format}/hooks/*.test.sh; do bash "$t" || exit 1; done` exits 0.
- Harness PostToolUse:Write on the `.md` sample: `cpu_sum_ms` after is below before, both pasted in spawn-equivalents; or the residual line in Baseline values names each hook's share and the sum.
- Byte-identical output on a benign `.md` payload for each hook: `diff before.out after.out` prints nothing.
- `scripts/affected-tests.sh --run` exits 0; `gh pr checks` 0 failing.

### Phase 4d: context-guard hook hot path [DONE]

Repo: claude-code-plugins. One PR, branch `perf/context-guard-hot-path` stacked on the phase 3 branch. Added
when phase 2 closed without an async row (DEVIATIONS.md): the PostToolBatch nudge stays on the
critical path at 1,254 ms (38 spawn-equivalents at S=33 ms) against a 3 S target, so its cost comes
down by removing exec'd processes, the same discipline as 4a and 4c. Scope: `zone-crossing-inject.sh`
(PostToolBatch and UserPromptSubmit, non-crossing path first), `zone-gate.sh`, `post-compact-mark.sh`;
profile before and after (12 interleaved trials, exec count under `bash -x`); behaviour byte-identical
on crossing and non-crossing payloads; an xtrace test pins the non-crossing spawn set; bump context-guard.

**Sanity Check:** every `plugins/context-guard/hooks/*.test.sh` exits 0; before and after tables pasted;
`diff` of outputs and state files empty per payload; PostToolBatch `max_ms` after is below before, both in
spawn-equivalents; `gh pr checks` 0 failing.

### Phase 5: Windows path-form correctness [DONE]

Repo: claude-code-plugins. One PR. File-disjoint from phases 2 to 4.

Production fixes (repro-first: each new test case fails on the unmodified script on this host):

1. `plugins/instruction-placement/scripts/render-index.sh`: line 295 (`"$TARGET" != /*`) is where
   a `C:/...` target gets cwd-prefixed; accept `[A-Za-z]:/` as absolute there. That alone is not
   enough: lines 303 and 384 strip `"$PWD"/` from `TARGET` after `cd "$ROOT"`, and under Git Bash
   `$PWD` becomes `/c/...` while `TARGET` stays `C:/...`, so the relative-target computation still
   fails. Normalize `ROOT` and `TARGET` to one form (the `$PWD` form after the `cd`, via
   `cd "$dir" && pwd` on the target's directory, or `cygpath -u` behind a `command -v cygpath` check
   with a visible skip notice) before both strips. The repro-first case exercises the full `C:/`
   round trip through both `check` and `write`, not only `check`. `hooks/index-drift.sh` stays
   unchanged unless the renderer fix is insufficient.
2. `plugins/docs-hygiene/skills/audit-noise/scripts/emit-findings.sh`: add the `REPO_ROOT_ALT` and
   `REPO_ROOT_PWD` fallback provenance carries (its lines 167 to 180), pass both to awk.
3. `plugins/claude-config/skills/audit-instructions/scripts/emit-findings.sh`: normalize the Python
   scanner's output (backslash separators, 8.3 short names such as `<drive>:\Users\<SHORT~1>\...`)
   to the git toplevel form (forward slashes, long name via `cygpath -l -m` or the Python side's
   `os.path.realpath`) before the in-repo comparison.

Host-only test defects, documented skip, never a silent PASS:

1. `plugins/ai-slop/skills/audit/scripts/detect.test.sh` (2 cases: MSYS `ln -s` copies),
   `plugins/code-tidying/skills/audit-comment-residue/scripts/detect.test.sh` (4 cases: NTFS-illegal
   filenames), `plugins/instruction-placement/scripts/lib/discover.test.sh` (1 case: symlink),
   `plugins/provenance/skills/audit/scripts/emit-findings.test.sh` (2 cases: mktemp alias form).
   Each case gets a host probe (`ln -s` round-trip readlink check, or an NTFS filename create
   attempt) and on a negative probe prints a visible `SKIP (host: <reason>)` line, counted
   separately from `ok`, with the `# silent-skip-ok: <reason>` annotation on the guard line in the
   format `scripts/check-silent-skips.sh` defines. Open question 5 covers whether that gate's scan is
   widened to these files in this PR.
2. Bump instruction-placement, docs-hygiene, claude-config, ai-slop, code-tidying, provenance.

**Sanity Check:**

- `bash plugins/instruction-placement/hooks/index-drift.test.sh` exits 0 on this host; the run's
  stale notice on a `C:/...` path is pasted (goal C).
- `bash plugins/instruction-placement/scripts/render-index.test.sh` exits 0 on this host and
  contains a case whose `--root` and `--file` are `C:/...` paths driven through `check` then
  `write`, with the written index diffed against the Linux-form run.
- `bash plugins/docs-hygiene/skills/audit-noise/scripts/emit-findings.test.sh` and
  `bash plugins/claude-config/skills/audit-instructions/scripts/emit-findings.test.sh` exit 0 on this
  host.
- For each of the four skip-annotated suites: exit 0 on this host, output contains at least one
  `SKIP (host:` line, and `grep -c 'ok "skip\|ok .skip' <suite>` returns 0.
- `bash scripts/check-silent-skips.sh` exits 0.
- The seven suites still exit 0 on Linux CI (`gh pr checks` 0 failing).

### Phase 6: skill listing budget [TODO]

Repo: claude-code-plugins. One PR, human-gated list.

1. Run `bash plugins/skill-quality/scripts/check-listing-budget.sh plugins` and paste the output;
   record the aggregate against the 8,000-character documented fallback and the top contributors.
2. **Citation sweep before any proposal.** 79 `SKILL.md` files route to other skills with "invoke
   `/<plugin>:<skill>` via the Skill tool", and callers' presence gates read a
   `disable-model-invocation` target as absent. Grep every `/<plugin>:<skill>` citation across
   `plugins/*/skills/*/SKILL.md` and `plugins/*/agents/*.md`, build the cited-target set, and
   exclude every cited target from the candidate list.
3. Propose `disable-model-invocation: true` for the remaining side-effect skills the model should
   never self-invoke (anything whose verb is destructive, publishing, mutating settings, or
   launching background sessions). Present as a table (skill, current description length, side
   effect, cited-by count, proposed flag) for the operator to approve row by row.
4. Apply approved rows; run `plugins/skill-quality/scripts/check-skill.sh` on each; bump each
   touched plugin.

**Sanity Check:**

- `bash plugins/skill-quality/scripts/check-listing-budget.sh plugins` output pasted; the aggregate
  line is at or below the budget line it prints (the script always exits 0, so the exit code is not
  the signal; the parsed aggregate is).
- `grep -l 'disable-model-invocation: true' plugins/*/skills/*/SKILL.md | wc -l` equals 66 plus the
  approved count (66 re-measured with this exact command on 2026-09-02).
- For every newly flagged skill `<p>:<s>`: `grep -rl "/<p>:<s>" plugins/*/skills/*/SKILL.md plugins/*/agents/*.md` prints nothing.
- The listing output's aggregate line is under the budget line it prints and its over-cap entry
  count is 0 (goal D).
- `scripts/affected-tests.sh --run` exits 0; `gh pr checks` 0 failing.

### Phase 7: statusline cost [DONE]

Repo: claude-code-plugins (rate-limit-guard, and context-guard only if wired). One PR.

1. Verify wiring: `~/.claude/statusline/entrypoint.sh` execs the highest-version
   `rate-limit-guard/*/scripts/statusline-tee.sh`; context-guard's tee is absent from that path on
   this host. Measure what is wired; record context-guard's tee as "not on the render path here,
   measured standalone" if at all.
2. Measure per render with the phase 1 statusline sample: tee plus render versus render alone,
   12 interleaved trials, spawn-equivalents.
3. Cut only what item 2's profile names. The script spawns no `date` or `mktemp` today (the temp
   name is `$$.$RANDOM$RANDOM`, `captured_at` is jq's `todate` inside the single jq pass), so the
   candidates are the jq pass itself, the `command -v jq` probes, and the settings-file reads.
   Whatever is cut, the atomic write (temp file plus rename with the EACCES retry) and the lock
   discipline survive unchanged. Add a no-change skip: hash the extracted fields (excluding
   `captured_at`) with a builtin-only digest or a cached copy of the last extracted string in the
   same directory, and skip the write when equal, so an unchanged payload costs no rename.
4. `statusline-tee.test.sh` gains a no-change case (second render writes nothing) and keeps the
   byte-for-byte passthrough case.
5. Bump rate-limit-guard (and context-guard if touched).

**Sanity Check:**

- `bash plugins/rate-limit-guard/scripts/statusline-tee.test.sh` exits 0.
- Harness statusline line: `max_ms` after is below before, both pasted, and the tee's own
  spawn-equivalent is at or below 2.
- `bash -c 'printf "%s" "$PAYLOAD" | bash plugins/rate-limit-guard/scripts/statusline-tee.sh cat' | cmp - <(printf '%s' "$PAYLOAD")` exits 0 (passthrough byte-identical).
- `bash plugins/rate-limit-guard/scripts/statusline-tee.test.sh` keeps its atomic-rename and concurrent-writer cases green (grep the test for `tmp\.` and `EACCES` cases: at least 1 each).
- Snapshot equality after any cut: the same payload fed to the pre-change
  and post-change tee writes `~/.claude/rate-limit-guard/rate-limits.json` files that are identical
  under `diff <(jq -S 'del(.captured_at)' before.json) <(jq -S 'del(.captured_at)' after.json)`, and
  both `captured_at` values match `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`.
- `gh pr checks` 0 failing.

### Phase 8: accounting, docs, final proof [TODO]

Repo: claude-code-plugins. One PR (docs only) plus the final transcript proof.

1. `docs/conventions/hook-budget/README.md`: replace the 2026-07-31 reference figures with the
   post-program per-event table in spawn-equivalents and the reference-host conversion, dated, with
   the harness sha256.
2. Per touched plugin README: accounting row (event, fires, spawn-equivalents, what changed).
   CHANGELOGs already carry each phase's entry; this phase adds none.
3. Final proof in the transcript, from a fresh session started after the last delivery:
   `enabledPlugins` after (diff against `baselines/enabled-plugins-before.json` empty); the STATED
   CHECK table read from the cache with `jq` over every measured `hooks.json` plus, per measured
   plugin, `installed_plugins.json` `version` and `gitCommitSha` equal to the delivered HEAD; the
   harness sha256; the final valid `--runs 3` run (S at most 160 ms); the constraint 1 mapping table
   with each moved, gated, async or consolidated hook's evidence run pasted.
4. Update this PLAN's phase tags to `[DONE]` and fill "Outcome".

**Sanity Check:**

- `grep -c 'spawn-equivalent' docs/conventions/hook-budget/README.md` is at least 1 and the file
  names the harness sha256.
- `diff <(jq -S .enabledPlugins ~/.claude/settings.json) baselines/enabled-plugins-before.json` prints nothing.
- The final `=== per event` block meets every (B) inequality, including `max_ms` under 1,000 on
  every per-tool-call line; a script line per inequality with `awk` over the TSV prints `PASS` for
  each; the run header is not `INVALID RUN`.
- `jq -r '.plugins | to_entries[] | select(.key | endswith("@melodic-software")) | "\(.key) \((.value | if type=="array" then .[0] else . end) | .version + " " + .gitCommitSha)"' ~/.claude/plugins/installed_plugins.json` pasted, every measured plugin's sha equal to its delivered HEAD.
- `gh pr checks` 0 failing.

### Baseline values (filled at phase 0 and phase 1)

| Measurement | Value | Source |
|---|---|---|
| Reference-host `bash -c :` | about 80 ms | hook-budget README, 2026-07-31 |
| Loaded-host `bash -c :` seen during the dispatcher measurement | 4,498 ms | guardrails README, 2026-08-30 |
| Per-Bash-call guard set before the dispatcher | 8 processes, about 2,450 ms summed medians | guardrails README 0.31.0 |
| Per-Bash-call guard set after the dispatcher | 1 process, about 1,220 ms of guard slices | guardrails README 0.31.0 |
| Harness `=== per event` at `main` with the extended harness | block below, S=33 ms, valid, `--runs 3`, 2026-09-02 (cache: `main` plus PR #3621 delivered, see DEVIATIONS.md) | `baselines/phase1-harness-main.tsv` (135 rows), `phase1-harness-main.out`, `phase1-installed-plugins.txt` |
| Harness sha256 at the dotfiles PR commit | `4cfaeeb41e3e3b3a1623295250fa8b7471878fb90e23a119e4735472a3f8f50a` (branch head `157633f`: main merged in with its `--plugin-root` addition, placeholder path spellings; supersedes `5a4dbb63...` at `d714f93`) | dotfiles branch `perf/hook-fanout-samples` |

#### Phase 0 baseline run (2026-09-02, extended harness at `c1b722b`, `--runs 3`, S=33 ms, valid)

Installed cache measured (`installed_plugins.json`, first entry per plugin; full list in `baselines/phase1-installed-plugins.txt`): guardrails 0.31.0, source-control 0.55.36, disk-hygiene 0.21.1, ruff-format 0.6.28, bash-format 0.7.28, biome-format 0.6.27, go-format 0.3.30, powershell-format 0.7.30, actionlint 0.8.27, instruction-placement 0.11.17, all at `a423e2c05` (PR #3621); every other plugin at its `main` install.

```text
=== per event: hook processes that fire, CPU sum of medians, slowest hook ===
(hooks run in parallel: wall per event ~= max; CPU per event ~= sum)
ConfigChange:user_settings fires= 1 skipped= 0 cpu_sum_ms=  604 max_ms=  604 async= 0 cpu_x_s=  18.3 max_x_s=  18.3
InstructionsLoaded:session_start fires= 1 skipped= 0 cpu_sum_ms=  343 max_ms=  343 async= 0 cpu_x_s=  10.4 max_x_s=  10.4
Notification:permission_prompt fires= 1 skipped= 0 cpu_sum_ms= 1029 max_ms= 1029 async= 0 cpu_x_s=  31.2 max_x_s=  31.2
PostCompact:-            fires= 1 skipped= 0 cpu_sum_ms=  630 max_ms=  630 async= 0 cpu_x_s=  19.1 max_x_s=  19.1
PostToolBatch:Read       fires= 1 skipped= 0 cpu_sum_ms= 1254 max_ms= 1254 async= 0 cpu_x_s=  38.0 max_x_s=  38.0
PostToolUse:Bash         fires= 0 skipped= 2 cpu_sum_ms=    0 max_ms=    0 async= 0 cpu_x_s=   0.0 max_x_s=   0.0
PostToolUse:Edit         fires= 4 skipped=22 cpu_sum_ms= 3276 max_ms= 1374 async= 0 cpu_x_s=  99.3 max_x_s=  41.6
PostToolUse:Write        fires= 4 skipped=22 cpu_sum_ms= 2757 max_ms= 1211 async= 0 cpu_x_s=  83.5 max_x_s=  36.7
PostToolUseFailure:Bash  fires= 1 skipped= 1 cpu_sum_ms=  739 max_ms=  739 async= 0 cpu_x_s=  22.4 max_x_s=  22.4
PreCompact:auto          fires= 1 skipped= 0 cpu_sum_ms=  694 max_ms=  694 async= 0 cpu_x_s=  21.0 max_x_s=  21.0
PreToolUse:Bash          fires= 1 skipped= 3 cpu_sum_ms= 2475 max_ms= 2475 async= 0 cpu_x_s=  75.0 max_x_s=  75.0
PreToolUse:Bash:subst    fires= 4 skipped= 0 cpu_sum_ms= 5176 max_ms= 3979 async= 0 cpu_x_s= 156.8 max_x_s= 120.6
PreToolUse:Edit          fires= 3 skipped= 0 cpu_sum_ms= 1495 max_ms= 1147 async= 0 cpu_x_s=  45.3 max_x_s=  34.8
PreToolUse:Write         fires= 3 skipped= 0 cpu_sum_ms=  971 max_ms=  773 async= 0 cpu_x_s=  29.4 max_x_s=  23.4
SessionStart:compact     fires= 2 skipped= 0 cpu_sum_ms=  303 max_ms=  209 async= 0 cpu_x_s=   9.2 max_x_s=   6.3
SessionStart:startup     fires= 2 skipped= 0 cpu_sum_ms=  298 max_ms=  210 async= 0 cpu_x_s=   9.0 max_x_s=   6.4
Stop:-                   fires= 4 skipped= 0 cpu_sum_ms= 1327 max_ms=  376 async= 0 cpu_x_s=  40.2 max_x_s=  11.4
StopFailure:rate_limit   fires= 2 skipped= 0 cpu_sum_ms=  871 max_ms=  531 async= 0 cpu_x_s=  26.4 max_x_s=  16.1
UserPromptExpansion:-    fires= 1 skipped= 0 cpu_sum_ms=  285 max_ms=  285 async= 0 cpu_x_s=   8.6 max_x_s=   8.6
UserPromptSubmit:-       fires= 1 skipped= 0 cpu_sum_ms=  975 max_ms=  975 async= 0 cpu_x_s=  29.5 max_x_s=  29.5
WorktreeCreate:-         fires= 1 skipped= 0 cpu_sum_ms=  523 max_ms=  523 async= 0 cpu_x_s=  15.8 max_x_s=  15.8
statusline:-             fires= 1 skipped= 0 cpu_sum_ms=  229 max_ms=  229 async= 0 cpu_x_s=   6.9 max_x_s=   6.9
```

Parse and spawn floor on the same host, 12 interleaved trials, medians: `bash -c :` 22 ms; `bash -c "source hook-utils.sh"` (2,139 lines) 26 ms, so the library parse is about 4 ms (0.2 spawn-equivalents) and phase 4b's switch condition (one spawn-equivalent) is not met; `bash -c` plus one `jq` call 72 ms, so each external `jq` costs about 50 ms (2.3 spawn-equivalents). The per-hook cost is external spawns (`jq`, `git`, formatters), not the library parse.

## Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| One fleet-wide dispatcher across plugins (research lever 3, marketplace level) | Violates constraint 2 (each hook stays declared in its own plugin's `hooks.json`) and couples plugin releases | Only if the constraint is lifted by the operator |
| Exec form for every bash hook (research lever 6) | Open Windows bug #90495 reports `args` dropped and routed through `bash.exe`; unmeasured here | A phase 3 live probe showing the context-budget exec-form hook matches on this host, plus a measured spawn saving of at least one spawn-equivalent per hook, reopens it as its own phase |
| `shell: "powershell"` for guards that inspect PowerShell commands | #90077 reports no `powershell.exe` fallback; pwsh startup is slower than bash on this host | Same probe-then-measure rule |
| Move per-tool guards to Stop or PostToolBatch (lever 4) | The guards decide (block); a per-turn event cannot gate a tool call | None: decisions stay per-tool |
| `async` on `zone-crossing-inject` for UserPromptSubmit too | Output must land before the prompt (H31, H12) | None |
| Cache-delivery helper committed under `scripts/` | Host-specific, mutates the operator's marketplace clone, and a new `.sh` there needs a suite under `affected-tests.sh` | Second host needs it, or the operator asks for it tracked |
| Skip 4b and only trim guards | Chosen as the default if 4a measures the parse below one spawn-equivalent | 4a measurement at or above one spawn-equivalent triggers 4b |
| Widen `check-silent-skips.sh` to plugin skill tests in phase 5 | Widens a gate inside a fix PR; may flag unrelated suites | Open question 5: if the operator wants the gate to govern, it becomes a small phase 5 sub-item with its own test case |

## Test strategy

Test-first where a behaviour changes (phases 4a, 4b, 5, 7); config phases (2, 3, 6) are verified by
jq assertions and equivalence runs rather than new suites. `/tdd:principles` was not invoked by the
drafting worker; the orchestrator may. Test-type classification per `/testing:plan` is not restated.

Test boundaries (existing unless marked new):

- **Harness `=== per event` block** (new, phase 1): the public interface every later phase's
  before and after claim drives.
- **Harness status classes** `NEVER_RUNS(if-on-non-tool-event)`, `RAN(best-effort)`, `RAN(async)`
  (new, phase 1).
- **`hooks.json` contract via `jq`** (existing shape; new assertions per phase): async rows, `if`
  rows, timeouts, `type == "command"`.
- **Live `claude --debug-file` probe** (new boundary, phases 2 and 3): the only place Claude Code's
  own `if` evaluation, exec-form spawning, and async batch delivery are exercised. The harness
  cannot stand in for it.
- **Per-guard `*.test.sh` and `run-guards.test.sh`** (existing, phase 4a): MUST-fire and
  MUST-stay-quiet cases; a hot-path change that flips either is a regression.
- **`lib/hook-utils.test.sh`, `sync-hook-utils.sh --check`, `--check-bump`** (existing, phase 4b)
  plus the lazy-load cases (new).
- **`index-drift.test.sh`, `render-index.test.sh`, the two `emit-findings.test.sh`** (existing,
  phase 5): repro-first, each new case red on the unmodified script on this host.
- **`check-silent-skips.sh`** (existing gate, phase 5): the skip annotation format.
- **`check-listing-budget.sh` output parse** (existing script, new assertion, phase 6).
- **`statusline-tee.test.sh`** (existing, phase 7) plus the no-change case (new).
- **Baseline-equivalence diffs** (new, phases 2 and 3): direct hook run before and after with the
  trigger-class payload, stdout and exit code compared byte-for-byte.

Edge cases: a `$()` command against a bare-command-name `if` (must skip); a NUL-bearing payload
through the dispatcher's primed cache (must fall through to real jq, already tested); an async hook
under `-p` teardown (documented, not tested); an unmatched statusline glob (already handled in the
entrypoint).

Existing tests to update: `run-guards.test.sh` (4a, 4b), `hook-utils.test.sh` (4b), the four
host-skip suites (5), `statusline-tee.test.sh` (7).

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Windows drops async PostToolUse firings in batches (#79230), so an async formatter misses edits | Med | Med | Phase 2 live probe counts firings on a three-file batch; a miss keeps the hook synchronous |
| `if` on the exec-form context-budget hook never matches on Windows (#90495) and the ask gate silently disappears | Med | High | Phase 3 live probe is mandatory before merge; on failure keep the unconditioned row and record the residual |
| A shortened timeout turns a gate fail-open (H20) | Low | High | Gating rows keep their timeouts; only advisory rows are right-sized |
| Guard hot-path edits change a decision | Low | High | Every guard's contract test plus the phase 4a before and after decision diff on the two payloads |
| The 17-carrier bump collides with concurrent plugin PRs | Med | Med | 4b runs last among code phases; rebase and re-run `--check-bump` before merge |
| Load-sensitive timings make (B) fail on a busy host | High | Low | Every figure is a ratio to the same-trial `bash -c :` median; run (B) on a drained host and state the load |
| Marketplace clone left on a branch after a failed delivery | Low | Med | Helper's trap returns it to `main`; sanity check in phase 0 |
| Removing an observability row loses telemetry someone reads | Low | Med | Phase 3 keeps every row unless its consumer is shown absent, and records the cut in the README |
| Skill flag changes hide a skill the operator relies on auto-invoking | Med | Low | Human-gated table, row by row |
| A flagged skill is a cited target of another skill's "invoke via the Skill tool" line, so callers' presence gates read it as absent | Med | Med | Phase 6 citation sweep excludes cited targets before any proposal |
| A lazy-load stub recurses when its module file is absent and a gate hangs to timeout, then fails open | Low | High | Stub checks the module guard variable after `hook::_load` and returns 2 with a notice; absent-module test case |
| Async rows worsen a Windows spawn storm (no dedup, timeout unenforced, batch drops) | Med | Med | Phase 2 process-table peak before and after; README caveat; storm-worsening row stays synchronous |
| Marketplace auto-update pulls the clone mid-phase and a measurement reads a different commit than believed | Med | Med | Delivery assertion on `installed_plugins.json` `gitCommitSha`, recorded before every run |

## Blast radius

**HIGH.** Twenty `hooks.json` files across the fleet, 17 library carriers, every consumer session's
per-tool critical path, one dotfiles script, production Windows-only fixes in three plugins, and a
skill listing change that alters what the model can auto-invoke. Two repositories.

## Stress-test summary

Pending: Step 3 (fresh-context plan reviewer) and Step 4 (`/planning:devils-advocate`, required at
HIGH) are the orchestrator's.

## Execution shape

### Phase file-overlap matrix

| Phase | Files | Overlaps with |
|---|---|---|
| 1 | dotfiles `common/measure-claude-hook-fanout.sh`, dotfiles README | none (other repo) |
| 2 | `plugins/{typos-format,claude-ops,disk-hygiene,context-guard}/hooks/hooks.json`, their `plugin.json`, CHANGELOG, README | 3 (claude-ops and disk-hygiene `hooks.json`, README), 7 (context-guard `plugin.json`) |
| 3 | `plugins/{context-budget,claude-ops}/hooks/hooks.json`, `plugins/{source-control,disk-hygiene,claude-ops}/README.md`, `plugins/context-guard/hooks/hooks.json` (timeouts), `plugin.json`, CHANGELOG | 2 |
| 4a | `plugins/guardrails/hooks/*.sh`, `*.test.sh`, README, `plugin.json`, CHANGELOG | 4b (`run-guards.test.sh`, guardrails `plugin.json`) |
| 4b | `lib/hook-utils.sh`, `lib/hook-utils.d/*`, `lib/hook-utils.test.sh`, `scripts/sync-hook-utils.sh`, `scripts/sync-hook-utils-*.sh` and tests, `.github/workflows/ci.yml`, 17 `plugins/*/hooks/hook-utils.sh`, 17 by N `plugins/*/hooks/hook-utils.d/*`, 17 `plugin.json`, 17 CHANGELOG, `run-guards.sh`, `run-guards.test.sh` | 2, 3, 4a, 4c, 5, 7 (via `plugin.json` and CHANGELOG of shared carriers; `run-guards.sh` with 4a) |
| 4c | `plugins/{typos-format,eol-normalizer,markdown-format}/hooks/*.sh`, `*.test.sh`, README, `plugin.json`, CHANGELOG; guardrails verifier guards only if profiled | 2 (typos-format `hooks.json` and `plugin.json`), 4a (guardrails), 4b |
| 5 | `plugins/instruction-placement/{scripts,hooks}/**`, `plugins/docs-hygiene/skills/audit-noise/scripts/*`, `plugins/claude-config/skills/audit-instructions/scripts/*`, `plugins/{ai-slop,code-tidying,provenance}/skills/*/scripts/*.test.sh`, six `plugin.json` and CHANGELOG | 4b (instruction-placement `plugin.json`) |
| 6 | approved `plugins/*/skills/*/SKILL.md`, their `plugin.json` and CHANGELOG | any phase whose plugin also owns an approved skill (resolved by ordering 6 after 2 to 5) |
| 7 | `plugins/rate-limit-guard/scripts/statusline-tee.sh`, `*.test.sh`, README, `plugin.json`, CHANGELOG (context-guard same set only if wired) | 2 (context-guard), 4b |
| 8 | `docs/conventions/hook-budget/README.md`, touched plugin READMEs, this PLAN | all (READMEs), docs only |

### Dependency graph

- 1 gates every measurement: the extended `=== per event` block is the before and after interface.
- 0 (baseline at `main` with the phase 1 harness) precedes 2 through 7.
- 3 precedes 2: shared `hooks.json` files, and 2's async rows should be applied to already-scoped rows.
- 4a precedes 4b: 4a's parse measurement is 4b's switch condition.
- 4c after 2 (typos-format `hooks.json` and `plugin.json` are shared) and after 4a (guardrails
  verifier guards, if profiled).
- 4b runs after every other code phase: it bumps 17 carriers, and any earlier phase's bump of the
  same plugin would otherwise collide.
- 5 is independent of 2, 3, 4a, 7.
- 6 after 2 through 5 so skill-flag bumps never collide with a hooks PR on the same plugin.
- 8 last. Integration-first: 1 and 0 are the integration slice and go first.

### Recommended shape

> Sequential spine: 1, then 0, then 3, then 2, then 4a, then 4c, then 6, then 4b, then 8.
> Wave A (parallel workers, single message, after 0): {3, 5}. File-disjoint.
> Wave B (parallel workers, after 2 merges): {4a, 7}. File-disjoint (7 touches only rate-limit-guard unless context-guard is wired, in which case 7 waits for 2).
> 4c runs alone after Wave B (shares typos-format with 2 and guardrails with 4a).
> Cost note: two parallel workers double token spend for those waves; each is a separate PR anyway, so the parallelism is elapsed time only.

### Scope-fencing tables

| Agent | Phase | ALLOWED files | LOC |
|---|---|---|---|
| W1 | 1 | dotfiles worktree: `common/measure-claude-hook-fanout.sh`, `README.md`, `docs/claude-hook-fanout.md`, `docs/maintenance.md` | about 180 |
| W3 | 3 | `plugins/context-budget/hooks/hooks.json`, `plugins/claude-ops/hooks/hooks.json`, `plugins/context-guard/hooks/hooks.json`, `plugins/{source-control,disk-hygiene,claude-ops,context-budget,context-guard}/README.md`, the same plugins' `plugin.json` and CHANGELOG | about 80 |
| W5 | 5 | the phase 5 file list, plus six `plugin.json` and CHANGELOG | about 200 |
| W2 | 2 | `plugins/{typos-format,claude-ops,disk-hygiene,context-guard}/hooks/hooks.json`, README, `plugin.json`, CHANGELOG | about 40 |
| W4a | 4a | `plugins/guardrails/hooks/*.sh`, `plugins/guardrails/hooks/*.test.sh`, `plugins/guardrails/README.md`, guardrails `plugin.json` and CHANGELOG | about 150 |
| W7 | 7 | `plugins/rate-limit-guard/scripts/statusline-tee.sh`, `statusline-tee.test.sh`, README, `plugin.json`, CHANGELOG | about 80 |
| W4c | 4c | `plugins/{typos-format,eol-normalizer,markdown-format}/hooks/*.sh` and `*.test.sh`, their README, `plugin.json`, CHANGELOG; `plugins/guardrails/hooks/{cli-flag-verify,skill-reference-verify,stale-path-verify}.sh` and tests only if the profile names them | about 120 |
| W4b | 4b | `lib/hook-utils.sh`, `lib/hook-utils.d/**`, `lib/hook-utils.test.sh`, `scripts/sync-hook-utils.sh`, `scripts/sync-hook-utils.test.sh`, `scripts/sync-hook-utils-*.sh` and their `*.test.sh`, `.github/workflows/ci.yml` (the new sync jobs only), `plugins/*/hooks/hook-utils.sh`, `plugins/*/hooks/hook-utils.d/**`, the 17 carriers' `plugin.json` and CHANGELOG, `plugins/guardrails/hooks/run-guards.sh`, `plugins/guardrails/hooks/run-guards.test.sh` | about 450 |

**Each agent FORBIDDEN:** any file outside its ALLOWED list; this PLAN (main session edits status
only); another agent's territory; `~/.claude/settings.json`; the marketplace clone (the main session
runs the delivery helper); `git push --force`; staging or committing outside its own branch.

**Worker brief hygiene:** the tool-command guards on this host block a Bash command string that
contains `cat >`, `printf >`, `echo >`, `python -c`, or the literal disk-hygiene engine filename.
A brief must not contain those strings even in prose, because a worker echoes its brief into
commands; write "use the Write tool" and name the engine by its skill, not its filename.

**Each agent reports at end:** work items completed, per-criterion Sanity Check verdict with the
command output, actual LOC delta, the before and after harness or profile numbers it produced, and
the PR URL with `gh pr checks` output.

**Divergence escalation (copy into every worker brief verbatim):**

```text
DIVERGENCE ESCALATION (mandatory): if reality diverges from this brief:
a precondition fails, a file/symbol named here is absent or different than
described, scope is blocked, or a design question arises mid-task, STOP.
Do not improvise, fix forward, or expand scope. Report to the orchestrator:
what you found, what the brief expected, and the exact state of your work
(files touched, edits applied / not applied). Await a revised brief.
```

### Sequential fallback

> If a scope-fence violation, a concurrent-edit race on a shared `plugin.json`, or a cannot-complete
> report occurs in Wave A or B, abort that agent and run its phase alone after the other wave member
> merges. The other agent continues.

### Per-phase routing table

| Phase | Surface | Basis |
|---|---|---|
| 0 | main-session | Mutates the operator's marketplace clone and reads `~/.claude/settings.json`; judgment on host load |
| 1 | sub-agent worker | Mechanical script extension in another repo, clear byte-compat contract |
| 2 | sub-agent worker, after open questions 3 and 4 are answered | Config edits plus equivalence runs; the live probe result is pasted back to main |
| 3 | sub-agent worker | Config edits plus README notes; live probe mandatory |
| 4a | sub-agent worker | Guard-local edits behind contract tests |
| 4b | promoted sub-topic, its own dispatch | 17-carrier fan-out and a new sourcing contract |
| 4c | sub-agent worker | Hook-local spawn cuts behind existing contract tests |
| 5 | sub-agent worker | File-disjoint script fixes with repro-first tests |
| 6 | main-session | Human-gated skill list; interview per row |
| 7 | sub-agent worker | One script, one test |
| 8 | main-session | Docs plus the final transcript proof, which only the main session can assemble |

## Open questions

1. **Tracking issue.** No issue number exists for this program. Recommendation: one tracking issue
   with a checklist of the eight PRs, each PR `Closes` a per-phase sub-issue or cites the tracker
   under `## Related` with `No related issue: <reason>` only where the operator prefers. Arbiter:
   operator.
2. **Bash `if` bare-name rule.** Whether `Bash(gh *)` counts as "more than a bare command name" for
   the H7 spawn rule. Phase 1 encodes the documented rule (anything after the name spawns on
   `$()`); phase 3's live probe records what 2.1.258 actually does. Arbiter: the probe.
3. **typos-format write mode.** `hooks.json` cannot make `async` conditional on the
   `typos_format_write_changes` userConfig. Options: keep synchronous (no async win on the largest
   per-Write hook), or drop write mode (a feature removal, needs the operator). A third option,
   two rows selected by `${user_config.*}` argv substitution, needs exec form (hook-config-delivery
   fact 1) and so trips constraint 8; it is struck. Recommendation: keep synchronous unless the
   operator drops write mode. Arbiter: operator.
4. **Operator visibility of async Stop hooks.** `hook-failure-audit.sh` and
   `guard_launch_monitor.py` exist to surface silent failures to the operator; async delivers their
   `systemMessage` to Claude on the next turn and never to the operator (H12). Recommendation: keep
   both synchronous, and make them cheaper instead (they are Stop hooks, once per turn, inside the
   500 ms per-turn budget already). Arbiter: operator.
5. **`check-silent-skips.sh` scope.** The gate scans `scripts/*.test.sh`, not the plugin skill tests
   phase 5 annotates. Annotate in its format regardless; whether to widen its scan in the same PR is
   the operator's call. Arbiter: operator.
6. **Timeout right-sizing on context-guard UserPromptSubmit and PostToolBatch** (60 s today,
   `[FALLBACK]` proposes 15 s). Arbiter: operator, since a shorter timeout on an advisory hook only
   drops a late nudge but the number is a taste call.
7. **Research verifier rows 4 and 7** were graded 2026-09-02 (both FAIL on corroboration and labels, not accuracy); RESEARCH.md carries the parent disposition: seven claims demoted to Gaps (measure first), five relabelled MEDIUM. The plan
   relies on H7, H9, H12, H31 and #79230; if the verifier overturns any of them the affected phase
   re-plans. Arbiter: the research-verifier teammate.
8. **When async PostToolBatch output lands.** If an async `zone-crossing-inject` on PostToolBatch
   only reaches Claude after the next user prompt, the synchronous UserPromptSubmit row already
   covers that moment and the async row is pure spawn cost with no nudge. The phase 2 live probe
   answers it; if the output lands after the prompt, the PostToolBatch row stays synchronous or
   is dropped with a mapping row. Arbiter: the probe, then the operator.
9. **InstructionsLoaded removal.** "Moved to nothing" is outside the goal's closed destination list,
   so removing the claude-ops InstructionsLoaded row (or any observability row) needs the operator's
   sign-off, and a sign-off also updates `docs/conventions/hook-telemetry` where its JSONL row is
   documented. Default: keep, matcher-scoped. Arbiter: operator.
10. **Goal turn budget.** The goal condition caps the program at 60 turns across nine PRs and two
    repositories, which is tight. Option: re-set the goal per phase (each phase's Sanity Check list
    as that phase's condition) and keep the program-level (B) run for phase 8. Arbiter: operator.

### Measure-first assumptions (unfalsified, recorded so no phase builds on them untested)

| Assumption | Where it bites | How it is tested |
|---|---|---|
| A `**/` path rule reaches absolute paths outside cwd | Phase 3 context-budget rows | Phase 3 live probe: Write to `~/.claude/settings.json` under a project-scope-only rule must NOT match; recorded either way |
| `Edit(...)` rules in `if` cover the Write tool | Phase 3 rows, harness `if_hits` | Phase 3 live probe uses a Write, not only an Edit, and the `--debug-file` line is pasted |
| `installed_plugins.json` `.plugins[<id>]` first array entry is the newest install | Phase 0 delivery assertion, harness `plugins()` | Phase 0: after a delivery, assert the entry whose `version` equals the branch `plugin.json` is the one the harness reads; if the array order differs, select by version, not index |
| `claude plugin update` refreshes the marketplace clone itself | Phase 0 helper | Helper records the clone HEAD before and after `claude plugin update`; the delivery assertion is on `gitCommitSha`, not on the clone state |
| Plugin hooks fire inside subagents on this host (#88441 reports user-settings PreToolUse hooks do not, for Bash inside Task subagents) | Every per-tool budget claim and the constraint 1 mapping | One `--debug-file` session in phase 3 dispatches a subagent that runs a Bash command; the log shows whether the guardrails dispatcher fired; recorded in Baseline values |
| `Bash(gh *)` is "more than a bare command name" for the H7 spawn rule | Phase 1 `RAN(best-effort)`, phase 3 residual note | Open question 2, settled by the phase 3 probe |

## Handoff to implementation

### User-approval gates

- Every `[FALLBACK]` row in the decisions table below.
- Phase 2: the two visibility questions (open questions 3 and 4) before any `async` flag is set.
- Phase 3: any InstructionsLoaded or other observability row removal.
- Phase 4b: the promotion to its own topic, and the go or no-go read off 4a's parse measurement.
- Phase 6: every skill flag row.
- Any proposal to adopt exec form or `shell: "powershell"` (constraint 8).
- Any change to a gating hook's timeout.

### Execution shape ([EXEC-SHAPE] tagged)

Decisions made (gate-passed):

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| [EXEC-SHAPE] Phase 3 before phase 2 | Ordering in the sequential spine; 2 waits for 3 to merge | Both edit `claude-ops/hooks/hooks.json` and `disk-hygiene/hooks/hooks.json` (read this session); async rows should apply to already-scoped rows |
| [EXEC-SHAPE] Phase 4 split into 4a (guard hot path) and 4b (library split), 4b promoted to its own topic | Two PRs instead of one; 4b gets `docs/topics/hook-utils-split/PLAN.md`; 4b runs last among code phases | Plan-template promotion trigger: more than five work items, more than 300 LOC, own sub-phases, independent commit boundary; 17-carrier bump collides with every other phase's `plugin.json` |
| [FALLBACK, confirm or override] 4b gated on 4a's parse measurement, default threshold one spawn-equivalent per hook process | 4b most likely closes as "measured, not needed" at that bar; a lower bar makes it run | Sizing guess, no evidence yet: the dispatcher already pays the parse once per event and no measurement of parse share exists (guardrails README accounts guard slices, not parse). The operator sets the number |
| [EXEC-SHAPE] Each phase bumps its own plugins' versions; phase 8 is docs and accounting only | Removes version bumps from phase 8's scope | Constraint 6: `claude plugin update` keys on the plugin version, so a phase cannot be delivered to the cache without its bump |
| [EXEC-SHAPE] Async status carried in the TSV status column (`RAN(async)`); sample identity in a ninth `sample` column appended after the legacy eight | Legacy columns 1 to 8 and the seven legacy rows are byte-identical; the header and every row gain one trailing field; TSV consumers are inventoried first (phase 1 item 1) | Brief's byte-compatibility requirement for the seven legacy samples; the existing awk summaries key on columns 1, 2 and 4 and ignore trailing fields |
| [EXEC-SHAPE] Phase 4c added for the per-Write formatter hot path | A tenth PR; owns the (B) `cpu_sum_ms` residual on the `.md` sample | Devil's-advocate measurement: typos-format plus eol-normalizer plus markdown-format plus the verifier dispatcher is about 13.7 spawn-equivalents against the 12 times S cap, and async reduces no `cpu_sum` |
| [EXEC-SHAPE] Harness validity gate at S at most 160 ms and `max_x_s=` (spawn-equivalents) beside the absolute `max_ms` | Phase 1 item 3; phase 0 helper refuses under load; phase 8 final run must be valid | `now_ms()` spawns `date` and `cut` per sample today, inflating S and hook time alike, so ratio targets get easier under load; the updated goal condition names the 160 ms bound and the 1,000 ms absolute ceiling |
| [EXEC-SHAPE] Live `claude --debug-file` probe is a named test boundary for phases 2 and 3 | Adds a mandatory probe step and pasted log line to each | The harness feeds payloads directly and never exercises Claude Code's own `if` evaluation, exec-form spawning or async delivery (harness source read this session; ledger H4, H22, #90495, #79230) |
| [EXEC-SHAPE] Waves A {3, 5} and B {4a, 7} parallel; everything else sequential | Elapsed-time saving only; each remains its own PR | File-overlap matrix above |
| [EXEC-SHAPE] Measurements reported as spawn-equivalents with the same-trial `bash -c :` median | Every before and after claim in this plan | hook-budget README method and the 4,498 ms loaded-host baseline recorded in the guardrails README |
| [FALLBACK, confirm or override] Cache-delivery helper lives untracked under `.work/hook-performance-levers/` with `--dry-run` and a return-to-main trap | Phase 0 deliverable location | It mutates the operator's marketplace clone and is host-specific; a tracked `scripts/*.sh` would need a suite under `affected-tests.sh` |
| [FALLBACK, confirm or override] context-guard UserPromptSubmit and PostToolBatch timeouts to 15 s | Phase 3 item 3 | H31 (a stuck UserPromptSubmit hook stalls the session); advisory hook, fail-open cost is a late nudge |
| [FALLBACK, confirm or override] Phase 1 worktree created at `D:/worktrees/dotfiles-perf-hooks` on a new branch `perf/hook-fanout-samples` from `origin/main` | Phase 1 step 0 | The brief names a worktree that does not exist; the harness is on dotfiles `main` at `5aceefb` |
| [FALLBACK, confirm or override] Phase 5 host skips print `SKIP (host: <reason>)` and carry the `# silent-skip-ok:` annotation even though the gate does not scan those files today | Phase 5 item 4 | `check-silent-skips.sh` scan scope read this session; the annotation format is the only sanctioned one in the repo |
| [FALLBACK, confirm or override] Phase 7 measures only the rate-limit-guard tee; context-guard's tee is recorded as not on this host's render path | Phase 7 items 1 and 2 | `~/.claude/statusline/entrypoint.sh` read this session |

Agent roster, ALLOWED and FORBIDDEN tables, sanity-check criteria: above under Execution shape.

### Mechanical work

- One PR per phase (4a, 4b and 4c separate), branch names `perf/<phase-slug>` from `main`, rebased
  before merge; the operator merges.
- Every probe, harness run and equivalence run happens in a session started after the delivery it
  measures (sessions pin their plugin version directory at start).
- Worker briefs carry the scope fence, the divergence-escalation clause, and the brief-hygiene rule
  above; a brief is grepped for the blocked strings before dispatch.
- Commit at green checkpoints inside a phase: after tests pass locally via
  `scripts/affected-tests.sh --run`, and again after the harness after-run is saved.
- Verification checkpoints per phase: the phase's Sanity Check list, `gh pr checks` pasted, the
  before and after harness or profile numbers saved under `baselines/` and distilled into this PLAN.
- PR body per `.claude/rules/pr-body-contract.md`, drafted before `gh pr create`.
- Sequential fallback as stated under Execution shape.
- After each phase's merge: return the marketplace clone to `main` (helper trap), re-run
  `jq -S .enabledPlugins ~/.claude/settings.json` and diff against the phase 0 capture.
