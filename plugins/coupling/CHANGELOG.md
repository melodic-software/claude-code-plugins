# Changelog

All notable changes to the `coupling` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.5] - 2026-10-04

### Changed

- **`/coupling:reduce` reads its per-run budget from the shared PR scope budget convention.** The
  plugin ships a generated copy at `reference/pr-scope-budget.md`, and the apply step points there
  instead of restating the target and hard cap. The convention leaves overflow handling to each
  adopter, so overflow still stays `proposed` in the ledger.

## [0.3.4] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.
- The plugin description is 500 characters or fewer, the limit claude.ai's marketplace sync enforces.

## [0.3.3] - 2026-10-02

### Fixed

- The `reduce` `argument-hint` uses Claude Code's official bracket notation: it keeps alternatives
  inside brackets with an unspaced `|`.

## [0.3.2] - 2026-10-01

### Changed

- Removed `reference/topic-docs.md` and its binding to the repository's topic-docs convention, which no longer exists. Plans, specs and findings live in the pull request body, the linked issue and the memory slice.

## [0.3.1] - 2026-09-28

### Changed

- **`reduce` remediations (#4583).** Externalize-environment-varying-values routes to
  `docs/plugin-philosophy.md` for the hardcoded-consumer-specifics doctrine instead of restating it.

## [0.3.0] - 2026-09-27

### Added

- `reduce change <old> <new>`: when one value changes, find every site that states it and
  classify each as setup, record, contract, fixture, generated, protected (CI, agent settings,
  hooks, lint configs, lock files, migrations), or unknown (a file kind the script does not
  recognize). `value-sites.py rules` prints every enforced pattern, and change-mode.md lists the
  same patterns under a suite check that fails when the two differ.
  Read-only; it reports the sites and proposes a reference form for each setup site.
- `reduce change apply <old> <new>`: after the human confirms the site list, change the setup sites,
  convert them to a reference form, and write contract corrections to a proposal file beside the
  ledger. A confirmed site set is not capped by the per-run budget.
- `skills/reduce/scripts/value-sites.py`: the deterministic inventory (every separator, escape,
  drive, and case spelling of the value, token boundaries, longest form first, path-based classes
  with a default-deny for unknown file kinds, a content anchor per row covering the line and its two
  neighbors, control bytes, Unicode line breaks, and bidi controls escaped in the row text, and a
  skip row for each binary, UTF-16, UTF-32, or outside-root file) and a byte-level `apply` that takes
  `path:line:col:anchor` sites and replaces only the match at that column. It refuses a site whose
  line changed since `find`, record, contract, generated, protected, and unknown sites, fixture
  sites without `--allow-fixture`, sites that are not tracked files inside the root, symlinks,
  hardlinks, binary and UTF-16 or UTF-32 files, unwritable targets, and any write that changes a
  file's control-byte count. It writes each file through a temp file and restores every replaced
  file if a write fails. Covered by `value-sites.test.sh`.
- `skills/reduce/reference/change-mode.md`: site classes, reference forms, the apply sequence, and
  pitfalls.

## [0.2.0] - 2026-09-23

### Changed

- `reduce` closes its report with what waits on the human first (the PR to merge, candidates
  needing a decision), then the ledger path and what was applied and routed.
- Scan subagents' briefs state when each is done and when it returns early.

## [0.1.8]

### Changed

- **Manifest description drops its em dashes.** Wording only; the plugin's behavior, options, and defaults are unchanged. The description renders into `docs/CATALOG.md`, which the repository's em-dash gate reads.
- **The plugin's prose drops its em dashes.** Six surfaces were rewritten: this changelog, `reference/topic-docs.md`, `skills/reduce/SKILL.md`, and three `skills/reduce/reference/` documents. Wording only, with no change to any coupling category, connascence level, remediation, or ledger status. The skill body keeps all twelve trigger phrases byte-identical. Two headings changed anchor, and the two Contents rows that linked them were updated in the same pass; nothing outside the file referenced either. `reference/topic-docs.md` now matches its seven sibling copies byte for byte rather than drifting from them. The released sections corrected in place are 0.1.1 and 0.1.0: their wording changed, their facts did not.
- **`seam` stays where this plugin defines it and goes where it does not.** `reference/coupling-model.md` keeps the published-seam entry, which names an explicit contract, a versioned API, or a documented extension point and then teaches that a seam is the fix working rather than the disease; `skills/reduce/SKILL.md` keeps "introduce a seam" in its list of architectural moves, the Feathers sense that document defines. The deletion test now reads "the new indirection", the word its own neighboring sentences use, and the ledger's rejected-reason placeholder states the condition instead of calling it load-bearing.
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`.** The gate now defends `CHANGELOG.md`, `reference/topic-docs.md`, every `skills/*/SKILL.md`, and the `skills/reduce/reference/` tree.

## [0.1.7]

### Changed

- **reduce:** the inert `shell: bash` frontmatter key is dropped, since no injection remains in the file (prompt-audit follow-up F12).
- **reference/topic-docs.md:** the contract pointer is the raw markdown URL again; the blob view with a section anchor is not fetchable at run time (prompt-audit follow-up F2).

## [0.1.6]

### Changed

- **reduce:** the gotchas section states its counterweights as current rules without the
  observed-failure framing, and the unverified-scan-claims rule keeps its reason without the
  incident that motivated it.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.1.5]

### Fixed

- **`reduce`:** the git pre-compute lines moved out of `## Pre-computed context` into a "Repository
  context. Gather first" body section of individual Bash calls, one command per call, each `head`
  bound kept inside its command and a failure read as an unknown value. The harness composes a
  skill's whole pre-compute block into one shell invocation, and a worktree-isolated session refuses
  a git-bearing compound command, which blocked these skills from loading inside a worktree. Same
  shape as the worktree skill's fix in #1619. Non-git pre-compute lines stay where they were.

## [0.1.4]

### Changed

- **Dynamic-context probe fallback made reachable.** The working-tree-status injection piped its
  probe into `head` before `||`, so the fallback could never run and a failed probe rendered an
  empty string under a label that reads as a clean tree. The fallback now sits in a brace group with
  the probe and the cap applies outside it. Whole-repo extract-ssot sweep.

## [0.1.3]

### Fixed

- **`reduce`'s coupling model has a working table of contents.** Its `## Contents` section listed
  all six headings as plain bullets with no links at all, so a reader of a 130-line reference could
  see the sections but not jump to one. Each row now links its heading and keeps the descriptive
  gloss as a when-to-read cue. Found while validating the sweep's table-of-contents pass, not by the
  audit itself. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.1.2]

### Changed

- **Instruction-surface de-slop (#2891, coupling cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change.

## [0.1.1]

### Changed

- **`reduce`: the hand-off table and its two prose chains name the Skill tool (#3002).** The
  `When | Then` table gains a one-line preamble stating that every skill in the `Then` column is
  invoked via the Skill tool; the PR step (`/source-control:pull-request create`) and the
  design-exploration hand-off (`/architecture:improve`) say so inline, as does the route-lane
  filing arm (`/work-items:track add`) in the same sentence as that hand-off. The table's
  preamble does not reach it, since it is prose outside the table. Wording only; presence
  gates and fallbacks unchanged.

## [0.1.0]

### Added

- `reduce` skill: iterative coupling reduction at four altitudes (docs, code, application,
  repository): model-typed scan with a verification gate, two-lane partition (safe
  behavior-preserving reductions applied under a scope budget; cross-file and architectural
  candidates surfaced and routed, never auto-applied), and a durable per-repo ledger via the
  topic-docs memory tier so successive runs resume instead of restarting.
- `reference/coupling-model.md`: the assessment model, covering the change-centric coupling definition,
  structured-design strength ladder, connascence (strength × degree × locality), volatility
  weighting, per-altitude mechanisms, and the not-a-finding list.
- `reference/remediations.md`: mechanism catalog (dependency injection, owned interfaces at
  volatile boundaries, configuration externalization, events/mediator, single-source-of-truth
  pointers, published contracts) with an explicit over-abstraction counterweight per entry.
- Topic-docs binding (`reference/topic-docs.md`) for the repo-scoped coupling ledger.
