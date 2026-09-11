# docs-naming-consistency

## Brief

> Scope-change note, 2026-09-11: the accepted answer to Q8 (two compatibility tombstones at the
> old uppercase paths) was found infeasible at plan review. A tombstone would share a tree with its
> lowercase twin, and on case-insensitive filesystems "checking out both files will result in the
> second one overwriting the first one" (Microsoft Learn, Azure Repos case sensitivity, fetched
> 2026-09-11); this repository runs two `windows-2025` CI jobs. Q12 in the interview register
> reopens the decision. The Brief below is written for the recommended answer (hard cutover, no
> tombstones, norm-conformant plugin bumps) and is revised if the user picks otherwise.

### TLDR

- Rename the 13 UPPERCASE-KEBAB `.md` files at the `docs/` root to lower-kebab-case with `git mv`,
  and update every live reference (links, backtick paths, bare stems, runtime constants) to the
  new names.
- No tombstones: the six absolute GitHub URLs in plugin bodies are repointed in the same PR, and
  every plugin whose body the sweep edits gets a patch bump and a changelog entry, which is what
  delivers the corrected citations to installed copies.
- Add enforcement: a deterministic `scripts/check-docs-naming.sh` (+ `.test.sh`, CI-wired,
  `affected-tests` mapped) that also refuses any two `docs/` paths differing only by case, and a
  path-scoped `.claude/rules/docs-naming.md` for `docs/**`.
- Record the rule as the next free ADR number; file one follow-up issue for an ADR-number
  uniqueness gate.
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
- Reference-update boundary (three-way). Tier 1, current surfaces (skill bodies, agents, READMEs,
  rules, scripts, prompts, `.github`, `docs/` outside `adr/`, `specs/`, `upstream/`): every form,
  bare stems included. Tier 2, `docs/adr/**`, `docs/specs/**`, `docs/upstream/**`: markdown links
  and backtick paths only, narrative untouched. Tier 3, plugin `CHANGELOG.md` released entries:
  untouched except the one markdown link in `plugins/visualization/CHANGELOG.md`, declared in the
  PR body and in that plugin's new release entry.
- Every plugin whose body the sweep edits gets a patch bump in `.claude-plugin/plugin.json` and a
  `## [x.y.z]` / `### Changed` entry, the shape 12 of the last 12 body-editing commits used.
- The 15 `GLOSSARY.md` mentions under `plugins/education/**` and
  `plugins/domain-driven-design/**` name a learner-workspace file and are excluded from the sweep.
- No file may be added whose path differs from another tracked path only by case.
- Checker exemptions: `README.md`, `CHANGELOG.md`, `INDEX.md`, the contract slice
  (`docs/topics/**`), and code files by extension (`.py`, `.sh`, `.mjs`, `.js`, `.ps1`).
- House style: no em dashes in any new rule, script comment, ADR, or skill prose; skill bodies
  state the current rule, never the incident.
- Draft PR first; Conventional Commits title; PR body with `## Summary`, `## Fix`,
  `## Verification`, `## Related`, a `No linked issue` line, the PLAN.md in a `<details>` block,
  and the pre-prune commit SHA.
- Validation: `scripts/affected-tests.sh --run` must select and pass every mapped suite; a changed
  file mapping to zero suites is an error.

### Acceptance criteria

- `git ls-files docs/ | grep -E '/[^/]*[A-Z][^/]*$' | grep -vE '/(README|CHANGELOG|INDEX)\.md$' | grep -v '^docs/topics/'` returns empty.
- `scripts/check-docs-naming.sh --check` exits 0 on the renamed tree and exits non-zero when a
  fixture adds `docs/NEW-FILE.md` or a case-colliding pair; its `.test.sh` proves both, and
  `scripts/affected-tests.sh --explain scripts/check-docs-naming.sh` selects that test.
- An offline relative-link resolver over every tracked `.md` reports 0 missing targets, and
  `! git grep -qE '(main|blob/main)/docs/[A-Z][A-Z-]*\.md'` holds (no absolute URL names an
  uppercase root file).
