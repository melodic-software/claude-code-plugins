# Changelog

All notable changes to the `code-tidying` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.14.8]

### Changed

- **Comment-residue cleanup (`/code-tidying:audit-comment-residue`).** History narration, plan/session references, and stale back-references in code comments rewritten as present-tense rationale or removed. Comment-only, no behavior change.

## [0.14.7]

### Changed

- **Long reference files carry a `## Contents` index.** 1 reference file in this plugin gained one.

  The predicate is `audit-progressive-disclosure`'s own: a reference file over 300 lines with no
  table of contents, which both official sources agree on by that length. Scope came from the
  detector's tier classification rather than a line count, so `SKILL.md` files are excluded by
  construction: they are invocation tier, not the on-demand reference tier the rule names. Files
  with fewer than five H2s were held out, because a three-row index on a long file earns nothing and
  the doctrine offers a grep recipe instead. Purely additive, with anchors generated from each
  file's own headings and verified to resolve. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.14.6]

### Changed

- **Behavior-preserving simplification pass (repo-wide batch-simplify).** Replaced the
  hand-rolled `--` argument-drain loops in `audit-comment-residue/scripts/detect.sh` and
  `audit-dead-code/scripts/dead-code-scan.sh` with the equivalent `TARGETS+=("$@"); break`;
  removed the inert trailing optional ticket-ref group from `cr_is_sanctioned_todo`'s
  unanchored regex in `lib/comment-shapes.sh` (boolean-only usage, group never affected the
  match); in `dead-code-scan.sh`'s gopls lane, derived the owned-file count from the hoisted
  `files_owned` result instead of a second same-predicate `count_owned` pass. Suites green
  (53 + 162); refutation pass ran 29 adversarial differential invocations plus a 3000-case
  regex fuzz, all byte-identical. Note the pass preserves the pre-existing (possibly
  unintended) behavior that any TODO/FIXME/HACK/XXX comment counts as sanctioned with or
  without a ticket ref.

## [0.14.5]

### Changed

