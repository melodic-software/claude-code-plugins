# skill-recommendation-system

> **Scope change — 2026-08-18.** The original Brief (commit `6cd302db`) was rewritten after
> `/planning:audit-answers` ran three fresh-context adversarial validators, plus `/discovery:explore`,
> `/discovery:research`, and a fresh-eyes verifier. Five of eight auditable decisions were challenged
> by all three validators independently. The candidate-source decision was **factually wrong** — the
> in-context skill listing omits 27% of the catalog outright and truncates most of the rest — and the
> output contract was **measured** at 139 options / 275 lines / ~4,100 tokens per invocation, i.e. the
> generated cheat sheet with an extra column. Both are replaced below. Findings ledger:
> `.work/skill-recommendation-system/audit-findings.md`.

## Brief

### TLDR

- New skill `/session-flow:show-options` — a human-facing menu answering "what should I run next?"
- **Two-tier output**: a ranked shortlist per bucket with full treatment, plus the complete remainder
  as bare names with explicit counts. Nothing is ever off-screen; one word expands any roster.
- **Two-rule presentation contract**: never omit a name; never let already-done or unnecessary
  influence rank or omission. A skill believed to have run is ranked normally and annotated.
- Candidates come from a **completeness ladder** — `/claude-ops:inventory` when installed, else an
  operator-supplied catalog via a documented seam, else the in-context listing **with its truncation
  stated in the output**. Never from the listing alone.
- **V1 ships manual-only** (`disable-model-invocation: true`): zero listing-budget cost, no trigger
  collision. Model-invocability is a graduation, gated on evidence.

### Goal

Turn the installed skill catalog — ~207 skills across 65 plugins here, plus built-ins — from
something the operator must remember into something they can consult. Invoked at any point, the skill
reads the session's durable state and trajectory and lays out candidate skills as ranked options
grouped by when they apply, each saying what it would add *to this conversation* and when someone
would skip it. It never withholds an option because it judges the step done or unneeded; that
judgment appears as an annotation and may affect order, never presence. Over repeated use it should
also widen the operator's working knowledge of their own catalog rather than re-showing the same
five skills forever.

### Constraints

- **No-gatekeeping, stated as two rules because one was insufficient.** (1) Never omit a candidate's
  name. (2) Never let "already done" or "unnecessary" influence rank or omission — such a judgment
  renders as an annotation (`ran this session`). Ranking is permitted and wanted; suppression is not.
  In-repo precedent to cite rather than invent: `plugins/session-flow/reference/structure.md:33-38`
  ("every section is always present… the absence is itself load-bearing") and `adhd:clarify`'s
  fidelity rule ("list omissions explicitly… the reader decides whether an omission mattered").
- **Never invent a candidate.** The contract forbids omission, which creates pressure to fill buckets
  from a truncated source. `workflow` already carries the counter-rule twice — "Never invent skill
  names — check what actually exists" — and the `skill-reference-verify` hook cannot help here (it is
  PostToolUse on `Write|Edit` of `*.md`; a menu rendered into the conversation is never graded).
- **Define the unnecessary/irrelevant boundary explicitly.** Omitting an *out-of-domain* skill
  (songwriting in a code session) is required; omitting an *unnecessary* one is banned. One word
  apart, and the whole option count swings on it. Undefined, the model relitigates it every firing
  and reintroduces the banned discretion.
- **Output must stay scannable.** Measured under the original contract: 139 options, 275 lines, 7
  screens, ~4,100 tokens — 97.8% of the catalog. The operator's own `adhd:shape` rule 9 ("cap lists
  at five items… five ranked items beat ten unranked") forbids that shape, and its single exemption
  is bounded by a bounded input, which a 207-skill catalog is not.
- **Candidate completeness is a correctness property, not a nicety.** The in-context listing omits
  **56 of 207** skills entirely (every `disable-model-invocation: true` skill — verified: none of
  `education:teach`, `disk-hygiene:clean`, `planning:questionnaire`, `claude-ops:plugins`,
  `claude-ops:lanes`, `repo-fleet-hygiene:apply`, `discipline:wait-what` appears in a live listing),
  and drops descriptions from the **least-invoked skills first** — i.e. exactly the forgotten ones.
  Measured by this repo's own tool: **101,563 chars against an 8,000-char budget, 12.7× over.**
  Sourcing from the listing alone reinstates the banned gatekeeping invisibly, biased the worst way.