- `node scripts/generate-catalog.mjs`, `node scripts/generate-cheatsheet.mjs --check`,
  `node scripts/validate-plugin-contracts.mjs`, the `overlap.py` tests, and
  `scripts/check-changed-skills.sh origin/main` all pass.
- The new ADR exists at the next free number, follows the observed ADR shape, and cites the checker
  and the rule file; `.claude/rules/docs-naming.md` exists with `paths: ["docs/**"]` and a matching
  row in the `AGENTS.md` rules table.
- Every plugin with a body edit on this branch has a manifest version strictly greater than on
  `origin/main` and a new `## [<v>]` entry (`scripts/check-changelog-parity.sh --check-bump origin/main`).
- IF any reference to an old uppercase name survives in a Tier 1 surface (link, backtick path,
  bare stem, runtime constant), THEN the anchored `git grep` sanity check or an affected test fails
  before the PR leaves draft.

### Captured assumptions

- No `.claude/topic-docs.yaml` exists, so the documented defaults apply; this PR does not add a
  concern file. Revisit if a later PR binds one.
- No other repository links to the 13 files by absolute URL. GitHub code search was unavailable
  from this session. Revisit if a 404 report arrives; the remedy is a follow-up that repoints it.
- Users on installed plugin copies older than this PR's bumps fetch a 404 for the two raw doctrine
  URLs until they update; this is the repository's declared posture for a rename ("a clean breaking
  change carried by a version bump and a changelog note").
- `acceptance_criteria_format` resolved to `free-text` (default; no convention-home region).
- The unwanted-behaviour criterion above covers the coverage prompt; no state-driven case applies.

### Out-of-scope

- In-file formatting consistency across `docs/` (headings, frontmatter shape).
- Renaming `README.md` / `CHANGELOG.md` / `INDEX.md` or any code file.
- Renumbering the duplicate ADRs 0018, 0025, 0028 (they stay; a follow-up issue asks for a
  uniqueness gate).
- The reusable naming-consistency skill (separate PR, second in sequence).
- Rewriting plugin `CHANGELOG.md` released entries beyond the one visualization link.
- Shortening the four over-cap skill descriptions the sweep touches; they are recorded in
  `scripts/skill-description-cap-baseline.txt` and WARN, not FAIL.

### Deferred questions

- None. Every asked question resolved to an answer in the register; Q12 is a reopened question
  awaiting the user, not a deferral.

## Plan

### Goal

**What**: rename the 13 UPPERCASE-KEBAB root files under `docs/` to lower-kebab-case, repoint
every live reference, bump every plugin the sweep edits, and add the rule, the gate, and the ADR
that stop the drift recurring.
**Why**: the 13 are the only files in a 193-file tree that break the rule every other naming
surface in this repository already states, and nothing today prevents the 14th.

### Standards grounding

No standards index exists (`.claude/standards.yaml` and `docs/standards/` absent; rung 6 of the
ladder, nothing persisted). The plan is grounded in the repository's own convention surfaces
read this session:

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `docs/adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md` | plugin bodies cite `docs/` by absolute URL, so a rename is an interface change | team |
| `docs/MIGRATION-PLAYBOOK.md` lines 483-490 | a rename is a clean breaking change carried by a version bump and a changelog note; the plugin cache is version-keyed | team |
| `docs/PLUGIN-PHILOSOPHY.md` lines 512-519 | silent shims forbidden | team |
| `scripts/check-changelog-parity.sh` header | released-entry body edits need a PR-body declaration and a release entry | team |
| `scripts/check-changed-skills.sh` and `scripts/skill-description-cap-baseline.txt` | every touched SKILL.md is linted; recorded cap breaches WARN | team |
| `scripts/check-fixture-git-isolation.sh`, `scripts/test-git-helpers.sh` | a fixture-building test clears inherited git env | team |
| `scripts/check-stale-base-overlap.sh` | a PR from a stale base fails on overlapping paths | team |
| `.claude/rules/skill-bodies-state-current-rules.md` | skill bodies state the rule, never the incident | team (ambient) |
| `.claude/rules/vendor-docs-are-not-style.md` | no em dashes in rules, skills, READMEs, AGENTS.md | team (ambient) |
| `.claude/rules/pr-body-contract.md` | draft PR, Conventional Commits title, four sections | team (ambient) |
| `plugins/architecture/skills/record-decision/SKILL.md` Gotchas | never renumber duplicate ADRs; pick highest plus one | team |
| `docs/conventions/topic-docs/README.md` lines 656-670 | `INDEX.md` reserved; PLAN.md pasted in the PR body; pre-prune SHA named; slice pruned before merge | team |

