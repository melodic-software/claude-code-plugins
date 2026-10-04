# Changelog

All notable changes to the `context-budget` plugin.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions 0.6.38 and 0.6.40 were reserved by parallel changes and never published.

## [0.9.3] - 2026-10-03

### Fixed

- **The `SessionStart` node-notice row no longer runs `powershell` on Linux.** It stopped at `${BASH_VERSION:+exit}`, which only bash sets; Claude Code runs hooks with `/bin/sh`, which is dash on Debian and Ubuntu (WSL included), so every session printed `powershell: not found`. The row now stops at `${PPID:+exit}`, which every POSIX shell sets.

## [0.9.2] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.9.1] - 2026-10-03

### Fixed

- The Windows PowerShell form of the optional Agent SDK install in `audit` and `setup` names the
  plugin data directory through the `${CLAUDE_PLUGIN_DATA}` token Claude Code substitutes when the
  skill loads, like the POSIX form beside it. It read `$env:CLAUDE_PLUGIN_DATA` at run time, which
  an operator's PowerShell does not set, so the install went to `\sdk` at the drive root.

## [0.9.0] - 2026-10-03

### Added

- A `SessionStart` hook row reports a missing `node` once per session, on both hook channels, and works on Windows without Git Bash. The notice names `/context-budget:check`. The row is shared across plugins, so a session with several of them sees one notice.
- `lib/prerequisites.mjs`, `lib/prerequisites.sh` and `lib/prerequisites.ps1`, the generated copies of the shared prerequisites checker and its `node-notice` stubs.

## [0.8.3] - 2026-10-02

### Changed

