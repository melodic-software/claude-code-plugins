# Changelog

All notable changes to the `code-tidying` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.13.3]

### Fixed

- **`audit-comment-residue` no longer silently skips paths containing spaces
  (#3126).** The default-target router parsed `git status --porcelain` with
  `awk '{print $NF}'`, which split a spaced path on its space and kept git's
  closing quote, so the file resolved to nothing and dropped out of the run.
  The audit then reported `files=0` plus `no code targets` — a false negative
  that reads as a clean tree, ending the investigation rather than prompting a
  retry. `detect.sh` now slices the path out of the porcelain record, takes the
  right-hand side of a rename (gated on the `R`/`C` status letter, so an
  ordinary path containing `" -> "` is left intact), and unwraps git's quoting.
  The skill's own `Uncommitted code files` pre-computed context carried the
  identical `$NF` parse and is fixed the same way. Git's octal escapes for
  control and non-ASCII bytes are still not decoded, so such a path continues
  to miss; the limitation is now recorded at the parse site instead of being
  silent.

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
