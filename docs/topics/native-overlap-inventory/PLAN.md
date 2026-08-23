# Native overlap inventory

## Brief

**TLDR:** Add a `claude-ops:audit-native-overlap` sibling skill that maps native Claude Code
surfaces (built-in CLI commands, bundled skills) against the current repo's plugin skills and
agents, records human-gated per-overlap verdicts in a committed verdict/record store (the SSOT)
rendered into a generated registry view (`docs/NATIVE-SURFACES.md`) whose rows carry recheck
triggers, and — only behind an explicit apply step — bakes routing-effective, presence-gated
native references into component descriptions plus Boundary sections in bodies, with a
deterministic store/registry freshness + parity check wired into CI.

### Goal

Every marketplace component whose purpose materially overlaps a native surface carries truthful,
routing-effective guidance about when to prefer or compose the native equivalent, sourced from a
single registry that announces its own staleness instead of decaying silently.

### Locked decisions

1. **Packaging** — new sibling skill in `claude-ops` (working name `audit-native-overlap`).
   Bare invocation is a read-only report; mutation only behind an explicit apply step (codified
   `audit` verb contract). Must be repo-generic: it targets "the current repo's plugin tree", never
   a hardcoded melodic-software layout (claude-ops ships to external consumers).
2. **Registry** — a two-part shape (amended post-validation: a generated doc cannot be the SSOT,
   or regeneration destroys human verdicts). The **SSOT is a committed, hand-editable
   verdict/record store** (a data file; exact path/format is Q13) holding, per overlap: native
   surface (with hidden/gated markers), our component, verdict + reason, evidence, observation
   record, and a four-part upstream-drift record with a per-row **recheck trigger** (a date alone
   does not qualify). `docs/NATIVE-SURFACES.md` is the **generated view** over that store
   (marker-fenced, never hand-edited, `--check` drift-gated like `docs/CATALOG.md`). Observation
   records distinguish their evidence class: *extraction-evidence* ("extracted from binary
   v<X> on <date>") vs *live-roster observation* ("observed in <env> session on <date>") — never a
   static availability assertion. Seeded candidate pairs stay in skill reference data (candidates,
   not verdicts).
3. **Baked guidance** — routing-effective text lives in frontmatter *descriptions* (in model
   context **by default, subject to the listing budget**: descriptions degrade to name-only when
   the 1%-of-window aggregate budget overflows, least-invoked first — and this repo's fleet
   currently exceeds that budget several-fold, so a baked phrase is the best available surface,
   not a guaranteed one), phrased as a read-time presence gate ("when the bundled X skill
   resolves in your session, prefer it for …; this skill for …"), within description budget. The
   audit report therefore includes a **budget-exposure section** (composing the existing advisory
   `check-listing-budget.sh`) and the store records a per-row "phrase may be budget-dropped"
   caveat where it applies. The
   body gets a fuller Boundary section where warranted (the `review` plugin's organic pattern is
   the model). Baked text is self-contained — shipped plugins never cite the registry doc (broken
   ref at install time). The native-reference phrasing gets its own owner convention doc
   (seam-phrasing covers cross-plugin references only).
4. **Verdict enum** — `prefer-native` / `prefer-ours` (reason required) / `complementary` /
   `superseded` / `defer` (undetermined: gated, experimental, or unverifiable surfaces). No blanket
   preference rule.
5. **Verdict authority** — candidates auto-detected with evidence; every verdict human-gated
   before any component file is modified.
6. **Detection posture** — floor-honest: consume `inventory.py` output with its integrity status
   carried into the report, seed from a hand-curated canonical-pairs list, allow human-added
   candidates. Honest under-recall over confident completeness. Two substrates, named explicitly:
   native-side rows come from `inventory.py` JSON; **target-side enumeration is the skill's own
   repo-tree scan** (`plugins/*/skills/*/SKILL.md` + `plugins/*/agents/*.md` frontmatter) —
   inventory.py scans installed trees, not necessarily the audited repo's.
7. **V1 sources** — built-in CLI commands + bundled skills (verdict-bearing, with hidden/gated
   markers). Cloud/session-provided skills: observation-only rows (defer verdict allowed, no baked
   lines) until an in-session capture protocol exists.
8. **V1 targets** — this repo's plugin skills and agents. Agents are registry-rows-only (no
   agent-file edits — role prompts load post-dispatch; actionable lines live at the dispatching
   skill's surfaces).
9. **Freshness** — a deterministic self-check script (exit 0 ok / 1 broken / 3 degraded), shipped
   as a skill deliverable and wired into CI or a loop lane. Its deterministic scope (amended
   post-validation — offline CI cannot decide that an upstream *event* fired): per-row trigger
   **presence**, record well-formedness, store↔generated-view parity, store↔baked-line parity, and
   locally decidable comparisons (e.g. store-recorded cli_version vs the current binary/inventory
   snapshot). Evaluating whether an event-based trigger actually *fired* (re-fetching the basis)
   is a session act performed by the audit skill's report, not by CI. `/claude-ops:changelog` is
   an on-demand semantic diff aid, not the refresh trigger (it has never completed an automated
   run here and is blind to server-side drift).
10. **Foreign-repo posture** (added post-validation) — the skill is repo-generic: store/registry
    paths are configurable (claude-ops userConfig precedent), and in a repo without this
    marketplace's conventions tree or CI gates, bare invocation degrades to report-only with the
    baking/apply machinery unavailable rather than erroring. CI wiring is a this-repo deliverable,
    not a skill deliverable.

### Constraints

- Naming grammar and `audit` mutation contract per `docs/PLUGIN-PHILOSOPHY.md`; skill `name`
  matches directory; portability checks (`check-skill-portability.sh`) must pass.
- Cross-plugin file imports forbidden — detection must reuse
  `${CLAUDE_PLUGIN_ROOT}/skills/inventory/scripts/inventory.py` from within claude-ops (same-plugin
  reuse only), which forces the packaging decision.
- Description edits respect the per-entry character cap and listing budget; presence-gated
  phrasing only — natives are plan/host/`disableBundledSkills`-gated, so any static availability
  assertion is wrong somewhere by construction.
- Repo process: PRs required, squash merge, Conventional Commits titles; fresh-docs mandate on
  manifest/schema claims; never hand-copy external docs — state the rule, link the source.
- Convention registry one-owner rule: the native-reference phrasing convention lands in an owner
  doc before any fleet-wide application.

### Acceptance criteria

1. `plugins/claude-ops/skills/audit-native-overlap/` exists, passes `skill-quality:check` and the
   repo's deterministic check scripts; bare invocation produces a report and mutates nothing.
2. The verdict/record store exists with at least the seeded canonical pairs at **skill-level
   target granularity with a source-class field** (bundled skill `code-review` vs
   `review:code-review`; bundled skill `simplify` vs `code-tidying:tidy` and
   `code-tidying:batch-simplify`; built-in command `security-review` vs
   `review:security-review`; bundled skill `run` vs `testing:run-e2e`; plus peers found during
   detection), every row carrying a verdict from the 5-value enum, evidence, a class-tagged
   observation record, and a per-row recheck trigger + verified date — the **initial verdict
   session is part of this build** (the PR author is the human gate) — and
   `docs/NATIVE-SURFACES.md` is generated from it.
3. The self-check script exits 0/1/3 and fails on trigger-less rows, malformed records,
   store↔view drift, store↔baked-line parity breaks, and failed locally-decidable comparisons
   (per locked decision 9's deterministic scope); it is wired into CI (or a loop lane) in the
   same change set, with an explicit exit-3 policy (Q15).
4. The native-reference phrasing convention doc exists with a registered owner.
5. The apply step, given approved verdicts, emits description phrases + Boundary sections, is
   **demonstrated on a claude-ops-internal component** (claude-ops is already bumping in this
   change set; other plugins' edits are sweep units under Q14), and parity is
   **direction-sensitive**: every baked line must trace to a store row, while a verdict row
   without a baked line is legal pending-sweep state. Nothing is applied on bare invocation.
6. The execution contract for the baking sweep (bulk application) is **written into the skill**:
   one plugin at a time — apply, verify (parity check + `skill-quality:check` + plugin version
   bump + CHANGELOG note), PR, close; a unit is closed only when its PR merges green. Sweep
   *execution* is Q14 (USER-RESERVED), not part of this build.

### Captured assumptions

- `inventory.py`'s JSON is the detection substrate, but its integrity block guards
  *extraction-level* drift only, not the emitter's own top-level key names (validated against
  `inventory.py:596-672`) — so the consumer MUST assert `schema == 1`, presence-check every key it
  reads, and report a missing key as `broken` consumer-side. This is a requirement, not an option.
- claude-ops takes a minor version bump for the new skill (additive change, semver minor). The
  bump drags two coupled edits into the same change set: the plugin.json "Ten skills: …"
  description rewrite and `docs/CATALOG.md` regeneration.
- The seeded canonical-pairs list is maintained in the skill's reference data (candidates only);
  verdicts live in the committed store; the registry doc is generated output.

### Out-of-scope

- MCP tools as sources (`mcp-tools:audit` owns that domain); our hooks as targets; our commands as
  targets (component class is empty — `commands/` is Prohibited).
- Cloud-lane capture protocol (in-session roster probe) — deferred post-V1; until then cloud rows
  are observation-only.
- Telemetry-driven verdict evidence (skill-usage.jsonl routing data) — post-V1 enhancement.
- Automatic verdicts or automatic baking of any kind.
- The undocumented bundled keep-set behavior (bundled descriptions possibly protected from budget
  dropping — single-source binary evidence, MEDIUM): no registry row or phrasing guidance builds
  on it until a live probe confirms it (post-V1; the routing asymmetry it would imply is noted in
  the phrasing convention doc as an open consideration, nothing more).

### Deferred questions

- Q12 (arbiter: /planning:plan): registry self-check placement — ci.yml gate vs loop-lane step vs
  both; pick with plan-time knowledge of CI cost and lane cadence.
- Q13 (arbiter: /planning:plan): exact registry column layout and generation format (single table
  vs per-source-lane sections), and where the seeded canonical-pairs data file lives inside the
  skill.
- Q14 (arbiter: USER-RESERVED): whether/when to run the fleet-wide baking sweep after the skill
  lands — the sweep touches many plugins' descriptions (routing-affecting) and is a separate
  human go/no-go beyond this build.
- Q15 (arbiter: /planning:plan): the wired gate's exit-3 policy under chronic degradation — the
  substrate is `degraded` on every run today (`VALIDATED_AGAINST = "2.1.228"` vs vendored binary
  2.1.232 vs upstream 2.1.241) — and whether bumping `VALIDATED_AGAINST` (with revalidation) is
  in this change set's scope.

## Plan

Deferred-decision resolutions (arbiter /planning:plan, evidence in `.work/native-overlap-inventory/`):

- **Q12 [EXEC-SHAPE]** — the self-check wires into `scripts/validate-plugins.sh` (the existing
  plugin-gate job already in `ci-status.needs`), following the autonomy plugin's precedent of a
  plugin-shipped `--check` script invoked there. No new CI job, so no lane-coverage membership
  change. A loop lane is not added (no lane machinery runs this repo's loops on a schedule today).
- **Q13 [EXEC-SHAPE]** — store at `docs/native-surfaces/records.json` (JSON, not YAML: the
  self-check is Python-stdlib-only per inventory.py's no-third-party discipline, and stdlib has no
  YAML parser). Registry view stays `docs/NATIVE-SURFACES.md`, per-source-lane sections. Seeded
  pairs at `plugins/claude-ops/skills/audit-native-overlap/reference/canonical-pairs.json`.
- **Q15 [EXEC-SHAPE]** — the wired gate fails on exit 1 (broken) and passes-with-printed-summary
  on exit 3 (degraded), matching the stale-but-honest doctrine; a chronically red gate on a
  condition the registry does not own is worse than an annotated pass. `VALIDATED_AGAINST` bump:
  **out of scope** [FALLBACK — confirm or override] — it belongs to inventory-skill maintenance
  and requires revalidation against the new build; filed as a follow-up in the PR body instead.

Contracts (store schema, pairs schema, exit codes, substrates): `design/design-resolution.md`.

### Phase 1: Native-references convention doc [TODO]

Create `docs/conventions/native-references/README.md` — the owner doc for native-surface
reference phrasing: the presence-gated description-phrase grammar ("when the bundled X skill
resolves in your session, …"), the Boundary-section shape for bodies (modeled on the review
plugin's provenance-classed sections), the self-containment rule (no registry citations from
shipped plugins), the guard vocabulary (availability is never asserted statically — natives gate
on settings/env, plan, platform, surface), the budget caveat (descriptions degrade to name-only
under the listing budget), and the keep-set open consideration (single-source, unconfirmed — no
guidance builds on it). Register the doc in `docs/PLUGIN-PHILOSOPHY.md`'s convention-registry
table (one-owner rule).

**Sanity Check:** `test -f docs/conventions/native-references/README.md` exits 0; `grep -c
"native-references" docs/PLUGIN-PHILOSOPHY.md` ≥ 1; `markdownlint-cli2` clean on the new doc.

### Phase 2: Skill skeleton + seeded pairs + evals [TODO]

Create `plugins/claude-ops/skills/audit-native-overlap/`:

- `SKILL.md` — frontmatter description ≤1,536 chars (audit verb contract: bare = read-only
  report; apply behind explicit argument), argument-hint, user-invocable; body <500 lines covering
  purpose, scope boundary vs siblings (inventory/audit-install-state/plugins/changelog), the
  two detection substrates, the report structure (overlap candidates + budget-exposure section
  composing `check-listing-budget.sh` + integrity floors carried), verdict enum + human gate,
  apply step contract, foreign-repo degraded posture, and the store/view/self-check anatomy.
  Read `plugins/skill-quality/skills/check/reference/fresh-eyes-declarations.md` before authoring
  judgment steps (adopted OQ5 default).
- `reference/canonical-pairs.json` — seeded candidates at skill-level granularity with class
  fields: bundled `code-review`→`review:code-review`; bundled `simplify`→`code-tidying:tidy`,
  `code-tidying:batch-simplify`; builtin-command `security-review`→`review:security-review`;
  bundled `run`→`testing:run-e2e`; bundled `morning`→`claude-ops:morning-brief`.
- `evals/evals.json` — per the skill-quality evals schema (`--require-evals` fires on new
  SKILL.md).

**Sanity Check:** `bash plugins/skill-quality/scripts/check-skill.sh
plugins/claude-ops/skills/audit-native-overlap/SKILL.md --require-evals` exits 0;
`python3 -c "import json;json.load(open('plugins/claude-ops/skills/audit-native-overlap/reference/canonical-pairs.json'))"`
exits 0.

### Phase 3: Scripts — detection, generation, self-check [TODO]

Create `plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py` (Python 3.11+,
stdlib-only), subcommands:

- `detect` — consume an inventory JSON (path arg; the skill body documents producing it via the
  sibling `${CLAUDE_PLUGIN_ROOT}/skills/inventory/scripts/inventory.py`), assert `schema == 1` +
  presence-check consumed keys (missing → broken); repo-tree scan for targets
  (`plugins/*/skills/*/SKILL.md`, `plugins/*/agents/*.md`); merge with `canonical-pairs.json`;
  emit candidate rows (evidence + integrity floors carried; never auto-verdicts).
- `generate` — render `docs/NATIVE-SURFACES.md` from `records.json` (marker-fenced, per-lane
  sections); `generate --check` regenerates and diffs (CATALOG.md pattern).
- `self-check` — exit 0/1/3 over the deterministic scope (store parse/schema, trigger presence,
  record well-formedness incl. observation class tags, store↔view drift, baked-line parity
  direction-sensitively via grep of components named in `baked` rows, locally-decidable
  comparisons). 2 reserved for argparse.
- Sibling tests: `test_overlap.py` (pytest-style, like `test_inventory.py`) + `overlap.test.sh`
  wrapper so `run-plugin-tests.sh` discovers it. Store/pairs paths configurable via flags with
  repo-relative defaults (portability; foreign-repo degraded mode = report-only when paths
  absent).

**Sanity Check:** `python3 plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py
self-check --store docs/native-surfaces/records.json --view docs/NATIVE-SURFACES.md` exits 0;
`bash plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.test.sh` exits 0;
`bash scripts/check-skill-portability.sh` exits 0.

### Phase 4: Store seed + generated registry [TODO]

Create `docs/native-surfaces/records.json` with the seeded rows: every row carries a
recommended verdict + reason (initial verdict session — recommendations surfaced for the human
gate in the PR; `morning`→`morning-brief` and the four canonical pairs at minimum, plus
`detect`-surfaced peers), class-tagged observation records (extraction-evidence from the vendored
binary run), per-row recheck triggers keyed on the drift-fast list (RESEARCH-recency-drift), and
`baked` flags all false except the Phase 5 demo row. Generate `docs/NATIVE-SURFACES.md`.

**Sanity Check:** `overlap.py self-check …` exits 0 (no trigger-less rows, view in sync);
`overlap.py generate --check` exits 0.

### Phase 5: Apply demo on claude-ops-internal component [TODO]

Run the apply step for one approved-recommended row: bundled `morning` skill vs
`claude-ops:morning-brief` (verdict: complementary — the bundled skill is a generic morning
digest; morning-brief is the repo-operator queue/PR/lane view). Bake the presence-gated
description phrase into `morning-brief`'s frontmatter description (within cap) and a Boundary
section into its body, per the Phase 1 convention. claude-ops is already bumping in this change
set, so no foreign plugin is touched (Q14 untouched). Set the row's `baked` flags true.

**Sanity Check:** `overlap.py self-check` exits 0 (parity: baked ⊆ store);
`grep -c "morning" plugins/claude-ops/skills/morning-brief/SKILL.md` shows the boundary section;
description length ≤1,536 (`check-skill.sh` exits 0 on morning-brief).

### Phase 6: CI wiring + plugin bump + coupled edits [TODO]

- Wire `overlap.py self-check` + `generate --check` into `scripts/validate-plugins.sh`
  (fail on exit 1; on exit 3 print summary and pass — Q15 policy, with a comment stating it).
- Bump claude-ops `plugin.json` 0.32.6 → 0.33.0; add `## [0.33.0]` CHANGELOG entry; rewrite the
  "Ten skills: …" description to eleven; regenerate `docs/CATALOG.md`.
- Add `docs/native-surfaces/records.json` + generated view to the repo (Phase 4 files land here
  if not already committed).

**Sanity Check:** `bash scripts/validate-plugins.sh` exits 0; `bash
scripts/check-changelog-parity.sh --check-bump plugins/claude-ops` (or the repo's exact
invocation) exits 0; `node scripts/generate-catalog.mjs --check` exits 0; `grep -c "Eleven
skills" plugins/claude-ops/.claude-plugin/plugin.json` = 1.

## Blast radius

MEDIUM-LOW. Additive: one new skill, one convention doc, two data/doc files, CI check inside an
existing job. The only behavior-adjacent edits are morning-brief's description (routing-affecting
for one skill, reversible) and the validate-plugins.sh wiring (could redden CI — mitigated by the
exit-3 pass policy and by running the full gate set locally before push). No foreign plugin
touched; sweep reserved (Q14).

## Stress-test summary

Formal /planning:devils-advocate skipped: blast radius below the trigger bar AND the design has
already survived three adversarial validation rounds (round-1 recommendations → 3 validators;
round-2 revisions; post-discovery 2-validator pass with challenged items amended into the Brief).
Step-3 fresh-context plan review: dispatched; findings verified and folded in before approval.

## Execution shape

Sequential, single implementer (phases share claude-ops files and each phase's sanity check
feeds the next; no material parallel-safe volume). Per-phase surface: implementation:implementer
worker for all six phases in one dispatch (phase order enforced by the plan), main session
orchestrates + verifies. Fallback: main-session inline execution if the worker cannot run gates.

## Open questions

None blocking. Q14 (fleet sweep go/no-go) remains USER-RESERVED post-merge. Follow-up filed in
PR body: VALIDATED_AGAINST bump + revalidation for inventory.py (Q15 resolution).

## Handoff to implementation

### User-approval gates

User pre-authorized the full chain through PR and merge ("Lets go with all recommendations …
get everything PR'd and merged"). Standing gates honored in the PR body instead of live prompts:
the seeded verdicts are labeled recommendations for review; the [FALLBACK] Q15 scope cut
(no VALIDATED_AGAINST bump) is called out for override.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential phases 1→6 in one implementer dispatch on branch `claude/cli-skill-inventory-v7hi82`;
commits per phase (Conventional Commits); PLAN.md phase tags advanced by the main session on
verified completion.

### Mechanical work

Before PR: run the full local gate set (`validate-plugins.sh`, `check-skill.sh --require-evals`
on new/changed skills, `check-skill-portability.sh`, `check-changelog-parity.sh`, markdownlint,
shellcheck on any .sh, `run-plugin-tests.sh` scope). PR per repo process (squash, Conventional
Commit title, template if present), subscribe to PR activity, drive CI green, merge
(user-authorized), then delete branch. Close-out (`/planning:plan close-out`) after merge:
PLAN.md into PR description happened at PR time; contract-slice prune is deferred until the user
requests it (the topic docs stay useful for the reserved Q14 sweep).