- **Shared `state-key.sh` synced ([#5837](https://github.com/melodic-software/claude-code-plugins/issues/5837)); no change to this plugin's lib.**
  It is now generated from the repository's canonical source by `scripts/sync-shared-copies.sh` and opens with a header saying so; edit
  the canonical, not the copy.

## [0.8.2] - 2026-10-03

### Changed

- `prerequisites.json` is converted to the schema `docs/conventions/prerequisites/` owns: a `requires` list whose entries carry `id`, `kind`, `need`, `for`, `detect`, `degrade`, `install` and `check`, in place of the retired `tools` list ([#5840](https://github.com/melodic-software/claude-code-plugins/issues/5840)). The plugin now ships the shared checker, `lib/prerequisites.mjs` with its `lib/prerequisites.sh` and `lib/prerequisites.ps1` stubs, generated from the repository's canonical copy.

## [0.8.1] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.
- The plugin description is 500 characters or fewer, the limit claude.ai's marketplace sync enforces.

## [0.8.0] - 2026-10-02

### Added

- **`audit` carries a Boundary section for the built-in `/skill-doctor` command.** The command is
  user-only, so the section offers it to the person for choosing which skills to turn off and keeps
  measuring what a toggle saved here. Its four-part records live in
  `reference/native-skill-doctor.md`.

### Changed

- **`audit`'s route-out sends skill pruning to `/skill-doctor`.** Unused MCP servers and plugins
  stay with the bundled `/doctor`. The README's Boundaries list, the lever catalogue's routes and
  the report's Routes section name the same split.

## [0.7.4] - 2026-10-02

### Changed

- **The settings-write checkpoint is registered on `Write|Edit|NotebookEdit`.** The `MultiEdit`
  alternative is dropped from the `hooks.json` matcher and the hook's tool list, so the hook no
  longer runs for a tool the current tools reference does not list. The contract test now asserts
  the registered matcher, and the option description and README match.

## [0.7.3] - 2026-10-02

### Changed

- The `settings_write_ask_enabled` title follows the plugin option naming convention
  (`docs/conventions/plugin-option-naming/`): "Settings-write-ask hook", and its description names
  the default. No key, type, or default changes.

## [0.7.2] - 2026-10-02

### Fixed

- The `audit` `argument-hint` uses Claude Code's official bracket notation: it keeps alternatives
  inside brackets with an unspaced `|`.
- The `setup` `argument-hint` uses Claude Code's official bracket notation: it leads with its check
  action.

## [0.7.1] - 2026-10-01

### Changed

- References to the `claude-config`, `claude-memory` and `claude-ops` plugins now use their new
  names, `harness-config`, `harness-memory` and `harness-ops`.

## [0.7.0] - 2026-10-01

### Added

- **`/context-budget:check` reads whether `node` resolves for the context-budget hooks.** The skill is model-invocable, read-only and never installs. A new `prerequisites.json` declares `node` and points at it, so `/claude-ops:prerequisites` and the per-plugin check read the same list.

## [0.6.48] - 2026-09-30

### Changed

- **`audit`'s description fits the 500-character listing budget.** It keeps the `explain-usage` route phrase and the trigger phrases, in fewer words ([#4661](https://github.com/melodic-software/claude-code-plugins/issues/4661)).

## [0.6.47] - 2026-09-29

### Changed

- **`audit`'s description opens with a presence-gated routing clause for the bundled
  `explain-usage` skill.** It routes a plain-language account of where this session's tokens went
  to `explain-usage` and keeps what a session costs before any work starts, per-tool attribution,
  and whether a settings change saved anything, the split its Boundary section states.
- **The `explain-usage` Boundary bullet no longer asserts that the skill ships with Claude Code.**
  It keeps the provenance class, what the skill does and how it is invoked, in the
  native-references template form.

### Added

- **`audit` carries a Boundary section for the built-in `/context` command.** `/context` is
  user-only, so the section offers it to the person for a live look at the current window and keeps
  startup cost, per-tool attribution, and before/after deltas here. Its four-part records live in
  `reference/native-context.md`.

## [0.6.46] - 2026-09-29

### Added

- **`audit` carries a Boundary section for the bundled skill `explain-usage`.** When it resolves,
  it explains where this session's tokens went after the fact; this skill keeps per-item startup
  measurement and the before/after ledger.

## [0.6.45] - 2026-09-29

### Fixed

- **`setup` passes the scope `claude plugin list` reports.** The headless toggle no longer says
  to always pass `-s user`: a rerun at a scope other than the installed one adds an install
  record and enables the plugin there. When the working directory is the home directory and the
  list labels one file as both `user` and `project`, pass `user`. The README and eval 6 say the
  same. The unsourced `fnm_multishells` path example is gone, and `setup` now ends with a
  `## Next` section pointing at `audit`.
- **`audit` reference text.** `engine.md` lists the binary stamp and `skillListingSignature`
  among the record's fields again (a splice had detached them from the sentence) and documents
  the two harness-only `cli-parse` marker lines, `Caveat:` and `<!-- synthesized-zero: -->`, as
  the hermetic test's input contract. The README's ConfigChange wording now matches the hooks
  page (Claude Code 2.1.284): a block does not apply to `policy_settings` changes, the hook
  discards `systemMessage`, and a blocked change surfaces no message.
- **Connectors lever.** The 2.1.259 `allowedMcpServers` fact is stated once, in the caveat,
  and the lever rows no longer cite changelog item ids. The manifest description says `fix`
  applies one approved project-scope trim instead of "applies nothing".

### Changed

- **Changelog corrections to released entries.** 0.6.42 carried bullets duplicated from 0.6.39
  and 0.6.41 and now records that it changed no plugin behavior; 0.6.36 gains the
  `settings_write_ask_enabled` description line it shipped without; a note under the header
  records that 0.6.38 and 0.6.40 were never published.

## [0.6.44] - 2026-09-28

### Changed

- **Argument hints** on `audit` stay inside the 100-character house style
  ([#3542](https://github.com/melodic-software/claude-code-plugins/issues/3542)).
  Examples, defaults, and flag catalogs that exceeded the budget now live in the skill body.

## [0.6.43] - 2026-09-28

### Fixed

- **`plugin-disable` lever states the observed `enabledPlugins` rule.** A plugin no scope names
  does not load, whatever its `defaultEnabled`; the settings reference agrees, the plugins reference
  still says it falls back to `defaultEnabled`, and the lever now says so. Two caveats carry the verification records
  (Claude Code 2.1.280): the no-fallback rule, and a non-Boolean value making Claude Code skip every
  `enabledPlugins` entry in its file. The lever cites the `settings-reference#enabledplugins`,
  `plugins-reference#defaultenabled`, and `settings#fix-a-broken-settings-file` anchors (#4660).

## [0.6.42] - 2026-09-28

### Changed

- No plugin behavior change. The version was bumped when the #4027 changelog campaign closed (#5162); the lever rows and connector wording shipped in 0.6.39 and 0.6.41.

## [0.6.41] - 2026-09-28

### Changed

- **Connector allowlists and `/context` counting**
  ([#4027](https://github.com/melodic-software/claude-code-plugins/issues/4027)).
  The connectors lever no longer says `allowedMcpServers` removes managed connectors. From
  Claude Code 2.1.259 only `deniedMcpServers` does; `allowedMcpServers` governs servers users
  add. The measurement contract no longer says `/context` makes no API call. It uses the
  token-counting API or, from 2.1.261, a local estimate, and connectors can arrive
  after the first turn. Pages read 2026-09-28.

## [0.6.39] - 2026-09-28

### Added

- **Lever rows for command-output caps** ([#4027](https://github.com/melodic-software/claude-code-plugins/issues/4027)). `bashOutputMaxChars` is disclose-only: it changes how much of a later command stays inline, and a startup snapshot of it measures zero. `taskOutputMaxChars` is recorded as removed in Claude Code 2.1.277, so the catalogue does not emit it.

### Changed

- **`/context` measurement basis.** `reference/engine.md` records that when the token-counting API is unavailable, `/context` uses a local estimate (Claude Code 2.1.261) instead of extra small-model requests. The commands page `/context` row fetched 2026-09-28 does not say that yet; the changelog is the behavior source until it does.

## [0.6.37] - 2026-09-28

### Changed

- **Connectors lever: only `deniedMcpServers` keeps a managed server off**
  ([#4027](https://github.com/melodic-software/claude-code-plugins/issues/4027), item 259-035).
  From Claude Code 2.1.259, `allowedMcpServers` governs servers users add; a literal
  `managed-mcp.json` / `managedMcpServers` entry that an allowlist used to filter out now
  loads. `connectors-disable` states that and names the docs lag on the managed-mcp page.
  Verified against the 2.1.259 changelog feed on 2026-09-28.

## [0.6.36] - 2026-09-28

### Fixed

- **Attribution keeps deny-run caveats**
  ([#3356](https://github.com/melodic-software/claude-code-plugins/issues/3356)).
  `attribute` used to publish only the baseline snapshot's `caveats`, so a disclosure raised
  by a deny run, including sdk mode's synthesized-zero note, never reached the record. The
  record now merges caveats from the baseline, each deny run, and the combined additivity run,
  dropping duplicates and keeping first-seen order.

### Changed

- **`settings_write_ask_enabled` description.** The userConfig description now says the ask covers Write, Edit, MultiEdit and NotebookEdit, and that shell writes and files rendered into place are outside the matcher.
- **Bare-name deny cites the `EndConversation` exception.** The permissions page now says
  bare-name removal applies to every tool except `EndConversation` (a deny cannot remove it
  while any other tool remains, and an ask rule never prompts for it). `engine.md`, the
  `deny-bare-tool` lever, and the audit skill say so. `EndConversation` is on the
  interactive-only list, because it never enters either attributed headless bucket. Re-read
  2026-09-28.
- **The rest of the post-use audit's still-live findings**
  ([#3356](https://github.com/melodic-software/claude-code-plugins/issues/3356)).
  `--operator-deny` keeps an operator's bare-name deny out of the interactive-only reason.
  `verify-catalogue --find-unstored` lists env names in the binary that no row cites, and the
  catalogue no longer claims to hold every switch. sdk snapshots keep per-skill `tokens` and
  `pluginName`, `slashCommands`, and `collapsedSkills`. `skill-overrides` and
  `disable-bundled-skills` store a runtime-resolved saving, and the listing cap is named as
  characters. `disable-artifact` is unmeasurable in a headless session. A built-in output style
  is not the custom-style lever. The report says a `nonrepo` total is a floor. `setup` treats
  an ephemeral Windows `node` shim as a failure on the pass path, names the settings-write-ask
  toggle, and prints a PowerShell install line. The plugin-reconfiguration convention records
  that `plugin list` can label one home-directory settings file as both `user` and `project`,
  and that the uninstall-drops-`pluginConfigs` caveat was not part of the 2.1.283 probe. The
  hook comment matches the headless stamp already in the audit skill (2.1.263).
- **Additivity refuses a synthesized zero.** `--verify-additivity` publishes `additive: null`
  when the combined run's bucket was filled in because the SDK omitted it, including the
  summed verdict. A measured pair within 1 token still counts as additive. `setup` tells the
  operator to pass `-s user` for this plugin: `-s` places enablement, the option value lands
  in user settings, and `claude plugin list` is not a scope to copy when one file has two
  labels. The headless `claude plugin install` line is for the operator to run.

## [0.6.35] - 2026-09-28

### Changed

- **Skill descriptions trimmed to 500 characters or fewer (#4661).** The one listed skill,
  `audit`, ran over 500. It now leads with its use case, keeps its quoted trigger phrases, and
  names the read-only default versus `fix`. What the body already carries is cut: A/B
  differencing mechanics and SDK-fallback detail. `check-listing-budget.sh
  plugins/context-budget/skills` goes from 799 to 500 characters. `setup` stays
  `disable-model-invocation: true`. No skill is renamed or merged.

## [0.6.34] - 2026-09-28

### Changed

- **The settings-write checkpoint claims only what it sees**
  ([#3864](https://github.com/melodic-software/claude-code-plugins/issues/3864)). The audit
  skill said the checkpoint asks on "any settings-surface write", but its matcher is
  `Write|Edit|MultiEdit|NotebookEdit`. The skill, README, `hooks.json` description, and hook
  header now say it covers file-editing tool calls, and name the routes it does not see. Those
  are shell writes (redirects, heredocs, `sed -i`, scripts), files rendered into place by a
  dotfile manager or any other program, and `managed-settings.d/` drop-ins. The README records
  why the hook is not widened to `Bash|PowerShell`. The audit `fix` path now makes its
  project-settings edit with a file-editing tool, so the checkpoint covers the plugin's own write.

## [0.6.33] - 2026-09-27

### Changed

- **`setup` probes `node` and the Claude Code CLI at load time.** `command -v node`,
  `node --version`, `command -v claude`, and `claude --version` run as pre-computed context, so
  `check` reads four rows instead of making those Bash calls. The two version probes are
  pre-approved in `allowed-tools`, since a load-time command that is not allowed aborts the skill
  outside auto mode. The FAIL rules are unchanged, and a policy-disabled injection falls back to
  the Bash probe.

## [0.6.32] - 2026-09-27

### Fixed

- **setup:** the reconfigure scope caveat now gives the measured reason to pass the scope
  `claude plugin list` reports: a rerun at another scope adds a second install record there and
  enables the plugin at that scope, while the value itself always lands in user settings. It no
  longer says the write lands at a scope that does not load. The advice is unchanged.
  It also says a rejected `--config` value prints a warning yet exits 0, so read the output.

## [0.6.31] - 2026-09-25

### Changed

- Comment-only pass with /code-tidying:dissolve-comments: restating comments, history narration and ticket back-references removed from scripts and tests, over-budget rationale shortened. Every edit is certified comment-only by a token-level proof, so behavior is unchanged; the removed text is recorded in the commit bodies.

## [0.6.30] - 2026-09-21

### Changed

- American spellings throughout this plugin's prose, ahead of the `en-us` locale the
  shared typos config adopts. Wording only: no behavior, option, default, or identifier
  changes. Released sections were corrected in place on the same terms.

## [0.6.29]

### Changed

- Merge the settings-path alternation in the settings-write-ask hook, inline the single-use snapshot predicates and share the degrade and exit assertions in the audit suites (behavior unchanged).

## [0.6.28]

### Changed

- Cite the marketplace `docs/` doctrine files by their lower-kebab names (`docs/plugin-philosophy.md`, `docs/migration-playbook.md`, and siblings); the files were renamed and the old uppercase paths no longer resolve.

## [0.6.27]

### Changed

- **Options reference drops its em dashes.** The generated How-to-set-these block is rewritten by `scripts/sync-plugin-options-docs.py`, which is the fix site: its output is regenerated, never hand-edited. The block no longer needs the ignore marker that exempted it from the repository's em-dash gate, so that marker is gone as well.

- **Manifest description drops its em dashes.** Wording only; the plugin's behavior, options, and defaults are unchanged. The description renders into `docs/CATALOG.md`, which the repository's em-dash gate reads.
- **The plugin's prose drops its em dashes.** Five surfaces were rewritten: this changelog, two `skills/audit/reference/` documents, `skills/setup/SKILL.md`, and the `context-sample.md` parser fixture. Wording only, with no change to any lever, measurement, or record schema. The fixture's rewritten line is preamble the parser skips, and `measure.test.sh` still passes 90 of 90. The released sections corrected in place are 0.6.6, 0.6.4, 0.6.1, 0.6.0, 0.5.1, 0.4.0, 0.3.0, 0.2.0, and 0.1.0: their wording changed, their facts did not.
- **The degradation-ladder caveat says what the rung depends on, in the document and in the code that emits it.** `reference/engine.md` and the `caveats` string in `skills/audit/scripts/measure.mjs` now both read "headless /context is undocumented as a -p-capable command, so this rung depends on unsanctioned behavior", instead of calling the mode load-bearing. A reader of the record and a reader of the reference see the same sentence.
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`.** The gate now defends `CHANGELOG.md`, every `skills/*/SKILL.md`, and the `skills/audit/reference/` tree.

## [0.6.26]

### Changed

- **`lib/state-key.sh`:** replica synced with the canonical copy. The non-repository rung now
  hashes the physical working directory, so one directory reached through two spellings keys once,
  and an exported `CDPATH` can no longer redirect `cd` or add a line to stdout.

## [0.6.25]

### Changed

- audit: dated records for the /doctor routing, the settings-write checkpoint, and the engine's mechanism citations, and the unverifiable per-tool wall-clock range dropped (prompt-audit follow-up F6)

## [0.6.24]

### Changed

- **The additivity claim is corrected in every home that carried it.** The skill
  body, the `deny-bare-tool` lever's `categoryBasis`, and the plugin README each
  asserted flatly that deltas add and a basket prices from its members. Measured
  readings say otherwise per bucket: the deferred side sums to the token, while
  the prefix side double-counts, so the sum of prefix deltas is only an upper
  bound on a basket's prefix saving. All three now say which side composes and
  which does not. The skill body and the lever's `categoryBasis` also point at
  `attribute --verify-additivity` for the per-bucket verdict; the README states
  the corrected claim without that pointer. (#3863)
- **`attribute --verify-additivity` reports a verdict per attributed bucket.**
  The record gains `perBucket`, carrying `{sumOfParts, combinedSaved, additive,
  reasons}` for each bucket, derived from the `prefixDelta`/`deferredDelta`
  values the per-tool rows already carry: no extra measurement pass, and one
  bucket vanishing no longer costs the other bucket its verdict. Skill-listing
  and Skills-token checks gate only the prefix column; the shared mode/binary
  checks gate both, so a combined-run listing mismatch does not publish the
  deferred verdict as unmeasured. A bucket absent from both runs is outside the
  binary's category vocabulary and gets no verdict row. (#3863)
- **`additive` is tri-state instead of boolean.** It was computed from the
  comparability flag, so an unmeasurable reading published as a definite
  `false`. `true` and `false` are now measured verdicts and `null` means the
  reading could not be measured, top level and per bucket alike. The saturation
  guard that produces the null saving is unchanged. (#3863)

## [0.6.23]

### Changed

- audit: the description discloses the explicit `fix` override instead of claiming an unconditional read-only contract; the Gotchas section states the listing-signature guard as the current rule without the narrative of the run that motivated it; a new honesty bullet says the snapshot's free-space and window figures belong to the spawned headless session and are no reason to shorten the audit.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.6.22]

### Added

- **`hooks/hooks.json` carries a top-level `description`.** The hooks reference
  documents the field as optional, and every hook set in this marketplace omitted
  it; it is the surface an operator reads when deciding what a plugin does to
  their session. One line naming what this plugin's hook set does. (#3719)

## [0.6.21]

### Changed

- **`measure.test.sh` runs its hermetic engine invocations through one `attr`
  helper.** Five near-identical calls each repeated the `cd "$WORK"` that keeps
  the engine in cli-parse mode, the `FAKE_MODE` export, the `--binary` and
  `--out` flags and the stdout redirect, differing only in fake mode, output
  file and the attribute flags under test. The extraction changes flag order
  only, and the engine's parser is order-insensitive; all 61 assertions are
  untouched. The formatter hook also re-indented one `case` block's labels.

## [0.6.20]

### Changed

- **`measure.mjs` sheds a `return null` the code itself declared unreachable,**
  and hoists a per-call `flagOnly` list to a module-level `FLAG_ONLY`. The
  unreachability was proven by execution rather than by reading: a tripwire
  placed immediately after the preceding `degrade()` call never fired, and the
  counterfactual that neuters `process.exit` shows the deleted line's only
  observable effect lives on a path `degrade()` never takes. The hoist was
  checked for evaluation-timing equivalence across 13 argv shapes. A ReDoS
  comment moves to present tense.
- **`levers.test.sh` extracts a `report_clean` helper** for three inline
  reporting blocks, with failure text byte-identical to what it replaced.
  Mutation-tested: inverting its comparison and breaking three levers both turn
  the suite red, one failure per problem. `measure.test.sh` gets one shfmt
  conformance fix.

## [0.6.19]

### Changed

- **The settings checkpoint records why it carries no `if` gate.** An `if` gate was evaluated for
  the PreToolUse row and rejected after a live probe: on Windows, Claude Code's `if` file rules do
  not match an absolute path outside the working directory under any anchoring form tested,
  including the home-relative, root-anchored, drive-letter and root-anchored recursive-glob
  spellings. The probe logged every candidate rule as skipped on a write to the user-global settings
  file and on a write to the managed-settings file, while the unconditioned row fired and returned
  `ask` for both; only a settings file inside the working directory matched. A gate would therefore
  drop the user-global and managed-settings checks silently, which is the opposite of what the
  checkpoint exists to do, so the row stays unconditioned until upstream matching reaches those
  paths. Documentation only; the registration and `settings-write-ask.mjs` are unchanged.

## [0.6.18]

### Changed

- **Options reference cites the plugin-reconfiguration convention.** The generated
  How-to-set-these block no longer restates the 2.1.240 verified-version record.

## [0.6.17]

### Changed

- **setup:** cite the plugin-reconfiguration convention for the native
  `/plugin configure` / headless `--config` path instead of restating the
  verified-version record inline.

## [0.6.16]

### Changed

- `setup` is check-only: the no-op `apply` action is dropped per PLUGIN-PHILOSOPHY's Check-only carve-out, and its reconfiguration guidance is now printed by `check` (#3583, customization-consistency Phase 1b).

## [0.6.15]

### Fixed

- **`lib/state-key.sh` now exits 2 when neither `sha256sum` nor `shasum` is on PATH, and prints no key.** The helper's `exit 2` ran inside a command substitution, so a host without either digest tool continued and printed a malformed key at exit 0. Synced from the canonical `claude-config` copy via `scripts/sync-state-key.sh`.

## [0.6.14]

### Changed

- **`setup`: normalized the probe-don't-recite directive and repaired residual grammar defects.**
  The directive had fractured under the same per-plugin de-slop campaign;
  `docs/PLUGIN-PHILOSOPHY.md` now owns the rule under a `runtime-grounded` clause, and the eighteen
  sites that campaign fractured carry one wording. Twenty setup skills assert the rule; the other
  two, `context-guard` and `rate-limit-guard`, state it about their own scripts in their own words
  and are left for a separate pass, so the fleet is not yet down to a single form. Whole-repo
  extract-ssot sweep.

## [0.6.13]

### Changed

- **The generated options block sits under `## Configuration`.** It was under `## Boundaries`. The
  generated table itself is unchanged; a `## Configuration` heading was added above it. Docs-hygiene
  sweep, L8-write-for-humans.

## [0.6.12]

### Changed

- **Options-reference regeneration.** `scripts/sync-plugin-options-docs.py` dropped the
  phrase `in order to` from its shared options template, per the repo's own
  write-for-humans style rule that the phrase is just `to`. The generated options
  block in `README.md` regenerated with the shorter wording; no other change.

## [0.6.11]

### Changed

- **Behavior-preserving simplification pass (repo-wide batch-simplify).** Corrected the
  `hooks/settings-write-ask.mjs` header comment's tool list to the code's actual
  Write/Edit/MultiEdit/NotebookEdit match set; in `skills/audit/scripts/measure.mjs`,
  deduplicated the twice-computed script-directory constant into one `SCRIPT_DIR` and moved a
  misplaced section divider to where the main section actually starts. Byte-identical output
  verified old-vs-new on the modes consuming the changed constants; suites green (12 + 61 + 3).

## [0.6.10]

### Changed

- **Instruction-surface de-slop (#2891, context-budget cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.6.9]

### Changed

- **Catalogue:** `include-git-instructions` now names `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS` as
  the headless measurement route (env overrides the settings key in the binary; the env name
  is not on the public env-vars page, so it stays a measurement route and the settings key
  remains the recommended emitted config). `simple-system-prompt`'s `conditions` now resolve the
  model-dependence from the binary's lean-prompt selector: opus-5-family models already default
  lean, so a measured zero there is explained (already-default), not merely reported
  ([#3200](https://github.com/melodic-software/claude-code-plugins/issues/3200)).

## [0.6.8]

### Added

- **Engine / report:** a full sweep no longer silently omits interactive-only tools. The
  attribution record carries `knownUncovered` from a maintained product-level list (Artifact,
  AskUserQuestion, SendUserFile, EnterPlanMode, ExitPlanMode) plus a class note for
  interactive-only MCP servers. A name that was a candidate this run is dropped from that
  list. The report contract documents known-uncovered alongside unmeasured-but-candidate
  ([#3199](https://github.com/melodic-software/claude-code-plugins/issues/3199)).

## [0.6.7]

### Changed

- **Catalogue:** settings-key citations that had drifted onto the settings overview page
  (`docs/en/settings`) now point at the per-key anchors on
  [`settings-reference`](https://code.claude.com/docs/en/settings-reference)
  (`disableWorkflows`, `disableArtifact`/`enableArtifact`, `includeGitInstructions`,
  `skillOverrides`, `disableBundledSkills`, `skillListingBudgetFraction` /
  `skillListingMaxDescChars`, `disabledMcpjsonServers`). `disableArtifact`'s emitted config is
  the user-scope form (`enableArtifact: false`); a project-scope write is the wrong lock
  ([#3198](https://github.com/melodic-software/claude-code-plugins/issues/3198)).
  `verifiedAgainst` is now CLI 2.1.241 (2026-08-23).

### Added

- **Engine:** `verify-catalogue` greps the stamped binary for each catalogue row's settings
  keys and env names and reports present/absent with hit counts. Run automatically on a
  version-jump recheck; the binary is the authority on existence at the measured version, the
  docs fetch on semantics
  ([#3198](https://github.com/melodic-software/claude-code-plugins/issues/3198)). CamelCase
  extraction is a linear scan (no nested-quantifier ReDoS), reads every prose field (not just
  `title`), and prefers a sibling `.exe` over a Windows `.cmd`/`.bat` shim.

## [0.6.6]

### Fixed

- **Engine:** the additivity verifier no longer coerces a null bucket delta to `0`. A combined
  deny can empty `System tools` or `System tools (deferred)` out of the snapshot; the snapshot
  comparison correctly records that bucket's delta as `null`, but the verifier summed it with
  `?? 0` and published a fabricated `combinedSaved: 0` as `comparable: true`. The additivity
  record (and each per-tool row, which had the same coercion) now reports the saving as `null`
  with `comparable: false` and a reason naming the vanished bucket
  ([#3197](https://github.com/melodic-software/claude-code-plugins/issues/3197)). A bucket
  absent from *both* runs remains a non-event: outside that binary's category vocabulary, not
  a missing measurement. In sdk mode, where numbers are exact and the category vocabulary is
  known, an omitted bucket is now recorded as an explicit `0` at snapshot time, so a combined
  deny that empties a bucket yields a real measured delta instead of an incomparable record.
  Every synthesized zero is named in the snapshot's `caveats[]` so a standalone
  `snapshot`/`compare`/`ledger` consumer can tell a reported 0 from a filled-in omission; the
  vanish/`comparable: false` path remains cli-parse only.

## [0.6.5]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).

## [0.6.4]

### Fixed

- **Docs:** the generated options block's headless route no longer implies `--config` applies
  only at install time, and now carries the CLI version its claim was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). The block also
  now separates the write from its effect: the value is stored immediately, but hooks are handed
  their `CLAUDE_PLUGIN_OPTION_*` at session start, so a check run in the same session still
  reports the old value and that is not a failed write. Two upstream links that pointed at empty
  backward-compatibility anchors on the settings page were repointed at the headings that hold
  the content.

### Added

- **`/context-budget:setup`**: the plugin declared `userConfig` but shipped no setup skill.
  Adds the fleet's uniform check/apply contract: `check` verifies what the native configuration
  prompt cannot, `apply` routes a reconfiguration and then reads the effective value back before
  reporting it ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)).

## [0.6.3]

### Fixed

- **Security:** the settings-write ask checkpoint matches paths case-insensitively. macOS and
  Windows filesystems resolve `.claude/Settings.json` to the same file as the lowercase name, so
  the previous case-sensitive match let a differently-cased write bypass the checkpoint silently
  on exactly the platforms it supports (PR security-review finding). Case-variant regression
  cases added to the hook contract test.

## [0.6.2]

### Fixed

- `--out` creates missing parent directories, so a fresh audit's first snapshot no longer
  discards an expensive measurement with ENOENT on the not-yet-created data dir (PR review
  finding).
- The `systemToolsComparable` predicate now includes every mismatch it records as a reason:
  binary path (same version, different install) and a moved Skills bucket under a matching
  listing both mark the comparison incomparable instead of warning while publishing the delta
  (PR review finding). Tests added for all three cases.

## [0.6.1]

### Fixed

- README carries the generated options reference for `settings_write_ask_enabled` (owed since
  the option shipped in 0.4.0; `scripts/sync-plugin-options-docs.py` gate).

- Ledger run IDs are collision-safe: a same-second rerun of the same lever (or a re-appended
  row) now lands in a numbered-suffix run file instead of silently overwriting the earlier one.
  The one-file-per-run contract held only by luck before (PR review finding). Test added.
- Windows command shims spawn correctly: binary resolution now prefers `claude.exe` over
  `claude.cmd`, and a `.cmd`/`.bat` shim is executed through the shell (Node cannot spawn
  command shims directly), so shim-only Windows installs measure instead of degrading
  (PR review finding). Untested on real Windows hardware and recorded as a manual-verification
  gap, matching the repo's convention.

## [0.6.0]

### Changed

- Empirical hardening from the first end-to-end shakedown and two fresh-context probes
  (v2.1.232, headless):
  - cli-parse `totalTokens` now excludes every `... (deferred)` category, not only the built-in
    one. HTTP MCP tools measured deferred in their own `MCP tools (deferred)` category
    (anthropics/claude-code#40314's upfront loading did not reproduce), and the headline must
    exclude both pools in both modes; engine.md's headline rule updated to match.
  - The ask-checkpoint's undocumented-`bypassPermissions` caveat upgraded to a measurement: at
    v2.1.232 headless the `ask` fires and blocks even under `bypassPermissions` (surfacing as a
    tool error carrying the reason); interactive behavior stays explicitly unmeasured. Hook
    header and SKILL.md fix-path wording updated.
  - New deny-bare-tool caveat: denying the tool-search tool is a measured anti-lever (it forces
    the entire deferred pool upfront); measure any infrastructure tool before recommending its
    deny. The tool-search-deferral row now records the dedicated MCP deferred bucket.

## [0.5.1]

### Changed

- Tightened the catalogue test's token-figure scan: any k-suffixed figure in a lever row now
  fails outright, and plain integers adjacent to the word token are caught in either order.
  That closes the gap the fresh-context acceptance verifier flagged (a plain-integer figure could
  previously slip past the mechanical check). Verified against a seeded violation.

## [0.5.0]

### Added

- Three fix-path eval cases: mutation only on the explicit `fix` argument (a mid-report aside is
  not an override), user-global settings stay print-only inside the fix path with the auto-mode
  classifier caveat stated as the reason, and one-lever-at-a-time apply → re-measure → ledger
  with batch requests refused on attribution grounds. Eval file passes the evals-quality gate
  with zero warnings.

### Verified

- Acceptance sweeps recorded: the shipped plugin greps clean of every research-run figure
  (cite-never-transcribe), the catalogue contract test and hook contract test pass, and the
  skill-layout gate reports zero errors.

## [0.4.0]

### Added

- The guided fix path, behind the explicit `fix` argument only (the verb contract's mutation
  override): per-lever walkthrough over measurement-resolved `recommendable-on-fit` catalogue
  rows, scope-split write posture (project settings editable after per-diff approval;
  user-global `~/.claude/settings.json` print-only, never written; managed policy never
  targeted; env levers printed), and a mandatory one-lever-at-a-time
  apply → re-measure → compare → ledger loop.
- PreToolUse checkpoint hook (`hooks/settings-write-ask.mjs`, exec-form `node` invocation):
  returns `permissionDecision: "ask"` for any Write/Edit targeting a Claude Code settings
  surface, so auto mode prompts instead of silently approving. It is documented as a checkpoint,
  not a guarantee (PermissionRequest hooks, `disableAllHooks`, and the undocumented
  `bypassPermissions` interaction are named). Fail-open on internal error; kill switch shipped
  as `settings_write_ask_enabled` userConfig (default true) read via the hook-process mirror;
  hermetic contract test covers ask/silent/kill-switch/garbage/backslash paths.

## [0.3.0]

### Added

- The report contract (`skills/audit/reference/report.md`): stamped header, smart-zone headline
  (reclaimed reasoning space, never cost) with optional context-guard zone framing when that
  plugin is installed, measured category totals, ranked per-tool attribution with incomparable
  rows carrying reasons instead of numbers and unmeasured tools listed rather than omitted,
  lever findings grouped by honesty category with citations and emitted config, route-outs,
  degradations. Reports persist one-file-per-run under the keyed data directory.
- SKILL.md report step wiring the contract into the audit workflow as the default deliverable.

## [0.2.0]

### Added

- The lever catalogue (`skills/audit/reference/levers.json`): every known operator-controllable
  switch over the fixed startup payload as data rows: honesty category (six-term vocabulary with
  a dual-ledger request/context-window distinction), category basis, condition resolution by
  measurement, posture (recommendable / disclose-only / never-recommend / report-only),
  detection, measurement route, exact emitted config, official citations, verified date, and
  recheck trigger per row. Net-negative and unverified levers are structurally barred from the
  recommendable posture.
- Catalogue contract test (`levers.test.sh`): categories confined to the vocabulary, citations
  required, postures consistent, and no shipped token figures. That makes the cite-never-transcribe
  rule mechanical.
- SKILL.md lever-presentation step wiring the catalogue's honesty rules into the audit workflow.

## [0.1.0]

### Added

- Initial release: the measurement engine and the `audit` skill's measurement workflow.
- `skills/audit/scripts/measure.mjs`: SDK-primary meter over the Agent SDK's structured context
  usage (exact integers, live tool enumeration), degrading to a version-aware parser of headless
  `/context` output (display-rounded, refuses loudly on format drift) and then to a structured
  error with a remediation; per-tool attribution of the built-in tool pools by bare-name-deny A/B
  differencing with an optional additivity verification; enforced comparability rules
  (skill-listing signature, one mode, one binary version); offline `compare` producing ledger
  rows and a per-project ledger (one file per run plus an appended history line) under a
  caller-derived state-keyed data directory; every record stamped with the measured binary path
  and version, mode, precision, and session kind.
- `/context-budget:audit`, the read-only measurement workflow: stamped baseline snapshot,
  attribution over the live tool list, before/after ledger loop; prints exact config
  (`permissions.deny` bare names) and applies nothing.
- `reference/engine.md`: record schemas, degradation ladder, mechanism citations, comparability
  rules.
- Hermetic engine test suite (`measure.test.sh`) over the parser, compare, and ledger surfaces.
- `lib/state-key.sh` adopted from the marketplace's shared per-project state-key cluster.
