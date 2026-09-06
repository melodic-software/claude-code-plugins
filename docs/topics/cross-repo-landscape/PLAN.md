# cross-repo-landscape

Container #3801 (`melodic-software/claude-code-plugins`). Planning slice #3807. Implementation
slices #3816 (map-landscape skill) and #3817 (design-handoff coverage table). Plan written
2026-09-06 against `origin/main` `912d6b3ec`. Design contract: `design/design-threads.md`
(T1–T11) and `design/design-resolution.md`. Verified 2026-09-06 by a fresh-context reviewer
(17 findings, all verified against the files and applied; summary under "Stress-test summary").

This file is contract-tier and never merges (`scripts/check-contract-slice-prune.sh`). Every
contract a worker needs is restated in the slice issue body; this file is the planner's and
reviewer's record.

## Brief

### TLDR

A new skill in the architecture plugin that maps a fleet of repositories into a C4 System
Landscape plus an application-portfolio table, and a six-dimension completeness check folded
into the design-handoff gate as advisory coverage reporting. No enterprise-architecture
framework is shipped as a skill.

### Goal

Answer "what systems do we have, who owns them, what do they run on, and how do they relate"
from the repositories themselves, and give the design-handoff gate a cheap completeness lens
over the six dimensions without importing a framework.

### Constraints

- Skill content is organization-agnostic: no publisher or organization names in the skill body.
- Repository discovery comes from an explicit argument, or from the repo-fleet-hygiene
  canonical-repo discovery when that plugin is installed. Amended 2026-09-06: the argument
  selects the mode. An explicit repository list bypasses discovery; a scan root triggers it,
  through the collaborator when installed and through the bundled walk otherwise. The
  collaborator's discovery is scoped, not argument-free, so a run with neither stops (T1, T2).
- Output lands in the consumer's declared architecture home, not a location this plugin picks.
  Amended 2026-09-06: no declaration mechanism existed; this lane creates it as a convention
  doc `<convention-home>/architecture/README.md` with `architecture_dir` and
  `landscape_dialect` keys, per
  `docs/adr/0018-express-team-shared-conventions-as-consumer-convention-docs.md` (T5), written
  by an operator-gated `architecture:setup apply` (T11). `architecture_dir` has no silent
  default: undeclared and unconfirmed, the skill stops and prints the recipe.
- The completeness check is advisory: it reports coverage and never blocks the gate on its own.
- No TOGAF or Zachman framework prose ships in either deliverable.

### Acceptance criteria (container, as amended)

- [ ] A map-landscape skill exists in the architecture plugin, discovers repositories from an
  explicit list argument, and uses the fleet-hygiene discovery when that plugin is present and a
  scan root is given.
- [ ] The skill emits a C4 System Landscape view plus a portfolio table carrying owner, target
  framework, runtime, dependencies, and last-touched date for each discovered repository.
- [ ] The design-handoff gate reports coverage of what, how, where, who, when, and why across
  resolved and directional design threads as an advisory table, and no coverage gap causes the
  gate to fail.

### Captured assumptions (as amended)

- The facts in the portfolio table are derivable from repository contents and metadata without
  a separate registry. Qualified: `owner` degrades CODEOWNERS → remote owner → `unknown`; the
  script never guesses (T3).
- Structurizr DSL and mermaid are both acceptable landscape dialects; the consumer's convention
  picks. Qualified: Structurizr has a native `systemLandscape` view; mermaid has no landscape
  type, so the landscape renders as a `C4Context` with no focal system, and mermaid marks its C4
  syntax experimental (T6; sources and recheck trigger recorded there).

### Out-of-scope

- Baseline-versus-target gap analysis (no written target architecture exists).
- TOGAF ADM guidance, the Zachman grid as a standalone skill, capability maps, work-breakdown
  structures.
- A standalone design-document skill.
- Container-level or component-level C4 views.
- Any write to a consumer's root instruction file outside the marked `convention-home` region
  (`architecture:setup apply` converges that region only, as the pilot does; `map-landscape`
  never writes it).

## Plan

Two file-disjoint phases, one PR each, parallel-safe. Neither depends on the other.

### Phase 1: `architecture:map-landscape` (#3816) [TODO]

Branch `feat/3816-map-landscape` from fresh `origin/main`. Files:

1. `plugins/architecture/skills/map-landscape/SKILL.md` (new). Frontmatter mirrors
   `skills/improve/SKILL.md`: `description` (with "Use when:" trigger phrases and a
   "Skip when:" clause naming `/architecture:improve` for single-codebase depth and
   `/repo-fleet-hygiene:audit` for cleanup), `argument-hint: "[--repos <a,b>] [--root <dir>]"`,
   `user-invocable: true`, `disable-model-invocation: false` (stated explicitly; check 24),
   `shell: bash`, `metadata.workflow-stage: explore`, `metadata.summary` ≤ 100 codepoints.
   Body sections, in order: Repository context (individual Bash calls, as `improve` does);
   Purpose; Resolve the architecture home and dialect (T5 ladder; run the vendored resolver,
   follow exit codes; inference proposes, confirmation binds; print the topic-doc recipe on
   confirmation; the reference doc is cited as `${CLAUDE_PLUGIN_ROOT}/reference/config.md`,
   never as a bare `reference/config.md`, which check 5 resolves against the skill directory);
   Discover repositories (T1 grammar; T2 seam with the gate sentence "when the
   `repo-fleet-hygiene` plugin is installed it owns bounded fleet discovery and
   canonical-checkout resolution: invoke `/repo-fleet-hygiene:audit` via the Skill tool with
   `--plan-file`; without it, run the bundled walk below and say so", the slug resolution and
   `mkdir -p` of the memory slice, the plan-file read filtered to `discovered` paths under a
   requested root, and the fallback walk rules); Collect facts (run
   `${CLAUDE_SKILL_DIR}/scripts/portfolio-facts.sh`,
   never derive by hand); Draw relationships (T4 evidence rule); Emit artifacts (T6, T7
   filenames and shapes, both dialects spelled out with a minimal example each in fences);
   What this skill does NOT do (modify any discovered repository; container/component views;
   gap analysis); Gotchas (mermaid asymmetry and experimental notice with source and date;
   `owner` ladder; local-HEAD last-touched; the fleet plan is a temp artifact in the memory
   slice, never committed). Under 200 lines (soft cap), never 500. No organization name, no
   framework name.
2. `plugins/architecture/skills/map-landscape/scripts/portfolio-facts.sh` (new, bash, POSIX
   awk/grep, no `grep -P`) and `portfolio-facts.test.sh` beside it: fixture repositories are
   created in `mktemp -d` by the test itself (one `.csproj` with `TargetFramework` and two
   `PackageReference`s; one `package.json` with `engines.node` and dependencies; one
   `pyproject.toml`; one `go.mod`; one empty repo; one with `CODEOWNERS`; one with an `origin`
   remote and no CODEOWNERS), each `git init`-ed with one commit so `last_touched` is real.
   Asserts every T3 field per fixture, including `unknown` on the empty repo, the dependency
   cap, and the owner ladder order. The test adopts the skill-script shape from
   `docs/conventions/shell-test-helpers/README.md` (`pass`/`fail`, `FAILED`/`CASE_NUM`
   counters) rather than a bespoke idiom. `scripts/run-plugin-tests.sh` discovers it.
3. `plugins/architecture/lib/resolve-convention-home.sh` (vendored copy): add the path to the
   `copies=(...)` array in `scripts/sync-resolve-convention-home.sh`, then run the script to
   copy. The canonical copy stays in `plugins/claude-config/lib/`.
4. `plugins/architecture/reference/config.md` (new): the consumer topic doc contract, modelled
   on `plugins/plugin-quality/reference/config.md` (where it lives, resolution order, format with
   a 4-backtick outer fence around the example, keys table for `architecture_dir`, which has
   no default, and `landscape_dialect`, default `mermaid`). No retired layers section (nothing
   to retire).
5. `plugins/architecture/skills/map-landscape/evals/evals.json` (new) with fixtures under
   `evals/fixtures/`, every fixture referenced by a case's `files[]`
   (`scripts/check-orphaned-fixtures.sh`). Cases: explicit list with the collaborator absent
   (both artifacts over exactly the listed repos, bundled walk not used); root with the
   collaborator installed (invokes the audit with `--plan-file`, reads canonical entries);
   root with the collaborator absent (bundled walk announced); dialect from a topic doc naming
   `structurizr` (emits `landscape.dsl` with `systemLandscape`); no topic doc and no inference
   evidence (asks once, defaults named); no scope at all (stops, names both forms).
