# PLAN: ADR authoring skill

**Spec container:** `github:melodic-software/claude-code-plugins#3802`
**Planning slice:** #3808. **Implementation slice:** #3818.
**Branch:** `plan/3808-adr-authoring-skill`. **Grounding date:** 2026-09-06.

## Brief

Restated from the container body on #3802. A thin ADR-authoring skill in the `architecture`
plugin, triggered by "record this decision" and reachable after `/planning:design-handoff`. It
discovers the consumer's existing ADR directory, numbering, and record shape and follows them.
When none exists it offers and defers; it never creates a convention unprompted. The upstream
template catalog is cited by URL only (CC BY-NC-SA 4.0, no vendored prose). The interview skill's
existing ADR offer routes to it presence-gated and behaves as today when the plugin is absent.

## Goal

**What**: add `/architecture:record-decision`, a single-owner ADR discovery ladder in the
`architecture` plugin, and two presence-gated routing sentences in the `planning` plugin
(interview, design-handoff).
**Why**: nothing today records a decision. The interview skill's ADR bullet has no target, and the
`improve` skill already carries an ADR discovery ladder that a second skill would otherwise
duplicate.

## Standards grounding

Small scale. Surfaces read, not recalled:

| Surface | What it fixed in this plan |
|---|---|
| `docs/PLUGIN-PHILOSOPHY.md` "Naming" | skill name is an imperative verb phrase: `record-decision`, not `adr` |
| `docs/PLUGIN-PHILOSOPHY.md` "Two-lane convention posture" | discovery over prescription; no shipped ADR directory default |
| `docs/conventions/seam-phrasing/README.md` | gate names the plugin, fallback stated in the same sentence, ownership framed |
| `docs/conventions/upstream-drift/README.md` | four-part record for the license citation |
| `.claude/rules/skill-bodies-state-current-rules.md` | skill bodies carry rules and reasons, no issue numbers or incidents |
| `plugins/skill-quality/scripts/check-skill.sh` header | 25 checks; description cap 1536, summary cap 100 codepoints, 500-line hard cap |
| `docs/MIGRATION-PLAYBOOK.md` "Evals" and "Version pinning" | evals warranted for judgment-bearing skills; version bump is the only delivery vehicle |

## What already exists (read before planning)

- `plugins/architecture/skills/improve/actions/deepening.md` line 24 carries an ADR discovery
  ladder (declared path in `CLAUDE.md`/rules first, then `docs/adr/`, `docs/decisions/`,
  `doc/adr/`, `.adr/`, `adr/`, plus `adr-*` / `*-decision*` files, walked from the examined
  directory up to the repo root). The new skill reuses it; it does not get a second ladder.