- **Do not walk the plugin cache directly.** `plugins/skill-quality/skills/check/SKILL.md:43-48`
  refuses that deliberately (the `<marketplace>/<plugin>/<version>` nesting is undocumented and the
  version dir changes on every update). Route to `/claude-ops:inventory`, which already owns fleet
  enumeration through a bundled script — `discipline:reuse-or-replace`-compliant where a second
  walker is not.
- **Portable.** Must degrade cleanly outside this repo. No runtime read of `docs/SKILL-CHEAT-SHEET.md`
  by path: it lives outside `plugins/`, and copied plugins cannot reference files outside their own
  directory. Name it as an example of the shape, resolve a real catalog through a documented seam.
- **No embedded inventory.** Confirmed by all three validators: rendered SKILL.md persists for the
  whole session (recurring token cost) and a hardcoded list rots — 7 skills were added here in five
  weeks. `workflow`'s own gotcha: "a navigator that has drifted from the actual capability inventory
  is worse than none".
- **Boundary carve against FOUR neighbors** (the fourth was unnamed in the original Brief), each in
  "What this skill does NOT do": `/session-flow:workflow` routes to the one next *stage* and mandates
  "route to exactly ONE owner… never present both" (`SKILL.md:149-160`) — structurally the inverse of
  this skill, so the carve must be explicit **and reciprocal**; `/session-flow:orient` reports
  position and prescribes nothing; `/discipline:use-your-skills` corrects the *model's* skipped-skill
  drift; the handoff document's **§14 "Suggested skills"** (`reference/structure.md:319-328`) already
  recommends fully-qualified skills tied to remaining work — carve: durable artifact for a cold
  reader vs live ephemeral menu.
- **Naming grammar.** `docs/PLUGIN-PHILOSOPHY.md:42-87` requires an imperative verb phrase, with
  exactly six per-name exceptions and "a name class is never blanket-sanctioned". All 207 skills
  conform. No CI gate enforces it — it fails at review.
- Repo conventions: `metadata.workflow-stage` (from the `STAGES` enum) and `metadata.summary`
  (≤100 codepoints) required; description ≤1,536 chars with single-quoted trigger phrases; body
  ≤500 lines hard / 200 soft.

### Acceptance criteria

- `plugins/session-flow/skills/show-options/SKILL.md` exists with `user-invocable: true`,
  `disable-model-invocation: true` (V1), and `metadata.workflow-stage: anytime`.
- Output renders two tiers: a ranked shortlist per bucket (≤5, full three-part treatment: invocation
  name, what it adds *to this conversation*, when you would skip it) and the complete remainder as
  bare invocation names with an explicit count (`Also live now (23): …`). Total ≤ ~60 lines / 2
  screens for a typical moment.