6. `plugins/architecture/README.md`: add the skill to the "Invoke" block and trigger phrases,
   plus a short "Consumer configuration" pointer to `reference/config.md`.
7. `plugins/architecture/CHANGELOG.md`: `## [0.7.0]` / `### Added` / a bold lead reading
   "New skill map-landscape" with the name in a code span (minor bump; precedent `planning`
   0.22.0, 0.25.0).
   `plugins/architecture/.claude-plugin/plugin.json` version `0.7.0`; extend `description`
   and `keywords` (`c4`, `landscape`, `portfolio`). `.claude-plugin/marketplace.json` carries
   no version field; its `tags` list for the plugin is kept identical to `keywords` (they are
   byte-identical today; no gate enforces it, so parity is a convention kept by hand).
8. Regenerate `docs/SKILL-CHEAT-SHEET.md` and `docs/CATALOG.md` with their generators
   (`scripts/generate-cheatsheet.mjs`, `scripts/generate-catalog.mjs`); never hand-edit.
   `docs/CATALOG.md` changes because the plugin `description` changes.
9. `plugins/architecture/skills/setup/SKILL.md` (new) plus `evals/evals.json` (setup skills are
   not evals-exempt): T11 verbatim, modelled on `plugins/plugin-quality/skills/setup/SKILL.md`
   minus its retirement records. Frontmatter: `user-invocable: true`,
   `disable-model-invocation: true`, no `metadata` block (the cheat-sheet generator excludes
   skills named `setup` and errors when one carries metadata), and the double-quoted
   `argument-hint: "check | apply [home=<dir>] [architecture_dir=<path>] [landscape_dialect=<structurizr|mermaid>]"`
   that `scripts/validate-plugin-contracts.mjs` requires; the body documents `check` and
   `apply` in code spans. `check` prints a PASS/FAIL/INFO table with one remediation line per
   FAIL and modifies nothing. `apply` converges the marked `convention-home` pointer region
   (inside the markers only, preserving unrelated content) and the topic doc; idempotent;
   proposes and waits when arguments are incomplete; non-interactive when all three are
   supplied; re-reads and reports the stored values after writing. Eval cases: `check` with no
   pointer line (FAIL row plus remediation); `check` with a conforming topic doc (all PASS);
   `apply` with incomplete arguments proposes and waits; `apply` with complete arguments writes
   without prompting and reports the read-back values.
10. `docs/conventions/config-cascade/README.md` "Implementers" table: add the `architecture`
    row (consumer config path = convention doc at the consumer's convention home,
    `<home>/architecture/README.md`; layers = `team, via pointer line`; conformance =
    new surface under the expression doctrine, no retirement record; keys owned by the plugin's
    `reference/config.md`). Conformance is tracked, not assumed; a new surface with no row is
    the gap that table exists to expose.

**Sanity Check** (each line records its result on unmodified `origin/main` `912d6b3ec`, run
2026-09-06, then the expected result after the phase):