- `plugins/planning/skills/interview/SKILL.md` line 155 already holds the two-lane posture
  ("write to the repository's declared ADR convention ...; if none is declared, offer and defer.
  Never prescribe a location or format"). The routing change adds the presence-gated hop in
  front of that sentence and keeps the sentence as the absent-plugin branch.
- `plugins/planning/skills/plan/context/close-out.md` holds the three-part ADR admission test
  (hard to reverse, surprising without context, real trade-off). Installed plugins cannot read
  each other's files, so the new skill restates the test in one sentence; close-out itself is
  not rewired (deferred question D2).
- `plugins/planning/skills/design-handoff/SKILL.md` never mentions ADRs. "Reachable after
  design-handoff" is therefore a change to that skill, not an existing path.
- This repository's own `docs/adr/` has 33 records, no `README.md`, no template, and duplicate
  numbers (`0018`, `0025`, `0028` each appear twice). It is the live manual-test target for
  "infer the shape from the records" and "report duplicates without fixing them".
- Listing budget: `check-listing-budget.sh plugins/*/skills` reports an aggregate estimate of
  142,805 chars against an 8,000 default. Every new entry adds pressure; the new description is
  capped at 700 chars by this plan (container deferred question C4 stays open).

## Input contract (where the decision content comes from)

The skill reads the decision from `$ARGUMENTS` and the conversation. A file path the user names
is read verbatim. It never reads `design-threads.md`, `PLAN.md`, or any other planning artifact
on its own: those formats belong to the `planning` plugin, and a cross-plugin file dependency
would need its own gate. When a routing site (interview, design-handoff) wants a decision
recorded, it passes the decision statement and its rationale in the invocation text. When
context, decision, or consequences are missing from what it was given, the skill asks; it never
invents them.

## Plan

Single implementation slice (#3818), one PR, four sequential phases. Execution shape is
per-item PRs per the container body.

### Phase 1: skill and shared discovery ladder [TODO]

Files:

| File | Action | What changes |
|---|---|---|
| `plugins/architecture/skills/record-decision/SKILL.md` | Create | the skill (contract below) |
| `plugins/architecture/reference/adr-discovery.md` | Create | single owner of the ADR discovery ladder, numbering inference, template inference |
| `plugins/architecture/skills/improve/actions/deepening.md` | Modify | line 24: replace the inline ladder with one sentence plus a link to `../../../reference/adr-discovery.md`, keeping "honor a declared location first" and "a single default glob misses most of them" |

**SKILL.md contract.**

Frontmatter:

- `description`: 700 chars or fewer. Must carry, single-quoted: 'record this decision',
  'write an ADR', 'architecture decision record', 'capture this decision', 'document why we
  chose'. Must state the discover-and-follow behavior and the no-convention offer-and-defer in
  the lead sentence, and a `Skip when` clause for supersession, index, and status lifecycle.
  Draft (edit freely, keep the phrases):
  "Record an architecture decision into the consuming repository's existing ADR convention:
  discovers the ADR directory, numbering scheme, and record shape already in use and writes one
  record that follows them; when no convention exists it names what it searched, offers common
  shapes, and writes nothing until the human chooses. Use when: 'record this decision',
  'write an ADR', 'architecture decision record', 'capture this decision', 'document why we
  chose X', or after a design handoff or interview resolves a decision worth keeping. Skip
  when: the decision is easily reversed and unsurprising (no ADR earned), or the ask is
  supersession, an index, or status lifecycle beyond what the convention already defines."
- `argument-hint: "[decision and its rationale, or a path to a file holding them]"`
- `user-invocable: true`, `disable-model-invocation: false`, `shell: bash`
- `metadata: workflow-stage: anytime`, `summary:` 100 codepoints or fewer, no `cadence`
  (only `operator` takes one).

Body sections, in order:

1. "Repository context. Gather first": copy the `improve` skill's block verbatim (individual
   Bash calls: current branch, working tree status with `| head -10` inside the command;
   failure read as unknown).
2. "Variables": `$ARGUMENTS`.
3. "Purpose": three sentences at most.
4. "Input contract": the paragraph above, restated for the model.
5. "Admission test (advisory)": a decision earns a record when it is hard to reverse AND
   surprising without context AND the result of a real trade-off. When the decision plainly
   fails, say so once and offer to skip; the human's call wins.
6. "Step 1. Discover the convention": read `../../reference/adr-discovery.md` and walk the
   ladder from the working area up to the repo root. Emit one paragraph naming the directory,
   numbering scheme, template source, and any duplicates or shape disagreement observed.
7. "Step 2a. Convention found": derive the next identifier (highest existing + 1, preserve
   zero-pad width and separator), the filename in the observed form, and the section set from
   the template source. Re-read the target directory immediately before writing (another
   session may have added a record). Write exactly one file. Report its path. Do not create,
   rename, or renumber any other file; report duplicates and leave them.
8. "Step 2b. No convention": list the rungs searched, offer two or three common shapes
   (directory, numbering, minimal sections) and point at the upstream catalog URL so the human
   can pick a template; stop. Write nothing. When the human chooses in the same session, create
   only what they chose (directory plus first record), nothing else (no index, no README unless
   asked).
9. "Upstream template catalog": URL
   `https://github.com/joelparkerhenderson/architecture-decision-record`, license named as
   CC BY-NC-SA 4.0, no prose copied, with the four-part record: claim (README-authored content
   is CC BY-NC-SA 4.0; bundled templates carry their own licenses), basis
   (`https://raw.githubusercontent.com/joelparkerhenderson/architecture-decision-record/main/LICENSE.md`),
   as-of 2026-09-06, recheck trigger (that LICENSE.md changes, or the repository moves). The
   rule stated beside it: templates are cited for the human to read, never pasted into the
   skill or into a record.
10. "What this skill does NOT do": supersession workflows, index generation, status lifecycle
    beyond the convention, migrating existing records, prescribing a convention, reading
    planning artifacts.
11. "Composition": one table. Invoked from `/planning:interview` and
    `/planning:design-handoff` when that plugin is installed (descriptive; the gates live at
    the callers). `/architecture:improve` reads the same ladder when scanning.
12. "Gotchas": duplicate numbers (pick highest + 1, report, never renumber); records that
    disagree in shape (follow the newest, say so); a subtree-local ADR directory found before
    the root one (nearest wins, name both); a convention declared in `CLAUDE.md` that points at
    a directory that does not exist yet (declared wins: create the record there and say the
    directory was created because the declaration named it).

Org-agnostic: no publisher, marketplace id, fleet repo name, or `MELODIC_*` key anywhere in the
skill or the reference file.

**`reference/adr-discovery.md` contract.** Rungs in order, first hit wins, walked from the
working area up to the repo root:

1. Declared: a `.adr-dir` file at the repo root (its content is the directory); a path named in
   the project's `CLAUDE.md`, `AGENTS.md`, `.claude/rules/`, or a documented docs convention;
   a standards index entry that names where decisions live; a `README.md` or template file
   (`adr-template.md`, `template.md`, `0000-template.md`, `NNNN-template.md`) inside a
   candidate directory.
2. Existing directory: `docs/adr/`, `docs/adrs/`, `docs/decisions/`,
   `docs/architecture/decisions/`, `doc/adr/`, `doc/architecture/decisions/`, `.adr/`, `adr/`,
   `architecture/decisions/`, plus any `*.md` whose name matches `adr-*` or `*-decision*`.
3. None: no convention. The caller decides what that means (the `improve` skill reads nothing;
   `record-decision` offers and defers).

Then two inference rules: numbering (parse the identifier prefix of every record; next is
highest + 1 at the same zero-pad width and separator; date-prefixed schemes use today's date in
the observed format; duplicates are reported, never fixed) and shape (an explicit template or
README wins; else the newest two or three records; on disagreement follow the newest and say so;
keep the metadata block form, status vocabulary, and heading set exactly).

**Sanity Check (Phase 1).** From the repo root:

- `test -f plugins/architecture/skills/record-decision/SKILL.md` exits 0 (exits 1 today)
- `test -f plugins/architecture/reference/adr-discovery.md` exits 0 (exits 1 today)
- `grep -q "creativecommons.org/licenses/by-nc-sa/4.0" plugins/architecture/skills/record-decision/SKILL.md` exits 0 (exits 1 today)
- `grep -q "adr-discovery.md" plugins/architecture/skills/improve/actions/deepening.md` exits 0 (exits 1 today)
- `! grep -q "docs/decisions/" plugins/architecture/skills/improve/actions/deepening.md` exits 0 (the inline ladder is gone; exits 1 today)
- `! grep -rqi "captures an important architectural decision" plugins/architecture/` exits 0 (no vendored catalog prose; exits 0 today and must stay 0)
- `! grep -rqiE "melodic|MELODIC_" plugins/architecture/skills/record-decision plugins/architecture/reference/adr-discovery.md` exits 0
- `CHECK_SKILL_SKILLS_ROOT=plugins/architecture/skills bash plugins/skill-quality/scripts/check-skill.sh --require-evals record-decision` exits 0 after Phase 2 (exits 1 today: no such skill; exits 1 after Phase 1 alone because evals are absent)
- `CHECK_SKILL_SKILLS_ROOT=plugins/architecture/skills CHECK_SKILL_SKIP_MARKDOWNLINT=1 bash plugins/skill-quality/scripts/check-skill.sh improve` still exits 0 (exits 0 today, 1 warning)

### Phase 2: evals and fixtures for the new skill [TODO]

Files:

| File | Action | What changes |
|---|---|---|
| `plugins/architecture/skills/record-decision/evals/evals.json` | Create | seven cases, schema `plugins/skill-quality/reference/evals.schema.json` |
| `.../evals/fixtures/existing-convention/docs/adr/README.md` | Create | declares `NNNN-kebab-title.md`, next = highest + 1, sections Status, Date, Context, Decision, Consequences; says nothing about supersession or an index |
| `.../evals/fixtures/existing-convention/docs/adr/0001-*.md`, `0002-*.md`, `0003-*.md` | Create | three short records in that shape |
| `.../evals/fixtures/inferred-shape/docs/decisions/ADR-007-*.md`, `ADR-008-*.md`, `ADR-008-*.md` (two files sharing `008`) | Create | no README, headings Context / Decision / Status, a deliberate duplicate number |
| `.../evals/fixtures/no-convention/docs/README.md`, `.../no-convention/src/notes.md` | Create | a tree with a `docs/` directory and no ADR directory or declaration |

Every fixture path appears in a case's `files[]` (the orphaned-fixtures gate keys on that). No
fixture directory contains a `.git`.

Cases (id, name, fixture, what passes):

1. `records-into-existing-convention` (existing-convention): writes
   `docs/adr/0004-<kebab>.md` with the README's section set; creates no other file; reports the
   path.
2. `infers-shape-when-no-template` (inferred-shape): writes `docs/decisions/ADR-009-<kebab>.md`
   mirroring the newest record's headings; reports the duplicate `ADR-008` and renames nothing.
3. `no-convention-offers-and-writes-nothing` (no-convention): names the rungs searched, offers
   shapes and the catalog URL, creates no directory or file.
4. `writes-only-what-the-human-chose` (no-convention; prompt includes the human's choice of
   `docs/adr/` with `NNNN-title.md` and Context / Decision / Consequences): writes
   `docs/adr/0001-<kebab>.md` and nothing else (no README, no index).
5. `refuses-to-vendor-catalog-prose` (existing-convention; prompt asks to paste a template from
   the catalog): declines to copy, cites the URL and license, offers the repository's own shape.
6. `stays-inside-the-convention` (existing-convention; prompt asks to also update an index and
   mark `0002` superseded): records the decision; states that index and supersession are outside
   what this convention defines and stops.
7. `applies-the-admission-test` (no fixture; prompt: record that a lint timeout was raised from
   30s to 60s): says the decision does not earn a record and offers to record it anyway only if
   the human insists.

**Sanity Check (Phase 2).**

- `bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/architecture/skills/record-decision/evals/evals.json` exits 0 (exits 2 today: file missing)
- `jq '.evals | length' plugins/architecture/skills/record-decision/evals/evals.json` prints `7`
- `bash scripts/check-orphaned-fixtures.sh --check` exits 0 (exits 0 today and must stay 0)
- `bash scripts/check-fixture-git-isolation.sh` exits 0
- `CHECK_SKILL_SKILLS_ROOT=plugins/architecture/skills bash plugins/skill-quality/scripts/check-skill.sh --require-evals record-decision` exits 0

### Phase 3: planning routes (interview, design-handoff) [TODO]

Files:

| File | Action | What changes |
|---|---|---|
| `plugins/planning/skills/interview/SKILL.md` | Modify | line 155 bullet (exact text below) |
| `plugins/planning/skills/design-handoff/SKILL.md` | Modify | one bullet added to "Handoff summary (gate passed)" after "Resolved decisions with their recorded rationale" |
| `plugins/planning/skills/interview/evals/evals.json` | Modify | cases 17 and 18 appended |
| `plugins/planning/.claude-plugin/plugin.json` | Modify | `0.36.5` to `0.36.6` |
| `plugins/planning/CHANGELOG.md` | Modify | `## [0.36.6]` entry, Changed, naming both skills |
| `plugins/planning/README.md` | Modify | "Graceful degrade" bullet gains "decision recording (`architecture`)" |

Interview line 155, replacement text (one bullet; keep the existing sentence as the fallback):

> **ADR, offered sparingly** *(engineering sessions only)*. Propose an architecture decision
> record only when a decision is hard to reverse AND surprising without context AND the result
> of a real trade-off. When the `architecture` plugin is installed, invoke
> `/architecture:record-decision` via the Skill tool, passing the decision and its rationale; it
> owns convention discovery, the no-convention offer-and-defer, and the write. Otherwise write to
> the repository's declared ADR convention (a managed `docs/adr/` README, a project rule, or an
> existing `docs/adr/` shape); if none is declared, offer and defer. Never prescribe a location
> or format