- **Instruction-surface de-slop (#2891, shard 11).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. Fenced report templates and quoted deferral-contract
  shapes keep their original punctuation.

## [0.14.4]

### Added

- **`/code-tidying:audit-dead-code`** — a read-only, whole-repo dead-code hunter for the
  category lane-rotated tidying and diff-scoped simplification structurally cannot see:
  code nothing has reached in a long time. Four lanes ship with **honestly unequal**,
  individually labelled confidence — `knip` (TS/JS: unused files, exports, types, enum
  members; not class members, which knip 6 rejects), `vulture` (Python, symbol-level,
  high-recall/low-precision with the FP-class suppressions that measurably work
  pre-applied), `gopls check -severity=hint` (Go, **unexported symbols only**, a stated
  coverage limit rather than a defect), and a portable `grep -w -F` lane (shell and other
  symbol languages, high-precision/acknowledged-low-recall). No lane builds or executes
  project code, no package runner is ever allowed to fetch, detector presence is proven by
  invocation rather than `command -v`, and run health is read from stderr instead of exit
  status — so a run reports one of ran / skipped / degraded / scanned-zero-files instead of
  passing a broken run off as clean. Every candidate is adjudicated against the
  dynamic-usage evidence static analyzers are blind to under a `--max` cap ordered by git
  recency (oldest-untouched first), landing as `dead`, `uncertain`, or `alive` with every
  `alive` citing the evidence that saved it. Suppressions are emitted as ready-to-paste
  text in each detector's native format. The skill never edits source and V1 writes no file.

### Changed

- **README roster repaired.** The prose said "Three skills" while four were on disk and
  `audit-comment-residue` had no bullet at all; the roster now lists all six.
- **Beck tidying #2 ("Dead Code") routes both ways.** `skills/tidy/reference/tidyings.md`
  now points at `audit-dead-code` for finding candidates repo-wide, and the new skill
  points back at `tidy` for applying the deletion.

### Fixed

- **knip findings honor the requested target.** The lane still invokes knip at the
  project root (no per-file input mode preserves cross-file usage) but now drops
  any finding whose path is outside the scoped `TS_FILES` set, so
  `--lane knip src/one-file.ts` no longer emits every owned file's unused
  exports.
- **Hoisted workspace installs are restored.** The knip restore probe walks
  ancestors for a nonempty `node_modules` the same way the binary locator does,
  so a nested package with no local cache is not marked degraded when the
  hoisted ancestor install is present.
- **Documented Bash floor matches namerefs.** `audit-dead-code` uses `local -n`
  (Bash 4.3+). The plugin README now states **Bash 4.3+** instead of "Bash 4+".

## [0.14.3]

### Fixed

- **`audit-comment-residue` shape-definition examples no longer self-match
  `audit-noise` (#3191).** Three rows of the residue-shape table wrote their
  illustrative phrases in plain double quotes (`"Task 2 replaces the old…"`,
  `"per your request"`, `"see PR #45"`). `audit-noise` strips inline-code spans
  before matching, so the sibling skill's backticked examples stay invisible
  while these three rows flagged against their own definitions. The quoted
  phrases are now wrapped in backticks. Detector behavior is unchanged.

## [0.14.2]

### Fixed

- **`audit-comment-residue` decodes the paths v1 porcelain escapes (#3126).** `0.13.3` fixed the
  spaced-path false negative by slicing the v1 record, and recorded at the parse site that git's
  octal escapes for control and non-ASCII bytes were still not decoded, so such a path continued
  to miss. `detect.sh` now reads the NUL-delimited `--porcelain -z` form instead, which git
  documents as performing no quoting or backslash-escaping, so there is nothing left to decode:
  `café.py`, a name holding a tab or a backslash, and a name literally containing `" -> "` all
  reach the audit. Under `-z` a rename emits the new path first and the original as a following
  record — the reverse of v1's display order — and that second record is consumed and dropped, so
  the intent-to-add rename `0.13.3` gated on the worktree status letter resolves structurally
  rather than by string-matching an arrow.

  The skill's `Uncommitted code files` pre-computed context moves to `-z` with it. `0.13.3` brought
  that line to parity with the v1 slice and added a test that extracts and runs it, so leaving it
  behind would have reopened the divergence that test exists to prevent — the audit would find
  `café.py` while the preview shown to the model still listed nothing. That test now reads the
  porcelain invocation out of `SKILL.md` as well as the awk program, rather than hardcoding a
  form: feeding `-z` input to a v1 program makes the v1 program look correct, because `-z` output
  carries no quoting for it to fail at decoding, so a hardcoded harness would have masked exactly
  the mismatch it was checking for. Its fixture set gains a non-ASCII name, the only one of the
  cases that both parses do not already agree on.

## [0.14.1]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).

## [0.14.0]

### Added

- **`dissolve-comments` empty-argument scope fallback (#3117).** A clean tree no longer ends the
  run at the friendly no-op exit: the empty argument now resolves down a ladder — uncommitted
  diff → the current branch's diff vs. the base/default branch (the PR diff when there is one) →
  the whole repository. The ladder advances on a rung's absence, never on emptiness — a rung that
  exists but yields no code files ends the run with the exclusion tally instead of widening, so a
  docs-only branch never escalates to repo-wide scope. Widening to repo-wide scope is confirmed
  in an interactive session (state what resolved and why, get a yes); a non-interactive/autonomous
  run proceeds deterministically but takes any widened scope in **safe mode** (class-A deletions
  only, every class-B as a proposal), never the full default mode.
- **Zero-in-scope runs report the exclusion tally (#3117).** A resolved scope whose every
  enumerated file is dropped by exclusions/exemptions reports total enumerated, 0 in scope, and
  counts per drop reason (non-code, GLOBAL HARD path, exempt surface, SSOT copy) instead of
  exiting silently — a clean repo is now distinguishable from a misconfigured run.

### Changed

- **`.claude/` exclusion wording reconciled (#3117).** `tidy`'s exclusions reference phrased the
  Claude Code surface as an enumerated glob list (`.claude/hooks/**` et al.) while
  `dissolve-comments`' safety reference said "`.claude/` agent config and hooks" — a literal
  reader of each reached different answers for a settings-wired bootstrap script outside
  `.claude/hooks/`. The GLOBAL HARD entry now covers `.claude/**` in full plus any script wired
  as a hook command in either project settings scope (`.claude/settings.json` or
  `.claude/settings.local.json`) wherever it lives (hook commands may point outside `.claude/`);
  the safety reference and `tidy`'s orientation summary state the same list.
- **The SSOT / materialized-copy header check is a Workflow scoping step (#3117).**
  `dissolve-comments` checked file headers for SSOT / do-not-edit declarations only as a Gotchas
  bullet; the check gates whether a file may be edited at all, so it now lives in Workflow step 1
  (triage the source, run its declared sync, never touch a copy) with the gotcha shrunk to a
  pointer plus the war story.

## [0.13.3]

### Fixed

- **`audit-comment-residue` no longer silently skips paths containing spaces
  (#3126).** The default-target router parsed `git status --porcelain` with
  `awk '{print $NF}'`, which split a spaced path on its space and kept git's
  closing quote, so the file resolved to nothing and dropped out of the run.
  The audit then reported `files=0` plus `no code targets` — a false negative
  that reads as a clean tree, ending the investigation rather than prompting a
  retry. `detect.sh` now slices the path out of the porcelain record, takes the
  right-hand side of a rename (gated on the `R`/`C` status letter in **either**
  the index or the worktree column, so an ordinary path containing `" -> "` is
  left intact while an intent-to-add rename — `mv old new && git add -N new`,
  which records `R` in the worktree column — still resolves), and unwraps git's
  quoting.
  The skill's own `Uncommitted code files` pre-computed context carried the
  identical `$NF` parse and is fixed to full parity — same column handling and
  the same `\"`/`\\` unescaping — rather than only to the quote-stripping half.
  The test suite now **extracts** that parser out of `SKILL.md` and executes it
  against the same fixtures, so the two cannot silently diverge again. Git's
  octal escapes for control and non-ASCII bytes are still not decoded by either,
  so such a path continues to miss; the limitation is recorded at the parse site
  instead of being silent.

## [0.13.2]

### Changed

- **Fixture-building tests clear inherited git environment (#2872).** Suites
  that build a git fixture now unset `GIT_DIR`, `GIT_WORK_TREE`, and
  `GIT_CONFIG` so an inherited environment cannot write the fixture identity
  into the caller's repository. Test-only; no plugin behavior change.

## [0.13.1]

### Changed

- **Cross-skill chains name the Skill tool (#3002).** `batch-simplify`'s grounding step
  (`/discovery:explore`, `/discovery:research`), its work-item filing (`/work-items:track add`),
  and its `context/reference.md` verification step (`/toolchain:check`); `tidy`'s explore/research
  steps, its PR step (`/source-control:pull-request create`), its scope-budget overflow filing
  (`/work-items:track add`, step 5), and `reference/scope-budget.md`'s
  deferral filing; `dissolve-comments`' `reference/safety.md` commit hand-off
  (`/source-control:commit`). Wording only — presence gates, fallbacks, and step order unchanged.

## [0.13.0]

### Added

- **`batch-simplify` narrows any scope to a path.** The argument grammar is now
  `[<scope>] [<path>...] [docs]`: a scope selects the file universe (a time window, the branch diff,
  or the whole repository) and a path selects a region of it. Narrowing is orthogonal to scope
  rather than a repo-only sub-mode, because binding it to `repo` would assert that only the
  whole-repository universe may be narrowed — leaving "what I changed this week, but only under
  `plugins/knowledge`" unreachable and forcing a second grammar change later. The path is applied as
  a native git pathspec on each mode's own discovery command, so merge-base semantics for branch
  mode and `--since` for a time window still hold over the narrowed set, and repo mode's
  confirmation gate and tracked-modification refusal still fire on the narrowed inventory. Purely
  additive: a path argument previously fell through to the ask-the-user rule in every mode, so no
  existing invocation changes meaning. A token counts as a path only if it **resolves** — without
  that condition the addition would have weakened the token-exact typo guard, turning `rebranch`
  from an explicit question into a silent sweep of nothing.
- **`repo <lane>` is explicitly rejected**, with the rationale recorded in the reference spoke. A
  lane in the sibling `/code-tidying:tidy` is a seven-part object (scope globs, merge semantics,
  watch-for patterns, extra exclusions, verification commands, commit type, research sources) of
  which this skill would use only the globs; reusing the word would leave `lane` meaning two
  different things in sibling skills of one plugin. Paths also compose where lanes do not — lanes
  exist only in repos that have configured `.claude/tidy-lanes/`.

### Changed

- **The hotspot-ranking question is recorded as settled** in `context/repo-mode.md`. The spoke
  previously argued only against the weak forms (churn alone, churn weighted by file size), leaving
  the strong form — churn weighted by a complexity or code-health measure, which is what "hotspot
  analysis" usually means — unaddressed and so open in practice. It is now rejected on a reason that
  reaches the strong form: ranking answers "where should I look first", a triage question repo mode
  has already answered by sweeping every group and filing High-only with no cap, so reordering work
  that is all going to happen anyway has no consumer. The one condition under which reopening would
  be coherent is named: ordering only matters under truncation or resume, so a truncation knob would
  have to land first.

## [0.12.1]

### Changed

- **Explicit `disable-model-invocation` on `batch-simplify` (#2968).** The skill now states the
  invocation mode the harness already applied for an absent key (`false`), so the choice is
  auditable and gated by `skill-quality:check` check 24. No behavior change. Rubric:
  `docs/conventions/invocation-mode/README.md`.

## [0.12.0]

### Added

- **`batch-simplify` gains a third scope mode, `repo`** — a behavior-preserving simplification
  sweep over every code file in the repository, not just a diff. Entry is explicit only: an
  explicit `repo` argument, or the user accepting the offer the empty-scan exit now makes. It
  never auto-escalates, and it presents an inventory summary — file count, group count, wave
  plan, scale estimate, exclusions by class — for confirmation before any group is dispatched.
  The file universe is `git ls-files --cached --others --exclude-standard` anchored to the repo
  root, so untracked non-ignored files are swept too and a run started in a subdirectory still
  covers the whole tree. The run refuses to start on tracked modifications inside the sweep
  universe, scoped so it cannot block the checklist the skill writes as its own first step, or
  any resume. `repo <path>` is deliberately not accepted in this version.
- **New progressive-disclosure spoke `context/repo-mode.md`**, loaded only when the mode fires:
  two-pass grouping with canonical-cluster detection (generated copies are edited via their
  source, never directly); dependency-only ordering with the reasoning against churn ranking
  recorded; a 4–6 concurrent-simplifier soft cap stated against the tooling's 20-subagent
  ceiling, degrading to sequential rather than retrying; an inline-prompt spawn contract that
  states the Write/Edit path explicitly and does not invoke the bundled `/simplify`; a mandatory
  per-group refutation verifier; idempotent resume with revert scoped to the group's file list;
  per-wave verification plus an end-of-run union pass; High-only work-item filing with no numeric
  cap; and one independently mergeable pull request per wave.
- **Externally managed and sync-generated directories are now a read-only deferred class** in the
  Phase 2 filters, recognized from what the consuming repo documents about itself rather than
  from a hardcoded path.

### Changed

- **`batch-simplify` Phase 7's verification exemption is scoped to the diff-scoped modes.** It
  previously asserted that an objective cross-ecosystem pass is "verification enough" because
  simplification is behavior-preserving — a scale-invariant claim that repo mode contradicts,
  since at repo scale no human reads the diff before it merges. Phase 7 also now reports files
  with no mapped test suite as unmapped rather than as passing.
- **`tidy` and `dissolve-comments` no longer describe `batch-simplify` as diff-only.** `tidy`'s
  differentiation prose named "a time-window or branch diff in waves" — the exact mechanism repo
  mode removes — and `dissolve-comments` called it "windowed batch sweeps" in two places. A
  reciprocal documentation boundary is now stated in both `batch-simplify` and `tidy`:
  `batch-simplify` owns factual staleness across the whole doc set in one pass; `tidy`'s
  `docs-prose` lane owns incremental structural prose work under a scope budget.
- The run checklist template gains repo-mode-conditional rows and states the filing tier per
  mode.

## [0.11.1]

### Fixed

- `batch-simplify` argument parsing is now token-exact. Branch mode matched any argument
  *containing* "branch", so a path or filename carrying those six letters silently swept the
  wrong file set; it now matches the whole argument against the branch trigger phrases. The
  `docs` flag was stripped by substring before mode parsing, which mutated any argument
  containing those four letters — including a `docs/` path — and left a corrupted remainder
  for the mode parser; it is now dropped token-wise, only when a token equals `docs`.
  Unknown arguments still route to the ask-the-user rule rather than a guess.

## [0.11.0]

### Added

- **New skill `/code-tidying:dissolve-comments`** — the edit-applying enforcement
  counterpart to `audit-comment-residue`: a three-way comment triage over a diff or
  explicit target that deletes zero-information comments, dissolves code-expressible
  comments into names and structure via named Fowler-catalog refactorings and then
  deletes them, and keeps only terse, load-bearing comments code cannot express.
  Class-B refactors apply only behind a discovered runnable test net (lint never opens
  the apply path); `safe` mode restricts applied edits to removals. Public-API doc
  comments, legal headers, machine-read directives, `TODO(#issue)` markers, and the
  plugin's standard path-exclusion tier are never touched; removed narrative is staged
  as a proposed commit-message block before deletion is final. Doctrine grounded in a
  verified research pass (Fowler, Martin ⇄ Ousterhout debate, McConnell, Google
  eng-practices, Anthropic prompting guidance) and locked through an interviewed,
  two-validator-audited task-branch Brief (contract tier — pruned before merge per the
  topic-docs convention); the surviving doctrine lives in the skill's `reference/`
  docs, and the decision trail in the branch history of
  `.work/plugin-marketplace-code-clarity/interview-checklist.md`.

### Fixed

- **README skill list drift** — `audit-comment-residue` was missing from the README's
  skill list; both it and the new `dissolve-comments` are now listed.

## [0.10.3]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.10.2]

### Changed

- **`tidy` no longer path-cites `source-control`'s private reference.** The §2.4.1 parenthetical
  and a §2.6 prose cite into `pull-request/reference/create.md` are removed (encapsulation audit,
  Path B); the `/source-control:pull-request create` invocation already in the sentence is the
  public reference.

## [0.10.1]

### Changed

- **Declared deviation for the single-layer gap (#723).** Tidy lane resolution
  intentionally omits the config-cascade contract's user-global and `*.local.*`
  overlay rungs: lane scope, verification commands, and watch-for patterns are
  repo-specific, the bundled lane is already the portable cross-repo baseline,
  and personal variation is limited to lane names the team does not track (an
  uncommitted team-path lane file never added to the index). Documented in the
  `tidy` and `setup` skills, plugin README, and the config-cascade Implementers
  row — closes the open conformance gap without adding overlay resolution.

## [0.10.0]

### Fixed

- **`/code-tidying:tidy`'s open-PR-count grant was inert.** It granted
  `Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/tidy/scripts/open-pr-count.sh:*)`, but
  `${CLAUDE_PLUGIN_ROOT}` is not substituted in `allowed-tools` — only `${CLAUDE_SKILL_DIR}` and
  `${CLAUDE_PROJECT_DIR}` are — so the rule stayed a literal string and never matched. The throttle
  pre-compute has been prompting or falling to the classifier since it shipped.

- **`/code-tidying:audit-comment-residue`'s grant worked, but only by accident.**
  `Bash(bash *audit-comment-residue/scripts/detect.sh*)` matched because its leading and trailing
  wildcards absorbed both the `bash` wrapper and the quotes around the body's path. That is the
  wildcarded-interpreter shape auto mode drops outright, and a rule anchored on a bare wrapper name
  matches that name at *any* path, including an unvetted copy.

  Both are repaired the same way, and the repair is not the obvious one. Dropping `bash` from the
  rule alone would have made these grants **dead**: `bash` is not among the wrappers Claude Code
  strips before matching (`timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`,
  `noglob`), so a rule without it stops matching a body that still says `bash <path>`. For
  `audit-comment-residue` that would have been a regression from a working grant to a broken one. The
  change is **paired**: the bodies invoke their scripts directly and unquoted, and the rules name the
  same strings — `Bash(${CLAUDE_SKILL_DIR}/scripts/open-pr-count.sh:*)` and
  `Bash(${CLAUDE_SKILL_DIR}/scripts/detect.sh:*)`.

### Changed

- **Both skills now grant the read-only commands their pre-computes pipe through** (`grep`, `head`,
  `echo`). A permission rule must match each subcommand of a compound command independently, so a
  script grant on its own left the surrounding pipeline uncovered and the pre-compute prompted
  regardless of whether the script rule matched.

### Added

- **`scripts/allowed-tools-pairing.test.sh`**, asserting the contract the fix establishes: no
  interpreter-led grant and no `${CLAUDE_PLUGIN_ROOT}` in `allowed-tools`, every bundled-script
  invocation in skill markdown unquoted and free of a `bash` wrapper, and every granted script
  present, executable, and actually invoked by a body.

## [0.9.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.8.0]

### Changed

- **`shell-tooling` lane decomposed to conform with the config-cascade contract (#724).**
  The bundled lane no longer tells a project lane at `.claude/tidy-lanes/shell-tooling.md` to replace
  it wholesale. It now publishes a `## Merge semantics` declaration to adopt, mirroring the
  `docs-prose` decomposition (#701): `Scope` is a per-section override (retargets tooling globs),
  while the watch-for patterns are **additive per language subsection** (a project's `### Bash` /
  `### PowerShell` entries append to the bundled ones), so bundled pattern improvements keep reaching
  consuming repos. Three calls the flat `docs-prose` shape did not have to make: `Preferred research
  sources` and `Verification commands` each carry explicit `### Bash` / `### PowerShell` subsections and
  override at that `###` granularity, so retargeting one language never silently wipes the other's
  authorities or checks;
  and `Lane-specific extra exclusions` is additive rather than an override, because the
  hook-directory HARD exclusions are what this lane exists around (they are on the plugin's global
  HARD list besides, which no lane layer resolves). No engine change — the resolution engine landed in 0.7.0 already merges whenever the
  project lane declares the section.
- **`docs-prose`'s declaration reworded to match.** Its `## Merge semantics` block described itself in
  absolute terms ("a project lane does **not** replace this file wholesale") when the engine merges
  only where the project lane declares the section. Same adopt-this-shape framing as `shell-tooling`
  now; no change to what any lane resolves to.
- **`setup` scaffolds bundled-lane overrides as merging lanes.** `apply` now writes only the sections
  a repo actually diverges on plus a `## Merge semantics` block, instead of starting from a full copy
  of the bundled lane — a copied section is frozen at its copy-time value, so the old instruction
  produced exactly the freeze-out the decomposition removes. `check` correspondingly stops FAILing a
  lane for a section it legitimately inherits (declared `## Merge semantics` + a bundled lane of the
  same name); it reports the inherited sections instead. The exemption is the declaration's, not the
  heading's — `check` FAILs a `## Merge semantics` section that is empty, unrelated, or silent on an
  omitted section, and an override of a `###`-keyed section that leaves its own content unkeyed.

## [0.7.2]

### Changed

- **Doc reference updated for the `config-cascade` seam rename (#1188).** The layering-contract link in
  `tidy/SKILL.md` and `tidy/lanes/docs-prose.md` now points at `docs/conventions/config-cascade/`
  (formerly `consumer-config-layering`). No behavior change.

## [0.7.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.7.0]

### Changed

- **`docs-prose` lane decomposed to conform with the consumer-config layering contract (#701).**
  A project lane at `.claude/tidy-lanes/docs-prose.md` no longer replaces the bundled lane wholesale.
  It now merges **per section** via a declared `## Merge semantics` block: the `Scope` block is a
  per-section override (retargets doc globs), while the generic watch-for patterns (P-1..P-6) are
  **additive** (a project's entries append to the bundled set), so bundled pattern improvements keep
  reaching consuming repos instead of being frozen out. The `tidy` lane-resolution engine now reads
  **both** the project and bundled layers and merges per the project lane's declared semantics; a lane
  with no `## Merge semantics` declaration still resolves project-only (legacy path), so lanes not yet
  migrated (`shell-tooling`, tracked in #724) are unchanged. Follow-up: the single-layer gap — no
  user-global or `*.local.*` overlay — is tracked in #723, not folded in here.

## [0.6.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.6.0]

### Changed

- **BREAKING — the `comment-residue` skill renamed to `audit-comment-residue`** (fleet conformance
  wave, naming grammar): `/code-tidying:comment-residue` → `/code-tidying:audit-comment-residue`. The
  old invocation stops resolving; update any saved references. The in-code `comment-residue-ignore`
  opt-out marker is unchanged.

## [0.5.1]

### Changed

- **batch-simplify resolves verification commands through the registered
  ecosystem-command owner** (fleet conformance wave, registry single-home).
  The baked per-ecosystem command table is gone: `/toolchain:build` when
  installed, else the project's own canonical commands, else manifest-derived
  entry points — never a memorized list.

## [0.5.0]

### Changed

- **`setup` split onto the uniform check/apply contract.** `check` inspects the tracked
  `.claude/tidy-lanes/<lane>.md` project lanes read-only (presence — absent is INFO, since `tidy`
  falls back to the bundled lanes — required sections, unreplaced `<placeholder>` tokens, and
  tracked-not-ignored via `git check-ignore`) and reports a PASS/FAIL/INFO table; `apply` runs the
  interview-and-scaffold flow, then re-runs `check` to verify each written lane. The lane/template
  scaffolding logic is unchanged; the read-only inspection path and the `check | apply` argument-hint
  are new, and `apply <lane>` targets a single lane.

## [0.4.3]

### Changed

- README declares the Bash 4+ requirement of the bundled scripts (`mapfile`,
  case-conversion expansions) with its Windows path (Git Bash) — cross-platform
  declaration wave. Script behavior unchanged (CRLF and drive-letter handling
  already present).

## [0.4.2]

### Changed

- Updated cross-plugin references for the `docs-hygiene` skill rename
  `declutter` → `audit-noise`: `comment-residue` now routes markdown noise to
  `/audit-noise` (SKILL.md, evals, detect script help text).

## [0.4.1]

### Changed

- Synced work-item filing routes to the reorganized `work-items` taxonomy:
  `/work-items:work-items add` is now `/work-items:track add` (README, `tidy`,
  `batch-simplify`, and the scope-budget reference).

## [0.4.0]

### Added

- Stdlib-only frontmatter-fence integrity check in the self-update lane's verification commands: a portable python one-liner that confirms every SKILL.md's `---` fences are present and the frontmatter between them is non-empty, since a broken fence would block the next session's skill discovery.