| Check | Command | Main | After |
|---|---|---|---|
| A1 | `test -d plugins/architecture/skills/map-landscape` | FAIL | PASS |
| A2 | `test -f plugins/architecture/lib/resolve-convention-home.sh` | FAIL | PASS |
| A3 | `grep -q 'plugins/architecture/lib/resolve-convention-home.sh' scripts/sync-resolve-convention-home.sh` | FAIL | PASS |
| A4 | `grep -q '^## \[0.7.0\]' plugins/architecture/CHANGELOG.md` | FAIL | PASS |
| A5 | `grep -q 'map-landscape' plugins/architecture/README.md` | FAIL | PASS |
| A6 | `grep -q 'map-landscape' docs/SKILL-CHEAT-SHEET.md` | FAIL | PASS |
| A7 | `! grep -qi 'melodic' plugins/architecture/skills/map-landscape/SKILL.md && ! grep -qi 'melodic' plugins/architecture/skills/setup/SKILL.md` | n/a (no file) | PASS |
| A8 | `! grep -qiE 'zachman\|togaf' plugins/architecture/skills/map-landscape/SKILL.md && ! grep -qiE 'zachman\|togaf' plugins/architecture/skills/setup/SKILL.md` | n/a (no file) | PASS |
| A9 | `grep -qE 'repo-fleet-hygiene' plugins/architecture/skills/map-landscape/SKILL.md && grep -qiE 'plugin is installed' plugins/architecture/skills/map-landscape/SKILL.md` | n/a (no file) | PASS |
| A10 | `grep -q 'systemLandscape' plugins/architecture/skills/map-landscape/SKILL.md && grep -q 'C4Context' plugins/architecture/skills/map-landscape/SKILL.md` | n/a (no file) | PASS |
| A11 | `bash plugins/architecture/skills/map-landscape/scripts/portfolio-facts.test.sh` | n/a (no file) | exit 0 |
| A12 | `test -f plugins/architecture/skills/setup/SKILL.md && grep -qE '^\| *.architecture. *\|' docs/conventions/config-cascade/README.md` (the dots stand for the backticks around the surface name; a literal backslash-backtick inside `grep -E` is a buffer-start anchor and can never match; run on main 2026-09-06: FAIL, the word `architecture` does not occur in that file at all) | FAIL | PASS |
| C1 | `bash scripts/sync-resolve-convention-home.sh --check` | PASS | PASS |
| C2 | `bash scripts/check-skill-count-claims.sh --check` | PASS | PASS |
| C3 | `bash scripts/check-orphaned-fixtures.sh --check` | PASS | PASS |
| C4 | `node scripts/validate-plugin-contracts.mjs` | PASS | PASS |
| C5 | `bash scripts/check-changelog-parity.sh --check-bump origin/main` | PASS | PASS |
| C6 | `bash scripts/check-changed-skills.sh origin/main` (the base ref is also `CHECK_SKILL_BASE_REF`; a stale local `main` skews both) | n/a | exit 0 |
| C7 | `npx markdownlint-cli2 <every changed .md>` | n/a | 0 issues |
| C8 | `shellcheck plugins/architecture/skills/map-landscape/scripts/*.sh` | n/a | clean |
| C9 | `bash scripts/validate-plugins.sh` (runs the contracts validator plus `generate-catalog.mjs --check` and `generate-cheatsheet.mjs --check`) | PASS | PASS |
| C10 | `bash scripts/check-changelog-parity.sh --check-preserved origin/main` | PASS | PASS |
| C11 | `bash scripts/check-changelog-parity.sh --check-order` | PASS | PASS |

Table cells escape `|` as `\|`; the commands as typed are `grep -qiE 'zachman|togaf'` and
`grep -qE '^\| *why *\|'` (the ERE alternation must be a bare `|`, or the absence check matches
only the literal string and passes vacuously). Absence checks (A7, A8) are paired with presence
checks on the same file (A9, A10) so a missing file cannot pass the pair. `grep -q` is used
throughout; `grep -c` exits 1 on zero matches and is never used as an absence assertion.

**Manual smoke** (recorded in the PR body, not a gate): run the skill against three local
repositories of different ecosystems with `--repos`, then once with `--root` and the
collaborator installed; confirm both artifacts land in the resolved `architecture_dir`, the
Structurizr output parses in the Structurizr Lite container or the DSL playground, and the
mermaid output renders on GitHub.

### Phase 2: coverage table in `planning:design-handoff` (#3817) [TODO]

Branch `feat/3817-design-handoff-coverage` from fresh `origin/main`. Files:

1. `plugins/planning/skills/design-handoff/SKILL.md`: new section `## Coverage report
   (advisory)` between "Binary gate" and "Handoff summary", carrying T8 verbatim: the six-row
   table shape (`Dimension | Covered by | Status`), the one-line reading rule per dimension, the
   status rule (RESOLVED or directional covers; TAGGED-DEFERRED never covers; `none` otherwise),
   emitted on PASS and FAIL alike after the unchanged verdict sentence, read over
   `design-resolution.md` on early-exit, never written to disk, never part of the verdict. The
   handoff-summary list gains one bullet ("Uncovered dimensions, verbatim from the coverage
   table") and the resume prompt carries them. Gotchas gain: "A coverage gap is information
   for the human, not a FAIL; do not promote it". The `description` gains one clause
   ("...then an advisory six-dimension coverage table...") while every existing "Use when:"
   phrase stays verbatim (check 3, trigger-keyword preservation against HEAD). The FAIL
   sentence "A thread that is unresolved AND untagged is a silent gap" is untouched.
2. `plugins/planning/skills/design-handoff/evals/evals.json`: three new cases, each with a new
   fixture referenced in `files[]`: `coverage-table-all-resolved` (fixture with threads that
   cover all six; expects six rows each naming a thread); `coverage-gaps-still-pass` (fixture
   with all threads resolved but nothing about `where` or `who`; expects PASS and two `none`
   rows); `coverage-on-early-exit` (a `design-resolution.md` fixture; expects the table read
   over it). Existing case 2 (`gate-fails-unresolved-untagged-thread`) gains one expectation:
   the FAIL verdict and routing are unchanged and the coverage table, if shown, follows them.
3. `plugins/planning/README.md`: the `design-handoff` row mentions the advisory coverage table.
4. `plugins/planning/CHANGELOG.md`: `## [0.37.0]` / `### Added` (a new output surface in an
   existing skill; minor). `plugins/planning/.claude-plugin/plugin.json` version `0.37.0`.
5. Regenerate `docs/SKILL-CHEAT-SHEET.md` only if `metadata.summary` changes (it should not).

**Sanity Check** (main results recorded 2026-09-06):

| Check | Command | Main | After |
|---|---|---|---|
| B1 | `! grep -qiE 'zachman\|togaf' plugins/planning/skills/design-handoff/SKILL.md` | PASS | PASS |
| B2 | `grep -qE '^\| *why *\|' plugins/planning/skills/design-handoff/SKILL.md` (the six reading rules are rendered as the example table itself, one row per dimension, so this row is the presentation contract, not an accident) | FAIL | PASS |
| B3 | `grep -q 'Dimension \| Covered by \| Status' plugins/planning/skills/design-handoff/SKILL.md` | FAIL | PASS |
| B4 | `test $(grep -c '"id":' plugins/planning/skills/design-handoff/evals/evals.json) -gt 5` | FAIL (5) | PASS (8) |
| B5 | `grep -q 'unresolved AND untagged is a silent gap' plugins/planning/skills/design-handoff/SKILL.md` | PASS | PASS |
| B6 | `grep -q '^## \[0.37.0\]' plugins/planning/CHANGELOG.md` | FAIL | PASS |
| B7 | `! (git diff origin/main -- plugins/planning/skills/design-handoff/SKILL.md \| grep -q '^-.*Use when:')` | PASS (no diff) | PASS; this is the only real gate on the description edit, since skill-quality check 3 is advisory and never FAILs |
| C2–C7, C9–C11 | as Phase 1 (C6 with `origin/main`) | PASS | PASS |

B1 passes on main by itself; B2 and B3 are the presence pair that fails today, so the trio
only passes once the section exists and still names no framework.

## Test strategy

No model-graded eval runner exists in this repository; `evals.json` is schema-validated and
quality-linted statically (CI `check-jsonschema`, `check-evals-quality.sh`). The deterministic
surfaces are:

| Surface | Boundary | Exists? | Test |
|---|---|---|---|
| `portfolio-facts.sh` JSON output | script stdout, one object per repo | introduced | `portfolio-facts.test.sh`, TDD: write the fixture assertions first, then the probes; `run-plugin-tests.sh` runs it |
| Vendored resolver | `lib/resolve-convention-home.sh` exit codes | exists (canonical in claude-config, tested there) | `sync-resolve-convention-home.sh --check` proves byte-identity; no new tests |
| Both SKILL.md files | static contract | exists | `check-changed-skills.sh main` (25 checks), `validate-plugin-contracts.mjs`, markdownlint |
| Eval cases | `evals.json` + fixtures | exists | schema + quality lint + orphaned-fixture gate |
| Gate behaviour on FAIL | prose | exists | eval case 2's added expectation; the manual smoke below |

Manual smoke for Phase 2 (recorded in the PR body): run `/planning:design-handoff` against the
three new fixtures copied into a scratch topic slice; confirm the verdict sentence is
byte-identical to today's on the single-gap fixture and the table has six rows on every run.

Criteria no gate in this repository can verify mechanically, and which the PR bodies must mark
as manual-smoke evidence so close-out does not read a green CI as proof: #3816 "produces both
artifacts over exactly the listed repositories", "uses its canonical-repository discovery", "is
a C4 System Landscape in the dialect the consumer's convention names", "written to the
consumer's declared architecture home"; #3817 "with the same message as today" (B5 pins one
sentence; byte-identity is the smoke). The setup skill's eval cases are schema-checked like
every other.

## Files affected