Design-handoff, new bullet:

> **ADR candidates.** Each resolved decision that is hard to reverse, surprising without
> context, and the result of a real trade-off. When the `architecture` plugin is installed,
> offer to invoke `/architecture:record-decision` via the Skill tool for each one, passing the
> decision and its recorded rationale from `design-threads.md`; otherwise list them under an
> "ADR candidates" heading in the summary for the human to record by hand. The offer never
> blocks the handoff

Interview cases 17 and 18 (no fixtures needed; the prompt supplies the decision):

- 17 `adr-offer-routes-to-architecture-when-installed`: prompt states the plugin is installed
  and gives a decision meeting all three admission parts; passes when the output invokes
  `/architecture:record-decision` via the Skill tool with the decision and rationale, and does
  not itself pick a location or format.
- 18 `adr-offer-unchanged-when-architecture-absent`: same decision, plugin absent, using
  `evals/fixtures/lock-stop-on-gap/codebase-survey.md` (already names `docs/adr/` with four
  records) as the survey; passes when the output writes to that declared shape or offers and
  defers, and never invokes the missing skill.

**Sanity Check (Phase 3).**

- `grep -c "architecture:record-decision" plugins/planning/skills/interview/SKILL.md` prints `1` (prints `0` today)
- `grep -q "if none is declared, offer and defer" plugins/planning/skills/interview/SKILL.md` exits 0 (exits 0 today; the fallback sentence survives)
- `grep -c "architecture:record-decision" plugins/planning/skills/design-handoff/SKILL.md` prints `1` (prints `0` today)
- `jq '.evals | length' plugins/planning/skills/interview/evals/evals.json` prints `18` (prints `16` today)
- `bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/planning/skills/interview/evals/evals.json` exits 0
- `grep -q '"version": "0.36.6"' plugins/planning/.claude-plugin/plugin.json` exits 0 (exits 1 today)
- `grep -q "^## \[0.36.6\]" plugins/planning/CHANGELOG.md` exits 0 (exits 1 today)
- `CHECK_SKILL_SKILLS_ROOT=plugins/planning/skills CHECK_SKILL_SKIP_MARKDOWNLINT=1 bash plugins/skill-quality/scripts/check-skill.sh interview` exits 0, and the same for `design-handoff`
- `wc -l < plugins/planning/skills/interview/SKILL.md` prints a number below 500 (284 today)

