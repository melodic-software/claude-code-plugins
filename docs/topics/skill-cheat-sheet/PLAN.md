# PLAN — skill-cheat-sheet (#1227)

## Brief

### TLDR

Generate a consumer-neutral, scan-and-go skill-selection cheat sheet at `docs/SKILL-CHEAT-SHEET.md`,
grouped by the session-flow workflow's own stage vocabulary, derived from new official
`metadata` frontmatter keys in each in-scope `SKILL.md`, drift-gated in CI — then split the
top-level README into a small entry point (phase 2). Issue: #1227.

### Goal

1. **Cheat sheet (phase 1).** A generated markdown page mapping "type of thing I'm doing" to
   the skill to invoke, covering the full dev lifecycle from "I don't know what I'm going to
   build" through discovery, research, planning, implementation, testing, review, verification,
   PR, and merge — plus an anytime/cross-cutting group (discipline correctors, re-anchoring,
   docs-hygiene, naming, visualization, education) and a session-lifecycle group, and an
   org-agnostic operator-cadence section (daily/weekly fleet rhythm). Every dev-lifecycle-relevant
   skill is included; no relevant skill left out.
2. **README split (phase 2).** Shrink `README.md` to a small entry point; push detail into
   linked pages; the cheat sheet is the primary "which skill?" destination. The generated
   catalog block's new home is decided here, and `scripts/generate-catalog.mjs`'s output path is
   parameterized accordingly.

### Constraints

