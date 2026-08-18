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

<empty — populated by /planning:plan>