### Phase 1: Rename the 13 and move the runtime consumers [DONE]

One structural commit. Every `git mv` and every hardcoded path constant moves together so no
intermediate state has a generator reading a missing file.

**File moves** (all `git mv docs/<OLD>.md docs/<new>.md`):

- [x] `CATALOG-TAXONOMY.md` -> `catalog-taxonomy.md`
- [x] `CATALOG.md` -> `catalog.md`
- [x] `CI-RUNNER-ROUTING.md` -> `ci-runner-routing.md`
- [x] `CLOUD-FLEET-SETUP.md` -> `cloud-fleet-setup.md`
- [x] `CLOUD-SESSIONS.md` -> `cloud-sessions.md`
- [x] `FINDING-YOUR-UNKNOWNS.md` -> `finding-your-unknowns.md`
- [x] `GLOSSARY.md` -> `glossary.md`
- [x] `MIGRATION-PLAYBOOK.md` -> `migration-playbook.md`
- [x] `NATIVE-SURFACES.md` -> `native-surfaces.md`
- [x] `OFFICIAL-DOCS.md` -> `official-docs.md`
- [x] `PLUGIN-ARTIFACT-PROTOCOL.md` -> `plugin-artifact-protocol.md` (no content edit)
- [x] `PLUGIN-PHILOSOPHY.md` -> `plugin-philosophy.md`
- [x] `SKILL-CHEAT-SHEET.md` -> `skill-cheat-sheet.md`

**Runtime consumers** (path constants, fixtures, allowlist proof):

| File | Action | Rationale |
|---|---|---|
| [x] `scripts/generate-cheatsheet.mjs` | MODIFY | `OUTPUT_PATH` and the header comment |
| [x] `scripts/generate-catalog.mjs` | MODIFY | `outputPath`, `taxonomyPath`, error text, header comment |
| [x] `scripts/validate-plugin-contracts.mjs` | MODIFY | canonical artifact-protocol path, comments, and the two bare stems at lines 101 and 187 |
| [x] `scripts/cheatsheet-config.mjs` | MODIFY | header comment |
| [x] `plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py` | MODIFY | default `--view` path and help text |
| [x] `plugins/claude-ops/skills/audit-native-overlap/scripts/test_overlap.py` | MODIFY | fixture path mirrors the default |
| [x] `scripts/check-docs-only.test.sh` | MODIFY | fixture files and assertions |
| [x] `scripts/generate-cheatsheet.test.sh` | MODIFY | fixture tree paths |
| [x] `scripts/docs-only-paths.txt` | MODIFY | the inertness-proof comment |
| [x] `docs/native-surfaces/records.json` | MODIFY | the store's own `note` field |
| [x] `plugins/*/reference/artifact-protocol.md` (six) | KEEP | byte-identical to the canonical; no content change |

**Sanity Check:**