Locked upstream (issue #1227 — not re-litigable):

- Auto-derived from `SKILL.md` frontmatter; only a thin hand-curated grouping layer (stage
  order plus group labels) is hand-maintained. Zero duplicated per-skill detail.
- CI drift check between the generated sheet and its frontmatter sources.
- Markdown canonical; any HTML rendering generated from it.
- Minimal per-skill detail: what/when one-liner + link. Clickable TOC on GitHub.

Locked this interview (validated by two independent fresh-context reviewers; evidence verified):

- **Data mechanism:** per-skill keys under the Agent Skills standard `metadata` frontmatter
  field — flat string→string, namespaced (shape precedent: `discipline-batch` keys), e.g.
  summary (hard cap ~100 chars, gated by skill-quality), stage, cadence, include/exclude.
  The `description` field CANNOT source the one-liner (median 577 chars; first-sentence median
  188; shortening blocked by the trigger-keyword-preservation check). Key vocabulary lands as
  part of the fleet-wide effort #1617 (this work is its first consumer).
- **Grouping spine:** the session-flow workflow stage vocabulary VERBATIM —
  `0. Contract` through `8. Retrospective` plus `PR lifecycle (after step 7)` (see
  `plugins/session-flow/skills/workflow/context/steps.md`) — plus the two new groups
  (anytime/cross-cutting, session lifecycle) and the operator-cadence section. Sequence-of-use
  is a distinct axis from `docs/CATALOG-TAXONOMY.md`; a short ownership note states both axes.
- **Audience:** consumer-neutral. Rows grouped by plugin within each stage with the install
  identifier visible, so a partial-install consumer can act on the page. Operator section framed
  as "how an operator runs this fleet", never owner-specific.
- **Generator:** new sibling script beside `scripts/generate-catalog.mjs`, sharing the
  marker-block + `--check` idiom; output paths parameterized in BOTH generators. `--check`
  wired into `scripts/validate-plugins.sh`. Generator fails on any unmapped in-scope skill and
  any orphaned mapping; exclusions are explicit entries. Emits an anchor-linked group TOC.
  Emits links only to paths it read from disk (offline lychee gate).
- **Location hazard:** the sheet lives at `docs/SKILL-CHEAT-SHEET.md` — NOT under
  `docs/topics/` (sole prefix in `scripts/docs-only-paths.txt`; placing it there would skip its
  own drift gate). Update the lane comment in `docs-only-paths.txt` and the pinning case in
  `scripts/check-docs-only.test.sh` when wiring CI.
- **Blast radius:** frontmatter sweep touches every in-scope `SKILL.md` (~183 skills across 61
  plugins) → `work-class: structural`. Version-bump/changelog posture for the sweep is decided
  at planning before the sweep starts.

### Acceptance criteria

- `docs/SKILL-CHEAT-SHEET.md` exists, generated, with: stage-grouped skill rows (one-liner +
  link + install identifier per plugin group), anytime + session-lifecycle groups, operator-
  cadence section, anchor-linked TOC; renders scannably on GitHub.
- Every dev-lifecycle-relevant skill appears exactly once in a stage or group; exclusions
  (infra hooks, setup skills, maintainer-only, personal-domain plugins) are explicit generator
  entries, not silent omissions.
- CI fails when frontmatter and sheet diverge, when an in-scope skill lacks mapping metadata,
  or when a mapping references a missing skill.
- Phase 2: README reduced to a small entry point whose links reach everything it previously
  contained; catalog generator still green at its new target.
- All existing gates green (validate-plugins, markdownlint, lychee, docs-only lane tests).

### Captured assumptions

- Fleet-wide metadata vocabulary (#1617) may land after this; the `cheatsheet-*` keys adopted
  here migrate into that vocabulary rather than beside it.
- Claude Code ignores unknown/spec-standard frontmatter fields (verified against current docs +
  in-repo production usage of `metadata`).

### Out-of-scope

- Standalone agent rows (9 agents) — deferred with trigger: when agents gain an equivalent
  metadata block (see #1617). Agent-invoking skills ARE on the sheet.
- Hook plugins as rows (not invoked), personal-domain plugins (songwriting, kindle-dedrm, x,
  ai-briefing, knowledge, machine-health).
- HTML rendering surface (later, generated from markdown only).
- Fleet-wide metadata classification beyond the cheat sheet's own keys (#1617).

### Deferred questions

- Exact `cheatsheet-*` key names and value enums — arbiter: `/planning:plan` (coordinate with
  #1617's naming guidance; flat string values per spec).
- Version-bump/changelog posture for the ~61-plugin frontmatter sweep (single fleet PR vs
  per-plugin) — arbiter: `/planning:plan`.
- Which README sections move where in phase 2, and the catalog block's new home — arbiter:
  `/planning:plan`.
- Whether operator-cadence rows also carry `status`/frequency detail beyond daily/weekly —
  arbiter: `/planning:plan`.

## Plan

### Deferred-question resolutions (arbiter: /planning:plan — resolved here)

1. **Key names + enums.** Three keys, namespaced per the Agent Skills spec recommendation
   (re-verified this session: <https://agentskills.io/specification#metadata-field> — flat
   string→string map, "reasonably unique" key names) and the in-repo `discipline-batch`
   precedent (consumer-prefixed):
   - `cheatsheet-summary` — the one-liner. Hard cap **100 characters** (Brief's "~100" fixed to
     an exact gateable number). String, plain text, no markdown.
   - `cheatsheet-stage` — enum slug; generator maps slug → display heading. Values and headings
     (spine verbatim from `plugins/session-flow/skills/workflow/context/steps.md`):
     `contract` → "0. Contract", `explore` → "1. Explore", `research` → "2. Research",
     `plan` → "3. Plan", `implement` → "4. Implement", `test` → "5. Test",
     `review` → "6. Review", `verify` → "7. Verify outcome", `retro` → "8. Retrospective",
     `pr` → "PR lifecycle (after step 7)"; plus non-workflow groups `anytime` → "Anytime /
     cross-cutting", `session` → "Session lifecycle", `operator` → "Operator cadence"
     (these three labels + overall order are the hand-curated grouping layer, owned by the
     generator config).
   - `cheatsheet-cadence` — enum `daily` | `weekly` | `continuous`. Required when
     `cheatsheet-stage: operator`, forbidden otherwise (generator-enforced). `continuous` exists
     because the fleet's own loop-lane skills are self-paced standing loops, not daily/weekly
     rows — without it Phase 1 mapping stalls on an approval-gated enum change. Pre-assigned
     operator rows so mapping cannot stall: `babysit-loop` (continuous), `work-loop`
     (continuous), `babysit-prs` (continuous — its home is the fleet loop, not single-PR
     lifecycle), `attend-queue` (daily), `morning-brief` (daily).
   - **No include/exclude key.** Exclusions are explicit generator-config entries (matches the
     acceptance criterion "explicit generator entries, not silent omissions"): a plugin-level
     exclusion list (the six personal-domain plugins — every one of the 61 plugins ships a
     `skills/` dir, so there is no "hook-only plugin" category), a rule-based exclusion
     (skill named `setup` ⇒ auto-excluded, reason "infra setup"), and a skill-level exclusion
     list for the rest (maintainer-only etc.), each entry carrying a reason string.
     Completeness rules (each a named generator failure): every in-scope skill has
     `cheatsheet-stage` XOR an exclusion; an exclusion naming a nonexistent skill is an orphaned
     mapping; a skill BOTH excluded AND carrying `cheatsheet-stage` is a conflict.
     Vendored copies (`plugins/*/skills/*/vendor/**/SKILL.md`, 6 files — byte-frozen upstream
     material gated by skill-quality check 8) are outside the inventory: the exact-depth glob
     `plugins/*/skills/*/SKILL.md` (183 files) is the in-scope universe.
   - #1617 coordination: keys are consumer-namespaced exactly like `discipline-*`; after merge,
     comment on #1617 listing the adopted keys so the fleet vocabulary absorbs (or renames) them.
2. **Version-bump/changelog posture for the sweep: single fleet PR, NO plugin version bumps, NO
   per-plugin changelog entries.** Basis: `docs/MIGRATION-PLAYBOOK.md` "Version pinning and
   update delivery" — a version bump is the *delivery vehicle to installed consumers*; the
   `cheatsheet-*` keys have no runtime consumer (the generator reads the repo working tree, not
   installed caches), so there is nothing to deliver. Precedent: `a85b22255d` (skill-touching
   chore, no bump). The one behavioral change — the new summary-cap check in skill-quality's
   `check-skill.sh` — DOES bump skill-quality's version + changelog (delivery-relevant).
   Single PR is forced anyway: the drift gate requires sweep + generator + sheet to land
   atomically, else CI is red between merges. Recorded for #1617 to ratify fleet-wide.
3. **README moves (phase 2).** The generated catalog block (README lines 51–162 of 187) moves to
   a new `docs/CATALOG.md`; `scripts/generate-catalog.mjs`'s hardcoded output path (line 14)
   becomes a parameterized target with the marker idiom unchanged. README shrinks to: intro,
   "Use this marketplace", a "Finding your way" section linking the cheat sheet (primary
   "which skill?" destination), `docs/CATALOG.md`, `docs/CATALOG-TAXONOMY.md`, "What's here",
   and "Official documentation" — everything previously reachable stays reachable via links
   (acceptance criterion).
4. **Operator-cadence detail: `daily` | `weekly` | `continuous` in v1, nothing richer.** Brief
   frames the section as "daily/weekly fleet rhythm"; `continuous` is forced by the loop-lane
   skills (see resolution 1). Richer status/frequency detail stays deferred with trigger: first
   operator row needing a fourth shape proposes the extension via #1617.

### Standards grounding

| Surface | Sections cited | Provenance |
|---------|----------------|------------|
| Repo `CLAUDE.md` | Fresh-docs mandate (frontmatter = contract surface, in scope); Branching & PRs | project |
| `AGENTS.md` | Synced standards not edited here; stage explicit paths (no `git add -A`) | project |
| `docs/MIGRATION-PLAYBOOK.md` | Version pinning and update delivery (decides posture above) | project |
| Repo hooks | `block-noncanonical-commit.sh`: commit via `git commit -F - --cleanup=verbatim`; no `echo >` file writes | project |
| Agent Skills spec | `metadata` field contract (fetched this session, 2026-07-26) | upstream |

### Phase 1: Key contract, grouping config, and mapping table [DONE]

Fresh-docs step first (CLAUDE.md mandate — frontmatter is a contract surface): re-fetch
<https://agentskills.io/specification> and <https://code.claude.com/docs/en/skills> via
`docs/OFFICIAL-DOCS.md` and cite them in the PR. Then:

- Create `scripts/cheatsheet-config.mjs` (imported by the generator): stage slug→heading map +
  group order (spine verbatim per resolution 1), plugin-level exclusions (personal-domain:
  `songwriting`, `kindle-dedrm`, `x`, `ai-briefing`, `knowledge`, `machine-health`), the
  `setup`-skill auto-exclusion rule, and skill-level exclusion entries, each with a reason.
- Draft the full mapping table at `docs/topics/skill-cheat-sheet/mapping.tsv` (branch-local
  contract slice — committed so the curation survives machine/session loss; pruned with the
  slice before merge): one row per SKILL.md —
  `plugin  skill  stage  cadence  summary  | EXCLUDE reason`.
  Source inventory: exact-depth glob `plugins/*/skills/*/SKILL.md` (183 files at plan time;
  vendor copies out of scope).
- Mapping guidance: design-shaped skills (planning:design, architecture, prototype,
  event-storming, domain-driven-design, naming) map to `plan` — the spine has no design stage;
  a `design` enum extension is the concrete trigger example recorded on #1617.
- Summary charset guard (YAML safety — an invalid value makes the claude CLI reject the plugin
  and, at runtime, silently drops that skill's ENTIRE frontmatter): plain scalar only; reject
  `": "`, `" #"`, trailing `:`, trailing whitespace, any tab/control character, and leading
  YAML-special characters (`[ ] { } > | * & ! % @ \` " ' - #` — `#` included: `summary: #x` is
  VALID YAML with value null while regex readers see literal text, a silent divergence).
  Enforced identically by the apply script and the generator; the apply script's `--dry-run`
  additionally round-trips every touched frontmatter block through a real YAML parser.
  Length cap unit: **Unicode codepoints** — Node side `[...s].length`, bash side
  `LC_ALL=C.UTF-8` pinned at the check site (em-dash-heavy house style makes byte-counting
  diverge across locales); measured after the same trailing-comment strip skill-quality's
  `skill_frontmatter::metadata_field` applies.
- Line-cap headroom pre-scan: for every non-excluded skill, `current lines + metadata insertion
  delta < 500` (check-skill.sh check 4 hard cap). Known at plan time: `babysit-loop` and
  `babysit-prs` both sit at 499 → each needs a ~4–6 line body trim in this PR (body edit, not
  metadata — covered by plan approval; precedent `a85b22255d` trimmed babysit-loop for exactly
  this cap).
- Commit checkpoint after green (repo workflow: commit-after-green per phase).
- **Sanity Check:** `node -e "import('./scripts/cheatsheet-config.mjs')"` exits 0;
  `wc -l < docs/topics/skill-cheat-sheet/mapping.tsv` equals
  `ls plugins/*/skills/*/SKILL.md | wc -l` (183 at plan time); an `awk` pass over non-excluded
  rows asserts summary ≤100 chars and the charset guard, exit 0.

### Phase 2: Generator [TODO]

Review: code-design

- Create `scripts/generate-cheatsheet.mjs`, sibling of `generate-catalog.mjs`, same idiom:
  marker block `<!-- cheatsheet:start -->` / `<!-- cheatsheet:end -->` in
  `docs/SKILL-CHEAT-SHEET.md`, `--check` mode with line-diff + exit 1 on drift, parameterized
  output path constant, plus a `--root <dir>` override so a fixture tree can drive tests before
  the sweep exists.
- Minimal frontmatter reader in the script (native, no deps — repo precedent: catalog generator
  uses `JSON.parse` only): extract the `metadata:` block's flat `cheatsheet-*` keys + `name`,
  stripping trailing `#`-comments exactly as `skill_frontmatter::metadata_field` does, so both
  consumers measure the same value. Constraint documented in-file: swept values are plain
  scalars passing the Phase 1 charset guard.
- Failure modes (all exit 1 with named skills): in-scope skill with no `cheatsheet-stage` and no
  exclusion entry; exclusion entry naming a missing skill; excluded skill carrying
  `cheatsheet-stage` (conflict); unknown stage/cadence enum value; summary >100 chars or
  charset-guard violation; `cadence` present without `stage: operator` (and vice versa).
- Output: anchor-linked group TOC using GitHub's slugging rules (headings like "0. Contract" and
  "PR lifecycle (after step 7)" are punctuation-heavy — slugger must match GFM exactly; the
  offline lychee lane runs `include_fragments = "full"` and will fail a mismatched anchor);
  per stage/group, rows grouped by plugin with the install identifier visible (`plugin-name`
  from marketplace.json) — `skill — summary` linking the relative `SKILL.md` path it read from
  disk (offline-link discipline). Lint-clean per `.markdownlint-cli2.jsonc`.
- Spine-drift assertion inside `--check`: each workflow-stage heading in
  `cheatsheet-config.mjs` must prefix-match its H2 heading in
  `plugins/session-flow/skills/workflow/context/steps.md`, same order — a session-flow stage
  rename then fails the sheet's own gate instead of silently stranding the copy.
- Commit `scripts/generate-cheatsheet.test.sh` + a 3-skill fixture tree (mapped / excluded /
  operator) driving `--root` through all seven enforcement failure modes — the repo pairs a
  `.test.sh` with every checker (17 existing); the generator's enforcement semantics are a
  checker in substance, and an uncommitted fixture would leave those semantics regression-free
  only until the first refactor.
- Commit checkpoint after green.
- **Sanity Check:** `bash scripts/generate-cheatsheet.test.sh` exits 0 (covers: fixture green
  generate + `--check`; missing `cheatsheet-stage` → exit 1 naming the skill; excluded skill
  carrying stage → exit 1 conflict; unknown enum, cap, charset, cadence-coupling → exit 1);
  `npx --no-install markdownlint-cli2` on the fixture output exits 0. (Full-tree green
  `--check` lands in Phase 3 — before the sweep, the real tree correctly fails ~170 unmapped.)

### Phase 3: Frontmatter sweep (scripted) [TODO]

- Write a throwaway apply script (`.work/skill-cheat-sheet/apply-mapping.mjs`, not committed —
  the PR diff is the review surface): reads the slice's `mapping.tsv`, inserts/updates the
  `metadata:` block (`cheatsheet-stage`, `cheatsheet-summary`, `cheatsheet-cadence` where
  operator) in each non-excluded SKILL.md, preserving existing metadata keys (19 skills already
  carry `discipline-*` etc.), enforcing the Phase 1 charset guard. `--dry-run` prints the diff
  summary first.
- [FALLBACK — confirm or override] Trim `babysit-loop/SKILL.md` and `babysit-prs/SKILL.md` bodies by ~4–6 lines each BEFORE
  applying (both at 499 vs the 500 hard cap; the metadata block adds 4 lines to each). Trim =
  tightening prose, zero semantic loss; verify trigger-keyword preservation via check-skill.sh.
- Apply; spot-check one skill per shape class (fresh metadata block, existing metadata block,
  operator row).
- Generate the real sheet; commit checkpoint after green.
- **Sanity Check:** `git diff --numstat -- ':!docs/topics' ':!docs/SKILL-CHEAT-SHEET.md'`
  touches only `plugins/*/skills/*/SKILL.md`; `plugins/skill-quality/scripts/check-skill.sh`
  passes on 3 swept sample skills (one per shape class); `node
  scripts/generate-cheatsheet.mjs && node scripts/generate-cheatsheet.mjs --check` exits 0
  against the full tree.

### Phase 4: skill-quality summary-cap gate [TODO]

Review: code-design

- Extend `plugins/skill-quality/scripts/check-skill.sh`: when `metadata.cheatsheet-summary` is
  present, FAIL if length >100 (reuse `skill_frontmatter::metadata_field`). Extend the
  checker's existing test file with cap-pass/cap-fail fixtures (locate at implementation; the
  plugin ships tests per repo `.test.sh` convention).
- Bump skill-quality's `plugin.json` version (patch) + `CHANGELOG.md` entry `## [<v>]` (the
  `--check-bump` gate requires the new entry).
- **Sanity Check:** checker exits nonzero on a fixture with a 101-char summary, zero at 100;
  `scripts/check-changelog-parity.sh --check-bump origin/main` exits 0.

### Phase 5: CI wiring + full gate run [TODO]

- `scripts/validate-plugins.sh`: add `node scripts/generate-cheatsheet.mjs --check` beside the
  catalog check (line 17 region).
- `scripts/docs-only-paths.txt`: update the lane comment to note the sheet deliberately lives
  OUTSIDE `docs/topics/` so its drift gate runs.
- `scripts/check-docs-only.test.sh`: add pinning case `docs/SKILL-CHEAT-SHEET.md` → `false`
  (alongside the README/CATALOG-TAXONOMY pins at lines 82–84).
- **CI-runtime pre-measure (the sweep makes this the first-ever full-fleet checker run):**
  time `scripts/check-changed-skills.sh origin/main` locally — it runs `check-skill.sh`
  (including check 7, which executes each skill's `*.test.sh`) on all ~183 changed skills;
  the `skill-quality-gate` job has `timeout-minutes: 15` (ci.yml:808). If projected CI runtime
  approaches the limit, raise that job's timeout in the same PR (justified in the PR body).
  Any pre-existing FAIL surfacing on a skill the sweep touched only mechanically is
  triaged: trivial (fix inline) vs real debt (STOP — surface to the user; see approval gates).
- Full local gate: `scripts/validate-plugins.sh`, `bash scripts/check-docs-only.test.sh`,
  `scripts/check-changed-skills.sh origin/main`, markdownlint over changed files, and the
  offline lychee lane (`include_fragments = "full"` — proves every generated TOC anchor
  resolves). `validate-plugins.sh`'s claude-CLI step doubles as the real-YAML-parser
  validation of the swept frontmatter.
- **Sanity Check:** every listed command exits 0; `grep -c "generate-cheatsheet"
  scripts/validate-plugins.sh` ≥1; `grep -c "SKILL-CHEAT-SHEET" scripts/check-docs-only.test.sh`
  ≥1; measured full-fleet checker runtime recorded here WITH its environment (Windows Git Bash
  spawn cost inflates it vs ubuntu — conservative; the draft-PR CI run is the real measure, so
  raise the timeout only if the DRAFT run approaches 15 min).

### Phase 6: Slice prune + PR 1 + #1617 coordination [TODO]

- **Prune the contract slice IN THIS PR (gate-forced):** `contract-slice-prune-gate`
  (`check-contract-slice-prune.sh --check-diff`, ci.yml:482–500) fails any PR whose net diff
  leaves a path landing under `docs/topics/`; `skill-cheat-sheet` is not in the BASE-read
  baseline, and PLAN.md is already committed on this branch — so PR 1 cannot merge with the
  slice present. Final commit before PR: copy PLAN.md + mapping.tsv to
  `.work/skill-cheat-sheet/` (machine-local working copies for phases 7–8), then delete
  `docs/topics/skill-cheat-sheet/`. PLAN.md pasted into the PR description in a `<details>`
  block is the durable publication (close-out step 1 happens here, not after phase 8).
- Add a one-line README link to `docs/SKILL-CHEAT-SHEET.md` in PR 1 (discoverability must not
  wait for PR 2; the line survives the Phase 7 rewrite).
- PR body carries: the fresh-docs citations; the mapping.tsv EXCLUDE rows (squash-merge nets
  the TSV out of history — the PR description is where exclusion reasons stay reviewable); and
  the **revert protocol**: a plain `git revert` of this PR is blocked by changelog-parity
  (`--check-bump` sees skill-quality's version move backward with a pre-existing entry) —
  revert-as-forward-fix instead: revert content, bump skill-quality to a NEW patch version with
  a "revert" changelog entry.
- Open as **draft PR first** — the draft CI run is the real full-fleet checker timing measure
  (Phase 5 decision point). Before merging: verify branch protection requires up-to-date
  branches (or merge queue); if not, flag in-flight PRs adding new skills that they will need
  `cheatsheet-stage` after this merges (else main goes red on their merge, not their PR).
- Commit per repo convention (`git commit -F - --cleanup=verbatim`, explicit paths, Co-Authored-By
  trailer), push, open PR referencing #1227; PR title passes `pr-title.yml` convention
  (`feat: ...`).
- After merge: comment on existing issue #1617 (comment, not create — no duplicate risk) with
  the adopted keys AND the precisely-scoped posture: no-bump applies ONLY while a key class has
  no runtime consumer; the first runtime consumer of `cheatsheet-*` (e.g. a which-skill router
  reading installed caches, the shape `/discipline:sweep-all` already has) must ship with a
  fleet bump wave, or pre-sweep-pinned installs never receive the keys.
- **Sanity Check:** `git diff --name-status origin/main...HEAD | grep "docs/topics/"` shows only
  deletions/none; PR checks green (plugin-gate, skill-quality-gate, changelog-parity-gate,
  contract-slice-prune-gate, hygiene); #1617 comment URL recorded in the PR thread.

### Phase 7: README split (issue phase 2 — second PR) [TODO]

- Branch from post-merge main. The slice no longer exists (pruned in PR 1); the working plan for
  this phase is the PR 1 description + `.work/skill-cheat-sheet/` copies — do NOT re-add
  anything under `docs/topics/` (the prune gate fails any PR that lands paths there).
- Parameterize `scripts/generate-catalog.mjs` output path (line 14) → `docs/CATALOG.md`; move
  the catalog block (README 51–162) there; regenerate; `--check` green at the new target.
- Rewrite `README.md` (186 → ~60 lines): intro, "Use this marketplace" (KEEPS the
  "Enable plugin suggestions for an organization" subsection — consumer-needed managed-settings
  JSON), "Finding your way" (cheat sheet primary, catalog, taxonomy), "What's here",
  "Official documentation", and the License section retained. Every link formerly in README
  reachable from the new pages.
- `scripts/check-docs-only.test.sh`: add pin `docs/CATALOG.md` → `false`.
- Sweep inbound references to the moved catalog anchors (`grep -rn "README.md#"` across repo).
- **Sanity Check:** `node scripts/generate-catalog.mjs --check` exits 0; README line count ≤80;
  `grep -rn "README.md#" --include='*.md' .` reports no dangling catalog anchors; docs-only test
  suite + offline lychee exit 0.

### Phase 8: PR 2 [TODO]

- Second PR per the same conventions, referencing #1227 (phase 2 scope). No slice to prune —
  it went with PR 1; this PR's plan-of-record is its own description (paste the phase 7–8
  section from the PR 1 `<details>` block).
- Close #1227 on merge; confirm the #1617 coordination comment exists.
- **Sanity Check:** PR checks green; `git diff --name-status origin/main...HEAD | grep
  "docs/topics/"` empty.

## Blast radius

MEDIUM — wide but shallow: ~185 files touched, yet every content change is an inert metadata
addition gated by four independent CI lanes (skill-quality per-skill, drift `--check`,
docs-only tests, changelog parity). "Inert" holds only while the YAML stays valid — invalid
frontmatter YAML makes that skill load with ALL frontmatter silently dropped (verified against
the claude CLI validator: per-skill blast, but silent), hence the charset guard + real-YAML
parse in the apply script + claude-CLI parse in the gates. The genuinely behavioral deltas are small and isolated (one checker extension, one
CI wiring line, one output-path parameterization). Known CI hazard: the sweep triggers the
first-ever full-fleet `check-skill.sh` run against a 15-minute job timeout (pre-measured in
Phase 5). Preempts #1617's vocabulary decision — mitigated by namespacing + the coordination
comment.

## Stress-test summary

Two independent fresh-context passes, both grounded against the live repo:

1. **Plan reviewer (Step 3):** 1 CRITICAL — the `contract-slice-prune-gate` runs on EVERY PR,
   so PR 1 had to prune `docs/topics/skill-cheat-sheet/` itself (plan restructured); 6
   IMPORTANT — Phase 2 sanity unsatisfiable pre-sweep (→ fixture `--root`), 189 vs 183
   inventory (6 byte-frozen vendor copies excluded), first-ever full-fleet checker run vs the
   15-min CI timeout, YAML/comment-strip parser divergence, lychee `include_fragments = "full"`
   vs generated anchors, "hook-only plugin" exclusion category matching zero plugins; 4
   suggestions (mapping durability, commit cadence, design-stage mapping guidance, README
   section coverage). All verified, all folded in.
2. **Devils-advocate (Step 4):** 0 CRITICAL, 4 HIGH, all empirically demonstrated and fixed
   in-plan: `babysit-loop`/`babysit-prs` at 499/500 lines → sweep-induced cap breach (trim
   step added); rebase trigger corrected to any `plugins/*/skills` change on main; plain
   `git revert` of PR 1 blocked by the changelog-parity bump gate (revert protocol documented);
   charset guard extended (trailing `:` = YAML parse error, leading `#` = silent null, tabs,
   control chars) + real-YAML round-trip in the apply script + cap unit pinned to Unicode
   codepoints. 6 MEDIUM (runtime-consumer scoping for the #1617 posture comment, committed
   generator test, spine-drift assertion, `continuous` cadence for loop-lane skills,
   green-before-merge stale-PR hole → branch-protection check, measurement-environment caveat)
   and 4 LOW — all folded in. Verdict: plan survives; architecture (keys, generator, single-PR
   atomicity, prune sequencing) confirmed against the real gates.

## Execution shape

Fully sequential, single session per PR: Phase 1 → 2 → 3 → 4 → 5 → 6, then 7 → 8. The sweep is a
deterministic script applied from the mapping table, not agent fan-out — parallel workers would
add cost without saving wall-clock (the mapping judgment happens once in Phase 1; application is
one script run). Phase 4 is file-disjoint from 2–3 and could parallelize, but its size (~40 LOC)
does not justify a worker.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | curation judgment (183 mapping rows) |
| 2 | main-session | new script, design judgment |
| 3 | main-session | scripted apply + spot-check |
| 4 | main-session | small, coupled to Phase 1 contract |
| 5 | main-session | small mechanical wiring |
| 6, 8 | main-session | PR lifecycle |
| 7 | main-session | README judgment + generator edit |

## Open questions

None blocking. Open probes carried into implementation: (a) skills with no natural stage —
observable via the generator completeness failure in Phase 2's sanity check; (b) exact location
of skill-quality's checker test file (Phase 4 locates it).

## Handoff to implementation

### User-approval gates

- Plan approval (Step 5) covers Phases 1–8.
- Mid-flight: any stage-enum change, any new exclusion CATEGORY (not individual entries), or any
  posture change (version bumps, PR split) returns to the user before proceeding.
- **Pre-existing skill-quality debt:** if Phase 5's first-ever full-fleet checker run surfaces
  FAIL-level findings on skills the sweep touched only mechanically, STOP and surface them —
  fixing unrelated fleet debt is a scope expansion the user decides.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Sweep applied by throwaway script from a reviewed mapping TSV (deterministic
  transform; PR diff is the review surface) instead of parallel agent fan-out or 183 hand edits.
- [EXEC-SHAPE] mapping.tsv lives in the branch-local contract slice (committed, pruned with the
  slice in Phase 6) rather than machine-local `.work/` — 183 rows of curation must survive
  machine/session loss between Phases 1 and 3.
- [EXEC-SHAPE] No per-file checkbox inventory for the 183-file sweep phase — the generator's
  completeness failure mode enumerates any missed file mechanically, which is the checkbox
  table's purpose at a scale where 183 rows would bloat PLAN.md.
- [EXEC-SHAPE] `generate-cheatsheet.mjs` SHIPS a committed `generate-cheatsheet.test.sh` +
  fixture tree (reversal of the earlier no-test lean, on stress-test evidence: all 17 repo
  checkers pair a test; the generator's seven enforcement failure modes are checker semantics,
  and leaving them fixture-less makes the "no silent omissions" acceptance criterion
  regression-prone after merge).
- [EXEC-SHAPE] Issue phase 2 ships as a second PR (drift gate does not couple README split to
  the sweep; smaller review surface).

### Mechanical work

- Commits: `git commit -F - --cleanup=verbatim` (repo hook blocks `-m`); explicit path staging
  only; Write tool for file writes (hook blocks `echo/printf >`).
- Squash merge; PR title = Conventional Commit; branch `feat/1227-skill-cheat-sheet` already
  matches scope.
- Sequential fallback: not applicable (no parallel shape).
- Re-fetch `origin/main` before each PR (main moves fast); rebase when ANY `plugins/*/skills`
  path changed on main — the drift gate couples the sheet to all 183 SKILL.md files, so a skill
  added/renamed/removed upstream means: update mapping.tsv row, re-run the apply script (it is
  a one-command re-run from the TSV by design), regenerate. Line up review promptly — every
  rebase of a slow PR repeats this loop.
