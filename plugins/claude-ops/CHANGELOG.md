# Changelog

All notable changes to the `claude-ops` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.33.1]

### Changed

- **`claude-ops-paths.test.sh`'s Windows path fixtures now carry `portability-ok:` markers**, so the
  whole-repo `check-shell-portability.sh --all` audit runs clean instead of reporting three hits it
  will always report. The backslashes in `'C:\temp\skills'`, `'\\server\share\skills'` and
  `'telemetry\skills'` are the input these cases normalize, not GNU `\s` classes, so the construct
  cannot be spelled away — an exemption with a stated reason is the correct disposition. Each marker
  rides its own `case` arm rather than a shared comment block above them, so reordering the arms
  cannot silently detach an exemption from the site it excuses. No behavior change; the suite's
  assertions are untouched.

## [0.33.0]

### Added

- **`/claude-ops:audit-skill-visibility` — audit whether the model can actually SEE each installed
  skill.** That is the question behind "why does most of my fleet never get used?": a skill the model
  cannot see can never be chosen, so unused is very often a visibility failure rather than a
  preference. *Visibility* is Claude Code's own term here — `skillOverrides` is documented under
  "Override skill visibility" — and this skill audits every way a skill loses it.
  Claude Code budgets the model-visible skill listing at `skillListingBudgetFraction` of the
  context window and, when it overflows, drops descriptions starting with the skills you invoke
  least. A skill at zero usage therefore loses its description, loses the keywords a request would
  match against, and stays at zero — "unused" is partly self-causing. The skill separates **starved**
  from **genuinely unwanted** from **not observable**, across three independent fields
  (`reachability`, `observation`, `starvation`) rather than one flat verdict, because those demand
  opposite actions: only `model-reachable` with no observation is a starvation candidate, `user-only`
  means you type it by design, and `misconfigured` is a fix that must never read as a removal.

  Two properties are enforced rather than documented:
  - **Cold verdicts are withheld when the data cannot support them.** A store younger than the window
    being asked about cannot distinguish "never invoked" from "never observed"; reporting the second
    as the first libels most of a fleet on any fresh install. Every window is clamped to a computed
    `observed_horizon`, and declined claims appear in a first-class `withheld` section with reasons.
  - **Sources are reconciled, never summed.** Native counters and `skill-usage.jsonl` record the same
    invocation, so at a given instant the count is the max across sources — while two same-instant
    events from ONE source still count twice, because those are two real invocations.

  The listing-overflow figure is computed from documented settings alone (budget = fraction ×
  context window × bytes-per-token, against summed description lengths), so it needs no undocumented
  constant; which particular skills lose descriptions is a labelled likelihood band. Skills with
  `disable-model-invocation`, bundled prompt skills, and `name-only` overrides spend no description
  budget and are excluded from both the sum and the ranking.

### Changed

- **`clean` can prune `skill-usage.jsonl`, opt-in and on its own window.** Inert unless
  `--skill-usage-scope` is passed, so a run without the flag behaves exactly as before — that is the
  rollback path. Its window is `--keep-skill-usage-days` (default 365, far longer than the 30-day
  hook-events window) because a starvation report wants long history and those rows carry skill
  names and branches only. Scope and directory arrive as **flags, never environment**: a
  skill-spawned `clean.sh` inherits no `CLAUDE_PLUGIN_OPTION_*`, and `CLAUDE_PLUGIN_DATA` in that
  context was observed pointing at an unrelated plugin's data directory, so `data-dir` demands an
  explicit `--skill-usage-dir` and traversal is refused outright.
- **`lib/state-key.sh` added as a registered carrier** and enrolled in `scripts/sync-state-key.sh`,
  so report paths carry a repo-identity and worktree discriminator instead of collapsing to one file
  per machine.

## [0.32.9]

### Fixed