Phase 1: `plugins/architecture/skills/map-landscape/{SKILL.md,evals/evals.json,evals/fixtures/*,scripts/portfolio-facts.sh,scripts/portfolio-facts.test.sh}`,
`plugins/architecture/skills/setup/{SKILL.md,evals/evals.json,evals/fixtures/*}`,
`plugins/architecture/lib/resolve-convention-home.sh`, `plugins/architecture/reference/config.md`,
`plugins/architecture/{README.md,CHANGELOG.md,.claude-plugin/plugin.json}`,
`scripts/sync-resolve-convention-home.sh`, `.claude-plugin/marketplace.json` (tags only),
`docs/conventions/config-cascade/README.md` (one Implementers row),
`docs/SKILL-CHEAT-SHEET.md`, `docs/CATALOG.md` (generated).

Phase 2: `plugins/planning/skills/design-handoff/{SKILL.md,evals/evals.json,evals/fixtures/*}`,
`plugins/planning/{README.md,CHANGELOG.md,.claude-plugin/plugin.json}`.

The two sets are disjoint except the generated docs, which Phase 2 does not touch.

## Alternatives and switch conditions

| Decision | Alternative | Switch when |
|---|---|---|
| Read the fleet-hygiene plan JSON (T2) | Parse the audit's human report from conversation | The plan writer drops `schema_version` or fleet-hygiene documents the report as the consumer surface |
| Read the plan JSON (T2) | A fleet-hygiene `discover` mode that prints canonical repos | That mode ships (deferred question 1); switch the seam and delete the schema check |
| Facts collector script (T3) | Prose-only probes | The script cannot stay POSIX-portable for a required ecosystem; then keep the script for the portable subset and instruct prose for the rest |
| Convention doc via vendored resolver (T5) | topic-docs durable tier (`vault_backend`) | The consumer's convention home is unresolvable AND a vault backend is bound; today neither is common, and the convention doc is the ADR 0018 shape for team-shared prose config |
| Directional threads cover a row (T8) | RESOLVED only | Review finds directional coverage hides real gaps in practice; the change is one word in the status rule |
| Minor bumps (0.7.0, 0.37.0) | Patch bumps | A written semver rule appears that classifies a new output surface as patch |

## Risks

- **`owner` column quality.** No repository states organizational ownership; the ladder ends at
  `unknown`. Mitigation: the header and the skill say so; never inferred from authors.
- **Mermaid C4 is experimental upstream.** A syntax change breaks rendered landscapes.
  Mitigation: stamped claim with recheck trigger in the skill's Gotchas; Structurizr is the
  stable dialect and the skill says so when asked.
- **Fleet plan JSON is an undocumented cross-plugin surface.** Mitigation: `schema_version`
  check with a fallback to the bundled walk, announced; deferred question 1 asks the owner to
  publish a contract.
- **Resolver cluster drift.** Enrolling a third carrier means every canonical change bumps
  three plugins (`--check-bump`). Accepted: that is the ADR 0019 cost and CI enforces it.
- **Description trigger-phrase regression in design-handoff.** skill-quality check 3 is
  advisory (WARN, never FAIL), so the protection is B7: a diff assertion the PR must run
  proving no `Use when:` line was removed. The edit is additive only.
- **Fleet discovery is not free.** `/repo-fleet-hygiene:audit` collects GitHub evidence
  (`gh api`, `git ls-remote`) on every run, so discovery-only use pays for a full audit and may
  need `gh` authentication. The skill says so; deferred question 1 asks for a lighter mode.
- **Config-additive scope.** The collaborator walks every configured root in addition to the
  CLI root; the `discovered`-prefix filter (T2) keeps the landscape to what was asked for.
- **Coverage table read as a criterion.** The skill text and the Gotcha say advisory; eval
  case `coverage-gaps-still-pass` pins it.

## Blast radius

LOW–MEDIUM. Phase 1 is additive (new skill, new script, new reference doc) plus one line in a
shared sync script and a minor version bump; no existing skill changes behaviour. Phase 2
changes an existing gate's output shape but not its verdict; `/planning:plan` reads the
artifacts on disk rather than the gate's emitted text (`plugins/planning/skills/plan/SKILL.md`
"Has `/planning:design` been done?"), so no downstream hop consumes the changed output. Both
plugins are published; consumers receive the changes on update. All changes are git-revertible.

## Stress-test summary