- [x] `git ls-files docs/ | grep -E '/[^/]*[A-Z][^/]*$' | grep -vE '/(README|CHANGELOG|INDEX)\.md$' | grep -v '^docs/topics/'` returns empty
- [x] `git ls-files | tr 'A-Z' 'a-z' | sort | uniq -d` returns empty
- [x] `node scripts/generate-catalog.mjs && git diff --quiet docs/catalog.md` exits 0
- [x] `node scripts/generate-cheatsheet.mjs --check` exits 0
- [x] `node scripts/validate-plugin-contracts.mjs` exits 0
- [x] `bash scripts/check-docs-only.test.sh && bash scripts/generate-cheatsheet.test.sh && bash scripts/validate-plugin-contracts.test.sh` exit 0
- [x] `bash plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.test.sh` exits 0

### Phase 2: Reference sweep by the three-way boundary, with plugin bumps [DONE]

Scripted, not hand-edited. Two maps applied with `sed` over the file set each tier allows: the
13-row basename map (`<OLD>.md` -> `<new>.md`) and the 11-row bare-stem map (`PLUGIN-PHILOSOPHY`
-> `plugin-philosophy`, applied only to Tier 1 and only where the stem is not followed by `.md`).
Then a deliberate pass over the sites the maps cannot judge.

**Tier 1, current surfaces, every form**: every tracked file EXCEPT `plugins/*/CHANGELOG.md`,
`docs/adr/**`, `docs/specs/**`, `docs/upstream/**`, `plugins/education/**`,
`plugins/domain-driven-design/**`, `.work/**`, `docs/topics/**`. Includes the six absolute GitHub
URLs, `.claude/rules/catalog-taxonomy.md`, `.claude/rules/ruff-pin.md`, `README.md`,
`.github/recurring-schedule.json`, `.claude/cloud-bootstrap.sh`, `.github/workflows/ci.yml`
comments, `prompts/cloud-bootstrap-rollout.md`, `scripts/skill-portability-tokens.txt`, every
plugin setup `SKILL.md` citing `docs/PLUGIN-PHILOSOPHY.md`, and `docs/conventions/**`.

**Lockstep edit**: `plugins/skill-quality/scripts/check-skill.sh` (four bare stems, two in
user-visible WARN text) and `plugins/skill-quality/skills/check/evals/evals.json` line 104, which
quotes that WARN text verbatim; both change in the same commit.

**Tier 2, `docs/adr/**`, `docs/specs/**`, `docs/upstream/**`**: markdown links and backtick paths
only (the basename map); bare stems and narrative untouched.

**Tier 3, plugin `CHANGELOG.md` released entries**: untouched, except
`plugins/visualization/CHANGELOG.md` line 212 (the one real markdown link), fixed under the same
patch bump every other touched plugin gets, with the correction named in the new release entry.

**Plugin bumps** (scripted): for each plugin with a non-CHANGELOG file edited on this branch
(54 today; recomputed from `git diff --name-only origin/main`), bump the patch component of
`plugins/<p>/.claude-plugin/plugin.json` and prepend a `## [<v>]` section with one `### Changed`
bullet ("Cite the marketplace `docs/` doctrine files by their lower-kebab names"). The visualization
entry additionally names the released-entry link correction.