- **Human-relay user-invoked-only skill handoffs (#2940).** `inventory`,
  `audit-performance`, and `audit-install-state` no longer instruct the agent to
  route/hand off to `/claude-ops:plugins audit` or `/disk-hygiene:clean`
  (`disable-model-invocation: true`); they tell the user to run those skills.
  Question|Owner tables and "Deletion belongs to …" ownership prose unchanged.

## [0.32.8]

### Changed

- Sync `hook-utils.sh` from `lib/` — two header-echo comments removed in
  `hook::emit_telemetry` (comment-only; no behavior change).

## [0.32.7]

### Fixed

- **Test harness no longer lets a fixture's git identity land in the caller's
  repository ([#2840](https://github.com/melodic-software/claude-code-plugins/issues/2840)).**
  `claude-ops-test-helpers.sh` now clears `GIT_DIR`, `GIT_WORK_TREE`,
  `GIT_INDEX_FILE`, `GIT_COMMON_DIR`, `GIT_PREFIX`, `GIT_OBJECT_DIRECTORY` and
  `GIT_CONFIG` at source time. `git -C <fixture>` is a readability guard, not an isolation
  guarantee: an exported **absolute** `GIT_DIR` overrides repository discovery,
  so `git config`'s default `--local` scope resolves to the caller's gitdir and
  the fixture identity is written there instead — leaving the fixture with no
  `.git` and silently re-authoring the caller's next commit. `GIT_CONFIG` is
  cleared as a **second** leak path rather than another spelling of the first:
  it replaces the file the `git config` subcommand reads and writes, so an
  identity write follows it past `-C`, past a cleared `GIT_DIR`, and past the
  working directory. Test-only change; no shipped hook behavior is affected.

## [0.32.6]

### Fixed

- **Hook-failure audit classifies a record three ways, and says so when it cannot tell (#2849).**
  0.32.5 (below, unreleased) split the message two ways and treated `exitCode` 126 or 127 as
  launch-failure evidence on its own. Review found that predicate wrong: a registered shell hook
  launches successfully and still exits 126 or 127 whenever a command *inside* it is missing or not
  executable, so labelling that a launch failure hands the operator the restart-the-session remedy
  for a defect restarting cannot touch — the exact misdiagnosis #2849 exists to fix, in a narrower
  shape. Classification is now three-way:
  - `launch failure` — the record's stderr carries an exec-failure signature (`execvpe`,
    `execve(`, `exec format error`). **Signature evidence decides this regardless of exit code.**
  - `completed non-zero exit` — no signature, and `exitCode` is not 126 or 127.
  - `ambiguous: exit 126/127 with no exec-failure signature` — the message states plainly that both
    readings are possible and gives **both** remedies (check that the registered command exists and
    is executable, *and* read the hook's own logic for a command it could not run) rather than
    picking one.

  The measured corpus (175 records, 2026-08-16) is why neither signal alone is sufficient: 163
  records carry an `execvpe` signature at `exitCode` **1**, and the single `exitCode` 127 record
  carries **no** stderr signature at all — exit code and signature are close to independent in
  practice. The signature set still deliberately excludes `command not found`, `cannot execute`,
  and cmd.exe's `is not recognized as an internal or external command`: a successfully launched
  hook prints all three about a command it ran itself.

  **Disclosed deviation from the issue.** Acceptance criterion 2 of #2849 said `exitCode` 126/127
  **or** an exec-failure stderr signature keeps the launch-failure wording. That `or` is too loose
  for the reason above, so this change deliberately refines the criterion it closes: 126/127 with
  no signature is reported as ambiguous instead of as a launch failure. Nothing else in the
  criteria changed, and the launch-failure wording is still kept verbatim wherever signature
  evidence supports it.

## [0.32.5]

### Fixed

- **Hook-failure audit tells a launch failure apart from a completed non-zero exit (#2849).** The
  `hook-failure-audit` Stop hook emitted one unconditional sentence — "A hook that fails to launch
  enforces nothing" — plus a restart-the-session remedy, on every record, including a hook that ran
  to completion and exited non-zero, the exact case #2593 was written for. Each record is now
  classified, and the diagnosis and remedy follow the classification: the launch-failure wording
  and the restart remedy are kept verbatim where they are correct and are simply not asserted about
  a hook that ran. Classes are counted per record, so one registration that failed several ways in
  the same unwarned batch is labelled with each class's own count and gets each class's sentence,
  rather than being relabelled by whichever record happened to come last; the per-class message
  flags are computed from those per-record counts, never from the collapsed group value. The class
  names and the discriminator that assigns them were refined under 0.32.6 above before either
  version shipped. `exitCode` alone cannot carry the split: all 175 records in the measured corpus
  (2026-08-16) have a non-null `exitCode`, and 1 is the code the WSL relay reports for its own exec
  failures. The completed-exit wording asserts only the absence of exec-failure evidence, never a
  positive launch, so a record with no `exitCode` at all is not told it launched.
- **The harness's synthesized "no stderr" sentence is no longer attributed to the hook (#2849).**
  The empty-stderr placeholder shipped in 0.32.2 keyed on `.stderr == ""`, a shape Claude Code does
  not emit — 0 of 175 measured records carry it, while 12 carry the literal
  `Failed with non-blocking status code: No stderr output`, which passed through verbatim and read
  as though the hook had emitted that sentence. Both shapes now render as
  `last stderr: (none — hook produced no stderr)`. A real stderr is still passed through unchanged;
  the match is exact, not a prefix.
- **Maintainer-facing prose removed from the operator-facing message (#2849).** The sentence
  "Includes exitCode and an empty-stderr placeholder so silent Stop failures remain attributable
  (hookName + command)" explained the fix's implementation to an operator trying to act on an
  incident, and is gone.

## [0.32.4]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.32.3]

### Changed

- **`known-issues/context/registry-schema.md` is now a pointer, not a copy.** A repo-wide
  derivability audit (#2695) spot-tested the doc: a fresh-context agent reproduced every field,
  enum, and validation rule from `scripts/registry_manager.py` alone — and more accurately than the
  restatement. The file now points at the script's `REQUIRED_FIELDS` / `VALID_CATEGORIES` /
  `VALID_STATUSES` / `validate_issue()` / `resolve_data_dir()` instead of restating them.

## [0.32.2]

### Fixed

- **Hook-failure audit names exit code and empty stderr (#2593).** Stop-hook
  failures that produce the harness line "No stderr output" still leave a
  `hook_non_blocking_error` transcript attachment; the audit message now
  includes `exitCode` and an explicit `(no stderr output)` placeholder, and
  points operators at `hook_failure_audit_enabled` (default true).

## [0.32.1]

### Added

- **`plugins`:** `fleet-state.sh --ids <selector>` emits the id list each `sync` step loops — one
  record per line, tab-separated, first field always the fully-qualified `<name>@<marketplace>`,
  CR-free by construction — so no caller hand-writes `jq -r … | while read` over the JSON.
  Selectors: `installed-user`, `current-project`, `missing-user-install`, `missing-enabled`.
  `current-project` carries the record's `scope` as a second field, because one plugin can hold both
  a project- and a local-scope record for the same repo and the id alone cannot pick the right `-s`
  flag. Refuses an unknown or absent selector (validated at parse time, so it reports as a usage
  error even when the marketplace is also unresolvable) and `--all` (no single block to project),
  rather than emitting a silently-empty list. A per-marketplace failure block goes to stderr in this
  mode, never stdout, since a `< <(…)` consumer cannot see the exit status and would read the error
  JSON as an id (#2578).

### Fixed

- **`plugins` sync steps taught an unguarded `jq` loop.** Steps 2-5 said "take `fleet-state.sh`'s
  `installed[]` / `missing_*`" and loop, without supplying the extraction, so every reader wrote
  their own `jq -r`. On Windows the native `jq` writes stdout in text mode and `$(…)` strips only
  the trailing CRLF, so every id but the last reached `claude plugin update` as
  `<name>@<marketplace>\r` and failed with `Plugin "<name>" not found` — text identical to the
  bare-name gotcha, so it misread as that. Observed live: 64/65 updates failed. Steps 2-5 now cite
  `--ids` (#2578).

### Changed

- **`plugins` gotchas: corrected the CRLF mechanism.** The CR section claimed a single-line capture
  retains the `\r`, which predicts the wrong symptom (all ids failing). Verified on jq 1.8.2 / MSYS
  bash 5.3.9: `$(…)` strips the trailing `\r\n` as a unit, so a single-line capture is clean and
  only multi-line output keeps a CR on every line **but the last** — the all-but-last signature that
  identifies the cause on sight. Also records that `mapfile -t` has no last-element reprieve, and
  that jq→jq relays are self-cleaning because jq's stdin is text-mode too, which narrows the hazard
  to jq output reaching a non-jq consumer (#2578).

## [0.32.0]

### Added

- **`hook-failure-audit` (Stop): surface hook launch/exec failures Claude Code records
  only as `hook_non_blocking_error` transcript attachments and shows to nobody (#2577).**
  A hook that fails to launch is a non-blocking error — the guarded tool call proceeds
  as if approved, silently. The #1416 incident class proved an in-plugin detector is no
  shelter: disk-hygiene's own Stop monitor shared its guard's registration form and died
  the same launch death on all 23 of its runs (163 unsurfaced failures total on the
  incident host, 22 of them AFTER the fix was on disk, in a session still running the
  stale pre-fix config). This detector is decoupled: it lives here, launches through
  this plugin's always-shell-form registrations, tails a bounded transcript window, and
  matches structurally (`.type == "attachment"` and
  `.attachment.type == "hook_non_blocking_error"` — never substring, so a
  `hook_success` quoting an error text or a message quoting a failure record cannot
  fire it). Warns via `systemMessage` once per session per distinct failing hook
  registration — identity is `(hookName, command)`, since several plugins register on
  the same event+matcher (re-warns when a NEW registration starts failing; marker loss
  degrades toward re-warning, never silence), names the stale-session restart remedy,
  and emits the standard telemetry envelope with privacy-safe subjects (hook names
  only). Kill switch: `hook_failure_audit_enabled`.

## [0.31.14]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.31.13]

### Fixed

- **hook-utils:** distinguish unresolved `physical_path`/`repo_root` answers and honor unquoted `#` in `bash_parse_segments` (#1487).

## [0.31.12]

### Fixed

- **`morning-brief` Queues section no longer hardcodes melodic-software queue labels
  on live runs (#610).** Default labels remain the melodic-software taxonomy, but
  live queries now filter to labels that exist in the target repo (like the
  telemetry-issue path, degrading to "no queue labels found" when none match).
  Pass `--queue-labels` to pin a custom comma-separated set and `--decision-label`
  to pin the parked-decision label.

## [0.31.11]

### Fixed

- **`skills/plugins` `sync` wrote a committed settings file, breaking the skill's own invariant.**
  SKILL.md states that `converge` is the one action that may touch a committed
  `.claude/settings.json`, and only behind a per-plugin confirm. Step 5 issued
  `claude plugin enable <id> -s project` for any `currentProject: true` completeness gap, and that
  call writes exactly that file (verified on Claude Code 2.1.228 in 0.31.8). 0.31.8 documented the
  exposure and asked the report to name it; this removes it. Step 5 now enables automatically only
  at `user` and `local` scope — neither is team-shared state, since `local` writes the gitignored
  `.claude/settings.local.json` — and reports a `project`-scope gap as an "Action needed" row
  carrying the runnable `cd`-into-its-own-`projectPath` command instead of filling it. Confirming
  was rejected as the fix: `converge` can afford a confirm because it aborts in an autonomous
  session, while `sync` is the headless maintenance action with no such abort, so there may be no
  human to answer. No `sync` path writes a committed settings file after this change.

## [0.31.10]

### Fixed

- **`plugins` SKILL.md: `install_new` userConfig prose no longer embeds a live placeholder in its own
  unset-state explanation (#2522).** Explanatory sentences now describe the placeholder token by
  shape (`${user_config.…}`) or by reference to the **Configured value** line; only that line keeps
  the live `${user_config.install_new}` substitution site Step 4 branches on.

## [0.31.9]

### Fixed

- **hook-utils:** scope `read_file_path` to git worktrees when project dir unset (#1091).

## [0.31.8]

### Fixed

- **`scope-semantics.md` claimed `converge` was the only action that surfaces a settings diff.**
  False by its own new evidence: `sync`'s Step 5 issues `enable <id> -s <that scope>`, and
  `enable -s project` writes the committed file the same way `install` does. The update exemption is
  re-verified and still holds, but it is now documented as the exception rather than the rule.

### Added

- **`scope-semantics.md` gains a verified write-behavior table for project scope.** `install`,
  `uninstall`, `enable`, and `disable` at `-s project` all write the committed
  `.claude/settings.json`; `update` does not; `-s local` writes the gitignored
  `.claude/settings.local.json` instead. Also recorded: `enable -s project` gates on the *merged
  effective* value, so enabling an id that is `true` only at user scope fails rather than writing a
  project entry.
- **`sync.md` Step 5 names its own exposure.** A `-s project` enable can leave a team-shared tracked
  file modified with no diff surfaced — the failure class `converge` Step 5 prevents, in the default
  action. Flagged with instructions to name it in the report; the diff-surfacing remediation is
  tracked separately.
- **`gotchas.md` records that a subdirectory install is invisible to the skill.** The CLI keys
  `projectPath` on the literal cwd — installing from `<checkout>/nested/subdir` recorded that
  subdirectory and created its own `.claude/settings.json` — while `fleet-state.sh` resolves the
  checkout root. A plugin installed below the checkout root therefore never matches
  `currentProject`, never updates, and never appears in a divergence row, while still loading in
  that subtree. The same mechanism is why two `git worktree` checkouts of one repo pin
  independently, which `converge` Step 2 now states directly.

## [0.31.7]

### Fixed

- **`skills/plugins` predicted the wrong settings-write behavior for `converge`.** `converge.md`
  Step 5 said `uninstall -s project` "can remove an `enabledPlugins` entry" from committed settings,
  which reads as "a clean tree means nothing was written". It always writes: verified on Claude Code
  2.1.228 with single calls against a clean tracked `.claude/settings.json`, it empties the map to
  `"enabledPlugins": {}` rather than deleting the key, writes the key even into a file that never had
  one, and rewrites the file in Claude Code's key order so unrelated sibling keys move. Step 5 now
  checks every touched project unconditionally and classifies the diff as inert (empty map plus
  reorder — recommend discarding, so a team-shared file carries no churn) or substantive (an entry
  actually removed — the user decides). `scope-semantics.md` records install's and uninstall's
  behavior as a section beside the update exemption, which was re-verified on the same version and
  still holds.

### Added

- **`skills/plugins` records that project scope keys on the working directory, not the repository.**
  Verified by uninstalling one id in a repo's main checkout and watching its `git worktree`'s record
  for the same id survive. Two checkouts of one repo share a `.git` and a tracked
  `.claude/settings.json` yet pin independently, so `converge` must keep them as separate rows with
  separate `cd` targets — converging one never clears the other.
- **`sync.md` records one observation on `installed_plugins.json` write timing.** A 63-plugin
  user-scope sweep on 2.1.228 had all 21 CLI-reported updates already visible to a post-sweep
  re-read. Logged as a single data point that does not retire the `<new>` fallback, since it shows
  only that the write landed before the re-read on that run.

## [0.31.6]

### Changed

- **Synced `hook-utils.sh`:** write `emit_telemetry`'s `data` payload to a temp file instead of passing it via `--argjson`, so payloads above the Windows command-line cap are not dropped (#1595).

## [0.31.5]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811); widen the valueless-short peel set and keep `-h` value-taking.

## [0.31.4]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811).

## [0.31.3]

### Changed

- **Synced `hook-utils.sh`:** refuse sub-minimum `stdin_read_timeout` values (#1883).

## [0.31.2]

### Changed

- **Synced `hook-utils.sh`:** `hook::jq_fields` returns 2 when jq is present but cannot parse the payload (#2157).

## [0.31.1]

### Fixed

- **`skills/inventory` bundled-skill fields could bleed from the next registration.** The extractor
  read each registration through a fixed 4000-character window — the failure mode `build_brace_map`
  exists to prevent for commands, and the one `reference/extraction.md` names as the thing not to
  do. A registration omitting a description adopted the following one's. Fields are now bound to
  their own literal via the brace map, and an unmatched brace is counted and surfaced rather than
  silently skipped.
- **Manifest-declared component paths were ignored.** `PLUGIN_COMPONENTS` carried a manifest key per
  component and a comment claiming the manifest is read before the tree; nothing read it. A declared
  path replaces the default directory, so scanning defaults regardless reported components a plugin
  does not ship. Dotted keys resolve the `experimental` block.
- **`--self-check` lost its diagnostic when no binary was found.** `pick_binary` stores its
  explanation under `reason`; the self-check path read only `error` and printed a generic message.
- **An unreadable CLI version passed silently.** It is itself a drift signal, so it now degrades the
  verdict instead of skipping the comparison.
- **`--self-check` degraded and an argparse usage error both exited 2.** A CI gate treating 2 as
  "degraded, warn" would silently swallow a mistyped flag. Degraded is now 3, leaving 2 to argparse:
  0 ok, 1 broken, 2 usage error, 3 degraded.

### Added

- **`skills/inventory` reads installed plugins and project scope.** Only marketplace catalogs were
  scanned, so a plugin installed from a marketplace that is no longer cached was invisible;
  `disk.installed_plugins` now walks the plugin cache, and catalog, installed, and enabled are
  reported as three distinct sets. A project's `.claude` tree contributes skills, agents, and wired
  hook events that no machine-scope scan sees — `--project-dir` defaults to the working directory.
  Wired hook events are reported, never hook scripts on disk, which would repeat the
  present-versus-active error the skill warns about.

## [0.31.0]

### Added

- **`audit-performance`: a read-only slowness-diagnostic capture, run at the moment the machine or
  a session feels slow — before anyone restarts or deletes anything.** The failure mode it replaces
  is the folk remedy: "it was slow, so I nuked `~/.claude` and reinstalled" destroys the evidence
  and permanently confounds the fix, because a reinstall also crosses version upgrades (v2.1.216
  fixed a quadratic long-session slowdown; v2.1.208 cut per-tool-call MCP overhead up to 7x;
  v2.1.207 fixed keystroke lag — all within weeks of each other). One engine pass
  (`audit_performance.py`, Python 3.11+ stdlib only) captures the evidence to separate the three
  documented suspects: **accumulated install-tree state** (retention-sweep health including the
  silent unparsable-settings pause, plus a timed stat-walk of the whole tree whose duration
  approximates what the product's own daily sweep costs on that volume right now), **version
  regression** (CLI version, probed with its own latency recorded — a ten-second `--version` is
  itself a finding), and **component bloat** (plugin-fleet and process censuses, with the verdict
  routed to `/claude-ops:plugins audit`). Phase timings are first-class evidence throughout: on a
  struggling machine the audit itself runs slow, and that is signal, not failure.

- **A bundled known-performance-issues reference** (`reference/known-performance-issues.md`,
  compiled 2026-08-12 under the upstream-drift stamp discipline) carrying the 2.1.2xx performance
  fixes with dates, the source-level accumulated-state mechanisms confirmed against v2.1.228 (the
  daily whole-tree sweep walk; the unparsable-`settings.json` silent sweep pause; `history.jsonl`
  and home-root `~/.claude.json` as the two never-swept growth files; uncapped resumed-transcript
  render cost), the weak evidence base behind the nuke-the-directory remedy, and the
  Windows-specific amplifiers (Defender per-file taxation, hidden non-elevated exclusion reads,
  Desktop-vs-CLI surface discipline). `/claude-ops:known-issues` remains the live-search
  complement.

- **Hard read boundaries.** The engine mutates nothing anywhere, never elevates (Defender guidance
  is advisory text for the operator's own elevated shell), and its content-read allowlist is two
  files — `settings.json` and `.last-cleanup`; `~/.claude.json` values and `history.jsonl`
  contents are stat-only line items, never opened. The skill reports and routes: deletion belongs
  to `/disk-hygiene:clean`, per-project shedding to `claude project purge`, deep inventory to
  `/claude-ops:audit-install-state`, and settings repair to `/claude-config:audit`.

## [0.30.0]

### Added

- **`skills/inventory` — read-only enumeration of the complete invocable surface.**
  Answers "what can this machine actually invoke, and where did each thing come from" in one
  report: built-in CLI commands with aliases and hidden/gated markers, bundled skills, and every
  component of every installed plugin across all marketplaces. Built-in and bundled surfaces are
  read from the shipped binary because upstream publishes no built-in command list —
  `docs/en/slash-commands` and `docs/en/skills` return byte-identical markdown since commands were
  merged into skills — so no documentation source is complete for them. Filters accept either a
  flag (`--builtin`, `--plugins`, `--marketplace <name>`, `--agents`, `--hooks`, `--diff`) or the
  equivalent sentence; one extraction feeds every view.

  The extraction survives ordinary releases by resolving at runtime what changes between them:
  registrar names come from the bundle's export maps (`registerBundledSkill:()=>xu`) rather than a
  hardcoded minified identifier, the bundle is located by export-name anchor rather than section
  layout, and each command's fields are read by brace depth rather than a text window — adjacent
  minified literals otherwise bleed into one another. `scripts/inventory.py` needs only Python
  3.11+; no `strings`, `jq`, or PowerShell, so it behaves the same on all three platforms.

  Every run carries an integrity verdict (`ok` / `degraded` / `broken`) because the failure that
  matters is not a crash but a clean-looking short list. Canary commands, a minimum resolved-to-
  registration-token ratio, a sweep for unrecognised registrar-shaped exports, and the
  resolved-versus-seen gap on bundled skills each convert a quiet shortfall into a stated one; a
  `degraded` run reports counts as floors rather than totals. `--self-check` prints one verdict
  line and exits 0/1/2 for use as a CI gate or scheduled drift check, with `/claude-ops:changelog`
  as the natural trigger. `VALIDATED_AGAINST` records the last human-verified build, so a consumer
  running an older plugin against a newer CLI is told its counts are believed rather than verified
  instead of being handed a wrong answer.

## [0.29.3]

### Fixed

- **`morning-brief --help` now lists `--stranded-days`.** The flag was parsed and documented in
  `SKILL.md` but missing from the script header that `--help` prints, so operators following
  #1938's `--stranded-days 6` instruction could not confirm it from `--help`. (#1969)

## [0.29.2]

### Changed

- **`skills/lanes/scripts` `--paginate` reads now carry `per_page=100`.**
  `restart-consumer.sh`'s telemetry-comment read and `telemetry-upsert.sh`'s comment listing
  paginated without a page size — complete, but non-conformant with the published pagination rule
  and 3.3x the requests at the 30-item default. No behavior change: both folds are page-shape
  agnostic. `telemetry-upsert.test.sh`'s `gh` stub matched the list endpoint with an exact `*/comments`
  suffix, which the query string would have fallen through silently; it now matches the query form
  explicitly.

### Fixed

- **`telemetry-upsert.sh`'s slurp rationale no longer misdescribes `gh --paginate`.** The comment
  above the comment listing claimed `--paginate` "concatenates one JSON array per page". It does
  not: with no `--jq`, `gh` merges array-shaped pages into ONE array, so `jq -s 'add'` unwraps a
  one-element slurp rather than concatenating. `--paginate` is still load-bearing (it is what makes
  a page-2 comment visible at all) and `add` is still correct — but for a different reason than the
  comment gave, and a reader trusting it would mispredict the next endpoint's shape. Same correction
  applied to the pagination fixture's header comment in `telemetry-upsert.test.sh`. Measured against
  `gh` 2.95.0.

## [0.29.1]

### Changed

- **Shared `hook-utils.sh`: the jq gate now has a fail-CLOSED sibling, and the posture reasoning
  lives at the helper (#2146).** `hook::require_jq` is unchanged and still fails OPEN — one visible
  skip notice per session, then exit 0 — which is the correct posture for every hook in this plugin,
  so **nothing in this plugin's behaviour changes**. What is new is `hook::require_jq_blocking`, a
  second named function that denies the tool call instead, for the narrow class of guards whose job
  is blocking an irreversible operation (today only two, both in `guardrails`). A sibling function
  rather than a parameter, because a flag's omitted value would default to fail-open and a guard
  whose flag someone forgot would then fail open *silently* — the exact defect #2146 reports,
  reintroduced at the API. The two postures are now argued together in one block above both
  functions, which is what #2146 asked for: previously each call site asserted a posture in a
  comment and nothing where the decision is made explained it. Synced from `lib/hook-utils.sh`.

### Fixed

- **`lane-launcher` preflight validation jq queries now fail closed on query errors.** The duplicate-name,
  path-safety, and field-typing checks in `resolve_config` ran their jq filters in command
  substitutions and treated empty output as "no problem" without checking whether jq succeeded. A
  malformed config that slipped past the sibling type gate could make a query error vacuously pass.
  Each substitution now checks jq's exit status and rejects the config when the validation query
  itself fails.

## [0.29.0]

### Added

- **`audit-install-state`: a read-only audit of the machine-scope Claude Code installation
  directory** — the `~/.claude` tree plus the home-root `~/.claude.json` — filling a gap nothing in
  the marketplace covered. `claude-config` audits a *repo's* configuration files and its coordinator
  refuses any target that is not the active project root; `disk-hygiene:clean` deliberately routes
  product-managed state *out* of its engine; `claude-ops:plugins` reads
  `~/.claude/plugins/installed_plugins.json` but nothing else in the tree. This is the missing
  sibling to `plugins` (fleet state) and `observability` (telemetry state).

  The skill is report-only and never writes to the target tree. It answers four questions and
  refuses a fifth: what is here (inventory split automatically into a per-file authored surface and
  rolled-up bulk trees, with a CSV artifact so "every file" literally exists), what Claude Code's own
  retention sweep already manages, what each number in a filename actually *is*, and whether the tree
  is in a deliberate or mid-experiment state. It does not answer "so what should I delete" —
  deletion routes to `/disk-hygiene:clean`, shedding project state routes to `claude project purge`.

- **The liveness gate is code, not advice — a number in a filename is not reliably a PID.** A prior
  audit came one step from deleting `ide/22580.lock` because a process lookup for "22580" returned
  nothing: 22580 is a listening TCP port, and the real PID in the file body was alive and serving a
  running IDE integration. A lookup against a non-PID returns a clean, confident, *wrong* "dead."
  `verdict_for()` therefore classifies the naming scheme first and calls the probe only when the
  number is a PID; a spy-probe test asserts it is never invoked for `ide/<n>.lock` (TCP port),
  `rate-limit-guard/*.tmp.<n>` (MSYS2 `$$`), `shell-snapshots/…` (epoch ms), `paste-cache/<hex>`
  (content hash), or any unrecognised numeric name. Unknown schemes fail closed, and a probe that
  cannot run reports `unverified`, never `dead`.

- **Evidence tags and sampled ranges are schema properties, not conventions.** Every emitted claim
  carries `measured` / `documented-default` / `inferred` / `no-upstream-row`, and every count that
  can move during a scan is emitted as `{min, max, n}` — there is no field a single averaged number
  could go in. A known-churning directory returning identical counts across fewer than three samples
  is flagged `unanimous_small_n_on_volatile_path`, because agreement within one moment on a dynamic
  system is a red flag rather than a confirmation.

- **Deliberate-state detection runs before any staleness verdict.** A revert ledger (`RESTORE.md`,
  `PLAYBOOK.md`, `restore*.py`, or a shallow `manifest.json` / baseline under `plugins/data/`)
  deny-lists its whole subtree — such a directory is frequently the *only* copy of somebody's revert
  path, and a prior audit's largest near-miss was a correct check run against a tree whose state was
  deliberate. The skill also records that a ledger's own summary is not authoritative and must be
  diffed against the stored baseline.

- **The CSV artifact is complete by construction.** `--csv` writes one row per file in the scan set
  — 86,653 rows for an 86,653-file install — and is the only artifact carrying per-file rows at
  all; `--authored-threshold` governs only which entries the JSON summary *labels* `per-file`
  rather than `rolled-up`. Driving the artifact off the JSON rollup instead produced
  a 169-row CSV for the same install (86,984 files at that instant; the tree is live and the total
  moved between runs) while the surrounding prose claimed completeness, so a test now
  pins `csv.rows == totals.files` and asserts a threshold of `0` does not shrink it. Omitting
  `--csv` reports `path: null` with a note that the run must not be described as covering every
  file.

- **Retention is resolved before any staleness claim, and an unparsable settings file is an
  error.** Upstream pauses the retention cleanup sweep entirely while `settings.json` fails to parse
  (unless managed settings supply `cleanupPeriodDays`), so a JSON syntax error is a retention outage,
  not a lint nit. The engine reports the effective window with its evidence tag, the sweep's own
  `.last-cleanup` watermark, and the plugin in-use sweep marker.

  The exception is measured rather than assumed: the paused-sweep finding is raised while reading
  `settings.json`, before managed settings have been looked at, so on an enterprise machine that
  supplies a valid `cleanupPeriodDays` it was left standing and told the reader that nothing is
  being swept and every staleness reading is suspect — when the exception named in its own claim
  applied. It is now withdrawn once managed settings are measured to supply a usable value; the
  parse failure itself stays on the record in `user_settings_parse`.

  `cleanupPeriodDays` is also validated rather than merely type-checked. `bool` is an `int` in
  Python, so `true` would have been read as a one-day window and `false` as a zero-day one, and a
  zero or negative value is below the documented minimum of one day — a negative window puts the
  retention cutoff in the *future* and marks effectively every swept file as past retention. A
  rejected value is reported as `invalid: <value>` in `user_setting_days` / `managed_setting_days`
  and the documented default stands.

- **An entry holding a secret-bearing file is classified by its contents, not by its own name.**
  Entry-level surfaces came from `SURFACE_TABLE` keyed on the top-level directory name alone.
  `ide/*.lock` is in the never-read list and every row under `ide/` was promoted to `secret`, but
  `ide` has no table row — so the entry line a reader scans first read `unclassified`, with the
  milder `unclassified-report-only` verdict, over rows that were all `secret`. A `secret` member
  now promotes its entry to `secret` (verdict `keep`) and the note carries the *count* of such
  files, so a mixed tree promoted by a couple of vendored `*.pem` bundles can be read against the
  entry's `files` field rather than assumed secret throughout.

- **The recent-writer cutoff is compared at the precision it is stored.** `FileRow.mtime` carries
  second precision while the cutoff carried microseconds; `.` (0x2E) sorts after `+` (0x2B), so a
  file written inside the window but during the cutoff second compared *lower* than the cutoff and
  was silently dropped from the behavioural-activity evidence. Same fix, and the same reason, as
  the rollup cutoff already applied.

### Changed

- **`plugin.json` now describes eight skills.** The description enumerates `audit-install-state`
  alongside the existing seven; `docs/CATALOG.md` regenerates from it.

## [0.28.6]

### Changed

- **Carries the shared hook library's new `hook::is_enabled` predicate.** `hook::check_enabled`
  exits the process when a plugin is gated off, which is correct for a hook but wrong for a
  caller that must keep running afterward. The resolution is now also available as a predicate
  that returns instead of exiting. No behaviour of this plugin changes; the version moves so
  consumers receive the updated library.

## [0.28.5]

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each dated claim below was re-checked against the complete raw markdown source of the page it cites (`https://code.claude.com/docs/en/<page>.md`), not a summarized fetch, and each was confirmed by a verbatim quote before its stamp was refreshed. No claim changed; only the verification dates moved.

  - `skills/observability/context/output-format.md` — Claude Code computing its own dollar figures
    from token counts at standard list rates, the basis for the fixed Token / cost caveat line
    (costs reference).

## [0.28.4]

### Changed

- **`skills/plugins`: an in-session `/plugin` install can now activate itself, and the reload
  guidance says why that does not apply here (#2176).** Claude Code 2.1.221 made the install summary
  report `Plugin is now active.` or `Run /reload-plugins to activate.`, where the second happens
  "because activating it would invalidate the prompt cache or because the activation attempt failed"
  (`code.claude.com/docs/en/discover-plugins`, fetched 2026-08-10); before that release "no install
  took effect in the current session until you ran `/reload-plugins` or restarted". Read naively, that
  reads like this skill's closing reload guidance is now over-cautious. It is not, and
  `context/scope-semantics.md` now records the reason rather than leaving a future reader to relax it:
  `sync` installs with the `claude plugin install` shell command, which "doesn't run in a session, so
  Claude Code loads the plugins it installs the next time you start Claude Code, or when you run
  `/reload-plugins` in a session that's already open". The activation line matters only when reading a
  user's own `/plugin` summary — and its prompt-cache branch is the same condition `--force` exists for.

## [0.28.3]

### Fixed

- **Shared `hook-utils.sh`: `hook::jq_fields` now REPORTS a NUL byte in a payload value
  (#2122).** 0.28.1 stopped a NUL from failing the helper's cardinality check, by stripping every
  NUL out of each value. That keeps the helper working, but stripping also silently rewrites the
  value — `--no-verify<NUL>x` arrives as `--no-verifyx` — so a caller that owns a block/allow
  verdict cannot tell a clean payload from one that carried a NUL, and matches against a token the
  payload never held contiguously. The fact is now reported in a new `HOOK_JQ_FIELDS_NUL` global,
  set on EVERY call including every failure path, so such a caller can fail closed on its own terms.
  It is computed from the values as the payload carried them, BEFORE the strip; strip first and the
  flag would read "0" on every payload. Values themselves are unchanged — still stripped, so a
  scanning caller still sees everything after the NUL. This plugin's own hooks do not consult the
  new global, so their behaviour is unchanged. Synced from `lib/hook-utils.sh`.

## [0.28.2]

### Fixed

- **Shared `hook-utils.sh`: `env -S` / `--split-string` no longer hides a whole command from the
  git guards (#2124).** `-S` exists so a shebang line can pass OPTIONS to env
  (`#!/usr/bin/env -S -i prog`), so the words it splits out are env's own arguments. The resolver
  spliced them back into the scan but resumed at the COMMAND dispatcher, which read a leading
  option in the split string as the command NAME and gave up — `env -S '-C <dir> git push --force'`
  resolved to no git at all, so every guard built on `hook::git_resolve_index` skipped the command
  unexamined. Parsing now resumes inside env's own option loop. That also keeps env's single chdir
  slot last-wins across the splice, so `env -C a -S '-C b git …'` reports `b`, matching GNU env.
  Synced from `lib/hook-utils.sh`.

## [0.28.1]

### Fixed

- **Shared `hook-utils.sh`: a NUL byte inside a payload value no longer makes `hook::jq_fields`
  come back empty (#2120).** The helper delimits its batched fields with NUL, and a JSON string may
  legitimately encode one — a `Write`/`Edit`/`NotebookEdit` content field can. jq emitted the raw
  byte, the read split that value in two, the cardinality check saw one value too many, and the
  helper returned non-zero — which every caller treats as "skip", so the hook exited without doing
  its work. Each value is now NUL-stripped INSIDE the jq filter, so the delimiter provably cannot
  occur in a value. Stripping is not a lesser alternative to an encoding scheme, it is the only
  representable behavior: a bash variable cannot hold a NUL byte, and the per-field command
  substitution this helper replaced dropped the byte and kept the rest of the value — so content
  AFTER a NUL is returned and scanned exactly as it was before the batching. Synced from
  `lib/hook-utils.sh`.

## [0.28.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.27.6]

### Fixed

- **`lanes`: the launch-commit marker is keyed in the repository it describes, so staleness
  detection survives a SHA-256 checkout (#1383).** `git hash-object` digests with the object format
  of whatever repository it resolves, and the launcher called it unscoped — keying on the CALLER's
  format while taking the toplevel from the repository `--repo` names. Reached from a SHA-1 working
  directory, a SHA-256 target produced a 40-character key, while `lanes/context/refresh.md`'s probe
  runs inside that checkout and computed the 64-character one: the launcher wrote its marker to a
  directory the probe never reads, and staleness detection was off with nothing to show for it. The
  comment above the key claimed both sides agreed because both call `git rev-parse --show-toplevel`,
  which settles the path and says nothing about the digest. Both digests are now taken with
  `-C "$REPO"`. `restart-consumer.sh` derived its ledger key the same unscoped way and is fixed with
  it; the hand-recompute snippets in the README, this changelog, and `refresh.md` already run inside
  the target repository and were correct as written.

- **`lanes`: a lane that sets an empty stop-gate marker disables that channel instead of falling
  through to the user's (#1865).** The option read ended `select(type == "string") ] | last //
  empty`, which prints nothing for an explicit `""` and nothing for an absent key — so the launcher
  could not tell the two apart, and dropped `--marker` for both. The arm record then carried no
  marker at all, and the gate's precedence (managed ▷ arm record ▷ user settings ▷ default) walked
  past it to the user-level marker, where a marker file left over from another lane can authorize a
  stop this lane never signaled. A `v:` prefix now carries "the lane set this" through the shell, so
  an explicit empty value reaches the helper. The sentinel is deliberately not symmetric: the gate
  substitutes the default token for an empty sentinel, so recording one would only shadow the
  user-level value without changing which token is matched.

- **`lanes`: the stop-gate arm id reaches only the autonomy installs that asked for it (#1865).**
  Arming keyed off an any-quantifier over the `autonomy` / `autonomy@*` namespace, then injected
  `lane_stop_gate_arm_id` into every entry in it — so one install requesting the gate had the id
  written into siblings that did not, and the option read likewise took its last match from any
  entry rather than a requesting one. The gate never treats this channel as a trusted verdict in
  either direction, so an id landing on an entry set to `false` was not overriding that `false`;
  what it did was mark installs the lane never asked to arm, leaving the settings handed to `claude`
  an inaccurate record of what was requested and letting a non-requesting entry's marker reach the
  arm call. One shared filter now defines "an entry that requested the gate", and detection, option
  extraction, and injection all use it. Arming every discovered helper script is unchanged and
  deliberate.

## [0.27.5]

### Fixed

- **README: the "copy the reference sink into your repo" wiring form now names its
  `hook-utils.sh` dependency.** The sink `source`s `hook-utils.sh` from its own directory, so the
  documented bare copy failed at startup (`No such file or directory`) — found dogfooding the
  wiring in the marketplace repo itself (#2021 line 5 disposition). The README now says to copy
  `hook-utils.sh` alongside or repoint the copy's `source` line.

## [0.27.4]

### Changed

- **`observability`'s report skeleton uses `<model>` placeholders in its token/cost table.** The two
  sample rows carried real model IDs, which read as data rather than as a template and date the
  skeleton as models turn over. They now match the `<model>` convention the Cache health table
  immediately below already used.

## [0.27.3]

### Changed

- **Shared `hook-utils.sh`: a hook invocation spawns three fewer external processes (#1978).**
  Every hook that buffers its stdin paid an `awk` (one float division, to slice the read timeout), a
  `printf | tr -d '\r'` pipeline (a fork and an exec to delete one byte class from a string bash
  rewrites in place), and a `jq -e .` validity probe over a buffer the read loop had already parsed
  with jq. On Windows Git Bash, where process creation is `fork()` emulation, each spawn costs
  ~140 ms. Behavior is unchanged: the slice keeps the three-decimal form `read -t` is given, the
  buffer is CR-stripped as before, and the completeness verdict is reused only when jq itself
  produced it — so a host without jq still fails open exactly as it did. Also adds
  `hook::jq_fields`, which extracts several fields from one payload in a single jq process for
  hooks that read two or three of them. Synced from `lib/hook-utils.sh`.

## [0.27.2]

### Fixed

- **`plugins` no longer treats `$HOME` as project context when the shell and the OS spell it
  differently.** The exclusion that keeps `$HOME` out of project scope compared `pwd -W`'s native
  path against `$HOME` exactly as the environment carried it. Those are the same directory in two
  spellings, and an MSYS mount alias carries no drive letter for the normalizer to reconcile, so
  `/tmp/x` never matched the `C:/…` reported for it — the exclusion silently failed and
  `$HOME/.claude/settings.json` was read as the project map, duplicating the user map. Both sides
  are now spelled by the same command before they are compared. Normalizing harder could not have
  fixed it: the two inputs disagreed before the normalizer saw them.

  Both spellings go through `builtin cd` / `builtin pwd`, extending the shadow discipline the
  script already applies to its own directory resolution. An exported `cd` that returns success
  without moving would otherwise resolve `$HOME` to the cwd, collapsing every corroborated non-git
  project onto `$HOME` and stripping its project settings — the inverse failure, and a worse one.

## [0.27.1]

### Changed

- **`observability` marks the Token / cost dollar column as a list-rate estimate.** ccusage prices
  tokens at public per-token list rates while subscription usage is plan-priced, so the USD figures
  are an estimate, not a bill; [costs](https://code.claude.com/docs/en/costs.md) (verified
  2026-08-04) documents the same list-rate caveat for Claude Code's own locally computed figures.

### Fixed

- **`changelog` `status` no longer goes silent on the first release outside the CC 2.1 series.**
  The applied-versions scan grepped git log with patterns pinned to `v2\.1\.`, so a 2.2.x/3.x
  release would return nothing without erroring. The scan now matches any
  `CC v<major>.<minor>.<patch>` (`-E --grep="CC v[0-9]+\.[0-9]+\.[0-9]+"`), semantics otherwise
  unchanged; a skill-wide sweep confirmed no other file carries the series pin — remaining
  `v2.1.x` literals are illustrative examples.
- **`changelog` fetch steps target the raw-markdown channel (`docs/en/changelog.md`), not the
  rendered HTML page.** The `.md` sibling is the smaller, chrome-free channel — 514,578 B against
  the rendered page's 2,696,671 B (~5x), measured 2026-08-04 — and both carry the same 355
  releases. It buys no extra version depth: WebFetch truncates **both** channels identically, to
  the same 32 most-recent versions with a `[Content truncated due to length...]` marker, because
  its budget applies after HTML-to-markdown conversion. Reaching a deep version needs a
  range-scoped fetch or a direct `curl`, on either channel. Every fetch-source reference in the
  skill now points at the `.md` URL.
- **`lanes` no longer skips a lane whose effort is `ultracode`.** The launcher validated
  `lanes[].effort` against `low|medium|high|xhigh|max`, so `ultracode` — a documented
  `claude --effort` value since CC 2.1.203 (verified 2026-08-04 against
  [model-config](https://code.claude.com/docs/en/model-config#adjust-effort-level)) — made the
  lane silently unlaunchable. The valid set now includes it, gated on the installed
  `claude --version` meeting that floor: below it the CLI rejects the value outright (`Unknown
  --effort value 'ultracode'`) and starts the session at the default effort, so the launcher skips
  the lane rather than launching it at an unintended effort. That check runs in the shared
  launch-input preflight, which `restart` already performs BEFORE stopping — so a lane the gate
  refuses keeps running rather than being taken down and left down. The whole run shares one
  `claude --version` probe, and `--dry-run` keeps working with no CLI installed (the exemption
  `require_claude` documents): with no binary to probe, the preview reports the gate unevaluated
  instead of refusing a lane a real run may well launch.

## [0.27.0]

### Added

- **`observability` reports cache health, the one cost signal its store already carried and its
  report never rendered.** `cc_metrics` has always split `claude_code.token.usage` by `attr_type`
  into `input` / `output` / `cacheRead` / `cacheCreation`, and `read-routing.md` has always pointed
  historical token metrics at the query file — but no report section rendered the cache half, so it
  reached an operator only if they went looking for it by hand. The skeleton now carries a **Cache
  health** section and the routing table a question keyed to it, with the reading upstream supplies:
  a high read-to-creation ratio is healthy, and creation staying high turn after turn means
  something keeps changing the request prefix ([actions that invalidate the
  cache](https://code.claude.com/docs/en/prompt-caching#actions-that-invalidate-the-cache),
  verified 2026-08-04).

  **Its own section rather than columns on Token / cost**, because the two differ in both source and
  grain. Token / cost is ccusage-sourced per-model over a window; the cache split lives in the OTEL
  store, and the pre-existing token-usage query is latest-session-scoped with no model dimension.
  Widening that table would have mixed two sources silently and rendered a per-model row from
  session-grain data. So this ships a **new per-model windowed query** rather than reusing the
  existing one — verified by execution against a live OTEL store, not composed from the schema.

  **Hot tier only, for a reason worth recording:** `cc_metrics_cold()` raises `IO Error: No files
  found that match the pattern …` when the cold tier holds no parquet yet, so a hot+cold union
  would break on any store that has not aged. The query file now says so where the union pattern
  is documented.

  **Reported at `INFO`, deliberately ungraded.** Every other numeric signal in this skill carries a
  severity band, and this one does not: upstream states the direction without a threshold, so a
  `HIGH`/`MEDIUM` cutoff would be a number this repo invented and then cited as if sourced. That
  rule sits in Rendering rules, outside the skeleton's fence — a directive placed inside it would
  be emitted verbatim into the operator's report. The invalidation causes stay behind the pointer
  rather than being enumerated into a list that drifts as the harness adds actions.

## [0.26.0]

### Changed

- **`lane-launcher.sh` arms the autonomy lane-stop gate at launch — fail closed (#1784).** The
  gate (autonomy 0.12.0+) no longer honors the bare `CLAUDE_PLUGIN_OPTION_*` environment, which is
  the only form a `--settings`-delivered option ever reaches a hook in — so passing
  `lane_stop_gate_enabled` through the lane's `settings` object alone would leave the lane silently
  ungated. A lane whose settings request the gate
  (`pluginConfigs["autonomy[@…]"].options.lane_stop_gate_enabled == true`) is now ARMED before
  launch: the launcher generates a random arm id, runs the autonomy plugin's
  `hooks/lane-stop-gate-arm.sh` (which records the lane's sentinel/marker config under autonomy's
  own install-derived data directory), and injects the id into the launched `--settings` as
  `lane_stop_gate_arm_id`. A gate-requesting lane that cannot be armed — helper missing (autonomy
  not installed or pre-0.12.0), arming error, managed-settings veto — is **skipped with an error**
  rather than launched ungated: the operator is present at launch, so failing closed there is
  cheap, while the hook itself stays fail-open at stop time. Helper discovery anchors on the
  launcher's own `plugins/cache` install path (never `CLAUDE_CONFIG_DIR`/`HOME`, which a watched
  repo's `env` block reaches — exactly the redirect this design closes); the new
  `--gate-arm-script FILE` flag overrides discovery for tests and dev checkouts. `--dry-run`
  previews the arming without writing anything. Lanes without a gate request launch exactly as
  before.

  On a machine carrying more than one autonomy install, **every** discovered helper must arm or
  the lane is skipped. Each install writes into its own install-derived store and the launcher
  cannot tell which one the session will load, so accepting a partial arm would launch a lane
  carrying an id its own gate resolves to nothing — ungated, with only a stale-arm notice to show
  for it. The preflight that checks helper presence reads discovery through a command substitution
  rather than `… | grep -q .`: under `pipefail` the `grep` exits on the first line and the producer
  takes SIGPIPE on its next write, so exactly those multi-install machines would read as "no helper
  found" and be refused a gate-requesting launch outright.

## [0.25.1]

### Changed

- **The `@path`-as-body rule now records that an inlined upsert enforces it mechanically, not on
  trust — and corrects which consumer the failure actually deceives (#943).** The rule's closing
  paragraph claimed the prose was "the only thing standing between" an inlined upsert and a silent
  observability fail-open. That is no longer true: every lane that inlines the `gh api` upsert —
  `source-control:babysit-loop`, `work-items:work-loop`, `work-items:attend-queue` — now carries three
  checks in its own block: a pre-write body gate, a check of the write's own exit status, and a
  post-write read-back of what the write stored. The paragraph states which guarantees travel inline
  (those three) and which do not: the 64 KiB cap, the body-file containment checks, retries, and this
  script's distinct non-zero exit codes — an inline branch always exits 0 and reports through stderr,
  so a caller cannot detect a failed cycle from its exit status. It also names the limits an inline
  block inherits rather than fixes: a PATCH that succeeds while storing the previous body still
  verifies, and the read-back proves *some* well-formed telemetry is present, not *this* cycle's.
- **Corrected: `morning-brief` is not the check a degraded telemetry body deceives.** The rule said a
  freshness check "passes over a blind lane". Verified against `morning-brief.sh`'s `print_telemetry`:
  it parses `lane:` and `last-cycle:` out of the comment BODY, so an `@path` body carries no `lane:`
  field and the lane disappears from the report entirely rather than reading as healthy. What a
  degraded body deceives is any consumer keying on the comment's timestamp instead of its body — the
  timestamp moves on every successful write regardless of content. The rule now attributes the
  failure that way rather than naming a sibling reader that would in fact surface it.

### Fixed

- **`lanes`: a lane field whose JSON value is `false` is no longer read as an absent field (#1784).**
  Both field readers in `lane-launcher.sh` used jq's `//` alternative operator, which fires on every
  FALSY value rather than on absence. A lane configured `"settings": false` therefore yielded
  `empty`, reached bash as `""`, and — because `validate_launch_inputs` guards its "settings must be
  a JSON object" check on `[[ -n "$settings" ]]` — that type check never ran at all: the lane launched
  with `--settings` silently omitted, no error, nothing for the operator to see. `lane_json_field` now
  tests presence with `has`, so `false` reaches the type check and the lane is skipped with the error
  that was already written for it. The scalar reader had the same collapse for `name`/`model`/
  `effort`/`prompt` (a mistyped `"effort": false` launched a lane with no effort), so those fields are
  now typed once at config time and a non-string value is a config error alongside the existing
  duplicate-name and path-traversal checks. An explicit `null` stays the JSON spelling of "no value"
  and remains equivalent to an absent field in both readers.

## [0.25.0]

### Changed

- **`telemetry-upsert.sh` accepts the writer-identity marker suffix (#1295).** The marker charset
  gains `@`, so a marker can name one *writer* (`<lane>@<instance>`) rather than a lane type — the
  loop-lane convention's fix for concurrent instances of one lane sharing, and clobbering, a single
  telemetry comment. This script is that convention's interim home, so a marker shape its validator
  rejected would have left the contract and its executable owner disagreeing. `@` is added to
  **both** lookaround classes in the two-tier detection's fallback as well, for exactly the reason
  `-` is already in them: without it, `lane:x` matches inside `lane:x@laptop-a` and would adopt that
  instance's comment — the boundary rule one level down from the `lane:triage` /
  `lane:triage-old` prefix collision it already guards. Two cases cover the new boundary in both
  directions, plus one asserting a suffixed marker validates at all.

### Fixed

- **`restart-consumer.sh` would have gone silently blind on suffixed markers.** Its per-lane
  `telemetry.marker` binding matched a comment by exact marker equality, so once lanes carry
  `<marker>@<instance>` no bound lane's comment would match — the consumer would report `no-state`
  forever and restart nothing, the worst failure shape for an unattended relaunch trigger. A bound
  marker now names a lane **type** and matches every writer instance of it, with the same trailing
  boundary that keeps `work-items:work-loop` from adopting `work-items:work-loop-v2`. A new optional
  `telemetry.instance` key pins one instance, as does writing the suffix into `marker` itself. The
  scan also no longer stops at the first matching comment when that comment is not asking: with
  several instances writing to one issue, a quiet sibling appearing first would otherwise mask a
  later instance's live restart request. What an unpinned binding does with a suffixed writer's
  request is *report* it: the run records `unbound-instance` naming the asking writer and
  relaunches nothing, because an instance-suffixed comment is some machine's writer and consuming
  it unpinned would relaunch the locally configured lane on **every** stopped consumer sharing the
  issue — sibling instances started by a request none of them owns. Only the pinned instance's
  comment, or the legacy un-suffixed one, is actionable.

## [0.24.4]

### Fixed

- **`lanes` and `observability` load again when invoked from a worktree-isolated agent (#1687).**
  Four `## Pre-computed context` lines carried genuine shell expansion — `lanes` line 16's
  `$(claude --version)` and line 19's `$c` / `${CLAUDE_OPS_LANES_CONFIG:-…}` / `$(git rev-parse …)`,
  `observability` line 19's `$f` / `$(…)` and line 21's `$d` / `${CC_OTEL_STORE:-…}`. The harness
  composes that whole block into one shell invocation, and the worktree-isolation Bash guard refuses
  any `$`-expansion, so the block failed and the skill never loaded. `lanes` line 16 is now the
  `$`-free `claude --version 2>/dev/null || echo "MISSING (required)"`; the other three hoist their
  logic into two bundled scripts — `skills/lanes/scripts/probe-lane-config.sh` and
  `skills/observability/scripts/probe-observability-state.sh` (`--hook-events` / `--otel-store`) —
  invoked through `${CLAUDE_PLUGIN_ROOT}`, which the harness substitutes into a literal path before
  any shell sees it, so the replacement lines carry no `$` at all. Path resolution, env overrides
  (`CLAUDE_OPS_LANES_CONFIG`, `CC_OTEL_STORE`), and every output string are unchanged and covered by
  equivalence tests that diff each script against the line it replaced. **One output shape did
  change:** the `claude CLI:` line now reads `2.1.220 (Claude Code)` rather than
  `present (2.1.220 (Claude Code))` — same information, no `present (…)` wrapper. `observability`
  line 20 (`OTEL collector :4318`) was already plugin-variable-only and is untouched.

## [0.24.3]

### Fixed

- **`plugins` skill: `sync` Step 1 no longer claims to self-heal, and states what to do when the
  refresh fails (#1764, F1).** `claude plugin marketplace update` is known to fail against an
  existing non-empty marketplace directory
  ([anthropics/claude-code#76129](https://github.com/anthropics/claude-code/issues/76129), open),
  and Step 1 documented no behavior at all on a non-zero exit in single/default mode — only `all`
  mode and Step 3 had inline-failure prose. Step 1 now says the refresh is attempted rather than
  guaranteed, cites the upstream bug, and directs a failure to "Action needed" with the catalog
  reported as possibly stale instead of current. Catalog-dependent mutations (Step 4 installs,
  Step 5 enable-state) are deferred for that marketplace until a run where the refresh succeeds —
  stale catalog metadata must not drive installs or enables. Cache surgery stays out of scope; the
  named staleness diagnostic is `git ls-remote origin HEAD` against the local `HEAD` (genuinely
  read-only — a plain `git fetch` writes `FETCH_HEAD`, remote-tracking refs, and objects).
- **`plugins` skill: `sync` now says where the report's `<old> → <new>` versions come from (#1764,
  F3).** The report format mandated a per-plugin version pair that no step instructed capturing.
  A new "Version capture for the report" section fixes three sources in precedence order — `<old>`
  from the pre-mutation snapshot the Concurrency section already requires, `<new>` from the update
  call's own output, and a post-sweep re-read as fallback — and forbids synthesizing a value.
  The fallback is explicitly second because `claude plugin update`'s help says "restart required to
  apply" and this skill has not established when the CLI writes `installed_plugins.json`; if that
  write is deferred, a post-sweep re-read would report no change for a plugin that did update.
- **`plugins` skill: the TOCTOU gotcha now covers catalog content, not just installed/enabled state
  (#1764, F2).** A refresh landing mid-session rewrites the catalog, so two reads within one session
  can legitimately disagree on plugin count — which is why diffing `fleet-state.sh`'s catalog
  against a separately-read raw `marketplace.json` is not a valid staleness check, and why a
  mismatch is not evidence of an enumeration bug.
- **`fleet-state.sh`: a non-git working directory no longer manufactures project context (#1764,
  F4).** `PROJECT_ROOT` fell through to bare `$PWD` whenever `CLAUDE_PROJECT_DIR` was unset and cwd
  was not a git tree, so the "project" settings read became whatever `.claude/settings.json` sat
  under cwd — in `$HOME`, the user settings file itself — and an install record whose `projectPath`
  equalled that directory would be promoted to `currentProject: true`. Project context now resolves
  from `CLAUDE_PROJECT_DIR`, a real git toplevel, or — because Claude Code does not require a
  repo — a non-git cwd corroborated by its own `.claude` directory, with `$HOME` always excluded
  (its `.claude` is user scope); an uncorroborated cwd stays an empty root, and the downstream
  reads were already guarded for it.
- **`plugins` skill: the action-router table reads as an index again (#1764, F5).** The `sync` row's
  Description spelled out the full six-step chain, complete enough that a session could execute the
  action without opening `context/sync.md` — which is how F1's and F3's gaps went unnoticed during a
  live run. Descriptions now name territory only, above an explicit instruction to read the linked
  detail file before executing.

## [0.24.2]

### Fixed

- **Shared `hook-utils.sh`: the OS temp tree is no longer treated as project content (#1769).**
  `hook::read_file_path` scoped a file to the project by prefix-matching `CLAUDE_PROJECT_DIR`, so a
  session whose project directory is the user's home admitted everything under the OS temp root —
  including Claude Code's own per-session scratchpad, which lives there. Hooks that lint, rewrite, or
  autocorrect then ran on throwaway files that are not project content and carry no project config to
  opt out with; the reported case was `typos-format` autocorrecting a shell variable in a scratch
  script and silently breaking it. The guard now rejects a file inside the OS temp tree when the
  project root is outside it. The exemption is deliberate and load-bearing: when the project root
  itself lives under temp — a `mktemp -d` fixture checkout, which is how this repository's own hook
  suites run — its files are still accepted. Temp roots come from `TMPDIR` / `TMP` / `TEMP` plus the
  POSIX defaults, canonicalized through the same pipeline the membership comparison already uses.
  Synced from `lib/hook-utils.sh`.

## [0.24.1]

### Fixed

- **Shared `hook-utils.sh`: a wrapper's working-directory change is no longer lost when a caller
  parses only git's own global options (#1503).** `hook::git_resolve_index` walks wrapper programs
  (`env`, `sudo`, …) to reach the real `git` token, and a caller that scopes its git-global parsing
  to the slice starting at that token cannot see a relocation the wrapper already performed — GNU env
  documents `-C, --chdir=DIR` as "change working directory to DIR". The resolver now reports those
  directories in a new `HOOK_GIT_RESOLVED_WRAPPER_DIRS` result global, in execution order, so a
  caller composes them ahead of git's own globals instead of dropping them. Five spellings are read
  (`-C DIR`, `-CDIR`, `--chdir DIR`, `--chdir=DIR`, and a clustered `-vC DIR`), a repeat within one
  `env` is last-wins as env itself resolves it, and sudo's `-D`/`--chdir` is read in its unclustered
  spellings. A chdir spelled inside `-S`/`--split-string` is NOT read; that path already fails open
  for any command on `main` and is tracked in #1814. This plugin does not consume the new global; the sync keeps its copy
  byte-identical with the source. Synced from `lib/hook-utils.sh`.

## [0.24.0]

### Added

- **`morning-brief` reports findings stranded on merged pull requests (#1777).** A review that lands
  *after* a merge had nowhere to go: the ruleset's `required_review_thread_resolution` is a
  merge-time predicate that already passed, the babysit lane works only *open* pull requests, and
  nothing on a merged pull request surfaces its open threads. Six findings — one P1 — posted 46
  seconds after #1720 merged sat unread for a day, and were found only because a later session
  happened to audit the merge batch.

  The new section compares each unresolved thread's first-comment timestamp against the pull
  request's `mergedAt`, so it reports **only** threads that could never have been seen by the gate;
  a thread predating the merge is an ordinary unresolved thread and is excluded. Findings are
  collapsed to one line per pull request at that pull request's **worst** severity with a count, so
  a P0 beside advisory findings can never be softened, and one noisy pull request cannot bury the
  rest. The window is `--stranded-days` (default 3), wide enough to cover both slow bot review and
  an operator-absent weekend.

  Run against this repository on its first live invocation, it immediately surfaced four further
  stranded findings on other merged pull requests, including a P1 recording that a shipped plugin
  cell never reached installations — so this is a standing leak, not a one-off.

  Severity is read from the **structured marker only** — the badge alt-text, the shields badge URL,
  or a leading bracket — never from body prose. A body-wide substring test falsely promotes a P2
  titled "Preserve P1 labels", and any finding that merely discusses `CRITICAL` or `SECURITY`.
  Ranking is numeric rather than lexicographic, because `"--"` sorts before `"P0"` as a string: an
  unclassified thread sitting beside a genuine P0 would otherwise collapse the pull request to
  `[--]` and hide it.

  A thread connection that **truncates** is reported as a partial read. `--paginate` follows only
  the outer cursor, so a pull request with more than 100 review threads would be silently cut short
  — and a partial read that renders as an all-clear is the same failure the section exists to catch.

  The section **fails loud rather than clear**. A GraphQL error document is well-formed JSON that
  simply carries no `data`, so an unread API would otherwise extract to an empty list and render as
  "every merged PR in the window is clear" — an all-clear asserted from an answer never received,
  which is the same fail-open shape the section exists to catch. Caught during development when a
  rate-limit error did exactly that; an API error now says explicitly that it is not an all-clear
  and prints the message.

## [0.23.2]

### Fixed

Six review findings raised on #1720 forty-six seconds *after* it merged, so they were never triaged
(#1759). All are in `lanes/scripts/restart-consumer.sh`.

- **A broken lock store reported as a held lock.** An ignored `mkdir` failure fell through to the
  contention branch: the absent stamp read as zero and the run reported `lock-held` with exit 0. An
  unattended consumer with a mistyped path, a permissions problem, or an unavailable volume would
  **never process a lane while Task Scheduler recorded successful ticks**. `acquire_lock` now
  separates "the store is unusable" (exit 4, loud) from "another run holds it" (exit 0, routine).
- **A lock reclaimed on age alone.** A legitimate run outliving the one-hour bound had its live lock
  removed, letting a second run enter the relaunch span concurrently — reachable because
  `lane-launcher.sh` performs an unbounded `git pull --ff-only` and marketplace update before launch.
  The holder now records an owner PID, and age only gates *when to ask*; liveness decides.
- **Offline telemetry parse failures swallowed.** An unconditional `return 0` after the fixture-read
  `jq` turned a missing, unreadable, or malformed `--telemetry-json` into a successful empty read,
  reported as `no-state` — indistinguishable from "the lane did not ask". The offline branch now
  carries the same contract the network read already had.
- **An unwritable ledger reduced to a warning.** The breaker counts attempts by querying the ledger,
  so an attempt that could not be recorded was invisible to `--max-restarts`: a launcher that kept
  failing was retried on every polling tick forever. Writability is now proved *before* the relaunch,
  and a failed append fails the lane instead of warning past it.
- **Liveness read from a stale snapshot before mutating.** The session list is loaded once per run,
  so a lane started since — by a concurrent operator invocation — still read as stopped, and
  `lane-launcher.sh restart` *stops* a running lane before relaunching. A healthy session could be
  interrupted despite the documented "not currently running" predicate. The predicate is now
  rechecked against a fresh list immediately before the mutation.
- **A reused PID could masquerade as the lock owner.** `kill -0` proves only that *some* process
  holds that number — and after the reboot this reclaim path exists to handle, the number is very
  likely reused, which would wedge every later tick exactly as before. The lock now records a boot
  identity beside the PID: a lock from a previous boot is reclaimed regardless of who holds its PID
  now, and where no boot identity is available a live PID may only *defer* the reclaim, never defer
  it past a hard 24-hour ceiling.
- **The fresh liveness re-check failed open.** A transient `claude agents --json` failure made the
  `&&` condition false and fell through to the launcher on the stale snapshot — reintroducing the
  race the re-check exists to prevent. A failed re-read is now an error that skips the mutation.
- **A post-launch ledger failure was still invisible.** The pre-flight probe cannot cover storage
  that disappears *during* the launcher's unbounded work, so a relaunch could succeed while its
  breaker row silently failed to persist and later ticks restarted the lane again. The outcome
  append now fails the lane even when the restart itself worked.
- **`print-schedule` dropped behavior-affecting options.** A non-default `--config` or
  `--target-repo` was absent from the emitted schtasks, logon, cron, and offline forms, so the
  scheduled invocation silently fell back to `<repo>/.work/lanes.json` and the checkout's own
  repository — a different lane configuration and a different telemetry repository than the command
  that generated it. All four forms now carry them; a defaulted option is still omitted.

## [0.23.1]

### Changed

- **`morning-brief`/`observability` scripts annotated for the
  shell-portability-lint gate's newly-active `date -d` class (#1510).** The
  gate (#1491) began enforcing GNU `date -d` usage repo-wide; this plugin's
  `morning-brief.sh` `to_epoch`/`from_epoch` helpers and the
  `observability` skill's `clean.sh` cutoff-timestamp resolution are
  already-correct dual-dialect code (GNU `date -d` tried first, BSD
  fallback in an `else` branch or a separate statement) but not
  same-line-guardable, so each `date -d` call site now carries a
  `portability-ok:` annotation documenting why. No behavior change.

## [0.23.0]

### Added

- **`lanes consume-restarts` — the lane restart-request consumer (#1653).** A loop lane that
  hits its cycle budget or the `/loop` seven-day expiry writes a `restart_request` into its
  telemetry state block and stops; nothing consumed that field, so every budget or expiry hit
  was a terminal manual-restart state. `scripts/restart-consumer.sh` (new `consume-restarts`
  action on `/claude-ops:lanes`) reads each configured lane's telemetry and relaunches the
  stopped lanes that asked, through `lane-launcher.sh restart` — so each lane's prompt, model,
  effort, and settings (autonomy tier) come from the existing lane config. Meant to run
  unattended on an OS-owned schedule (Task Scheduler / cron): `print-schedule` emits the
  registration and removal commands; registering them stays an operator action. Guardrails: a
  telemetry comment is a signal, never a target (only operator-configured lanes can be
  relaunched; nothing from a comment is interpolated into a command); a per-lane circuit
  breaker (default 3 restarts per rolling 24 h) that **fails closed** — a run ledger that does
  not parse reports the budget as spent, with a warning, rather than silently restoring the
  full budget on exactly the file a crashed writer left behind; a not-currently-running
  predicate that makes the consumer self-clearing without editing another writer's comment;
  and an mkdir-atomic **cross-process lock** held across the whole read → decide → relaunch →
  append span. The lock is load-bearing rather than defensive: the emitted registration is two
  scheduled tasks (a poll and an `ONLOGON` companion) that both fire at logon, and Task
  Scheduler's instance policy is per task, so without it both runs read the same breaker count
  and one lane name ends up with two background sessions. A run that cannot take the lock
  skips cleanly (exit 0, `lock-held`); a lock left by a hard-killed run ages out. A telemetry
  read that ERRORS is its own `api-error` decision, never conflated with `no-state` ("the lane
  did not ask"). Observability: a JSONL run ledger under the plugin data dir recording
  incidents only — not the routine per-tick decisions, which on a 15-minute schedule would
  grow the breaker's own input by hundreds of rows a day forever — plus the consumer's own
  sentinel-marked telemetry comment in the `morning-brief.sh` format, posted by default to the
  issue that reader resolves (its own title search, reused), so a schedule that stops firing
  surfaces as a STALE lane in the morning brief. `check` is read-only in fact as well as in
  contract: it takes no lock and writes no ledger, which is what lets the documented Verify
  step tell a correctly-registered `run` schedule from a `check`-only one. Design record and
  labeled UNVERIFIED items: `skills/lanes/context/restart-consumer.md`.
  - **The circuit breaker bounds relaunch ATTEMPTS, not successes.** `restarted` and `failed`
    rows both spend budget. Counting only `restarted` left the breaker permanently closed on
    exactly the failure it exists for — a launcher that exits non-zero, or one that returns
    success while the background lane never appears (the UNVERIFIED Windows
    scheduler-spawn hazard this consumer confirms rather than trusts) — so every tick would
    re-attempt a pull, a marketplace refresh, and a launch, indefinitely. The pre-launch read
    failures (`error`, `api-error`) stay ledgered but uncounted: a transient forge outage must
    not spend a lane's restart budget.
  - **A failed issue lookup is an `api-error`, not a routine `no-telemetry` tick.**
    `resolve_issue_by_title` piped `gh issue list` into `jq`, so an unreachable or unauthorized
    forge became an empty result and read as "no issue carries this title" — an unattended
    consumer stayed apparently healthy while never observing that lane's request. It now
    returns non-zero on the list failure, and the caller records `api-error` and flags the run,
    matching what `lane_comment_bodies` already did for the comment read.
  - **The target repo resolves from the checkout directory.** `gh repo view` takes an
    `[<owner>/]<repo>` argument and parses a leading path segment as a HOST, so passing the
    absolute checkout path made the default (no `--target-repo`) path — the one every generated
    scheduled command uses — exit 4 before reading any request. The repo is now selected by
    running the command in `$REPO`.
  - **The published telemetry comment no longer carries the absolute ledger path.** A default
    data dir embeds the operator's home-directory user name and a `--data-dir` override can
    carry internal host or organization names, all of which the comment made as visible as the
    repository is. It now names the file relative to whatever data dir the reader's own machine
    resolves.

## [0.22.1]

### Fixed

- **Shared `hook-utils.sh`: a path spelled as a Windows 8.3 short name now canonicalizes to the
  same physical path as its long spelling (#1636).** `hook::physical_path` canonicalized with
  GNU realpath, which under Git Bash resolves symlinks but leaves 8.3 short names (`KYLESE~1`)
  unexpanded, so a short-form path — the shape Claude Code's own scratchpad paths take — read
  as a different path than its long form everywhere the canonicalizer's output is compared. The
  lib now expands short names on Windows/MSYS hosts (new `hook::expand_8dot3`, via `cygpath -l`)
  on the resolver's success path, and only when the expanded form actually differs — a
  legitimate long name containing `~` passes through untouched. 8.3 generation is a per-volume
  property (`fsutil 8dot3name query`), so the mismatch was live only on volumes that generate
  short names. For this plugin that means the path-membership validation in
  `claude-ops-paths.sh` no longer rejects an in-project path over its spelling, and
  `claude_ops::repo_slug` derives one slug per repository instead of a second, divergent slug
  for a short-form spelling of the same root. Synced from `lib/hook-utils.sh`.

## [0.22.0]

### Added

- **`lanes`: `telemetry-upsert.sh` refuses a degraded telemetry body before it writes it, then
  confirms what landed (#952).** The gate is pre-write: the caller's body is rejected with exit `3`,
  having made no API call at all, if it begins with a literal `@` or falls under a 16-byte floor.
  This guards the #943 defect class — a caller that composed an `@path` string as its body content,
  meaning the file, posts the literal path text, and because the comment's timestamp still moves the
  telemetry surface looks fresh while carrying no data, an observability fail-open no freshness check
  can see. Catching it before the `POST`/`PATCH` means nothing degraded is ever published to a public
  tracking issue, and there is no window in which a reader finds one. The wrapper's own plumbing
  cannot commit the mistake (it reads the body into a shell variable before any `gh` call), so the
  gate exists for the body TEXT a lane hands it. After the write the comment is re-read through a
  separate `GET` and the same assertions re-run against what a reader will actually find, plus the
  marker sentinel. That pass is scoped honestly: because the sent body was already cleared and the
  `GET` targets the id just written, it sees only what happened to that comment afterwards — a
  mangled store, a concurrent writer stripping the sentinel, a deletion — and a failure exits `6`
  naming the comment's URL. It cannot detect that detection resolved the wrong comment, and editing
  another user's comment is not its job either (that `PATCH` 403s and exits `5`). The create/update
  response echo is deliberately not trusted in place of the re-read: it proves the request was
  accepted, not what landed. An unreachable `GET` is retried once and then reports the cycle
  UNCONFIRMED rather than known-bad — a check that could not run is not a check that disagreed. It
  carries `gh`'s own error text (bounded) and branches its verdict on it: a `404` says the comment
  is NOT RETRIEVABLE — deleted, its issue deleted, or the token's read access lost — which rules out
  the "probably intact" reading that anything else (a `403`/`429` secondary rate limit) keeps. The
  retry is a network-blip guard only — it does not honor `Retry-After`, so a secondary rate limit
  outlasts both attempts by design. Capturing that error text is a diagnostic and never the thing
  that fails a good write: an unwritable `TMPDIR` degrades to no capture rather than turning exit
  `0` into exit `6`. One limitation is stated rather than papered over — the read-back asserts
  properties, not that the body changed, so a PATCH that silently no-ops still verifies and a stale
  comment reads as a good cycle; freshness belongs to the reader (`morning-brief`), not here. There
  is no `--no-verify` opt-out; this script is driven by lane prompts, so an escape hatch would be
  reachable by the same caller the gate exists to catch.
- **`lanes` doctrine: the `@path`-as-body anti-pattern is stated once, in the skill.** Telemetry and
  comment bodies are passed as file contents or piped, never as an `@path` string interpolated into
  a body value: `gh issue comment --body @path` and `gh api -f body=@path` send the literal text.
  Reading from a file takes `gh issue comment --body-file`, or `gh api -F`/`--field key=@path` —
  `gh api` has no `--body-file` flag at all. The rule covers the `gh api` upsert a lane inlines as
  well as the wrapper, because an installed plugin cannot invoke a sibling plugin's script and an
  inlined upsert carries none of the wrapper's body checks.

### Changed

- **`telemetry-upsert.sh` now rejects bodies it previously accepted (#952).** A body beginning with
  a literal `@`, or shorter than 16 bytes, exits `3` instead of being posted. Both shapes are the
  #943 fail-open rather than legitimate telemetry, so the rejection is the point — but a caller
  passing either today changes from a silent success to a hard failure. The `@` rule is positional,
  so a body whose FIRST line is a GitHub @mention is rejected too: lead with a telemetry key and put
  mentions on a later line. No in-repo caller is affected: nothing invokes the wrapper yet, by
  design (routing the operator loop-prompt through it is #943, out-of-repo).

### Fixed

- **`telemetry-upsert.sh` no longer exits `1` after a successful upsert whose API response carried
  no `html_url`.** The trailing `[[ -n "$html_url" ]] && printf …` was the script's last command, so
  its false branch became the exit status.

## [0.21.6]

### Fixed

- **Shared `hook-utils.sh`: a large tool payload no longer makes this plugin's hooks silently
  skip (#1563).** `hook::buffer_stdin` read the hook payload with `read -d ''`, which consumes a
  pipe one byte at a time (~32 KB/s on Git Bash), so the `stdin_read_timeout` bound was really a
  ~64 KB throughput ceiling rather than the stall detector it was written to be. Past that ceiling
  the read returned a truncated payload and rc 1, and this plugin's hooks took their `|| exit 0`
  branch — the hook did not run at all, with no diagnostic, on exactly the large writes it was
  most wanted for. The read is now chunked (`read -N`), which bash satisfies with block reads, and
  the bound became a true idle bound: `read -t` is a deadline for the whole requested read rather
  than an inactivity timer, so a timed-out read that nevertheless returned bytes is now treated as
  progress — its partial chunk is kept and a fresh window is armed. Only a window that delivers
  nothing at all is a stall. `read -N` is Bash 4.1+, and these hooks support Bash 3.2+ (macOS
  system bash), so the pre-4.1 path falls back to the delimiter read inside the same re-arming
  loop. Measured: 50 KB drops from ~2100 ms to ~20 ms, 200 KB from ~6800 ms to ~85 ms. Synced
  from `lib/hook-utils.sh`.
- **`skill-usage-expansion-audit` could hang on a large payload.** It read `expansion_type` with a
  jq here-string. Bash fills a here-string's pipe itself, so a payload at or above the pipe capacity
  (65536 bytes) blocks the hook forever before jq is exec'd. The bounded stdin read used to reject
  anything that large before it got here; now that it does not, the call goes through
  `printf | jq` instead. Reproduced on the shared library's own equivalent call: a 65536-byte buffer
  hung indefinitely while 65000 returned immediately.

### Changed

- **`stdin_read_timeout` is documented as the idle bound it now is.** This plugin already exposed
  the option, and its README and manifest description both described it as bounding "how long each
  hook waits for its payload before failing open" — a total read deadline. It is now an inactivity
  deadline: any byte resets it, so a producer that keeps emitting is bounded by Claude Code's own
  hook timeout rather than by this value, and the bound is read in four slices so a stall is detected
  within a quarter of the configured interval — except on a shell without fractional `read -t`
  (Bash 3.2, the macOS system shell), where the bound is read as one window and the detection can
  take up to two intervals. Documentation only — the configuration contract users
  read was materially misleading after the shared-library change above.

## [0.21.5]

### Fixed

- **`known-issues` contact links now point at the migrated documentation domain.** Anthropic moved
  the Claude Code docs from `docs.claude.com/en/docs/claude-code/<slug>` to
  `code.claude.com/docs/en/<slug>`; the three links in
  `skills/known-issues/context/issue-templates.md` still used the old host and survived only on a
  301. Each replacement was verified by fetching the old URL, observing the redirect, and
  confirming the target page's topic. The bare docs root does not redirect like the others (302 to
  `platform.claude.com`, then 307 to `code.claude.com/docs`), so it now points at the Overview
  page, which matches this repo's dominant `/docs/en/<slug>` convention.

## [0.21.4]

### Changed

- **Test scaffolding: migrated `mktemp -p` temp file/dir creation to the portable `mktemp "$DIR/template"` form.** BSD/macOS `mktemp` has no `-p` flag; the directory now rides in the positional TEMPLATE argument instead, which both GNU and BSD `mktemp` accept identically. Test-only — no hook behavior change. Part of #1527 (`claude-ops-test-helpers.sh`).

## [0.21.3]

### Fixed

- **Shared `hook-utils.sh`: a bare or trailing unquoted `NAME=value` Bash
  command no longer leaks the assignment value into the privacy-safe
  telemetry/audit subject.** `hook::extract_bash_subject` stripped a leading
  `VAR=value` prefix only when a following command word consumed it, so a
  command whose LAST token was an unquoted assignment (e.g. `TOKEN=ghp_…`)
  survived to the subject and emitted `Bash:TOKEN=ghp_…` into
  `hook-events.jsonl` and any wired `HOOK_TELEMETRY_SINK`. This plugin's
  `permission-denied-audit` and `tool-failure-audit` hooks compute their
  subject through this helper, so the leak was reachable here. A resolved token
  still shaped like a shell assignment now bails to the bare `Bash` subject,
  matching the existing quoted-value bail (`VAR=x cmd` still reduces to
  `Bash:cmd`). Synced from `lib/hook-utils.sh`; the subject is
  telemetry/audit-only, so no audit hook's outcome changes.

## [0.21.2]

### Fixed

- **`plugins` skill's `converge.md` no longer overstates when `uninstall` needs `-y`.** It claimed
  any non-TTY `uninstall` requires `-y` "by the CLI itself." Verified against the live CLI (2.1.220)
  and current docs: `-y` only skips `uninstall`'s `--prune` confirmation, and this action's
  `uninstall` calls never pass `--prune` — so `-y` was never warranted here and adding it would only
  ever bypass a different, unused prompt, not Step 3's per-plugin confirm (#1410).

## [0.21.1]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.
  The recipe also now requires the reinstall to re-supply **every** key whose value should
  stay non-default, not only the key being changed: uninstalling drops the stored
  `pluginConfigs` entry, so an omitted key silently falls back to its manifest default.
  Record the current values before uninstalling.

## [0.21.0]

### Added

- **`lanes` skill: `lane-launcher.sh` now captures and persists the launch commit
  (`#792`).** `context/refresh.md`'s git staleness probe referenced a
  `<lane-launch-commit>` placeholder with no producer — the repo HEAD when
  `lanes start`/`restart` last ran was advisory-only, with no automated way to
  retrieve it. `lane-launcher.sh` now captures `git rev-parse HEAD` right after
  the pre-launch pull (a pure read, so it also previews correctly under
  `--dry-run`) and writes it, for every lane actually (re)started that run, to
  `<data-dir>/lanes/<lane>-launch-commit` — a lane `start` skips as
  already-running keeps its existing marker untouched. New `--data-dir DIR`
  option (default: the `$CLAUDE_PLUGIN_DATA` env var if set, else
  `~/.claude/plugins/data/claude-ops`, matching `check-all.sh`'s convention).
  `SKILL.md`'s invocation now passes `--data-dir "${CLAUDE_PLUGIN_DATA}"`
  explicitly — per current
  [plugins-reference](https://code.claude.com/docs/en/plugins-reference#environment-variables),
  `CLAUDE_PLUGIN_DATA` is exported as a real env var only to hook/MCP/LSP
  subprocesses, not to a script a skill shells out to via the Bash tool, so a
  script-internal fallback alone would silently miss the marketplace-qualified
  data directory in a real session. The write is best-effort: a failure (or an
  unresolvable HEAD) warns on stderr but never fails an already-launched lane.
  `context/refresh.md` and `SKILL.md` now point the probe at the real marker
  file instead of the unfillable placeholder, with an explicit hex-only-input
  note for anyone who later sources the value from something other than `git
  rev-parse`, and a `tr -d '\r'` strip on the marker read (the repo's standing
  CRLF-hazard convention for any captured Windows value). New regression cases
  in `lane-launcher.test.sh` cover the capture/write, the
  skip-if-already-running case, `--dry-run` (preview only, no write),
  unresolvable-HEAD (best-effort, no failure), and the `$CLAUDE_PLUGIN_DATA`
  fallback.
  - The probe's `data_dir` is sourced from `SKILL.md`, which is the only surface
    where it resolves. Per
    [plugins-reference](https://code.claude.com/docs/en/plugins-reference#environment-variables),
    `${CLAUDE_PLUGIN_DATA}` substitutes inline in *skill and agent content* but is
    exported as a real environment variable only to hook and MCP/LSP subprocesses
    — and `context/refresh.md` is read raw rather than rendered as skill content.
    An env-var-with-fallback expression there would have silently resolved to the
    unqualified `~/.claude/plugins/data/claude-ops` guess, read no marker, and
    skipped the staleness check without saying so. `SKILL.md` now carries the
    substituted `data_dir=` assignment and `context/refresh.md` points at it.
  - A lane name is now validated as a single path component at config preflight
    (exit `3` on `/`, `\`, `.`, or `..`). The name is the marker's filename, so
    without that check two distinct configured lanes — `work` and
    `group/../work` — would share one marker file and a targeted restart of
    either would make the other's probe read a launch commit it never launched
    at. Rejecting rather than encoding keeps the documented
    `<data-dir>/lanes/<lane>-launch-commit` path literally true.
  - The marker path is namespaced by repo
    (`<data-dir>/lanes/<repo-key>/<lane>-launch-commit`). The data directory is
    plugin-wide but a lane name is only unique within one repo, so a
    conventional `work` lane in two checkouts would otherwise share a marker and
    each repo's probe would diff against the other's unrelated history — usually
    an invalid-revision error, at best a silently wrong answer. `<repo-key>` is
    `git hash-object` over `git rev-parse --show-toplevel`: a digest rather than
    a character fold, because folding collapses two real checkout paths like
    `/repos/foo-bar` and `/repos/foo/bar` onto one key, and git's canonical
    (symlink-resolved) toplevel rather than the `--repo` argument, because the
    documented probe asks git directly and both sides must land on the same key.
    Print the key for a checkout with
    `printf '%s' "$(git rev-parse --show-toplevel)" | git hash-object --stdin`.
  - A (re)start that cannot record its own commit (unresolvable HEAD, or a failed
    write) now removes any marker the previous launch left. Leaving it made the
    probe treat that older commit as the new session's launch point and report
    already-consumed merges indefinitely; removing it degrades the probe to its
    honest "no marker → skip" branch. `--dry-run` still touches nothing.

## [0.20.0]

### Added

- **`lanes`: per-lane `settings` passthrough, wiring the autonomy lane-stop gate into the shipped
  launch flow (#535 review follow-up).** The autonomy plugin's `Stop`-hook lane-stop gate is
  default-OFF and documents a per-session opt-in via `claude --settings`, but the lane launcher —
  the repository's shipped standing-lane flow — built only `claude --bg -n … [--model] [--effort]`
  and never supplied that override, so no launched lane ever received the gate or its operator
  notification. The lane config now takes an optional per-lane `settings` JSON object that the
  launcher passes verbatim as `--settings` (session-only, never persisted) on `start`/`restart`,
  validated as an object at preflight so a malformed value skips the lane instead of failing the
  launch with an opaque CLI error. Generic by design: any session-only settings override rides the
  same field; the gate opt-in (`pluginConfigs` → `autonomy@<marketplace>` → `options`) is the
  motivating example documented in `context/config.md`.

## [0.19.3]

### Fixed

- **`plugins` skill: `fleet-state.sh` no longer crashes with `Argument list too long` against a
  large-catalog marketplace (`#1336`).** Every `jq --argjson <name> "$value"` call site carrying a
  catalog/installed/enabled-scale JSON payload embedded that value as a literal command-line
  argument; for a marketplace catalog large enough (confirmed against a real 273-plugin catalog,
  reproduced here with a synthetic 500-plugin fixture), the serialized JSON exceeded the
  platform/shell's argv-length ceiling and `jq` failed before emitting anything — silently dropping
  that marketplace from `sync`/`audit`/`converge`. Confirmed on Windows Git Bash/MSYS `jq`, but the
  underlying argv-length ceiling is a real limit on every platform, just reached sooner there.
  Every affected call site now routes its payload through a temp file via `jq --slurpfile` instead
  of `--argjson`, so catalog size never determines whether a marketplace can be synced. Only the
  fixed-size boolean `--argjson` uses (`au`/`ci`/`autoUpdate`) remain untouched. Covered by a new
  large-catalog case in `fleet-state.test.sh` (asserts no argv-length crash and full,
  non-truncated output) plus a static guard locking the remaining `--argjson` count to booleans
  only.
  - Temp files created for `--slurpfile` routing live in one per-run directory removed by an EXIT
    trap; each call site invokes the writer inside a `$(...)` subshell, so files are not tracked in
    an array (a subshell-local append would vanish on return) — the whole directory is the cleanup
    unit instead.
  - A malformed source file (e.g. `settings.json`) used to make the affected `--argjson` fail loud
    immediately; `--slurpfile` instead tolerates a genuinely empty payload as "zero JSON values"
    and would have silently degraded the report to `null` fields. The writer now emits a
    deliberately-invalid token for an empty payload so jq's own parser still errors at the call
    site, preserving the prior fail-loud behavior. Covered by a new malformed-`user_settings.json`
    case in `fleet-state.test.sh`.

## [0.19.2]

### Documentation

- `hooks/claude-ops-test-helpers.sh` now points at
  `docs/conventions/shell-test-helpers/README.md`, the repo's owner doc recording that per-plugin
  shell assert-helper duplication and per-script exit-code taxonomies are deliberate, not drift. No
  behavior change.

## [0.19.1]

### Fixed

- **`plugins` skill: the default (no-`--marketplace`) path no longer breaks after a mid-session
  version bump of claude-ops itself (`#1176`, audit finding F1).** `fleet-state.sh`'s
  `resolve_default_marketplace` exact-matched the running plugin root against the version-pinned
  `installPath` in `installed_plugins.json`; any time the session's loaded version differed from the
  installed one — a marketplace `autoUpdate` shortly after session start, or `sync`'s own Step-3
  self-update — the join found nothing and the skill's primary invocation form failed with "could not
  resolve the default marketplace". Added a version-agnostic fallback that matches the version-stripped
  `…/cache/<marketplace>/<plugin>` prefix (exact match still tried first; marketplace stays
  distinguishable), plus a clearer error that prints the searched root and names the version-skew cause.
  Covered by a new version-skew case in `fleet-state.test.sh`.

### Changed

- **`context/gotchas.md`: generalized the CRLF gotcha (audit finding F2).** The trailing-`\r` hazard
  is not `jq`-only — any captured Windows value (`python` `print`, PowerShell interop, `git config`,
  a CRLF file read) can corrupt a constructed `claude plugin` id so the CLI reports
  `Plugin "<name>" not found` with the full id passed (marketplace suffix silently corrupted). Rescoped
  the entry to "any captured value", documented the collision with the bare-name symptom, and
  cross-referenced the two.
- **`plugins` SKILL.md: corrected the `install_new` render contract (audit finding F3).** An unset
  `${user_config.install_new}` renders the literal placeholder (the manifest `default` is not
  substituted for an unset key; verified against CC 2.1.218) — the common default-config case. The doc
  now reads that literal placeholder as the expected unset state → use the default `ask` without
  flagging it as an invalid value; only an explicitly-set unsupported value is the invalid case.

## [0.19.0]

### Added

- **`skill_usage_scope` userConfig — the skill-usage store's home is now scope-selectable
  (`repo` | `user` | `data-dir`), and the repo scope keeps `git status` clean via a
  machine-local `.git/info/exclude` entry (`#1151`).** Previously the store was forced into
  every consuming repo's tree (`.claude/observability/skill-usage.jsonl` as untracked
  `git status` noise) and the `skill_usage_dir` containment validation made user/machine
  scope unreachable by config — containment as a ceiling instead of a default. Now: `repo`
  (default, unchanged location) resolves the contained `skill_usage_dir` subpath under the
  repo root and idempotently adds the store dir to `.git/info/exclude` (machine-local; never
  `.gitignore` or tracked files; tracked content is unaffected by ignore semantics; opt out
  with the new `skill_usage_git_exclude=false` for teams that deliberately commit the
  telemetry); `user` resolves the same contained subpath under `$HOME` — one cross-repo
  operator store; `data-dir` writes `${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>` —
  plugin-owned, update-safe, keyed by repo. Unknown scope values fall back to `repo` with a
  one-time advisory (prose-validated; the manifest schema has no enum type). Store rows gain
  `project` (project-root basename, display) and `project_id` (basename + 8-char digest of
  the physical path — same-basename checkouts stay distinguishable) so cross-repo scopes
  keep repo identity; the data-dir key uses the same collision-resistant slug, and the
  exclude line is segment-normalized (a configured `./x` or `x//y` still matches) and
  glob-escaped (`*` `?` `[` in a configured dir write a literal exclude pattern, not a
  glob that over-matches sibling dirs). A `skill_usage_dir=.` (repo-root) store excludes
  the store file (`/skill-usage.jsonl`) rather than the whole tree.
  **Default-flip decision (recorded):** the default deliberately stays `repo` — the store
  sits beside `hook-events.jsonl` per the observability skill's project-local posture (that
  skill reads only `hook-events.jsonl` and the OTEL store, so colocation is convention, not
  a read dependency), the exclude entry removes the status noise that motivated the change,
  and flipping would silently relocate existing consumers' data.

## [0.18.3]

### Security

- **`plugins` fleet-state: hook-utils.sh is now resolved only from the script's
  own location, closing an arbitrary-file `source` via `FLEET_STATE_HOOK_UTILS`.**
  The test-only `FLEET_STATE_HOOK_UTILS` env override let any caller able to set
  an environment variable (a project `.claude/settings.json` env block, an
  inherited shell, another hook) redirect the `source` at an attacker-controlled
  file, executed with the script's ambient permissions — the existing guard only
  checked the path existed, not that it was trusted. `hook-utils.sh` is a fixed
  sibling shipped with the plugin, so it is now loaded unconditionally from the
  script-relative plugin root; the override was removed rather than gated because,
  once the path is script-relative, an override can only ever equal that trusted
  default (both test call sites already resolved to it). `CLAUDE_PLUGIN_ROOT` is
  no longer consulted for this sibling file (it equals the script-relative root
  in production); it is still used for marketplace self-resolution. The
  script-relative path is computed with `builtin cd`/`builtin pwd` and
  `command dirname` so an inherited environment that exports shell functions of
  those names (`BASH_FUNC_cd%%` and friends, imported by bash before the script
  runs) cannot hijack the computation and redirect `source` at an attacker tree.
  No behavior change in production.

## [0.18.2]

### Changed

- Sync of the shared `hook-utils.sh`: the git-option parser distinguishes `--config-env`
  (an env-var name) from `-c`/`--config` (an inline value), and a `--config-env` alias for
  a guarded subcommand is refused by shape rather than by resolving the environment
  variable's value (`#740`). No behavior change for this plugin — it does not inspect git
  config values; shipped so consumers receive the shared library update.

## [0.18.1]

### Changed

- **`lanes` skill — document that a relaunch is the only context reset a loop
  lane gets.** A `/loop` lane re-invokes in the same session and cannot `/clear`
  itself, so the "restart at ~N% context" discipline has no in-session
  enforcement; the skill's `restart` (fresh session from the canonical prompt) is
  the actual reset, and it is operator- or launcher-initiated, not automatic. The
  SKILL.md now states this so a lane prompt does not wrongly assume per-cycle
  freshness. Interim documentation ahead of an automatic relaunch trigger. (#551)

## [0.18.0]

### Added

- **`statusMessage` declared on every hook's `hooks.json` handler** (8 handlers)
  (hook-observability convention, `docs/conventions/hook-observability/`).

### Fixed

- **`skill-usage-audit` and `skill-usage-expansion-audit`'s config-invalid /
  destination-unwritable skip paths are now user-visible.** Previously
  agent-only (`additionalContext`), matching neither channel a missing
  runtime prerequisite requires per the doctrine. Both now route through
  `hook::emit_skip_notice` gated by `hook::notice_once` (once-per-session
  `systemMessage` + `additionalContext`).

## [0.17.4]

### Fixed

- **`morning-brief` test coverage gaps and `usage()` fragility.** Three non-blocking
  nits deferred from the PR #569 review: added a regression test for the
  `any=0` telemetry path (a non-empty comments array where none carry a `lane:`
  field), added a regression test for `--rec-maxlen 0` (full, untruncated
  RECOMMENDED preview), and replaced `usage()`'s hardcoded `sed -n '2,35p'` line
  range with a sentinel-based extraction (shebang to first blank line) so the
  header comment can grow or shrink without silently truncating or over-running
  `--help` output.

## [0.17.3]

### Changed

- **lanes: recorded why the mid-session staleness git probe is not `!`-injected.**
  Evaluated the lanes skill's git probes against the precompute convention (#864).
  The two `git rev-parse --show-toplevel` probes in `SKILL.md`'s front matter are
  already `!` dynamic-context injections (fallback + `shell: bash`), so nothing to
  convert there. The `context/refresh.md` staleness probe correctly stays a body
  instruction — it fails all four conditions: conditional (only when weighing a
  restart), needs a computed `<lane-launch-commit>` argument, and its `git fetch`
  is an unbounded network round-trip that mutates remote-tracking refs. Added that
  reason inline so a future reader does not re-litigate the decision.

## [0.17.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.17.1]

### Fixed

- **`install_new` userConfig had no `default` key.** SKILL.md's `plugins` skill renders
  `${user_config.install_new}` expecting Claude Code to substitute the configured value, falling
  back to `"ask"` when unset; with no declared default, the literal placeholder leaked through
  unrendered instead. Added `"default": "ask"` to the `install_new` entry in `plugin.json`,
  matching what the entry's own description already documented and the pattern every boolean
  option in the manifest already follows (e.g. `api_error_audit_enabled`).

## [0.17.0]

### Added

- **`lanes` skill — scripted two per-cycle lane mechanics that need no reasoning.**
  A `/loop` lane otherwise hand-assembles both every session; now the prompt
  references a script and the output is deterministic and testable.
  - **`machine-behavior.sh`** emits the MACHINE-BEHAVIOR block — gh identity, clone
    path, worktree inventory (root + count + per-worktree branch), and installed
    plugin versions — as a verbatim-printable text block. It emits only
    mechanically unambiguous facts: it deliberately does NOT compute "deviations
    from standing rules" (a model judgment over prose rules, not a scripted field).
    Plugin versions are the INSTALLED runtime versions (read from
    `installed_plugins.json`), which can lag repo HEAD mid-session per
    `context/refresh.md` — the honest number for a running lane. `--plugin <id>`
    (repeatable) scopes the block to the plugins a lane runs.
  - **`telemetry-upsert.sh`** maintains exactly ONE marker-identified telemetry
    comment on a tracking issue, editing it in place instead of posting a second
    (the interim home of the #502 telemetry contract). It writes a
    machine-detectable sentinel `<!-- claude-ops:lane-telemetry marker=STR -->`,
    finds it across all comments (paginated, so a match on any page prevents a
    duplicate) and PATCHes it; failing that, adopts the most recent comment by the
    authenticated user carrying the raw marker as a whole token (boundary-matched,
    so a shorter marker never adopts a longer lane's comment); else creates one. The marker
    charset excludes `>` so it can never close the HTML comment early. Because the
    script is prompt-driven, inputs are hardened against exfiltration: `--repo` is
    validated as `owner/repo` before URL interpolation, a real `--body-file` must
    resolve under `--body-dir`/`$CLAUDE_PLUGIN_DATA` and may not be a symlink
    (pipe an in-memory body via `-`), and the body is capped at 64 KiB.

  Both ship with a sibling `.test.sh` (PATH-stubbed `gh`/`git`, fixture
  `installed_plugins.json` and comment lists — no network) and are documented in
  the skill's `SKILL.md`. (#538)

## [0.16.0]

### Added

- **`plugins` skill — `fleet-state.sh` now emits `missing_from_user_install`.**
  A new user-scope completeness field (catalog ids not installed at `user`
  scope, minus any explicitly opted out) alongside the existing all-scope
  `missing_from_install`. `sync` Step 4 now keys its user-scope install offer
  off this field: a plugin installed only at `project`/`local` scope was absent
  from all-scope `missing_from_install` and so was never offered a user-scope
  install, silently breaking the "usable from any directory" guarantee for it.
  The existing `missing_from_install` field and its all-scope semantics are
  unchanged; the report template (`SKILL.md`) references the new field for its
  "needs install" action. (#254)

### Fixed

- **`plugins` skill — `fleet-state.sh` shape validation now checks each plugin
  entry, not just the top-level type.** A drifted individual entry (a non-array
  value) passed the `{plugins: {...}}` object check, then failed inside the
  installed-flatten `jq` pipeline in a command substitution; with `set -uo
  pipefail` but no `set -e` the failure was swallowed and the script exited 0
  with `installed: []` instead of failing loud per its stated design. The check
  now asserts every entry is an array and exits 2 on drift. (#254)
- **`plugins` skill — `fleet-state.sh --marketplace` with no name now exits 2
  instead of infinite-looping.** With one positional param left, `shift 2`
  failed silently (no `set -e`), leaving `$1` unchanged so the arg loop re-read
  `--marketplace` forever and the post-loop guard was never reached. The empty
  check now runs inside the `--marketplace` branch, before `shift`. (#254)

## [0.15.4]

### Changed

- **`changelog` skill — installed CC version is now precomputed via `!`
  dynamic-context injection.** The version-awareness step previously told Claude
  to run `claude --version` as a body instruction (a per-invocation tool
  round-trip); it now inlines the probe at load time with
  `` !`claude --version || echo "(CC version unavailable)"` ``. The probe is
  deterministic and read-only, carries the mandated `|| echo` defensive
  fallback, and drops the bash-only `2>/dev/null` redirect so the command and
  its fallback stay valid on both the bash default and the Windows PowerShell
  host. No behavior change.

## [0.15.3]

### Added

- **`lanes` skill — mid-session staleness & restart-cadence guidance
  (`context/refresh.md`).** Loop lanes merge fixes to the very plugins they run on,
  but a running lane keeps the skill versions it loaded at launch. New
  documentation establishes, against current Claude Code docs, that a true
  mid-session hot-reload of a running loop lane is not achievable — a live session
  retains its launch-time plugin versions, `/loop` never re-reads a skill's body on
  later cycles, and a loop cannot self-trigger `/reload-plugins` — so restart is the
  honest refresh mechanism (composing with the #496 context-reset cadence). Adds a
  read-only git probe to detect an unconsumed self-fix on `origin/main` and a
  trigger-based + periodic-floor restart cadence keyed to `/claude-ops:lanes
  restart`. The probe resolves the repo's default branch rather than assuming
  `main`. SKILL.md gains a summary section, a cross-reference, and an eval. No
  script or behavior change. (#514)

## [0.15.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.15.1]

### Fixed

- **`lanes` skill — launch aborts on a failed pre-launch refresh.** `start` /
  `restart` previously ran `refresh_repo_and_plugins || rc=1` and launched lanes
  regardless, so a failed `git pull --ff-only` (divergent/dirty checkout) or
  `claude plugin marketplace update` still seeded background lanes from stale
  repo/plugin state. The refresh is a documented launch prerequisite, so an
  unexpected failure now hard-stops the launch (exit non-zero) with an actionable
  message; `--no-pull` / `--no-update` remain the intentional-skip path (a
  skipped step is not a failure). (#639)

- **`lanes` skill — unknown restart/stop targets are rejected before any refresh
  mutation.** `restart does-not-exist` ran `git pull --ff-only` +
  `claude plugin marketplace update` before discovering the target was unknown.
  The `TARGET_LANES` existence check now runs up front in `main`, ahead of the
  refresh step, so a misspelled target fails fast (exit 3) with no repo/plugin
  mutation — matching `stop`'s fail-first behaviour. (#639)

## [0.15.0]

### Added

- **`lanes` skill** — a scripted launcher that starts, restarts, stops, and
  reports loop lanes as **named background Claude Code sessions** seeded from
  canonical prompt files, replacing the manual morning refresh (cancel loop,
  clear, re-paste the canonical prompt) across N lanes. `start` (default) and
  `restart` first `git pull --ff-only` and `claude plugin marketplace update`,
  then launch each configured lane with `claude --bg -n <lane>` mirroring the
  lane's `model`/`effort`; `status` prints a per-lane running/stopped table with
  the live sessionId; `stop` ends a lane via `claude stop <sessionId>` (resolved
  from `claude agents --json` — there is no `claude agents stop` verb). Acts on a
  session **only** when its name is a configured lane, so a hand-started session
  is never touched. Lanes come from a JSON config (`--config`, else
  `$CLAUDE_OPS_LANES_CONFIG`, else `<repo>/.work/lanes.json`); `--dry-run`,
  `--no-pull`, `--no-update`, and `--agents-json` support previewing and offline
  reuse. Prompt files are read from a session-local `.work` dir today via the
  single `prompt_dir`/`resolve_prompt_dir` seam, which composes with #480
  (loop-prompt authoring skill) when durable prompt storage lands.

## [0.14.0]

### Added

- **`morning-brief` skill** — a read-only, `gh`-based operator morning view for
  the current repo, collapsing the daily hand-run queries into one 5-second
  picture: open counts per queue label (`priority: needs-triage`, `status: ready`,
  `status: needs-decision`, `needs-human`), the gh-native merge-ready PR list
  (non-draft + `mergeStateStatus=CLEAN`), parked `status: needs-decision` issues
  with their RECOMMENDED lines (uppercase marker preferred, case-insensitive
  fallback), and loop-lane telemetry freshness (per-lane `last-cycle` age, marked
  `STALE` past `--stale-hours`, plus any `flags:`). Owner/repo is derived from
  `gh repo view`, never hardcoded; the telemetry issue is auto-discovered by title
  (`--telemetry-issue` to pin) and degrades to "no telemetry issue found" where
  absent. The authoritative PR merge gate remains `/source-control:babysit-prs`;
  this list is a fast glance, not a substitute for that skill's classification.

## [0.13.1]

### Changed

- **`hook-telemetry-sink` quiet jq skip documented at the site** with a
  `silent-skip-ok` annotation (the marketplace's new silent-skip CI gate). No
  behavior change: the sink is fire-and-forget — its producer discards
  stdout+stderr, so prerequisite visibility is owned by the producer side.

## [0.13.0]

### Changed

- **BREAKING: `known-issues scan` is read-only on bare invocation** (fleet
  conformance wave: the naming doctrine's `scan` verb contract). It reports
  untracked references and prints the registering invocation; the registry
  write now requires the explicit `scan --add` override.

## [0.12.0]

### Changed

- **`setup` skill refactored onto the uniform check/apply contract** (fleet conformance wave).
  `/claude-ops:setup` replaces the interactive-validation shape with `check` (default, read-only:
  reports the effective `registry_dir` and `skill_usage_dir` destinations, their defaults, and
  containment status as PASS/FAIL/INFO) and `apply` (non-interactive: states the
  per-machine-vs-repository-resident tradeoff and routes reconfiguration through Claude Code's native
  prompt, with the fresh-install-only `--config` headless semantics). Containment validation, the
  personal-not-team-policy framing, and the dated `pluginConfigs` claim are unchanged. Setup still
  never writes user settings or `pluginConfigs`.

## [0.11.3]

### Changed

- **Freshness riders on platform-fact docs** (fleet conformance wave). The
  `plugins` skill's scope-semantics doc now carries a verified-date header
  (all version-gated claims re-verified: `/reload-plugins --force` ≥ 2.1.163,
  renames ≥ 2.1.193, `plugin prune` ≥ 2.1.121, `userConfig` type set); the
  monitor-restart claim now cites its actual source (plugins-reference). The
  setup skill's `pluginConfigs` claim is dated and pinned to ≥ 2.1.207.

## [0.11.2]

### Changed

- Refresh of the bundled shared hook-utils library, which gains the git argv-grammar parser used by
  the guardrails plugin's git guards. No behavioral change to this plugin's hooks.

## [0.11.1]

### Changed

- Shared `hook-utils.sh` resynced with the fleet's new prerequisite-visibility
  helpers (jq-free notice emitters, once-per-session gate, jq gate). No
  behavior change for this plugin's audit hooks. README now states the hook
  runtime (Bash via Git Bash on native Windows, jq) and the jq fail-open
  behavior.

## [0.11.0]

### Changed

- **Per-hook kill switches migrated to native `userConfig`** (the fleet-wide
  kill-switch doctrine ruling). Each audit hook's toggle is now a `userConfig`
  boolean (default `true`), read by the hooks through the native
  `CLAUDE_PLUGIN_OPTION_<KEY>` hook-process mirror: `api_error_audit_enabled`,
  `config_change_audit_enabled`, `instructions_loaded_audit_enabled`,
  `permission_denied_audit_enabled`, `pre_compact_audit_enabled`,
  `skill_usage_audit_enabled` (shared by both skill-usage audit hooks), and
  `tool_failure_audit_enabled`. The `instructions-loaded-audit` session_start
  opt-in is now the `instructions_loaded_audit_log_session_start` option
  (default `false`), and the stdin read bound is the `stdin_read_timeout` option
  (default `2`). Configure interactively with `/plugin configure claude-ops` or
  headless via `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_<NAME>_ENABLED` and
  `HOOK_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START` environment variables are
  retired and no longer read. A consumer that set any of these in a settings
  `env` block must re-express the value as the matching `userConfig` option.
  Zero-config behavior is unchanged (all audit hooks on, same defaults). The
  `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is unaffected.

## [0.10.1]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.10.0]

### Changed

- **Breaking:** renamed the `troubleshoot` skill to `known-issues` (plugin ID `claude-ops` is
  unchanged). Update any old invocations: `/claude-ops:troubleshoot` → `/claude-ops:known-issues`.
  The skill looks up and tracks known upstream Claude product issues; it never diagnoses or fixes
  local problems, so the old name over-promised. Behavior, actions, and the `registry_dir` option
  are unchanged; the registry is now referred to as the known-issues registry.

## [0.9.0]

### Added

- New `plugins` skill (`/claude-ops:plugins`): brings a machine's plugin fleet current on demand.
  `sync` (default) refreshes marketplaces, updates in-repo project/local-scope installs plus the
  user-scope sweep, installs new catalog plugins per the `install_new` policy, and fills any
  `enabledPlugins` completeness gap — all CLI-mediated, never hand-editing Claude Code's internal
  state files. `audit` runs the same algorithm read-only. `converge` is the one action that can
  touch a committed `.claude/settings.json`: it detects actionable (version-behind) scope
  divergence, previews and confirms per plugin, then surfaces the resulting diff for review — never
  auto-committed, and it aborts outright in an autonomous session. Adds a read-only
  `scripts/fleet-state.sh` state-inspection script and the `install_new` userConfig scalar
  (`ask` default / `all` / `none`).

## [0.8.0]

### Changed

- Rewired OTEL retention to stop, poll, and start the provisioning-owned `otelcol-contrib`
  Windows service. A failed stop or status query aborts before mutation; the prune lock remains
  held through restart, and a failed restart is visible to the caller.

### Removed

- Removed the duplicate Collector configuration and the private/public `start-collector.sh`
  process launchers. Machine provisioning is now the sole Collector lifecycle and configuration
  owner.

## [0.7.0]

### Changed

- Moved long-running telemetry lifecycle to machine provisioning: the boot-time
  `otelcol-contrib` Windows service owns collection, and the provisioning Compose stack owns the
  optional Aspire dashboards.

### Removed

- Removed the private and public `start-dashboard.sh` entry points and their tests. Claude
  sessions no longer create or replace machine-owned dashboard containers.

## [0.6.0]

### Changed

- Renamed three skills (plugin ID `claude-ops` is unchanged, only the leaf names moved). Update any
  old invocations:
  - `claude-observability` → `observability` (`/claude-ops:observability`)
  - `claude-troubleshooting` → `troubleshoot` (`/claude-ops:troubleshoot`)
  - `claude-code-changelog` → `changelog` (`/claude-ops:changelog`)