- Buckets are **Now**, **Next**, **Skipped upstream**, and a **Spotlight** of 3:
  - *Skipped upstream* replaces "Backfill" and is **artifact-grounded** — only stages upstream of the
    detected position whose output artifact is absent on disk. (Measured: collapses 27 → 2 real
    items. `workflow` already mandates artifact-grounded stage detection: "verify a stage from its
    artifact or output… not from conversation vibes".)
  - *Spotlight* replaces "Standing" (which held 60 options, 43% of the catalog, and predicted
    nothing): 3 skills ordered **least-recently-surfaced**, from a small ledger this skill writes
    itself.
- An option whose stage already ran still appears, ranked normally, annotated — verified by an eval
  case where exploration is complete and `/discovery:explore` remains listed with an annotation.
- A refusal eval case proves the skill does not invent a skill name absent from the resolved catalog.
- The candidate ladder is exercised: with `/claude-ops:inventory` present the pool is the full fleet;
  without it the output **states** that the listing is truncated and by how much.
- Running in a repo with no marketplace metadata still yields buckets from names and descriptions.
- Body carries the four-neighbor boundary section; `workflow`'s precedence clause is amended
  reciprocally to cede option-surfacing.
- `evals/evals.json` exists (mandatory — `check-changed-skills.sh` passes `--require-evals`), schema-
  conforming, including the refusal case.
- **Success criterion, so the design can fail:** the operator invokes ≥1 presented option in a
  majority of firings, and a never-before-run skill is invoked at least once a week. Recheck the
  bucket cut if not.

### Captured assumptions

- `/claude-ops:inventory` is the right completeness source — revisit if its output shape proves
  unusable or if it is commonly uninstalled.
- Four buckets with a 3-item spotlight is the right cut — revisit if Skipped-upstream is
  persistently empty or Spotlight is persistently ignored.
- A self-written last-surfaced ledger is enough to drive rotation without any Claude Code internal
  state — revisit if rotation feels arbitrary in use.

### Out-of-scope

- A deterministic `UserPromptSubmit` per-prompt routing hook — deferred, consistent with the same
  deferral in `/discipline:use-your-skills`. **Note its recorded revisit trigger ("skills repeatedly
  not firing despite the soft re-anchor") is arguably firing now; the PR must adjudicate it in
  writing rather than leave it silent.** `Stop` / `TaskCompleted` are the deterministic
  boundary events, never `UserPromptSubmit` — the original Brief out-scoped the wrong hook.
- Copying `ask-matt`'s `PHASE-BOUNDARIES.md` pattern: its first-yes-wins ordering is a *filtering*
  structure this contract forbids. (Resolves the old Q10.)
- Changing `orient`, `use-your-skills`, or the handoff document. `workflow` gets a reciprocal
  boundary amendment only.
- A new plugin; agents/commands/MCP tools as candidates (skills only in V1).

### Deferred questions

- Q4 — Read `~/.claude.json` `skillUsage` (`usageCount` / `lastUsedAt`) or OTEL to bias surfacing
  toward never-run skills? V1 no longer *depends* on it: rotation runs off this skill's own ledger,
  which decouples the learning mechanism from undocumented internal state. Defer until V1 is in use;
  **arbiter: USER-RESERVED**.
- Q10 — *(closed by research — see Out-of-scope.)*
- Q11 — Should the skill offer to execute a picked option (`session-flow:orchestrate` /
  `discipline:sweep-all` are precedents), or stop at presentation? Defer until V1 is in use;
  **arbiter: USER-RESERVED** (changes acceptance criteria).
- Q12 — `metadata.workflow-stage`: `anytime` or `session`? Actual split is `session` 9, `retro` 2,
  `anytime` 1 — not the "11 of 13" an earlier artifact claimed. **arbiter: /planning:plan**.

### Implementation obligations surfaced by the audit

Not decisions — mechanically forced work a plan must carry:

1. **`contract-slice-prune-gate` fails on this branch right now** (verified by direct run).
   `docs/topics/<slug>/` is Contract tier: committed on the task branch only, **pruned before merge**,
   and adding the slug to `scripts/contract-slice-baseline.txt` exempts nothing (the gate reads the
   baseline from the base revision). The PR must graduate durable outcomes out of the slice, name the
   pre-prune commit SHA in its body, and delete the slice in a final commit.
2. Five forced out-of-skill edits: `plugins/session-flow/.claude-plugin/plugin.json` (its description
   enumerates all thirteen skills **by name and states the count**), a version bump, `CHANGELOG.md`,
   `README.md` — including **line 3's "bundling thirteen skills"**, missed by the exploration — and
   two regenerated docs (`docs/SKILL-CHEAT-SHEET.md`, `docs/CATALOG.md`). `marketplace.json` needs no
   change.
3. Extract `plugins/session-flow/reference/gather.md` as the shared durable-state probe. `orient` and
   `workflow` already inline near-identical blocks; `point-dont-copy` pins the duplication threshold
   at **two**, so a third copy is barred. Preserve the `#1687` no-precompute rationale
   (`$`-expansion fails in worktree-isolated agents). Resolve paths through the topic-docs binding —
   never hardcode `.work/` or `docs/topics/`, which are configurable defaults.
4. Durable state is the **primary** signal, conversation secondary — the original inverted this, and
   the compacted session (where at most ~5 skills' content survives re-attachment) is exactly when
   the operator most needs the skill and conversation is least reliable.
5. Budget the token cost explicitly; ~10 boundary firings at the original 4,100 tokens would have
   been ~41k tokens/session of menu.

## Plan

**Standards grounding.** No `standards-index` is present in this repo (the planning binding's
resolution ladder finds none, and `plugins/*/reference/standards-contract.md` exists only for
`planning` and `review`, neither materialized into a consumer index here). Grounding therefore comes
from the repo's own ambient governance, loaded for the surfaces this task touches:
`docs/PLUGIN-PHILOSOPHY.md` (naming grammar §42-87, skills-as-primary-surface §164-188, instruction
economy §551-584), `docs/CATALOG-TAXONOMY.md`, `docs/conventions/topic-docs/`,
`docs/conventions/seam-phrasing/`, and `plugins/skill-quality/` as the check authority.

**Q12 resolved** (arbiter `/planning:plan`): `metadata.workflow-stage: anytime`. Basis — the Brief's
goal is invocation "at any point"; the nearest functional sibling `workflow` is `anytime`, while the
nine `session`-tagged session-flow skills are lifecycle *actions* (handoff, clean-stop, keep-going).
`anytime` is also the cheat sheet's cross-cutting group. Noted: that group is ~57 rows, so the
grouping is semantic, not a discoverability win.

### Phase 1: Probe the candidate ladder [TODO]

De-risks the one genuine viability unknown before any authoring: whether `/claude-ops:inventory`'s
output is actually consumable as a catalog source, including the manual-only skills the in-context
listing omits. If it is not, the ladder's top rung changes and Phase 3's contract changes with it —
so this resolves first and cheaply.

Work items:

1. Invoke `/claude-ops:inventory` and capture its output shape (fields available per skill: name,
   description, plugin, any metadata).
2. Confirm it enumerates `disable-model-invocation: true` skills (the 56-skill blind spot).
3. Record the resolved rung-1 contract in `design/design-resolution.md`'s contract sketch; if
   inventory is unusable, record the fallback (operator-supplied catalog seam becomes rung 1) and
   flag it as a scope-change note.

**Sanity Check:** the captured output contains a line for `education:teach` (a manual-only skill
absent from every in-context listing) — `grep -c 'education:teach' <capture>` returns ≥1. A zero
here means rung 1 does not solve the completeness defect and the phase's fallback path applies.

### Phase 2: Extract the shared durable-state gather seam [TODO]

`orient` and `workflow` each inline a near-identical probe block. `point-dont-copy` pins the
duplication threshold at **two**, so adding a third copy in Phase 3 is barred. Extract first.

| File | Action | Rationale |
|---|---|---|
| `plugins/session-flow/reference/gather.md` | CREATE | Shared probe engine; named blocks consumers cite |
| `plugins/session-flow/skills/orient/SKILL.md` | MODIFY | Cite the seam; keep its fuller read set |
| `plugins/session-flow/skills/workflow/SKILL.md` | MODIFY | Cite the seam (subset) |

Must preserve verbatim: the `#1687` no-precompute rationale (`$`-expansion fails in
worktree-isolated agents), the "treat any failure as an unknown value and carry on" rule, and the
20-entry `git status --porcelain` cap. Paths resolve through the topic-docs binding — never
hardcode `.work/` or `docs/topics/`, which are configurable defaults.

**Sanity Check:** `grep -c 'reference/gather.md' plugins/session-flow/skills/orient/SKILL.md
plugins/session-flow/skills/workflow/SKILL.md` returns ≥1 for each, AND
`grep -c '1687' plugins/session-flow/reference/gather.md` returns ≥1, AND
`bash plugins/skill-quality/scripts/check-skill.sh plugins/session-flow/skills/orient/SKILL.md` and
the same for `workflow` both exit 0.

### Phase 3: Author the skill — integration slice [TODO]

The end-to-end slice: a real invocation resolving a real catalog and rendering a real two-tier menu.

| File | Action | Rationale |
|---|---|---|
| `plugins/session-flow/skills/show-options/SKILL.md` | CREATE | The skill |

Frontmatter: `user-invocable: true`, `disable-model-invocation: true`,
`metadata.workflow-stage: anytime`, `metadata.summary` ≤100 codepoints, description ≤1,536 chars
with single-quoted trigger phrases.

Body must carry, at minimum: the candidate ladder with pool-health reporting; the two-rule
no-gatekeeping contract plus the never-invent rule (citing `reference/structure.md:33-38` as
in-repo precedent, not inventing it); the unnecessary-vs-irrelevant test written explicitly; the
four buckets with tier-1/tier-2 rendering; the Spotlight rotation ledger; the four-neighbour
boundary section; and the HTML polarity (terminal = shortlist, HTML = complete sortable table,
ephemeral tier per `docs/conventions/topic-docs/`).

Body ≤500 lines hard / 200 soft — promote the HTML rules and the bucket-derivation detail to
`context/` spokes if the body approaches 200.

**Sanity Check:** `bash plugins/skill-quality/scripts/check-skill.sh
plugins/session-flow/skills/show-options/SKILL.md` exits 0, AND the body contains no enumerated skill
inventory — `grep -cE '^\s*[-|].*\/(discovery|planning|session-flow|discipline):' SKILL.md` returns
only the boundary/example references (expected ≤12, hand-verified), never a catalog. AND a live
invocation renders both tiers: output contains a bucket heading and an "Also …(N):" counted
remainder line.

### Phase 4: Evals [TODO]

`evals/evals.json` is mandatory — `check-changed-skills.sh` passes `--require-evals` on any changed
SKILL.md. Schema: `plugins/skill-quality/reference/evals.schema.json`; house dialect is
`expectations`; `files: []` with narration matches all 13 siblings.

Cases (the refusal case is written first, per `check-evals-quality.sh` Q9):

1. **Refusal / anti-pattern** — does not invent a skill name absent from the resolved catalog.
2. **No-gatekeeping** — exploration already complete; `/discovery:explore` still appears, ranked
   normally, annotated rather than dropped.
3. **Two-tier shape** — output caps tier 1 at 5 per bucket and states a count for the remainder.
4. **Pool health** — with no `/claude-ops:inventory` available, output states the listing is
   truncated rather than presenting it as complete.

**Sanity Check:** `bash plugins/skill-quality/scripts/check-evals-quality.sh
plugins/session-flow/skills/show-options/evals/evals.json` exits 0, AND
`python3 -c "import json;d=json.load(open('.../evals.json'));assert len(d['evals'])>=4"` succeeds.

### Phase 5: Reciprocal boundary amendment to `workflow` [TODO]

`workflow`'s "When two capabilities both fit" (`SKILL.md:149-160`) mandates "route to exactly ONE
owner… never present both" — structurally the inverse of this skill. Its own precedence ladder
adjudicates *against* a newcomer on all three tests, so the carve must be written into `workflow`,
not merely asserted in `show-options`.

Amend that section to cede option-surfacing explicitly: the route-to-one rule governs **stage**
routing; presenting the option set is owned by `show-options`. `workflow` keeps `'what comes next'`
(V1 `show-options` is manual-only, so there is no auto-trigger race), but gains a one-line
cross-reference.

**Sanity Check:** `grep -c 'show-options' plugins/session-flow/skills/workflow/SKILL.md` returns ≥1,
AND `check-skill.sh` on `workflow` exits 0, AND check 3 (trigger-phrase preservation) does not
report a removed trigger.

### Phase 6: Plugin surface and regenerated docs [TODO]

| File | Action | Rationale |
|---|---|---|
| `plugins/session-flow/.claude-plugin/plugin.json` | MODIFY | Description enumerates every skill **by name and states the count** — "thirteen" → "fourteen", add the entry; bump `version` from `0.23.9` |
| `plugins/session-flow/CHANGELOG.md` | MODIFY | Matching `## [<version>]` heading — `check-changelog-parity.sh --check-bump` fails without it |
| `plugins/session-flow/README.md` | MODIFY | **Line 3 "bundling thirteen skills"** (missed by exploration, caught by the verifier), the question table, and a `### show-options` subsection |
| `plugins/session-flow/skills/setup/SKILL.md` | MODIFY | "the other eleven skills are zero-config" count |
| `docs/SKILL-CHEAT-SHEET.md` | REGENERATE | `generate-cheatsheet.mjs --check` fails on drift |
| `docs/CATALOG.md` | REGENERATE | `generate-catalog.mjs --check`; carries plugin.json's description verbatim |
| `.claude-plugin/marketplace.json` | KEEP | Verified: carries no skill-level data |

**Sanity Check:** `bash scripts/validate-plugins.sh` exits 0 (runs both generators with `--check`),
AND `bash scripts/check-changelog-parity.sh --check-bump` exits 0, AND
`grep -c 'thirteen' plugins/session-flow/README.md plugins/session-flow/.claude-plugin/plugin.json`
returns 0 for both.

### Phase 7: Full gate sweep and close-out [TODO]

1. Run the changed-skill gate: `bash scripts/check-changed-skills.sh` (exits 0).
2. Run `bash scripts/check-skill-leaf-names.sh --check` and `check-skill-portability.sh` on the
   changed files.
3. **Contract-slice prune with pointer** — `contract-slice-prune-gate` currently FAILS on this
   branch (verified). Graduate durable outcomes first: this Brief's validated design record is ADR
   material under the admission test (hard to reverse — the candidate-source and output contracts;
   surprising without context — "why not just read the skill listing?"; a real trade-off — three
   rejected alternatives). Write `docs/adr/` entry, name the pre-prune commit SHA in the PR body,
   then a final commit deletes `docs/topics/skill-recommendation-system/`.

**Sanity Check:** `bash scripts/check-contract-slice-prune.sh --check-diff origin/main` reports no
paths remaining under `docs/topics/`, AND `bash scripts/check-changed-skills.sh` exits 0.

## Blast radius

**MEDIUM.** Confined to one plugin plus two regenerated repo docs, and V1 is manual-only so it adds
no listing-budget cost and cannot auto-fire. The elevating factors are that Phase 2 modifies two
shipped skills' gather blocks (a regression there degrades `orient` and `workflow`, not just the new
skill) and Phase 5 edits a doctrine section other skills' routing depends on.

## Stress-test summary

Unusually, the adversarial pass ran *before* planning rather than after: `/planning:audit-answers`
dispatched three fresh-context validators over the decision set, plus a fresh-eyes verifier over the
exploration artifact. Five of eight decisions were challenged by all three independently; two were
factually wrong and were replaced in the Brief. A Step-3 plan-reviewer still runs against this plan
body — the prior pass validated the *decisions*, not the *phasing*.

## Execution shape

Predominantly sequential: Phase 1 gates Phase 3's contract, Phase 2 must precede Phase 3 (the
duplication threshold), and Phase 6 consumes Phase 3's frontmatter.

| Phase | Surface | Basis |
|---|---|---|
| 1 Probe | main session | One invocation plus a judgement call on output shape |
| 2 Gather seam | main session | Edits two shipped skills; regression risk wants direct oversight |
| 3 Skill body | main session | The judgement-heavy core; the whole contract lands here |
| 4 Evals | sub-agent worker | Mechanical against a fixed schema, file-disjoint from Phase 5 |
| 5 workflow amendment | main session | Doctrine edit — small, high-consequence |
| 6 Plugin surface | sub-agent worker | Mechanical count/enumeration edits plus two generator runs |
| 7 Gate sweep | main session | Interprets gate output and owns the prune-with-pointer |

**One parallel opportunity:** Phases 4 and 6 have zero file overlap and neither consumes the
other's output; both depend only on Phase 3. Running them concurrently saves little (both are
small), so the recommendation is **sequential**, with parallelism available if Phase 6 grows.