One fresh-context verifier round (2026-09-06), 17 findings, each verified against the files
before acting: 1 CRITICAL (the issue bodies were not yet amended and #3816's criterion 2
contradicted T1; amended, see the issue notes), 5 IMPORTANT (config-additive scope could
widen the mapped fleet, fixed by the `discovered` filter in T2; skill-quality check 3 is
advisory, so B7 is the real gate on the description edit; the philosophy requires a `setup`
skill once a consumer configuration surface exists, added as T11; the config-cascade
Implementers table needs a row; three CI gates were missing from the C-series, added as
C9–C11), 11 SUGGESTION (all applied: table-escaping note, B2 presentation contract, C6 base
ref, slug and `mkdir -p` before the seam call, ownership framing in the gate sentence, ADR
filenames, collector path in design-resolution, `${CLAUDE_PLUGIN_ROOT}`-anchored reference
cite, keyword/tag parity, skill-script test shape, manual-smoke marking of unverifiable
criteria). Verified sound by the same round: plan-file keys, no-scope failure, read-only audit,
discovery restatement, verb-table stance, T8 status rule, no downstream consumer of the gate's
emitted text, marketplace version fields, bump levels, sync enrollment, generator inputs,
eval schema, test discovery, org-agnosticism tokens.

Second fresh-context round (2026-09-06, after the amendments and the issue-body rewrites), 14
findings: 1 CRITICAL (the A12 grep as typed used a backslash-backtick, which `grep -E` reads as
a buffer-start anchor, so it could never match; retyped with dots and re-run on main), 7
IMPORTANT (the same check truncated by CommonMark in the issue body; #3817's B2 requires bare
dimension names in the table, now stated; the collector invocation in #3816 lacked its
`${CLAUDE_SKILL_DIR}` anchor and the never-by-hand rule; the setup spec omitted the validator's
quoted `argument-hint` grammar, the philosophy's readback and non-interactive bullets, and the
pilot's pointer-region convergence, so T11 was realigned to the pilot; the absence greps
skipped the setup skill; the Brief's "argument as fallback" contradicted `--repos` winning
outright; T5 still carried a `docs/architecture` default), 6 SUGGESTION (all applied: fleet-plan
gotcha, `git fetch origin main` before the diff gates, B7 pairing note, no `metadata` block on
setup, a fourth container criterion for setup, amendment notes marking the plan as unreachable
from a worker's branch). Checks it ran on the current tree reproduce the recorded results.

## Execution shape

Per-item PRs (container setting). Phase 1 and Phase 2 are file-disjoint and run in parallel in
separate worktrees; no ordering dependency. Each phase is one worker (`implementation:implementer`
via `/implementation:implement-dispatch`), scope-fenced to its file list above. A Phase 1 worker
that needs the resolver's grammar reads the canonical copy's header comment; it never edits the
canonical copy.

| Phase | Surface | Basis |
|---|---|---|
| 1 | one worker, worktree-isolated | new files plus one shared-script line; judgment in SKILL.md prose, deterministic script under TDD |
| 2 | one worker, worktree-isolated | 66-line SKILL.md gains one section; evals + fixtures |

Close-out: container #3801 is graded against its amended body; the planning slice closes with
this plan's summary.

## Deferred questions

1. Should `repo-fleet-hygiene` publish a `discover`-only mode or a documented plan-JSON schema
   for consumers? File against that plugin when Phase 1 lands; until then the `schema_version`
   check plus fallback carries the coupling.
2. Resolved during verification: `architecture:setup` ships in Phase 1 (T11) because the
   plugin philosophy requires a setup skill once a consumer configuration surface exists, and
   its `apply` converges the shared pointer region exactly as the pilot's does (the region is
   machine-owned by doctrine). Nothing remains open here.
3. Should `/planning:design` Phase 2 prompt for threads across the six dimensions at design
   time (upstream of the gate)? Out of scope by #3817's exclusion; revisit after the table has
   been read in practice.
4. C3 from the Brief: baseline-versus-target gap analysis, blocked on a written target
   architecture.

## Handoff to implementation

- Worker briefs are the amended issue bodies of #3816 and #3817 (dated amendment notes).
- Both PRs bump their plugin version and CHANGELOG; nothing else enforces it.
- Both PRs must pass every C-series check locally before opening.
- Phase-tag edits to this file are unnecessary: it never merges.