### Phase 4: architecture plugin surfaces, regen, gates [TODO]

Files:

| File | Action | What changes |
|---|---|---|
| `plugins/architecture/.claude-plugin/plugin.json` | Modify | `0.6.10` to `0.7.0`; description gains one clause naming decision recording; keywords add `adr`, `decision-record` |
| `plugins/architecture/CHANGELOG.md` | Modify | `## [0.7.0]` entry: Added (record-decision, adr-discovery reference), Changed (deepening ladder pointer) |
| `plugins/architecture/README.md` | Modify | "What it does" gains a numbered item for decision recording; "Invoke" gains `/architecture:record-decision`; "Configuration" paragraph already says it adapts to the project's ADRs, keep |
| `.claude-plugin/marketplace.json` | Modify | architecture `tags` add `adr` |
| `docs/CATALOG.md` | Regenerate | `node scripts/generate-catalog.mjs` |
| `docs/SKILL-CHEAT-SHEET.md` | Regenerate | `node scripts/generate-cheatsheet.mjs` |

**Sanity Check (Phase 4).**

- `grep -q '"version": "0.7.0"' plugins/architecture/.claude-plugin/plugin.json` exits 0 (exits 1 today)
- `grep -q "^## \[0.7.0\]" plugins/architecture/CHANGELOG.md` exits 0 (exits 1 today)
- `grep -q "record-decision" plugins/architecture/README.md` exits 0 (exits 1 today)
- `grep -q "record-decision" docs/SKILL-CHEAT-SHEET.md` exits 0 (exits 1 today)
- `node scripts/generate-catalog.mjs --check` and `node scripts/generate-cheatsheet.mjs --check` exit 0
- `bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0 (exits 0 today with no bump; must still exit 0 with both bumps)
- `bash scripts/check-skill-leaf-names.sh --check` exits 0
- `bash scripts/check-skill-count-claims.sh --check` exits 0
- `node scripts/validate-plugin-contracts.mjs` exits 0
- `bash scripts/validate-plugins.sh` exits 0
- `bash scripts/check-changed-skills.sh origin/main` exits 0
- `bash scripts/affected-tests.sh --run` exits 0
- `npx markdownlint-cli2 "plugins/architecture/**/*.md" "plugins/planning/skills/interview/SKILL.md" "plugins/planning/skills/design-handoff/SKILL.md" "plugins/planning/README.md" "plugins/planning/CHANGELOG.md"` reports 0 issues

## Test strategy

- Static gates are the test net: the Phase 1 to 4 Sanity Checks above, all run from the repo
  root on the PR branch. Each phase has at least one check that exits 1 on the unmodified tree
  and 0 after the phase (verified on `main` at 912d6b3ec on 2026-09-06).
- Model-graded evals: seven new cases for `record-decision`, two appended to `interview`.
  `check-evals-quality.sh` and the CI schema step validate shape; grading runs when the eval
  runner is invoked.
- Manual run against this repository (the reviewer does this once on the PR branch):
  `/architecture:record-decision` with a decision from the PR description. Expected: the skill
  reports `docs/adr/`, `NNNN-kebab.md`, no README or template, shape inferred from `0030`
  (Status and Date lines, Context, Decision, Consequences), names the `0018`, `0025`, `0028`
  duplicates, and proposes `0031-<kebab>.md`. Discard the file afterwards; this repository's
  own ADR for this work, if any, is close-out's business.
- Manual run against an empty temp directory with `git init`: expected the no-convention
  branch, no file created, and `git status --porcelain` empty.
- Existing evals untouched: `improve` (5 cases) and `design-handoff` (its expectations name
  gate outcomes, not the bullet set of the summary).

## Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Name the skill `/architecture:adr` (the issue title's spelling) | Naming section requires an imperative verb phrase; `adr` is a noun with no registered exception | a documented naming exception for user-typed initialisms that covers this case |
| Keep the discovery ladder inline in `deepening.md` and copy it into the new skill | two ladders drift; reuse-or-replace | never; a single owner is strictly better here |
| Put the ladder in `skills/record-decision/context/` and have `improve` cite across skills | plugin-level `reference/` already hosts shared material (`topic-docs.md`) and is the established home | none |
| Route only the interview (leave design-handoff untouched) | the Brief's first criterion says "reachable after design-handoff", and that skill never mentions ADRs today, so nothing reaches it without a sentence | the human strikes that clause from the Brief |
| Also rewire `plan/context/close-out.md` step 2 | outside the Brief's constraints; deferred as D2 | a follow-up slice under a new container |
| Have the skill read `design-threads.md` itself | cross-plugin artifact dependency on a planning-owned format | never; the caller passes the content |
| Split #3818 into an architecture PR and a planning PR | the planning sentences name a skill that must exist; one PR keeps the seam atomic and the container has one implementation slice | a reviewer asks for smaller PRs; then land architecture first |
| Bump planning to 0.37.0 | fleet precedent (0.36.5 added a presence-gated route as a patch) | a reviewer reads the interview change as a behavior change consumers depend on |
| Ship a bundled minimal template for the no-convention branch | the Brief forbids prescribing; the catalog URL is the offer | a later container decides lane 1 applies to a minimal template |

## Blast radius

MEDIUM-LOW. Two plugins. One new skill directory and one new reference file; two sentences in
two planning skills; one line in `deepening.md`; version, changelog, README, manifest edits;
two regenerated docs. No hooks, no scripts, no schema, no consumer config surface. Rollback is
reverting the PR.

Risks:

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Listing budget: one more description in an already over-budget aggregate | High | Low per entry | description capped at 700 chars; container C4 notes this lane is drop-first |
| Interview check 3 warns on trigger-keyword drift | Low | Low | the description is untouched; only the body changes |
| Design-handoff evals grade the summary strictly | Low | Low | added bullet is additive; expectations name gate outcomes |
| A worker vendors catalog prose "for convenience" | Medium | High (license) | Phase 1 absence grep plus eval case 5 |
| The worker creates a directory on the no-convention path | Medium | Medium | eval cases 3 and 4; the SKILL.md step text says "write nothing" before any offer |
| Version parity gate fails on a CHANGELOG heading typo | Low | Low | Phase 4 runs `--check-bump origin/main` |

## Execution shape

Four phases, fully sequential: 1 → 2 → 3 → 4. Phase 2 grades Phase 1's skill; Phase 3 names
Phase 1's skill; Phase 4 regenerates docs from Phases 1 and 3. One worker, one PR, draft until
green. No parallel waves: the phases share `plugins/architecture/**` and the regenerated docs.

| Phase | Surface | Basis |
|---|---|---|
| 1 | sub-agent worker | file creation from a written contract |
| 2 | sub-agent worker | fixture and eval authoring from the case list |
| 3 | sub-agent worker | two exact sentence replacements plus two eval cases |
| 4 | sub-agent worker | mechanical bumps, regen, gate runs |

Divergence escalation applies verbatim to the worker brief: a precondition that fails, a file
or line that differs from this plan, or a design question stops the worker, who reports state
and waits.

## Open questions (deferred)

- D1 (container C4): listing-budget pressure across the fleet. Unchanged; this lane remains the
  designated drop-first lane.
- D2: `plan/context/close-out.md` step 2 still tells the model to write ADRs by hand at
  graduation. Rewiring it to `/architecture:record-decision` is a follow-up outside #3802.
- D3: the `improve` skill reads ADRs through the same ladder but takes no action on the
  no-convention rung. That asymmetry is by design and recorded in `adr-discovery.md`.

## Handoff to implementation

### User-approval gates

- None beyond PR review. No `[FALLBACK]` tags. A worker that wants to add a rung to the ladder
  not listed here stops and reports.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential, single worker, single draft PR, per-item PR shape. Worker brief is the body of
issue #3818 after amendment; this file is contract-tier and never merges.

### Mechanical work

Commit at the end of each phase. Run the phase's Sanity Check before its commit. Flip the PR to
ready only after the Phase 4 list is green. Prune this contract slice before merge per the
topic-docs convention (it lives on the planning branch, which is never merged).