Scope fences if Phases 4/6 are parallelised — ALLOWED for the evals worker:
`plugins/session-flow/skills/show-options/evals/**` only. ALLOWED for the surface worker:
`plugins/session-flow/.claude-plugin/plugin.json`, `plugins/session-flow/CHANGELOG.md`,
`plugins/session-flow/README.md`, `plugins/session-flow/skills/setup/SKILL.md`, plus the two
generated docs. FORBIDDEN for both: `PLAN.md`, `show-options/SKILL.md`, each other's territory.
Sequential fallback: on any fence violation or concurrent-edit race, re-run both phases in order in
the main session.

## Open questions

- Q4 (usage-metrics surfacing) and Q11 (execute-after-pick) remain USER-RESERVED — see Brief.
- Whether the Spotlight ledger lives in the memory slice or a plugin-data path is a Phase 3
  implementation call; both are self-ignored and neither changes the contract.

## Handoff to implementation

### User-approval gates

- **Phase 1 fallback** — if `/claude-ops:inventory` cannot supply a usable catalog, the ladder's top
  rung changes. Surface the finding and confirm the fallback before authoring Phase 3.
- **Phase 7 ADR** — confirm the ADR's placement and that the graduated content is right before the
  prune commit deletes the slice; a prune is not reversible from the branch alone.

### Execution shape (`[EXEC-SHAPE]` tagged)

Sequential seven-phase ordering with the routing table above; Phases 4/6 parallelisable with the
stated fences and fallback.

### Mechanical work

Commit per phase, conventional-commit subjects. Each phase's `Sanity Check` runs before its commit.
Phase 6's generator runs must be committed together with the source edits that caused the drift.
