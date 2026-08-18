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
`docs/conventions/seam-phrasing/`, **`docs/conventions/liveness-assertion/`** (owner doc for
green-with-hidden-findings — the truncated-pool-reported-as-complete failure is that class verbatim,
and the ladder's disclosure contract conforms to it rather than inventing a term),
**`docs/conventions/plugin-data-report-keying/`** (owner doc for the Spotlight ledger's keying and
retention), and `plugins/skill-quality/` as the check authority.

**Command form for `check-skill.sh`, used by every phase below.** The script takes a *skill name*
resolved under a skills root, never a path — verified: passing a path FAILs with "Skill not found".
Every invocation in this plan uses the form `scripts/check-changed-skills.sh:72-75` uses:

```bash
CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/session-flow/skills" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  bash plugins/skill-quality/scripts/check-skill.sh <skill-name>
```

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

Capture destination: `.work/skill-recommendation-system/inventory-capture.md` (memory tier — a raw
capture, never the contract slice, which Phase 7 prunes).

**Sanity Check:** `grep -q 'education:teach' .work/skill-recommendation-system/inventory-capture.md`
exits 0 — `education:teach` is manual-only and absent from every in-context listing, so its presence
proves rung 1 actually closes the completeness defect. A non-zero exit means it does not, and the
phase's fallback path applies.

### Phase 2: Route durable state to `orient` — do NOT extract a seam in V1 [TODO]

> **Corrected 2026-08-18 by the plan review.** The original phase extracted
> `plugins/session-flow/reference/gather.md` for two consumers, on the stated basis that `orient` and
> `workflow` were the only two. **That was factually wrong — verified: seven session-flow skills
> carry the block and its `#1687` rationale** (`continue-in-background`, `find-handoff`, `handoff`,
> `orient`, `retro`, `running-retro`, `workflow`). Extracting for two would leave five divergent
> copies *plus* a new seam — two sources of truth for one probe, worse than the status quo the phase
> existed to fix.

**Pre-flight consumer census (work item 1, before anything else):**
`grep -rln '1687' plugins/session-flow/skills/` — re-run at execution time and reconcile against the
seven above; a changed census changes this phase's verdict.

**Resolution: `show-options` gathers nothing of its own. For durable state it routes to
`/session-flow:orient`,** a same-plugin sibling that already reads a strict superset of what the
Brief's probe listed. This is `discipline:reuse-or-replace`'s "reuse the established way", adds zero
new duplication, and unblocks the skill without a seven-file refactor. It was also validator B's own
recommendation, recorded before this correction.

**Sub-topic promotion (per the plan skill's trigger — 8 files, independent commit boundary, its own
verification need):** the seven-way gather extraction is promoted OUT of this topic into its own
effort. It is real, worth doing, and must not ride this skill's PR. Phase 7 files it as a tracked
follow-up so the finding is not lost with the pruned slice.

**Sanity Check:** `! grep -q '1687' plugins/session-flow/skills/show-options/SKILL.md` exits 0 (the
new skill inlines no copy of the probe), AND
`grep -q 'session-flow:orient' plugins/session-flow/skills/show-options/SKILL.md` exits 0, AND
`test ! -e plugins/session-flow/reference/gather.md` (no seam created in this PR).

### Phase 2b: Seam-phrasing conformance for the routed call [TODO]

Routing to `orient` and to `/claude-ops:inventory` are both cross-component invocations.
`docs/conventions/seam-phrasing/` requires three elements *at the reference site*: the **gate** ("if
that plugin is installed"), the **fallback**, and **ownership framing**. `orient` is same-plugin so
it needs no install gate, but `/claude-ops:inventory` does. No CI gate covers this — it fails at
review.

**Sanity Check:** for the `claude-ops:inventory` reference, all three elements are present —
`grep -q 'if.*installed' SKILL.md` exits 0 AND the ladder's rung-2/rung-3 fallback is stated in the
same paragraph AND the sentence names inventory as the owner of fleet enumeration (hand-verified
against the convention's three-element list, which has no mechanical checker).

### Phase 3: Author the skill — integration slice [TODO]

The end-to-end slice: a real invocation resolving a real catalog and rendering a real two-tier menu.

| File | Action | Rationale |
|---|---|---|
| `plugins/session-flow/skills/show-options/SKILL.md` | CREATE | The skill |

Frontmatter: `user-invocable: true`, `disable-model-invocation: true`,
`metadata.workflow-stage: anytime`, `metadata.summary` ≤100 codepoints, description ≤1,536 chars
with single-quoted trigger phrases, plus an **`argument-hint`** (every mode-bearing sibling ships
one) so the operator can scope the menu. Decide `shell: bash` deliberately: required only if the
body carries `!` dynamic-context injections (check 19 FAILs on bash-only syntax without it) — V1
routes its gathering to `orient`, so the default is **no `shell:` key**.

Body must carry, at minimum:

1. The candidate ladder, all three rungs. **Rung 2 must be fully specified** — it is the only rung
   that works in a consuming repo without `claude-ops`. Define: the documented file the consumer
   project may supply, its resolution order, its format, and its failure behavior. Name
   `scripts/generate-cheatsheet.mjs` → `docs/SKILL-CHEAT-SHEET.md` as the in-repo generator of
   exactly this artifact shape, and either adopt that format for the seam or reject it in writing
   (`discipline:reuse-or-replace`).
2. **Truncation disclosure conforming to `docs/conventions/liveness-assertion/`** — cite that
   convention; do not coin a local term. Presenting a truncated pool as complete is
   green-with-hidden-findings.
3. The two-rule no-gatekeeping contract plus the never-invent rule, citing
   `reference/structure.md`'s **"Every section is always present"** section by name (never by line
   range — nothing gates line drift).
4. The unnecessary-vs-irrelevant test, written explicitly.
5. **Signal priority: durable state PRIMARY, conversation secondary** (Brief obligation 4).
6. The four buckets with tier-1/tier-2 rendering, and an explicit **output budget** (Brief
   obligation 5): tier 1 ≤5 per bucket, whole output ≤~60 lines.
7. **Degraded behavior when the memory root is unreadable or empty** — in a worktree, sibling lane,
   or fresh clone the memory slice is invisible, so every upstream artifact reads "absent" and
   Skipped-upstream would falsely claim everything was skipped. The skill must report "cannot ground
   upstream stages here" rather than infer.
8. Behavior with **no marketplace metadata** — still yields buckets from names and descriptions.
9. The Spotlight rotation ledger. **Location decided here, not at implementation time:** memory tier
   under the resolved `memory_dir`, accepting that it resets per worktree and per clone.
   `${CLAUDE_PLUGIN_DATA}` is rejected — it is keyed to the plugin id *and nothing else*, so one
   file per machine would let a spotlight surfaced in repo A suppress it in repo B
   (`docs/conventions/plugin-data-report-keying/`). Concurrent-write posture: last-write-wins,
   declared.
10. **Slug selection** for the artifact-grounded bucket: explicit argument → most-recently-modified
    slice → branch-derived.
11. The four-neighbour boundary section.

**HTML rendering is CUT from V1.** It appears in no Brief acceptance criterion, and it would drag in
the ephemeral tier's full obligations (`mktemp` with trailing Xs, a Windows `%LOCALAPPDATA%` branch,
`docs/conventions/windows-path-emit/`). Revisit as a V2 enhancement.

Body ≤500 lines hard / 200 soft — promote bucket-derivation detail to `context/` spokes if the body
approaches 200.

**Sanity Check:** `CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/session-flow/skills"
CHECK_SKILL_SKIP_MARKDOWNLINT=1 bash plugins/skill-quality/scripts/check-skill.sh show-options`
exits 0. AND the body embeds no catalog — portable regex, all namespaces, hard numeric ceiling:
`test "$(grep -cE '^[[:space:]]*[-|].*/[a-z0-9-]+:[a-z0-9-]+' plugins/session-flow/skills/show-options/SKILL.md)" -le 15`
(GNU-only `\s` is banned by `scripts/shell-portability-tokens.txt`; the earlier 4-namespace
alternation false-passed on a catalog drawn from any other plugin). AND the end-to-end render is
checked by **installing the plugin locally** — `claude --plugin-dir plugins` and invoking
`/session-flow:show-options` — output contains a bucket heading and a counted `Also …(N):` remainder
line. If local install is unavailable in the executing environment, this clause downgrades to the
Phase 4 eval assertions and the plan records that no live render was performed.

### Phase 4: Evals [TODO]

`evals/evals.json` is mandatory — `check-changed-skills.sh` passes `--require-evals` on any changed
SKILL.md. Schema: `plugins/skill-quality/reference/evals.schema.json`, whose `required` is
`["skill_name","evals"]`. House dialect is `expectations`. Siblings use `files: []`; **none of the
13 declares `narration`** (the earlier claim that they did was wrong). Set `narration: true`
deliberately on any case whose prompt names a path — Q4 WARNs on path-shaped prose when `files` is
empty and `narration` is unset, and several of these prompts will name `.work/…` or `plugins/…`.

Cases:

1. **Refusal / anti-pattern** — does not invent a skill name absent from the resolved catalog.
2. **No-gatekeeping** — exploration already complete; `/discovery:explore` still appears, ranked
   normally, annotated rather than dropped.
3. **Two-tier shape and size** — tier 1 capped at 5 per bucket, a stated count for the remainder,
   and total output within the ≤~60-line budget.
4. **Pool health** — with no `/claude-ops:inventory` available, output states the listing is
   truncated rather than presenting it as complete.
5. **No marketplace metadata** — in a repo without `workflow-stage` frontmatter, still yields
   buckets from names and descriptions (Brief acceptance criterion, previously uncovered).
6. **Ungroundable memory root** — worktree/fresh clone with no readable memory slice: reports that
   upstream stages cannot be grounded rather than declaring everything skipped.
7. **Durable-state primacy** — thin/compacted conversation with rich durable state: buckets derive
   from the durable reads, not from the conversation.

**Sanity Check:** `bash plugins/skill-quality/scripts/check-evals-quality.sh
plugins/session-flow/skills/show-options/evals/evals.json` exits 0 — noting its Q9
refusal-coverage check is a **WARN, not a FAIL**, so the refusal case is asserted explicitly here
instead:

```bash
python3 -c "
import json
d = json.load(open('plugins/session-flow/skills/show-options/evals/evals.json'))
assert d['skill_name'] == 'show-options'
assert len(d['evals']) >= 7
assert any('invent' in json.dumps(c).lower() for c in d['evals']), 'no refusal case'
"
check-jsonschema --schemafile plugins/skill-quality/reference/evals.schema.json \
  plugins/session-flow/skills/show-options/evals/evals.json
```

(CI validates the schema through a `check-jsonschema` action rather than a repo script; running the
binary directly is the local equivalent.)

### Phase 5: Reciprocal boundary amendment to `workflow` [TODO]

`workflow`'s "When two capabilities both fit" (`SKILL.md:149-160`) mandates "route to exactly ONE
owner… never present both" — structurally the inverse of this skill. Its own precedence ladder
adjudicates *against* a newcomer on all three tests, so the carve must be written into `workflow`,
not merely asserted in `show-options`.

Amend that section to cede option-surfacing explicitly: the route-to-one rule governs **stage**
routing; presenting the option set is owned by `show-options`. `workflow` keeps `'what comes next'`
(V1 `show-options` is manual-only, so there is no auto-trigger race), but gains a one-line
cross-reference.

**Sanity Check:** `grep -q 'show-options' plugins/session-flow/skills/workflow/SKILL.md` exits 0,
AND `check-skill.sh` on `workflow` (standard form above) exits 0 with check 3 (trigger-phrase
preservation) reporting no removed trigger.

### Phase 6: Plugin surface and regenerated docs [TODO]

**Every count target is stated explicitly** — an executor that merely increments ships a still-wrong
number, because "eleven" is *already* off by one against today's thirteen skills.

| File | Action | Exact change |
|---|---|---|
| `plugins/session-flow/.claude-plugin/plugin.json` | MODIFY | `thirteen` → `fourteen`; add the `show-options` entry to the by-name enumeration; `version` **`0.23.9` → `0.24.0`** (new skill = minor) |
| `plugins/session-flow/CHANGELOG.md` | MODIFY | Add `## [0.24.0]` heading — exact match required |
| `plugins/session-flow/README.md` | MODIFY | **line 3** `thirteen` → `fourteen`; **line 254** `eleven` → `thirteen`; the question table; a `### show-options` subsection |
| `plugins/session-flow/skills/setup/SKILL.md` | MODIFY | **line 2** (frontmatter description) `eleven` → `thirteen` |
| `docs/SKILL-CHEAT-SHEET.md` | REGENERATE | `generate-cheatsheet.mjs --check` fails on drift |
| `docs/CATALOG.md` | REGENERATE | `generate-catalog.mjs --check`; carries plugin.json's description verbatim |
| `.claude-plugin/marketplace.json` | KEEP | Verified: entry carries `name`/`source`/`category`/`tags` only, no skill-level data |
| `scripts/skill-leaf-name-registry.txt` | KEEP | Verified: no other plugin owns the `show-options` leaf |

**Sanity Check** — note the stale-count grep is phrased as a *negative* assertion, because
`grep -c` returns exit 1 on zero matches and the desired outcome here is zero:

```bash
node scripts/generate-catalog.mjs --check && node scripts/generate-cheatsheet.mjs --check
bash scripts/check-changelog-parity.sh --check-bump origin/main
bash scripts/check-changelog-parity.sh --check-preserved origin/main
! grep -qE 'thirteen|eleven|twelve' plugins/session-flow/README.md \
    plugins/session-flow/.claude-plugin/plugin.json \
    plugins/session-flow/skills/setup/SKILL.md
CHECK_SKILL_SKILLS_ROOT="$PWD/plugins/session-flow/skills" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  bash plugins/skill-quality/scripts/check-skill.sh setup
```

The generators run directly rather than via `validate-plugins.sh`, which exits 2 when `claude` is
not on `PATH` (here it resolves only through `node_modules/.bin`) — an environmental failure, not a
real one. `check-skill.sh setup` is included because this phase edits a shipped skill's
frontmatter description, the listing-budget and trigger-preservation surface.

### Phase 7: Full gate sweep and close-out [TODO]

1. Gate sweep — every script takes its base ref explicitly (verified: bare invocation exits 1 with a
   usage error):

   ```bash
   bash scripts/check-changed-skills.sh origin/main
   bash scripts/check-skill-leaf-names.sh --check
   bash scripts/check-skill-portability.sh
   bash scripts/check-shell-portability.sh      # new SKILL.md is in its scan scope
   bash plugins/skill-quality/scripts/check-listing-budget.sh plugins/*/skills
   ```

2. **Write ADR `docs/adr/0014-<slug>.md`** (next free number; 0013 is the current highest). This is
   a **distilled new document, not a `git mv`** — the graduated content is the decision record
   extracted from a Brief that also carries phase mechanics which should not survive. It earns an
   ADR on all three admission tests: hard to reverse (the candidate-source and output contracts),
   surprising without context ("why not just read the skill listing?"), and a real trade-off (three
   rejected alternatives). The ADR must carry:
   - the candidate-source decision and why the in-context listing alone was rejected (the measured
     12.7× overflow and the 56 invisible skills);
   - the two-rule no-gatekeeping contract and why one rule was insufficient;
   - **the Brief's success criterion and its recheck trigger** — otherwise the only falsifiability
     hook this design has dies with the pruned slice;
   - **the `CATALOG-TAXONOMY` subject-wins adjudication** — one paragraph on why session-lifecycle
     placement beats catalog-subject placement (`claude-ops`, where `inventory` already claims "list
     all my skills"), since the plan cites that convention and must apply it;
   - **the `use-your-skills` revisit-trigger adjudication** the Brief's Out-of-scope demands in
     writing.

3. **File the promoted sub-topic** — the seven-way gather-block extraction (Phase 2) as a tracked
   work item, so the finding survives the prune.

4. **Contract-slice prune with pointer** — the gate FAILS on this branch today (verified; it names
   both `PLAN.md` and `design/design-resolution.md`). After graduation: name the pre-prune commit SHA
   in the PR body, then a final commit deletes `docs/topics/skill-recommendation-system/`.

**Sanity Check:** `bash scripts/check-contract-slice-prune.sh --check-diff origin/main` exits 0 with
no paths under `docs/topics/`, AND `bash scripts/check-changed-skills.sh origin/main` exits 0, AND
`test -f docs/adr/0014-*.md`.

## Blast radius

**LOW-to-MEDIUM — revised down after the plan review.** The original MEDIUM rested largely on Phase 2
modifying two shipped skills' gather blocks. That phase no longer modifies them at all: the seam
extraction was withdrawn (it would have touched seven skills, not two) and `show-options` routes to
`orient` instead. What remains: one new skill file, one evals file, a doctrine amendment in
`workflow` (Phase 5), and mechanical count edits plus regenerated docs. V1 is manual-only, so it adds
**no description cost** to the listing budget — a name-sized floor remains, since the listing always
carries every skill name — and cannot auto-fire. The one genuinely load-bearing edit is Phase 5's
doctrine change, which other skills' routing reads.

## Stress-test summary

Unusually, the adversarial pass ran *before* planning rather than after: `/planning:audit-answers`
dispatched three fresh-context validators over the decision set, plus a fresh-eyes verifier over the
exploration artifact. Five of eight decisions were challenged by all three independently; two were
factually wrong and were replaced in the Brief. A Step-3 plan-reviewer still runs against this plan
body — the prior pass validated the *decisions*, not the *phasing*.

## Execution shape

Predominantly sequential: Phase 1 gates Phase 3's contract, Phase 2's census verdict gates Phase 3's
routing, and Phase 6 consumes Phase 3's frontmatter.

| Phase | Surface | Basis |
|---|---|---|
| 1 Probe | main session | One invocation plus a judgement call on output shape |
| 2 Route-not-extract | main session | A census plus a recorded verdict; no file edits |
| 2b Seam phrasing | main session | Folds into Phase 3's authoring; no separate edit surface |
| 3 Skill body | main session | The judgement-heavy core; the whole contract lands here |
| 4 Evals | sub-agent worker | Mechanical against a fixed schema, file-disjoint from Phase 6 |
| 5 workflow amendment | main session | Doctrine edit — small, high-consequence |
| 6 Plugin surface | sub-agent worker | Mechanical count edits plus two generator runs |
| 7 Gate sweep | main session | Interprets gate output; owns the ADR and the prune-with-pointer |

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
- ~~Spotlight ledger location is a Phase 3 implementation call~~ — **closed by the plan review**: it
  changes behavior either way (memory tier resets per worktree; `${CLAUDE_PLUGIN_DATA}` is keyed to
  the plugin id alone, so one file per *machine* leaks across repositories). Decided in Phase 3:
  memory tier, last-write-wins, stated.
- The V2 HTML rendering tier, cut from V1 in Phase 3, has no owner doc in this repo — if it returns,
  it needs the ephemeral-tier and `windows-path-emit` conformance the review enumerated.

## Handoff to implementation

### User-approval gates

- **Phase 1 fallback** — if `/claude-ops:inventory` cannot supply a usable catalog, the ladder's top
  rung changes. Surface the finding and confirm the fallback before authoring Phase 3.
- **Phase 7 ADR** — confirm the ADR's placement and that the graduated content is right before the
  prune commit deletes the slice; a prune is not reversible from the branch alone.

### Decisions made (gate-passed)

Every choice below was made by `/planning:plan`, not stated in the Brief. Each cleared the
confidence gate — its basis is evidence captured this session, with no surviving reasonable
alternative. Override any of them.

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| `[EXEC-SHAPE]` `workflow-stage: anytime` (Q12, arbiter=plan) | Which cheat-sheet section the skill lands in | `anytime` is a valid `STAGES` slug and requires no `cadence`; the nearest functional sibling `workflow` is `anytime` while the nine `session`-tagged siblings are lifecycle actions |
| `[FALLBACK — confirm or override]` **Withdraw the gather-seam extraction; route to `orient` instead** | Phase 2 stops editing shipped skills entirely; blast radius drops | Verified: seven skills carry the block, not two. Extracting for two leaves five divergent copies plus a new seam — two sources of truth. Routing is `reuse-or-replace`-compliant and was validator B's own recommendation |
| `[FALLBACK — confirm or override]` **Promote the seven-way extraction to its own topic** | Real cleanup work leaves this PR's scope | The plan skill's sub-topic trigger fires (8 files, independent commit boundary, own verification need). Filed as a tracked item in Phase 7 so it survives the prune |
| `[EXEC-SHAPE]` **Cut the HTML rendering tier from V1** | Removes a whole rendering surface from Phase 3 | It appears in no Brief acceptance criterion, and it pulls in ephemeral-tier `mktemp` semantics, a Windows branch, and `windows-path-emit` — none budgeted |
| `[EXEC-SHAPE]` **Spotlight ledger → memory tier, last-write-wins** | Closes an open question rather than deferring it | `${CLAUDE_PLUGIN_DATA}` is keyed to the plugin id and nothing else (`plugin-data-report-keying`), so a fixed filename is one file per machine, shared across every repo |
| `[EXEC-SHAPE]` **Version `0.23.9` → `0.24.0`** | Fixes the CHANGELOG heading Phase 6 must write | A new skill is a feature addition; `check-changelog-parity.sh` requires an exact heading match |
| `[EXEC-SHAPE]` **ADR is a distilled new document, not a `git mv`** | Changes Phase 7's graduation mechanism | The Brief carries phase mechanics that should not survive into an ADR; only the decision record graduates |

### Execution shape (`[EXEC-SHAPE]` tagged)

Sequential ordering with the routing table above; Phases 4/6 parallelisable with the stated fences
and fallback.

### Mechanical work

Commit per phase, conventional-commit subjects. Each phase's `Sanity Check` runs before its commit.
Phase 6's generator runs must be committed together with the source edits that caused the drift.