**Deliberate pass** (from the exploration's bare-name table, plus the 27 bare-stem hits): confirm
each hit names the docs file and not a same-named file elsewhere; the `GLOSSARY.md` learner
workspace is the known false positive and is excluded by path.

**Sanity Check:**

- [x] An offline relative-link resolver over every tracked `.md` (scratch script; resolves each
      `](relative/path.md)` against the file's directory) reports 0 missing targets
- [x] `! git grep -qE '(CATALOG-TAXONOMY|CATALOG|CI-RUNNER-ROUTING|CLOUD-FLEET-SETUP|CLOUD-SESSIONS|FINDING-YOUR-UNKNOWNS|GLOSSARY|MIGRATION-PLAYBOOK|NATIVE-SURFACES|OFFICIAL-DOCS|PLUGIN-ARTIFACT-PROTOCOL|PLUGIN-PHILOSOPHY|SKILL-CHEAT-SHEET)\.md' -- ':!plugins/*/CHANGELOG.md' ':!docs/adr' ':!docs/specs' ':!docs/upstream' ':!plugins/education' ':!plugins/domain-driven-design' ':!docs/topics'` holds
- [x] `! git grep -qE '\b(PLUGIN-PHILOSOPHY|MIGRATION-PLAYBOOK|OFFICIAL-DOCS|CATALOG-TAXONOMY|SKILL-CHEAT-SHEET|CLOUD-SESSIONS|CLOUD-FLEET-SETUP|FINDING-YOUR-UNKNOWNS|NATIVE-SURFACES|CI-RUNNER-ROUTING|PLUGIN-ARTIFACT-PROTOCOL)\b' -- ':!plugins/*/CHANGELOG.md' ':!docs/adr' ':!docs/specs' ':!docs/upstream' ':!docs/topics'` holds
- [x] `! git grep -qE '(main|blob/main)/docs/[A-Z][A-Z-]*\.md'` holds
- [x] `scripts/check-changelog-parity.sh --check-bump origin/main && scripts/check-changelog-parity.sh --check && scripts/check-changelog-parity.sh --check-order` exit 0
- [x] `scripts/check-changed-skills.sh origin/main` exits 0
- [x] `scripts/check-purged-em-dashes.sh` exits 0

Phase 2 evidence notes: the link resolver reports 0 targets newly missing against `origin/main`
(the 31 pre-existing misses are example paths and placeholders in specs, changelogs, and skill
context files, identical on both trees); the URL check's one hit is a `README.md` fixture inside
`scripts/check-skill-portability.test.sh`, which is in the exempt set. `docs/architecture/landscape.json`
was regenerated through `reference-edges.sh` (edge counts unchanged; six `files` samples re-sorted)
and `render-landscape.sh` produced byte-identical `landscape.md` and `portfolio.md`.

### Phase 3: Checker, rule file, CI wiring [TODO]

**Checker** (CREATE):

- [ ] `scripts/check-docs-naming.sh`: `--check` mode; walks `git ls-files docs/`; passes a
      basename when it matches `^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9.]+$`, or is `README.md` /
      `CHANGELOG.md` / `INDEX.md`, or the path is under `docs/topics/`, or the extension is a
      code extension (`py sh mjs js ps1`); additionally fails when any two tracked paths under
      `docs/` differ only by case; prints one `path: reason` line per offender; exit 1 on any
      offender; header comment states the rule and its reason
- [ ] `scripts/check-docs-naming.test.sh`: black-box, mktemp fixture tree with a throwaway git
      repo built through `scripts/test-git-helpers.sh` (or `unset GIT_DIR GIT_WORK_TREE GIT_CONFIG`)
      so `scripts/check-fixture-git-isolation.sh --check` passes; no `ok "skip"` line; asserts
      pass on a clean tree, fail on `docs/NEW-FILE.md`, pass on `docs/x/README.md`, pass on
      `docs/topics/t/PLAN.md`, pass on `docs/a/b_c.py`, pass on `docs/a/v1.2.schema.json`, fail
      on `docs/Foo.md` beside `docs/foo.md`

**Rule file and index** (CREATE / MODIFY):

- [ ] `.claude/rules/docs-naming.md`: `paths: ["docs/**"]`; states the rule, the exemptions, that
      `scripts/check-docs-naming.sh --check` is the gate (path rules load on read, not on file
      creation), and links the ADR from Phase 4; no em dash
- [ ] `AGENTS.md`: one new row in the "Conventions that load on demand" table

**CI and validation wiring** (MODIFY):

- [ ] `.github/workflows/ci.yml` `lint` job: "Run docs-naming tests" (`bash scripts/check-docs-naming.test.sh`,
      gated on `run_shell`) then "Check docs/ filenames are lower-kebab" with `id: docs_naming`
      and `continue-on-error: true`, beside the skill-leaf-names pair; a
      `docs-naming=${{ steps.docs_naming.outcome }}` line in the outcome block that
      `scripts/aggregate-hygiene-results.sh` consumes
- [ ] `scripts/affected-tests.sh --explain scripts/check-docs-naming.sh .claude/rules/docs-naming.md .github/workflows/ci.yml` returns no `UNMAPPED`

**Sanity Check:**

- [ ] `scripts/check-docs-naming.sh --check` exits 0 on the working tree
- [ ] `bash scripts/check-docs-naming.test.sh` exits 0 and prints one `ok` line per case above
- [ ] `shellcheck scripts/check-docs-naming.sh scripts/check-docs-naming.test.sh && shfmt -d scripts/check-docs-naming.sh scripts/check-docs-naming.test.sh` exit 0
- [ ] `scripts/check-fixture-git-isolation.sh --check && scripts/check-silent-skips.sh` exit 0
- [ ] `actionlint .github/workflows/ci.yml` exits 0
- [ ] `grep -c 'docs-naming' AGENTS.md` returns 1 and `grep -c '^paths:' .claude/rules/docs-naming.md` returns 1
- [ ] `! grep -rqP '\xE2\x80\x94' .claude/rules/docs-naming.md scripts/check-docs-naming.sh scripts/check-docs-naming.test.sh` holds (no em dash in any new file)

### Phase 4: ADR at the next free number [TODO]

- [ ] Compute the number as highest existing plus one at write time (0033 as of this revision;
      recheck after the Phase 5 base sync) and write
      `docs/adr/<NNNN>-name-docs-files-lower-kebab-case-with-conventional-exceptions.md` through
      `/architecture:record-decision` in the observed shape: the rule and its exemptions; hard
      cutover with no tombstones and why (case collision on case-insensitive checkouts); the
      three-way historical-record boundary; the duplicates-stay stance for ADR numbers; the checker
      and rule file as the enforcement pair; Consequences name the 404 window for stale installed
      plugin copies and the `stale-path-verify` hook's advisory notices on future edits citing a
      retired path
- [ ] `.claude/rules/docs-naming.md` links the ADR

**Sanity Check:**

- [ ] `ls docs/adr/ | grep -oE '^[0-9]{4}' | sort | uniq -d | grep -vE '^(0018|0025|0028)$'` returns empty (the new number is unique)
- [ ] `grep -c '^- Status: accepted' docs/adr/<NNNN>-*.md` returns 1
- [ ] `scripts/check-docs-naming.sh --check` still exits 0

### Phase 5: Sync, validate, publish, close out [TODO]

- [ ] **Phase-entry**: `git fetch origin main && git merge --no-edit origin/main`; re-run the
      Phase 2 sed maps and every Phase 1 to 4 sanity check on the merged tree; re-check the ADR
      number against `origin/main`; `scripts/check-stale-base-overlap.sh --check origin/main` exits 0
- [ ] `scripts/affected-tests.sh --run` exits 0 with every changed file mapped
- [ ] `markdownlint-cli2` over changed markdown, `typos`, `editorconfig-checker`, `shellcheck`, `shfmt -d`, `actionlint` all exit 0
- [ ] Commits in Tidy-First order: (A) Phase 1, (B) Phase 2 sweep + bumps, (C) Phase 3, (D) Phase 4; each green on its own sanity block; PLAN.md phase tags advance in the same commits
- [ ] PR body: PLAN.md inside a `<details>` block, the pre-prune commit SHA, the visualization
      released-entry correction declared, `## Verification` filled with the commands and exit codes
- [ ] **Phase-entry check** for the follow-up issue: `gh issue list --state all --search 'ADR number uniqueness in:title'`; if a match exists comment on it, else create "Add an ADR-number uniqueness gate (existing duplicates 0018/0025/0028 stay)" citing the new ADR; record the number under `## Related`
- [ ] Close-out: `git rm -r docs/topics/docs-naming-consistency/` in a final commit; flip the PR to ready

**Sanity Check:**

- [ ] `scripts/check-contract-slice-prune.sh --check-diff origin/main` exits 0 on the final head
- [ ] PR body contains all four section headings, a `No linked issue` line, a `<details>` block, and a 40-hex pre-prune SHA
- [ ] The follow-up issue number is recorded in the PR body's `## Related`

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Tombstones at the old uppercase paths | Case-only path pairs cannot coexist on macOS or Windows checkouts (Microsoft Learn); two `windows-2025` CI jobs | A tombstone mechanism that does not require the old path (none exists for raw URLs) |
| Keep the two URL-targeted files uppercase, rename 11 | Leaves the two most-cited doctrine files as the outliers and defers the identical decision; no measurable trigger for "cached copies aged out" | The user prefers a two-step rollout |
| Rename README/CHANGELOG too | 463 references, changelog-parity gate, ~155 absolute URLs; every fetched style guide exempts them | A style guide the org adopts mandates lowercase README |
| Edit plugin bodies without bumps | Contradicts 12/12 recent commits; installed copies never receive the corrected citations | The marketplace starts refreshing installed copies on content hash |
| Rewrite all plugin CHANGELOG released entries | 55 non-link mentions; each edit needs a declaration | A link checker starts flagging backtick paths |
| Rule file only, no script | Rules load on read, never on file creation; the drift happened ungated | The harness gains a create-time rule trigger |
| ls-lint or remark-lint as the gate | Adds a dependency for a 60-line bash check the repo's siblings already pattern; research on both is MEDIUM (single-pool) | The repo adopts either tool for another reason |
| Renumber duplicate ADRs here | `record-decision` Gotchas: never renumber | The ADR convention changes |
| Shorten the four over-cap descriptions here | They are recorded in the cap baseline and WARN; shortening is a semantic edit to trigger surfaces | The baseline file is retired |

### Test strategy

Test boundaries (the public interfaces the tests drive):

- `scripts/check-docs-naming.sh --check` (newly introduced): black-box `.test.sh` with a mktemp
  fixture repo; Red first (the failing `NEW-FILE.md` and case-collision cases before the script),
  then Green, then the exemption cases
- `scripts/generate-cheatsheet.mjs --check`, `scripts/generate-catalog.mjs`,
  `scripts/validate-plugin-contracts.mjs` (existing): their `.test.sh` suites, fixtures updated
- `overlap.py` defaults (existing): `test_overlap.py` fixture path updated
- Every touched `SKILL.md` (existing gate): `scripts/check-changed-skills.sh origin/main`
- Reference integrity (no existing boundary): a scratch offline link resolver before and after the
  sweep; the weekly `link-check.yml` lane is the durable backstop
- No regression test for the rename itself beyond the generators: a rename has no behavior; the
  sanity greps are the assertions

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A bare-stem mention in a skill body is missed or over-rewritten | Med | Low | the bare-stem map is Tier 1 only; the deliberate pass; the anchored sanity greps |
| An external repo links to one of the 13 by absolute URL | Low | Low (one 404) | captured assumption; a follow-up repoints it |
| A user on a stale installed plugin copy fetches a 404 | Med | Low | the declared posture; the bumps deliver the fix on update; ADR Consequences say so |
| A concurrent plugin bump on main collides with one of the 54 | Med | Low | `--check-bump` VERSION COLLISION fails loudly; Phase 5 re-sync and rebump |
| The sweep touches a file main also changed (stale-base gate) | High | Low | Phase 5 phase-entry merge and re-run |
| The checker false-positives on a legal future name | Low | Med (advisory red) | regex allows dots inside the stem; `v1.2.schema.json` test case; `continue-on-error` |
| The contract-slice prune drops the plan a reviewer wanted | Med | Low | PLAN.md in the PR body plus the pre-prune SHA |

### Execution shape

Fully sequential: Phase 1 -> 2 -> 3 -> 4 -> 5. Phase 2 needs Phase 1's paths; Phase 3's checker
runs over the renamed tree; Phase 4's ADR is linked from Phase 3; Phase 5 re-syncs and validates
the whole. The sweep and the bumps are scripts, not volume hand-editing.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | thirteen `git mv` plus path constants; one commit |
| 2 | main-session | two scripted sed maps, a scripted bump loop, and a judgment pass over bare-stem hits |
| 3 | main-session | new script authored test-first; CI wiring |
| 4 | main-session | ADR prose; house style |
| 5 | main-session | sync, validation, commits, PR body, issue, prune |

### Open questions

- Q12 (reopened Q8): hard cutover with bumps (recommended) or keep the two URL-targeted files
  uppercase. The plan is written for the recommendation.

### Handoff to implementation

#### User-approval gates

- Q12 resolution before Phase 1 starts. No other gates; no `[FALLBACK]` decisions.

#### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Sequential, all main-session (table above).
- [EXEC-SHAPE] Bumps and the two sed maps are scripts run once, not hand edits; the scripts live in the session scratchpad, not the repo.
- [EXEC-SHAPE] No exemptions registry file: with no tombstones the checker's exemptions are the fixed conventional set, hardcoded with their reasons; a registry is added when the first path-specific exemption is needed.
- [EXEC-SHAPE] The CI step is `continue-on-error: true` with an aggregated outcome, matching every sibling `check-*.sh` step in the `lint` job.
- [EXEC-SHAPE] The offline link resolver is a scratch script; the durable link lane is the existing weekly `link-check.yml`.
- [EXEC-SHAPE] Commit boundaries follow Tidy First: rename, sweep and bumps, gate, ADR.

#### Mechanical work

- Each phase's Sanity Check block is the verification checkpoint; a red check stops the phase.
- If implementation diverges (a consumer the exploration missed, a generator that reads the old path indirectly), stop and re-plan via `/planning:plan review`.

## Blast radius

HIGH by file count (roughly 165 files across 54 plugins and 20 convention READMEs, plus a CI
workflow, a rule file, two generators, and 54 manifest bumps), LOW by reversibility (every change
is a `git revert` away; no data, schema, or published API), and every consumer that could break is
covered by an existing CI gate. Triggers matched: "new conventions or enforcement mechanisms" and
"infrastructure changes", so the formal stress-test ran.

## Stress-test summary

Fresh-context plan reviewer: 1 CRITICAL, 4 IMPORTANT, 4 SUGGESTION. Devil's-advocate: 1 CRITICAL,
1 HIGH, 2 MEDIUM, 4 LOW. All verified against the repository before this revision:

- CRITICAL (both): tombstones would create case-colliding path pairs; confirmed by the Microsoft
  Learn primary and the two `windows-2025` jobs. Fixed: no tombstones; Q12 reopened; the checker
  now refuses case collisions.
- IMPORTANT: the URL-carrying plugins needed bumps for installed copies to receive the fix; the
  repo's norm is a bump on every body edit (12/12 recent commits). Fixed: scripted bumps for every
  touched plugin.
- IMPORTANT: sanity greps were unanchored and would match 27 bare stems and 27 false-positive
  raw URLs. Fixed: `.md`-anchored and `main/docs/[A-Z]` patterns; bare stems handled by a Tier 1
  map with the `check-skill.sh` + `evals.json` lockstep edit.
- IMPORTANT: the new test must satisfy the fixture-git-isolation and silent-skips gates. Fixed in
  Phase 3.
- IMPORTANT: stale base and ADR number claimed on main. Fixed: branch merged with `origin/main`
  (stale-base gate exit 0); ADR number computed at write time; Phase 5 re-sync.
- HIGH (devil's-advocate): four touched skills fail the description cap. Refuted: all four are in
  `scripts/skill-description-cap-baseline.txt`, so `check-changed-skills.sh` downgrades them to
  WARN; a sanity check runs that gate explicitly.
- SUGGESTIONS adopted: `! git grep -q` form; `docs/upstream/**` (and `docs/specs/**`) as Tier 2;
  em-dash grep over new files; pre-prune SHA in the PR body; `stale-path-verify` noted in the ADR.
