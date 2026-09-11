# docs-naming-consistency

## Brief

### TLDR

- Rename the 13 UPPERCASE-KEBAB `.md` files at the `docs/` root to lower-kebab-case with `git mv`,
  and update every live reference (links, backtick paths, bare names, runtime constants) to the
  new names.
- Leave two declared, removal-triggered compatibility tombstones at the old
  `docs/PLUGIN-PHILOSOPHY.md` and `docs/MIGRATION-PLAYBOOK.md` paths; no other stubs.
- Add enforcement: a deterministic `scripts/check-docs-naming.sh` (+ `.test.sh`, CI-wired,
  `affected-tests` mapped) and a path-scoped `.claude/rules/docs-naming.md` for `docs/**`.
- Record the rule as ADR 0031; file one follow-up issue for an ADR-number uniqueness gate.
- Everything else (in-file formatting, the reusable skill, ADR renumbering) is out of this PR.

### Goal

Every file under `docs/` follows one naming rule a reader can state in a sentence: lower-kebab-case
for markdown and data files, with the conventional exceptions (`README.md`, `CHANGELOG.md`,
`INDEX.md`, code files in their ecosystem's casing, and the branch-only contract slice), so that
the 13 root files stop being the only outliers, nothing that points at them breaks, and the drift
cannot silently recur.

### Constraints

- Filenames only. In-file formatting (headings, frontmatter) is deferred to a later pass.
- `git mv` per file, history-preserving; no content edit to `docs/PLUGIN-ARTIFACT-PROTOCOL.md`
  (six `plugins/*/reference/artifact-protocol.md` copies must stay byte-identical to it).
- Runtime consumers move in the same commit: `scripts/generate-cheatsheet.mjs`,
  `scripts/generate-catalog.mjs`, `scripts/validate-plugin-contracts.mjs`,
  `plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py` and `test_overlap.py`,
  `scripts/check-docs-only.test.sh`, `scripts/generate-cheatsheet.test.sh`,
  `scripts/docs-only-paths.txt`.
- Reference-update boundary (three-way): current surfaces (skill bodies, agents, READMEs, rules,
  scripts, prompts, `.github`, `docs/` outside `adr/`) update every form; `docs/adr/` bodies update
  links and backtick paths only, narrative untouched; plugin `CHANGELOG.md` released entries stay
  untouched except the one markdown link in `plugins/visualization/CHANGELOG.md`, fixed with a
  declared patch bump per the changelog-parity discipline.
- The 15 `GLOSSARY.md` mentions under `plugins/education/**` and
  `plugins/domain-driven-design/**` name a learner-workspace file and are excluded from the sweep.
- Tombstones: exactly two, each a short pointer carrying the new raw URL and a removal trigger;
  allowlisted by the checker with that trigger. No silent shim.
- Checker exemptions: `README.md`, `CHANGELOG.md`, `INDEX.md`, the contract slice
  (`docs/topics/**`), code files by extension (`.py`, `.sh`, `.mjs`, `.js`, `.ps1`), and the two
  tombstones.
- House style: no em dashes in any new rule, script comment, ADR, or skill prose
  (`.claude/rules/vendor-docs-are-not-style.md`); skill bodies state the current rule, never the
  incident (`.claude/rules/skill-bodies-state-current-rules.md`).
- Draft PR first; Conventional Commits title; PR body with `## Summary`, `## Fix`,
  `## Verification`, `## Related` and a closing-keyword line.
- Validation: `scripts/affected-tests.sh --run` must select and pass every mapped suite; a changed
  file mapping to zero suites is an error.

### Acceptance criteria

- `git ls-files docs/ | grep -E '/[^/]*[A-Z][^/]*$'` lists only `README.md`, `CHANGELOG.md`,
  `INDEX.md` basenames, files under `docs/topics/`, and the two declared tombstones.
- `scripts/check-docs-naming.sh` exits 0 on the renamed tree and exits non-zero when a fixture adds
  `docs/NEW-FILE.md`; its `.test.sh` proves both, and `scripts/affected-tests.sh --explain
  scripts/check-docs-naming.sh` selects that test.
- No relative markdown link anywhere in the repo resolves to a missing file (checked with an
  offline link resolver over every tracked `.md`), and `git grep` for each old uppercase basename
  returns hits only in: the two tombstones, plugin `CHANGELOG.md` released entries, the
  `GLOSSARY.md` learner-workspace false positives, and prose that narrates history.
- `node scripts/generate-catalog.mjs`, `node scripts/generate-cheatsheet.mjs --check`,
  `node scripts/validate-plugin-contracts.mjs`, and the `overlap.py` tests all pass against the new
  paths.
- The six absolute GitHub URLs in plugin bodies name the new lower-kebab paths.
- `docs/adr/0031-*.md` exists, follows the observed ADR shape, and cites the checker and the rule
  file; `.claude/rules/docs-naming.md` exists with `paths: ["docs/**"]` and a matching row in the
  `AGENTS.md` rules table.
- IF any reference to an old uppercase name survives in a current surface (link, backtick path,
  runtime constant), THEN the offline link check or an affected test fails before the PR leaves
  draft.

### Captured assumptions

- No `.claude/topic-docs.yaml` exists, so the documented defaults apply (`docs/topics` contract
  dir, `.work` memory dir, `branch` tier); this PR does not add a concern file. Revisit if a later
  PR binds one.
- No other repository links to the 11 non-tombstoned files by absolute URL. GitHub code search was
  unavailable from this session (token scoped to this repo). Revisit if a 404 report arrives; the
  remedy is one more declared tombstone.
- `acceptance_criteria_format` resolved to `free-text` (default; no convention-home region in
  `AGENTS.md`).
- The unwanted-behaviour criterion above covers the coverage prompt; no state-driven case applies.

### Out-of-scope

- In-file formatting consistency across `docs/` (headings, frontmatter shape).
- Renaming `README.md` / `CHANGELOG.md` / `INDEX.md` or any code file.
- Renumbering the duplicate ADRs 0018, 0025, 0028 (they stay; a follow-up issue asks for a
  uniqueness gate).
- The reusable naming-consistency skill (separate PR, second in sequence).
- Rewriting plugin `CHANGELOG.md` released entries beyond the one visualization link.
- Any change to the `docs/conventions/<concern>/` README+CHANGELOG template or the changelog-parity
  gate.

### Deferred questions

- None. Every asked question resolved to an answer in the register; the duplicate-ADR remediation
  and the reusable skill are out-of-scope follow-ups, not open decisions.

## Plan

### Goal

**What**: rename the 13 UPPERCASE-KEBAB root files under `docs/` to lower-kebab-case, repoint
every live reference, leave two declared tombstones, and add the rule, the gate, and the ADR that
stop the drift recurring.
**Why**: the 13 are the only files in a 193-file tree that break the rule every other naming
surface in this repository already states, and nothing today prevents the 14th.

### Standards grounding

No standards index exists (`.claude/standards.yaml` and `docs/standards/` absent; rung 6 of the
ladder, nothing persisted). The plan is grounded in the repository's own convention surfaces
read this session:

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `docs/adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md` | plugin bodies cite `docs/` by absolute URL, so a rename is an interface change | team |
| `docs/PLUGIN-PHILOSOPHY.md` lines 512-519 | silent shims forbidden; a declared, visible, bounded window is the sanctioned form | team |
| `docs/conventions/consumer-config-layering/README.md` | the repo's one tombstone precedent | team |
| `scripts/check-changelog-parity.sh` header | released-entry body edits need a PR-body declaration and a release entry | team |
| `.claude/rules/skill-bodies-state-current-rules.md` | skill bodies state the rule, never the incident; `## Next` sections | team (ambient) |
| `.claude/rules/vendor-docs-are-not-style.md` | no em dashes in rules, skills, READMEs, AGENTS.md | team (ambient) |
| `.claude/rules/pr-body-contract.md` | draft PR, Conventional Commits title, four sections, closing keyword | team (ambient) |
| `plugins/architecture/skills/record-decision/SKILL.md` Gotchas | never renumber duplicate ADRs | team |
| `docs/conventions/topic-docs/README.md` | `INDEX.md` reserved at every depth; contract slice pruned before merge | team |

### Phase 1: Rename the 13 and move the runtime consumers [TODO]

One structural commit. Every `git mv` and every hardcoded path constant moves together so no
intermediate state has a generator reading a missing file.

**File moves** (all `git mv docs/<OLD>.md docs/<new>.md`):

- [ ] `CATALOG-TAXONOMY.md` -> `catalog-taxonomy.md`
- [ ] `CATALOG.md` -> `catalog.md`
- [ ] `CI-RUNNER-ROUTING.md` -> `ci-runner-routing.md`
- [ ] `CLOUD-FLEET-SETUP.md` -> `cloud-fleet-setup.md`
- [ ] `CLOUD-SESSIONS.md` -> `cloud-sessions.md`
- [ ] `FINDING-YOUR-UNKNOWNS.md` -> `finding-your-unknowns.md`
- [ ] `GLOSSARY.md` -> `glossary.md`
- [ ] `MIGRATION-PLAYBOOK.md` -> `migration-playbook.md`
- [ ] `NATIVE-SURFACES.md` -> `native-surfaces.md`
- [ ] `OFFICIAL-DOCS.md` -> `official-docs.md`
- [ ] `PLUGIN-ARTIFACT-PROTOCOL.md` -> `plugin-artifact-protocol.md` (no content edit; six plugin copies stay byte-identical)
- [ ] `PLUGIN-PHILOSOPHY.md` -> `plugin-philosophy.md`
- [ ] `SKILL-CHEAT-SHEET.md` -> `skill-cheat-sheet.md`

**Runtime consumers** (path constants, fixtures, allowlist proof):

| File | Action | Rationale |
|---|---|---|
| [ ] `scripts/generate-cheatsheet.mjs` | MODIFY | `OUTPUT_PATH` and the header comment name the sheet |
| [ ] `scripts/generate-catalog.mjs` | MODIFY | `outputPath`, `taxonomyPath`, error text, header comment |
| [ ] `scripts/validate-plugin-contracts.mjs` | MODIFY | canonical artifact-protocol path and its comments |
| [ ] `scripts/cheatsheet-config.mjs` | MODIFY | header comment names the sheet |
| [ ] `plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py` | MODIFY | default `--view` path and its help text |
| [ ] `plugins/claude-ops/skills/audit-native-overlap/scripts/test_overlap.py` | MODIFY | fixture path mirrors the default |
| [ ] `scripts/check-docs-only.test.sh` | MODIFY | fixture files and assertions name the new paths |
| [ ] `scripts/generate-cheatsheet.test.sh` | MODIFY | fixture tree writes and reads the new sheet path |
| [ ] `scripts/docs-only-paths.txt` | MODIFY | the inertness-proof comment names the lane inputs |
| [ ] `docs/native-surfaces/records.json` | MODIFY | the store's own `note` field names its rendered view |
| [ ] `plugins/discovery/reference/artifact-protocol.md` and the five sibling copies | KEEP | byte-identical to the canonical; a pure rename changes no content |

**Sanity Check:**

- [ ] `git ls-files docs/ | grep -E '/[^/]*[A-Z][^/]*$' | grep -vE '/(README|CHANGELOG|INDEX)\.md$' | grep -v '^docs/topics/'` returns empty
- [ ] `node scripts/generate-catalog.mjs && git diff --quiet docs/catalog.md` exits 0
- [ ] `node scripts/generate-cheatsheet.mjs --check` exits 0
- [ ] `node scripts/validate-plugin-contracts.mjs` exits 0
- [ ] `bash scripts/check-docs-only.test.sh && bash scripts/generate-cheatsheet.test.sh && bash scripts/validate-plugin-contracts.test.sh` exit 0
- [ ] `python3 -m pytest plugins/claude-ops/skills/audit-native-overlap/scripts/test_overlap.py -q` (or the repo's `overlap.test.sh`) exits 0

### Phase 2: Reference sweep by the three-way boundary [TODO]

Scripted, not hand-edited: a 13-row old->new map applied with `sed` over the file set each tier
allows, then a manual pass over the bare-name mentions the map cannot see.

**Tier 1, current surfaces, every form** (links, backtick paths, bare basenames, JSON note
strings, stderr text): every tracked file EXCEPT `plugins/*/CHANGELOG.md`, `docs/adr/**`, the
`GLOSSARY.md` learner-workspace false positives (`plugins/education/**`,
`plugins/domain-driven-design/**`), `.work/**`, and `docs/topics/**`. Includes the six absolute
GitHub URLs (`plugins/review/skills/setup/SKILL.md`, three files under
`plugins/review/skills/quality-gate/context/`, `plugins/source-control/reference/config-resolution.md`,
`plugins/claude-config/skills/unhobble/SKILL.md`), `.claude/rules/catalog-taxonomy.md`,
`.claude/rules/ruff-pin.md`, `README.md`, `.github/recurring-schedule.json`, `.claude/cloud-bootstrap.sh`,
`.github/workflows/ci.yml` comments, `prompts/cloud-bootstrap-rollout.md`, and every plugin setup
`SKILL.md` that cites `docs/PLUGIN-PHILOSOPHY.md`.

**Tier 2, `docs/adr/**`**: markdown links and backtick paths only; narrative sentences untouched.
The ADR 0018 citation carries line numbers into the philosophy doc; the path moves, the line
anchor is left as written (the doc content did not change).

**Tier 3, plugin `CHANGELOG.md` released entries**: untouched, except
`plugins/visualization/CHANGELOG.md` line 212 (the one real markdown link), fixed together with a
patch bump of the visualization plugin and a release entry naming the correction, per the parity
discipline.

**Bare-name mentions needing a deliberate pass** (from the exploration's table): `PLUGIN-PHILOSOPHY.md`
in `plugins/planning/skills/{audit-answers,devils-advocate,plan}/SKILL.md`,
`plugins/docs-hygiene/skills/{audit-derivability,compress}/SKILL.md`,
`plugins/implementation/skills/implement-dispatch/SKILL.md`, `plugins/verification/skills/confirm/SKILL.md`,
`plugins/playbooks/skills/fable-5/context/orchestration.md`; `OFFICIAL-DOCS.md` in
`plugins/plugin-quality/skills/audit/reference/component-types/hook.md` and
`plugins/skill-quality/reference/evals.schema.json`; `FINDING-YOUR-UNKNOWNS.md` in
`plugins/implementation/skills/implement-dispatch/SKILL.md` and `plugins/planning/skills/brainstorm/SKILL.md`.
The sed map covers these because it matches the bare basename; the pass confirms each hit is the
docs file and not a same-named file elsewhere.

**Sanity Check:**

- [ ] An offline relative-link resolver over every tracked `.md` (scratch script; resolves each
      `](relative/path.md)` against the file's directory) reports 0 missing targets
- [ ] `git grep -lE '(CATALOG-TAXONOMY|CI-RUNNER-ROUTING|CLOUD-FLEET-SETUP|CLOUD-SESSIONS|FINDING-YOUR-UNKNOWNS|MIGRATION-PLAYBOOK|NATIVE-SURFACES|OFFICIAL-DOCS|PLUGIN-ARTIFACT-PROTOCOL|PLUGIN-PHILOSOPHY|SKILL-CHEAT-SHEET|docs/CATALOG\.md|docs/GLOSSARY\.md)' -- ':!plugins/*/CHANGELOG.md' ':!docs/adr' ':!plugins/education' ':!plugins/domain-driven-design' ':!docs/topics'` returns only the two tombstones from Phase 3 (empty before Phase 3)
- [ ] `git grep -c 'raw.githubusercontent.com/[^ )]*docs/[A-Z]'` returns 0 and `git grep -c 'github.com/[^ )]*blob/main/docs/[A-Z]'` returns 0
- [ ] `scripts/check-changelog-parity.sh --check-bump origin/main` passes for the visualization bump
- [ ] `scripts/check-purged-em-dashes.sh` exits 0 (the sweep introduced no em dash)

### Phase 3: Tombstones, checker, rule file, CI wiring [TODO]

**Tombstones** (CREATE, each ~12 lines, modelled on the `consumer-config-layering` precedent):

- [ ] `docs/PLUGIN-PHILOSOPHY.md`: "Moved -> `plugin-philosophy.md`", the new raw URL, and the removal trigger: delete once no installed plugin version that fetches this path remains in circulation (the six URL sites now point at the new name)
- [ ] `docs/MIGRATION-PLAYBOOK.md`: same shape

**Checker** (CREATE):

- [ ] `scripts/check-docs-naming.sh`: `--check` mode; walks `git ls-files docs/`; passes a basename when it matches `^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9.]+$`, or is `README.md` / `CHANGELOG.md` / `INDEX.md`, or the path is under `docs/topics/`, or the extension is a code extension (`py sh mjs js ps1`), or the path is listed in `scripts/docs-naming-exemptions.txt`; prints one `path: reason` line per offender; exit 1 on any offender; comment header states the rule and its reason, no incident narration
- [ ] `scripts/docs-naming-exemptions.txt`: the two tombstone paths with the removal trigger as the comment; the checker fails on a STALE entry (a listed path that no longer exists) so the exemption cannot outlive the tombstone
- [ ] `scripts/check-docs-naming.test.sh`: black-box, mktemp fixture tree (copies the SUT, inits a throwaway git repo); asserts pass on a clean tree, fail on `docs/NEW-FILE.md`, pass on `docs/x/README.md`, pass on `docs/topics/t/PLAN.md`, pass on `docs/a/b_c.py`, pass on an exempted tombstone, fail on a stale exemption entry

**Rule file and index** (CREATE / MODIFY):

- [ ] `.claude/rules/docs-naming.md`: `paths: ["docs/**"]`; states the rule (lower-kebab for markdown and data files), the exemptions, and that `scripts/check-docs-naming.sh --check` is the gate; links the ADR from Phase 4; no em dash
- [ ] `AGENTS.md`: one new row in the "Conventions that load on demand" table
- [ ] `.claude/rules/catalog-taxonomy.md` and `.claude/rules/ruff-pin.md`: already repointed in Phase 2 (KEEP here)

**CI and validation wiring** (MODIFY):

- [ ] `.github/workflows/ci.yml` `lint` job: a "Run docs-naming tests" step (`bash scripts/check-docs-naming.test.sh`, gated on `run_shell`) followed by a "Check docs/ filenames are lower-kebab" step with `id: docs_naming` and `continue-on-error: true`, placed beside the skill-leaf-names pair; a `docs-naming=${{ steps.docs_naming.outcome }}` line in the outcome aggregation block
- [ ] `scripts/affected-tests.sh --explain scripts/check-docs-naming.sh scripts/docs-naming-exemptions.txt .claude/rules/docs-naming.md` returns no `UNMAPPED`; if the exemptions file is unmapped, record it in `scripts/affected-tests-no-suite.txt` with the lane that reads it

**Sanity Check:**

- [ ] `scripts/check-docs-naming.sh --check` exits 0 on the working tree
- [ ] `bash scripts/check-docs-naming.test.sh` exits 0 and prints one `ok` line per case above
- [ ] `shellcheck scripts/check-docs-naming.sh scripts/check-docs-naming.test.sh && shfmt -d scripts/check-docs-naming.sh scripts/check-docs-naming.test.sh` exit 0
- [ ] `actionlint .github/workflows/ci.yml` exits 0
- [ ] `grep -c 'docs-naming' AGENTS.md` returns 1 and `grep -c 'paths:' .claude/rules/docs-naming.md` returns 1
- [ ] `scripts/affected-tests.sh --explain` over every new file returns no `UNMAPPED`

### Phase 4: ADR 0031 [TODO]

- [ ] Write `docs/adr/0031-name-docs-files-lower-kebab-case-with-conventional-exceptions.md` through `/architecture:record-decision` in the observed shape (Status, Date, Context, Decision, Consequences): the rule and its exemptions; the two declared tombstones and their removal trigger; the three-way historical-record boundary; the duplicates-stay stance for ADR numbers (never renumber; a uniqueness gate is the fix); the checker and rule file as the enforcement pair
- [ ] `.claude/rules/docs-naming.md` links the ADR (KEEP the link target consistent)

**Sanity Check:**

- [ ] `ls docs/adr/0031-*.md | wc -l` returns 1 and `grep -c '^- Status: accepted' docs/adr/0031-*.md` returns 1
- [ ] `scripts/check-docs-naming.sh --check` still exits 0 (the ADR filename obeys the rule)

### Phase 5: Validate, publish, close out [TODO]

- [ ] `scripts/affected-tests.sh --run` exits 0 with every changed file mapped
- [ ] `markdownlint-cli2` over changed markdown, `typos`, `editorconfig-checker`, `shellcheck`, `shfmt -d`, `actionlint` all exit 0
- [ ] Commits in Tidy-First order: (A) Phase 1 structural rename + consumers, (B) Phase 2 sweep + visualization bump, (C) Phase 3 tombstones + checker + rule + CI, (D) Phase 4 ADR; each commit green on its own phase sanity checks
- [ ] Draft PR: Conventional Commits title (`docs: rename docs/ root files to lower-kebab-case and gate the rule`), body with `## Summary`, `## Fix`, `## Verification`, `## Related`, opening `No related issue: <reason>` line, the PLAN.md pasted per the contract-slice close-out, and the declared CHANGELOG body edit named in the body
- [ ] **Phase-entry check** for the follow-up issue: `gh issue list --state all --search 'ADR number uniqueness in:title'`; if a match exists comment on it, else create the issue "Add an ADR-number uniqueness gate (existing duplicates 0018/0025/0028 stay)" citing ADR 0031 and the never-renumber gotcha
- [ ] Close-out: `git rm -r docs/topics/docs-naming-consistency/` in a final commit so `scripts/check-contract-slice-prune.sh --check-diff origin/main` passes; flip the PR to ready; subscribe to PR activity

**Sanity Check:**

- [ ] `scripts/check-contract-slice-prune.sh --check-diff origin/main` exits 0 on the final head
- [ ] PR body contains all four section headings and a closing-keyword or `No related issue:` line
- [ ] The follow-up issue number (created or pivoted-to) is recorded in the PR body's `## Related`

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Rename README/CHANGELOG too | 463 references, changelog-parity gate, ~155 absolute URLs; every fetched style guide exempts them | A style guide the org adopts mandates lowercase README |
| No tombstones (hard 404) | Contradicts the repo's own precedent and forbids nothing the doctrine forbids | Both URL-targeted files gain zero fetches from installed plugin copies (all consumers updated) |
| Tombstones for all 13 | 11 files have no absolute-URL consumer; 13 uppercase files defeat the goal | A 404 report names one of the other 11 |
| Rewrite all 29 plugin CHANGELOGs | 29 declared patch bumps for 55 non-link mentions | A link checker starts flagging backtick paths |
| Rule file only, no script | Rules fire on read, never on file creation; the drift happened ungated | The harness gains a create-time rule trigger |
| ls-lint or remark-lint as the gate | Adds a dependency for a 40-line bash check the repo's 80+ siblings already pattern; research on both tools is MEDIUM (single-pool) | The repo adopts either tool for another reason |
| Renumber duplicate ADRs here | `record-decision` Gotchas: never renumber; inbound links break | The repo's ADR convention changes to allow renumbering |

### Test strategy

Test boundaries (each is the public interface the tests drive):

- `scripts/check-docs-naming.sh --check` (newly introduced): black-box `.test.sh` with a mktemp fixture repo; Red first (write the failing `NEW-FILE.md` case before the script), then Green, then the exemption and stale-entry cases
- `scripts/generate-cheatsheet.mjs --check`, `scripts/generate-catalog.mjs`, `scripts/validate-plugin-contracts.mjs` (existing): their existing `.test.sh` suites, fixtures updated to the new paths
- `overlap.py` defaults (existing): `test_overlap.py` fixture path updated
- Reference integrity (no existing boundary): a scratch offline link resolver over every tracked `.md`, run before and after the sweep; the weekly `link-check.yml` lane is the durable backstop
- No regression test for the rename itself beyond the generators: a rename has no behavior; the sanity greps are the assertions

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A bare-name mention in a skill body is missed by the map | Med | Low (stale prose) | the Phase 2 deliberate pass over the exploration's bare-name table; final `git grep` sanity |
| An external repo links to one of the 11 non-tombstoned files | Low | Low (one 404) | captured assumption; remedy is one more exemption-listed tombstone |
| Case-insensitive checkout on a contributor machine sees the old-case file as dirty | Low | Low | `git mv` per file lands as one commit; CI checks out a finished commit |
| The checker false-positives on a legal future name (e.g. a versioned schema `v1.2.schema.json`) | Low | Med (advisory red) | regex allows dots inside the stem; test case covers `*.schema.json`; the step is `continue-on-error` like its siblings |
| The visualization patch bump collides with a concurrent bump on main | Low | Low | `check-changelog-parity.sh --check-bump` fails loudly; rebump |
| The contract-slice prune drops the plan a reviewer wanted to read | Med | Low | PLAN.md pasted into the PR body per the close-out procedure |

### Execution shape

Fully sequential: Phase 1 -> 2 -> 3 -> 4 -> 5. Phase 2's sweep needs Phase 1's new paths on
disk; Phase 3's checker must run green over the renamed tree; Phase 4's ADR is linked from
Phase 3's rule file; Phase 5 validates the whole. No file-disjoint pair carries enough
independent work to justify a second agent, and the sweep is a script, not volume hand-editing.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | thirteen `git mv` plus path constants; tightly coupled, one commit |
| 2 | main-session | scripted sed map plus a judgment pass over bare-name hits |
| 3 | main-session | new script authored test-first; CI wiring needs the aggregation block read |
| 4 | main-session | ADR prose; house style |
| 5 | main-session | validation, commits, PR, issue |

### Open questions

None at approval time. Every interview question resolved (11/11, validated).

### Handoff to implementation

#### User-approval gates

- None beyond this plan approval. No `[FALLBACK]` decisions; no scope expansion proposed.

#### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Sequential, all main-session (table above).
- [EXEC-SHAPE] The tombstone allowlist lives in `scripts/docs-naming-exemptions.txt` (a registry file, the pattern `skill-leaf-name-registry.txt` and `em-dash-purged-paths.txt` already use) rather than inline in the script, so removing a tombstone is a one-line diff.
- [EXEC-SHAPE] The CI step is `continue-on-error: true` with an aggregated outcome, matching every sibling `check-*.sh` step in the `lint` job and the advisory-first doctrine of ADR 0003.
- [EXEC-SHAPE] The offline link resolver is a scratch script, not committed; the durable link lane is the existing weekly `link-check.yml`.
- [EXEC-SHAPE] Commit boundaries follow Tidy First: structural rename first, then the sweep, then the new gate, then the ADR.

#### Mechanical work

- Verification checkpoint at each phase boundary is that phase's Sanity Check block; a red check stops the phase.
- If implementation diverges (a consumer the exploration missed, a generator that reads the old path indirectly), stop and re-plan via `/planning:plan review` rather than patching forward.

## Blast radius

HIGH by file count (roughly 190 unique files touched by the sweep, plus a CI workflow, a rule
file, and two generators), LOW by reversibility (every change is a `git revert` away; no data,
schema, or published API), and every consumer that could break is covered by an existing CI
gate. Triggers matched: "new conventions or enforcement mechanisms" and "infrastructure changes"
(a CI workflow step), so the formal stress-test runs.

## Stress-test summary

<!-- Step 3 plan-reviewer and Step 4 devils-advocate results recorded here before approval -->
