# overengineering-detection-skill

## Brief

> Status: LOCKED (user confirmed 2026-08-17) — all 14 interview questions answered
> (`.work/overengineering-detection-skill/interview-checklist.md`, register gate clean).

### TLDR

A new marketplace plugin, `overengineering`, that audits an existing **enforcement surface** — Claude
Code hooks/guards/standing instructions/component clutter, git hooks, CI/CD checks, branch
protections, GitHub apps and automation, external integrations — under an **evidence-earned-keep**
verdict model, and on explicit request starts a human-in-the-loop **realignment** process that peels
back what no longer earns its cost. The inverse of `claude-config:audit-automation-gaps`: that skill
default-REJECTs new automation; this one treats every incumbent as a retirement candidate until
evidence says otherwise.

### Goal

Give the operator a repeatable, self-correcting course-correction process for accumulated
enforcement/automation clutter: detect it, reconstruct why it exists, re-derive the simplest adequate
solution, and (behind an explicit gate, with the user) realign to it.

### Constraints

- **Evidence-earned-keep.** Every artifact on the surface is scrutinized; KEEP must be earned by
  empirical evidence (history, firings, catches, friction/heat-map signals), never asserted.
  Verdicts: KEEP / RETIRE / DOWNGRADE / CONSOLIDATE / UNPROVEN (silence is neither exoneration nor
  proof of waste; UNPROVEN routes to the time-boxed ablation track).
- **Docs are claims, not evidence.** Existing markdown, comments, and rationale text are treated as
  claims to verify — they may be misleading or AI-generated; every verdict cites at least one
  empirical source, and doc-only support is explicitly marked unverified.
- **Rediscovery over critique.** For each artifact: reverse-engineer the original problem, then
  re-solve it fresh with a bias toward simpler/native/built-in mechanisms; only uncovered use cases
  justify bespoke enforcement. Account for tech drift (a native solution may exist now that didn't).
- **Refactoring cost is weighed.** Verdicts weigh removal/refactor pain and testing cost; "wrong or
  overengineered" still leans toward fixing it, but the cost enters the verdict.
- **Read-only by default.** `overengineering:audit` reports only (marketplace `audit` verb contract).
  Mutation happens solely through `overengineering:realign`, explicitly invoked, which drives the
  discovery/planning skills (interview, explore, research, plan) with the user per accepted finding —
  never applied on a whim.
- **Two single-purpose skills, no duplication.** Shared scrutiny method lives in one plugin-level
  context doc both SKILL.mds reference (intra-plugin sharing is sanctioned; only cross-plugin imports
  are barred); the skills compose at runtime through the persisted findings artifact
  (`docs/PLUGIN-ARTIFACT-PROTOCOL.md` seam).
- **Intent-reconstruction checkpoint.** When the audit's "what problem was this solving" read is
  low-confidence: attended runs ask the user (reusing `/planning:interview` mechanics,
  presence-gated); unattended runs record OPEN-INTENT and never guess. "I don't know" is an accepted
  answer that routes the item to the empirical/ablation track.
- **Protected categories (minimal, configurable).** Security-class artifacts (secret/credential
  guards, destructive-operation guards, security-critical CI) are fully audited with evidence
  reported, but their verdict is capped at FLAG-FOR-HUMAN — the skill never recommends RETIRE for
  them on its own. Consumers can extend, narrow, or empty the set via declared config.
- **Neighbor boundaries.** This plugin owns the cross-surface retirement verdict and never
  re-implements a sibling's layer: instruction-text findings route to
  `claude-config:audit-instructions`, contested Claude-layer ablation to `claude-config:unhobble`,
  prospective additions to `claude-config:audit-automation-gaps`, plugin claims-vs-reality to
  `plugin-quality:audit` — all presence-gated with documented prose fallbacks.
- **Consumer-agnostic** per `docs/PLUGIN-PHILOSOPHY.md`: no org/repo/machine/user assumptions;
  synced/managed-file routing (e.g. a standards-sync upstream) detected generically from the
  consumer's own declarations.
- **Lane-reusable core.** The scrutiny method (evidence → intent reconstruction → rediscovery →
  verdict) is written so a future product-code overengineering lane can reuse it; V1 ships only the
  enforcement-surface lane.
- **Report format.** Persisted, diffable Markdown findings report is the single source of truth and
  carries everything that drives the reasoning (evidence citations, intent reconstruction,
  rediscovery alternatives, cost weighing, verdict); concise inline terminal summary always; rendered
  HTML view is an optional presence-gated layer.

### Acceptance criteria

- New plugin `plugins/overengineering/` passing this marketplace's structural checks
  (`skill-quality:check`, plugin manifest schema, naming grammar — `realign` added to the verb table
  with its contract documented).
- `overengineering:audit`: bare invocation is read-only; walks the enforcement surface generically;
  emits the layered report (Markdown SSOT + inline summary; HTML presence-gated); every verdict cites
  ≥1 empirical source or is classed UNPROVEN; protected-class items capped at FLAG-FOR-HUMAN;
  low-confidence intent reconstructions surface as checkpoint questions (attended) or OPEN-INTENT
  rows (unattended).
- `overengineering:realign`: consumes the findings artifact; per accepted finding drives
  interview → explore/research → plan → implement via presence-gated skill composition with
  documented fallbacks; no mutation without explicit per-item user acceptance.
- Findings artifact is diffable across runs (stable ordering/ids) so a future scheduled lane can
  report deltas.
- Shared method doc exists once at plugin level; neither SKILL.md duplicates it.
- Skill design grounded in the pre-design pipeline: `/discovery:research-deep` consensus pass
  (authorities on overengineering/YAGNI/speculative generality, process-tooling sprawl) plus
  `/discovery:explore` inventory of a real enforcement surface with concrete peel-back precedents
  (e.g. the #2021 instruction-economy gate).
- Follow-up GitHub issues filed at Brief lock for the two deferred lanes (product-code
  overengineering; scheduled/delta runs), linked from Out-of-scope below.

### Captured assumptions

*(none — `me` mode drove all branches to decisions; see the register, Q1–Q14 all answered)*

### Out-of-scope (V1)

- Code-level overengineering in product code — separate deferred lane; core method written
  lane-reusable; tracked in
  [#2897](https://github.com/melodic-software/claude-code-plugins/issues/2897).
- Scheduled/daily autonomous runs — deferred; V1's diffable findings enable a later delta lane;
  tracked in [#2898](https://github.com/melodic-software/claude-code-plugins/issues/2898).
- Fleet-native multi-repo scanning — fleet coverage composes per-repo via existing fleet machinery.

### Deferred questions

*(none — the register holds no deferred or blocked rows)*

## Plan

> Status: APPROVED (stress-tested Steps 3+4; user standing authorization 2026-08-17 —
> "I approve. We can probably do a /handoff and clear, and then run the implementation or
> implementation dispatch" — plan stays inside the locked Brief, all 9 open-question defaults
> adopted verbatim)
> Scale: Medium-Large (new plugin, ~20 new files, 4 shared-surface modifications) — full template.
> Implementing sessions: the verified discovery corpus lives in
> `.work/overengineering-detection-skill/` (EXPLORE*.md, RESEARCH*.md) — memory tier, this
> container only. Shipped plugin files cite live literature directly, never `.work/` paths.

### Standards grounding

No standards index exists (`.claude/standards.yaml` absent, `docs/standards/` absent) — resolution
ladder rung 4 (inferred, offer-to-persist declined as out of scope for this task). Grounded surfaces:

| Surface | Sections cited | Provenance |
|---------|----------------|------------|
| Plugin philosophy | `docs/PLUGIN-PHILOSOPHY.md` — Naming/verb table (:55-67), Native-first (:121-142), Instruction economy + hook rubric (:551-624), consumer-agnostic + presence-gating (:30-40) | team (tracked) |
| Artifact protocol | `docs/PLUGIN-ARTIFACT-PROTOCOL.md` (protocol v2) — artifact kinds, missing-prerequisite behavior, byte-identical binding copies | team (tracked) |
| Detector findings | `docs/conventions/detector-findings/README.md` — the consent-gate boundary this plugin's artifact must stay OUTSIDE of | team (tracked) |
| Finding suppression | `docs/conventions/finding-suppression/` — stable content-hashed id shape reused for finding ids | team (tracked) |
| CI gate inventory | `.work/overengineering-detection-skill/EXPLORE-constraints.md` (verified vs `ci.yml`) — the full gate list Phase 6 must clear | team (verified sidecar) |

### Phase 1: Method core + findings-artifact contract [DONE]

The semantic heart; gates Phases 3-4. All files new.

| File | Action | What |
|------|--------|------|
| `docs/topics/overengineering-detection-skill/design/design-resolution.md` | Create | Done during planning (Tier B early-exit + type sketch) — commit with this plan |
| `plugins/overengineering/context/scrutiny-method.md` | Create | The lane-reusable scrutiny core (below) |
| `plugins/overengineering/context/findings-artifact.md` | Create | The audit→realign artifact contract (below) |

**`scrutiny-method.md` must encode** (each with its live-source citation; discovery-corpus pointers
for implementers are in this plan, not the shipped file):

1. Carry-cost framing — verdicts argued in cost-of-carry, never cost-to-build (Fowler, YAGNI four
   costs; RESEARCH-findings F1).
2. Evidence taxonomy, tiered: runtime/telemetry firings → git/issue/CI history → incident records →
   operator attestation → docs-as-claims (explicitly marked unverified). Silence = UNPROVEN, never
   KEEP (Brief; RESEARCH F2 Kohavi base rate).
3. **Three independent liveness questions** — source posture, wiring, runtime enforcement — with the
   generalized false-green failure modes (a checked-in artifact whose header claims wiring it lost;
   a wired guard whose runtime timeout fails open; EXPLORE current-state §3/§9 as the discovered
   specimens, described generically).
4. Intent reconstruction — original-problem reverse-engineering; low-confidence → checkpoint
   question (attended) or OPEN-INTENT row (unattended); "I don't know" routes to ablation track.
5. Rediscovery — re-solve fresh, native/built-in-first (PLUGIN-PHILOSOPHY native-first gate);
   tech-drift check; invocation ≠ usage trap (hook components fire without invocation telemetry).
6. Verdict ladder — KEEP / RETIRE / DOWNGRADE / CONSOLIDATE / UNPROVEN + FLAG-FOR-HUMAN cap;
   refactor/removal/testing cost enters the verdict. **Cap semantics stated explicitly**: the cap
   applies to retirement-direction verdicts only (RETIRE/DOWNGRADE/CONSOLIDATE → FLAG-FOR-HUMAN);
   a protected item with keep-supporting evidence stays KEEP with a protected marker — the cap
   never hides KEEP evidence.
7. Protected classes — security-class artifacts fully audited, verdict capped FLAG-FOR-HUMAN,
   consumer-configurable set (Chesterton's fence / absence-of-incident trap; RESEARCH F8; Knight
   Capital risk-side F9). Plus the **intentionally-dormant** class exempt from inactivity-based
   retirement (kill switches, emergency guards — Piranha's own finding). Ships a **default pattern
   list** for the protected categories and an explicit tie-break: **when protection status is
   uncertain, treat as protected** — a misclassified guard must fail toward the cap, never away
   from it.
7b. UNPROVEN triage — evidence availability varies wildly by consumer (this repo's telemetry/ADR
   corpus is an outlier; the modal consumer has none). The report LEADS with an
   evidence-availability assessment naming which tiers exist in this repo; when UNPROVEN
   dominates, rank UNPROVEN items by carry cost (the F1 frame) and recommend a bounded ablation
   batch (Piranha's batched, owner-routed precedent, F7) — never an undifferentiated UNPROVEN
   wall with dozens of concurrent 30-day ablations.
8. Analogical-thresholds table — alert accuracy <50% (Ewaschuk only), ~10% false-positive rate
   (Ewaschuk only), exercised less than ~quarterly (SRE book only), five-condition staleness gates
   (LaunchDarkly), inactivity windows (Piranha) — EVERY row labeled "analogical transfer from
   alerting/feature-flag literature", consumer-configurable; the refuted categorical
   no-consumer-means-retire claim must NOT appear (RESEARCH-caveats).
9. YAGNI scope boundary — peeling enforcement ≠ abandoning quality-enabling practices (Fowler,
   explicit; RESEARCH F3).
10. Rollback ladder — config-disable-first → observe (default 30 days / one release cycle,
    configurable) → delete with recorded rationale (matches LaunchDarkly two-stage order and the
    #2021/#2058 precedent class, described generically).
11. Ownership — ownerless mechanisms escalate to the operator as owner of last resort; authorship
    evidence (blame, issue links) recorded during intent reconstruction (Piranha model).

**`findings-artifact.md` must specify** (contract per `design/design-resolution.md` type sketch):
frontmatter (`type: overengineering-findings`, `schema: 1`, `date`, `scope`, `branch`); stable
content-hashed finding ids (finding-suppression id discipline); stable ordering (layer → path →
id); a **stable spine / free prose split** — the machine-stable fields (id, layer, artifact path,
verdict, status) are line-formatted and diff-comparable across runs, while evidence/intent/
rediscovery/cost prose is recomputed freely (this split is also the deferred delta lane's
contract, #2898 — diffing full prose rows would report model noise); per-finding fields (artifact,
layer, verdict, evidence citations, intent, rediscovery, cost, status); status vocabulary includes
**DELEGATED-EXTERNAL** (accepted finding whose remediation lies outside this repo — org IaC,
managed-file upstream — carrying a pointer to the delegation artifact: upstream PR, admin issue);
status transitions owned by realign only; **durable judgment record** — an operator's accepted-keep
or REJECTED judgment optionally persists as a suppression entry in the tracked
`.claude/overengineering.md` per `docs/conventions/finding-suppression/` (content-hashed ids
already match), written by realign behind the same per-item gate, so judgments survive branch
switches, merges, and container reclaims — the memory-tier artifact alone is ephemeral by design;
ABLATION-\* state likewise records a durable pointer (suppression entry or issue link); home
resolved through the plugin's
`reference/topic-docs.md` binding into the concern-scoped memory tier (never committed), with a
**branch-keyed sub-path** (precedent: `.work/reviews/<branch-slug>/`) so concurrent
branches/worktrees never clobber each other; **re-run merge semantics** — a re-audit carries
forward the prior artifact's `status` fields by stable finding id (ACCEPTED / REJECTED /
ABLATION-\* survive; evidence and verdicts are recomputed fresh; findings whose artifact vanished
are dropped with a note), so operator judgments are never wiped and re-reported — the
noisy-repeat failure `docs/conventions/finding-suppression/` exists to prevent; the
explicit NOT-`review-findings` boundary with its rationale.

**Sanity Check:**

- `test -f plugins/overengineering/context/scrutiny-method.md && test -f plugins/overengineering/context/findings-artifact.md` — exit 0.
- `for t in KEEP RETIRE DOWNGRADE CONSOLIDATE UNPROVEN FLAG-FOR-HUMAN; do grep -q "$t" plugins/overengineering/context/scrutiny-method.md || echo "MISSING $t"; done` — no output (each verdict token present).
- `grep -Eq "carries forward|carry.forward" plugins/overengineering/context/findings-artifact.md && grep -q "branch" plugins/overengineering/context/findings-artifact.md` — exit 0 (re-run merge semantics + branch-keyed home specified).
- `grep -ci "analogical" plugins/overengineering/context/scrutiny-method.md` ≥ 1 AND every threshold row in the thresholds table carries the label (Read assertion on the table).
- `grep -rn "\.work/" plugins/overengineering/` returns empty (no memory-tier citations in shipped files).
- `grep -in "intentionally.dormant" plugins/overengineering/context/scrutiny-method.md` non-empty.

### Phase 2: Plugin scaffold + registrations [DONE]

Consumer configuration goes through the **config-cascade convention**
(`docs/conventions/config-cascade/`), NOT `userConfig`: the Brief's "consumers can extend, narrow,
or empty the set" means the consuming repo (team-tracked), and the artifact protocol is explicit
that `userConfig` "is not a coordination surface for repository artifacts" — a policy-class
protected-set emptied silently in one operator's personal config would defeat the FLAG-FOR-HUMAN
cap's purpose. A tracked `.claude/overengineering.md` concern file carries: protected-categories
set (extend/narrow/empty), threshold overrides, observation-window, and optional suppression
entries (Phase 1's durable judgment record). **Merge form declared next to the keys** (a hard
cascade rule): the protected-set and suppression keys are **policy-floor class** (ratified #649 —
the team-tracked layer wins direct conflicts; personal `.local.md` layers may extend/tighten
only, never empty or weaken; provenance reported when a personal layer contributes), because a
gitignored overlay silently emptying the protected set would recreate the exact hole that
disqualified `userConfig`; threshold/window keys use the ordinary refinement form. "Empty the
set" (Brief-locked) stays possible — via the team-tracked layer, the reviewable place for it.
Key ownership lives in the plugin's bundled `reference/consumer-config.md` (the cascade's
boundary rule: the plugin's own bundled reference, not just a README section); the README
summarizes and points. No `userConfig` block ships in V1, so `plugin-options-docs-gate` is
trivially green.

| File | Action | What |
|------|--------|------|
| `plugins/overengineering/.claude-plugin/plugin.json` | Create | name/description/version 0.1.0; no `userConfig` (config-cascade concern file instead, above) |
| `plugins/overengineering/CHANGELOG.md` | Create | 0.1.0 entry, newest-first |
| `plugins/overengineering/README.md` | Create | Plugin overview + consumer-config summary pointing at `reference/consumer-config.md` |
| `plugins/overengineering/reference/consumer-config.md` | Create | Owner doc for the `.claude/overengineering.md` keys: shape, merge forms (policy-floor vs refinement per key), suppression-entry format (finding-suppression contract) |
| `docs/conventions/config-cascade/README.md` | Modify | Implementers-table row for the new surface: layers, merge form, policy-floor declaration |
| `.claude-plugin/marketplace.json` | Modify | Catalog entry (`quality` or per `docs/CATALOG-TAXONOMY.md` fit) |
| `plugins/overengineering/reference/topic-docs.md` | Create | Overengineering's OWN binding delta doc — structure modeled on `plugins/planning/reference/topic-docs.md`, content its own: names what THIS plugin writes (the findings artifact) with its tier/home row. The 8-plugin cluster DIFFERS by design; only artifact-protocol.md is byte-identical |
| `plugins/overengineering/reference/artifact-protocol.md` | Create | Byte-identical to `docs/PLUGIN-ARTIFACT-PROTOCOL.md` |
| `scripts/validate-plugin-contracts.mjs` | Modify | Add `"overengineering"` to the hardcoded `lifecycleProtocolCopies` list (:125) so the dedicated byte-identity check covers the fifth copy |

Leaf-name registry: `realign` is single-owner — the registry lists COLLISIONS only, and `--check`
fails on a registered entry carried by fewer than 2 plugins, so `realign` is deliberately NOT
registered. The `audit` owner-set update rides with Phase 3 (the commit that creates the skill
directory), keeping every pushed commit `--check`-clean.

**Sanity Check:**

- `python3 -c "import json; json.load(open('plugins/overengineering/.claude-plugin/plugin.json')); json.load(open('.claude-plugin/marketplace.json'))"` — exit 0.
- `cmp plugins/overengineering/reference/artifact-protocol.md docs/PLUGIN-ARTIFACT-PROTOCOL.md` — exit 0 (topic-docs.md is a delta doc — no `cmp`; instead: `grep -q "overengineering-findings" plugins/overengineering/reference/topic-docs.md`).
- `bash scripts/check-cross-plugin-source-drift.sh --check` — exit 0.
- `node scripts/validate-plugin-contracts.mjs` — exit 0 with the fifth copy listed.
- `grep -rn "userConfig" plugins/overengineering/.claude-plugin/plugin.json` — empty (config rides the cascade concern file).

### Phase 3: `overengineering:audit` skill [DONE]

Eval-first: write `evals/evals.json` scenarios before/alongside the SKILL body (this marketplace's
test-first analog for prose skills).

| File | Action | What |
|------|--------|------|
| `plugins/overengineering/skills/audit/SKILL.md` | Create | Frontmatter (description with "Use when:" triggers, argument-hint, metadata.summary); body: invocation contract, surface walk order, verdict + report emission, neighbor routing. Invocation contract carries: a **scope/layer argument** (audit one layer or subset — the full ~100+-item walk of a mature repo exceeds one context; layer-scoped passes compose via the re-run merge semantics) and an **`unattended` argument** (selects OPEN-INTENT behavior; attended is the default — the harness gives a prose skill no reliable interactivity probe, so dispatched/scheduled callers own the flag) |
| `plugins/overengineering/skills/audit/context/surface-walk.md` | Create | Generic layer-by-layer walk: Claude hooks/settings/plugin components → repo + git hooks → CI workflows/gate scripts → branch protections (forge-API presence-gated, else OPEN-INTENT/unreadable rows) → forge apps/automations → standing instructions → declared external integrations. Per layer: discovery probes + evidence sources. **Incremental artifact writes** — the artifact is written per layer as the walk proceeds (a partial artifact is a checkpoint; re-run merge semantics make resume natural; a context-exhausted run dies with its completed layers persisted). **Shallow-clone probe** up front (`git rev-parse --is-shallow-repository`) — on a shallow clone the history tier is reported *unavailable* (distinct from silent), so UNPROVEN verdicts cite the missing tier. CI granularity: lane-level verdicts by default, scripts + suppression files cited as lane evidence; a lane that aggregates multiple independent checks (its script's member list is mechanical evidence) gets per-member sub-verdicts inside the lane row — a single verdict cannot express "retire member A, keep member B" where clutter concentrates |
| `plugins/overengineering/skills/audit/context/report-template.md` | Create | Layered output: findings artifact (SSOT, per Phase 1 contract) + inline terminal summary (always) + HTML view (presence-gated on the visualization plugin, documented fallback: skip) |
| `plugins/overengineering/skills/audit/evals/evals.json` | Create | Scenarios: (1) bare invocation is read-only and says so; (2) docs-are-claims — header/comment claiming wiring is verified against actual settings, not believed; (3) protected-class item gets evidence + FLAG-FOR-HUMAN cap, never RETIRE; (4) silent artifact → UNPROVEN, not KEEP; (5) threshold cited with its analogical label; (6) unattended low-confidence intent → OPEN-INTENT row, no guess; (7) three liveness questions asked independently (wired-but-dead-at-runtime case); (8) no-telemetry repo → report leads with evidence-availability assessment and a carry-cost-ranked bounded ablation batch, not an undifferentiated UNPROVEN wall; (9) ambiguous guard (e.g. a hook blocking `--no-verify`) → protected tie-break applies the cap |
| `scripts/skill-leaf-name-registry.txt` | Modify | Add `overengineering` to the existing `audit` owner set — in THIS phase's commit (the one creating the skill directory) so `--check` stays green on every pushed commit; `realign` is single-owner and deliberately unregistered |

The audit resolves consumer configuration (protected set, thresholds, observation window) from the
`.claude/overengineering.md` concern file per the config-cascade convention (Phase 2).

Body requirements: bare invocation NEVER mutates (verb contract); every verdict cites ≥1 empirical
source or is UNPROVEN; attended low-confidence intent → checkpoint questions (reuse
`/planning:interview` mechanics presence-gated, inline questions as fallback); neighbor routing
presence-gated with prose fallbacks (instruction text → `claude-config:audit-instructions`;
contested Claude-layer ablation → `claude-config:unhobble`; prospective additions →
`claude-config:audit-automation-gaps`; plugin claims-vs-reality → `plugin-quality:audit`);
incumbent-first: search for an existing owner before proposing remediation; consumer-agnostic
(no org/repo hardcodes; synced/managed-file custody detected from the consumer's own declarations).

**Sanity Check:**

- `python3 -c "import json; json.load(open('plugins/overengineering/skills/audit/evals/evals.json'))"` — exit 0; validates against `plugins/skill-quality/reference/evals.schema.json`.
- `grep -E -in "read-only|never mutates|reports only" plugins/overengineering/skills/audit/SKILL.md` non-empty (`grep -E`, portable alternation).
- Every cross-plugin slash reference in the skill sits in a sentence carrying presence-gating ("if installed" / "when present" / "presence-gated") — `grep -rEn ":audit-instructions|:unhobble|:audit-automation-gaps|plugin-quality:audit|planning:interview|visualization:" plugins/overengineering/skills/audit/` each hit line manually confirmed gated; zero unguarded references.
- `bash scripts/check-skill-leaf-names.sh --check` — exit 0 (audit owner set updated in the same commit as the skill directory).
- `/skill-quality:check` green on the skill.

### Phase 4: `overengineering:realign` skill [DONE]

| File | Action | What |
|------|--------|------|
| `plugins/overengineering/skills/realign/SKILL.md` | Create | Consumes the findings artifact; missing artifact → stop with visible message naming `overengineering:audit` (protocol v2 missing-prerequisite rule). Per accepted finding: interview → explore/research → plan → implement via presence-gated skill composition (`/planning:interview`, `/discovery:explore`, `/discovery:research`, `/planning:plan`, `/implementation:implement`), each with a documented inline fallback. No mutation without explicit per-item user acceptance. Rollback ladder from `scrutiny-method.md` governs execution order (config-disable-first → observe → delete). UNPROVEN items route to the time-boxed ablation track; protected items surface FLAG-FOR-HUMAN evidence and require the human's own call; realign updates finding `status` fields (the artifact's only writer). Out-of-repo surfaces (org IaC, managed-file upstream — detected via the audit's custody reads): the flow produces a **delegation artifact** (upstream PR, admin issue, or written instructions) and sets `DELEGATED-EXTERNAL` with the pointer, never edits in-repo. Accepted-keep/REJECTED judgments are offered persistence as tracked suppression entries in `.claude/overengineering.md` (per-item gate; Phase 1 contract) so they survive branches and containers |
| `plugins/overengineering/skills/realign/evals/evals.json` | Create | Scenarios: (1) no findings artifact → stop, names audit, no scan of its own; (2) per-item gate — user accepts item 2 of 3, only item 2 proceeds; (3) protected finding → presents evidence, asks, never auto-retires; (4) RETIRE execution proposes config-disable-first, not immediate deletion; (5) UNPROVEN → offers ablation track with observation window; (6) composition skill absent → visible manual fallback, not silent skip |

**Sanity Check:**

- `python3 -c "import json; json.load(open('plugins/overengineering/skills/realign/evals/evals.json'))"` — exit 0; schema-valid.
- `grep -E -in "per-item|per accepted finding|explicit.*acceptance" plugins/overengineering/skills/realign/SKILL.md` non-empty.
- `grep -in "stop" plugins/overengineering/skills/realign/SKILL.md` shows the missing-artifact stop naming the audit skill.
- `grep -l "scrutiny-method.md" plugins/overengineering/skills/*/SKILL.md | wc -l` = 2 AND neither SKILL.md restates the verdict-ladder definitions (Read assertion) — shared-method SSOT held.
- `/skill-quality:check` green on the skill.

### Phase 5: Marketplace docs integration [DONE]

| File | Action | What |
|------|--------|------|
| `docs/PLUGIN-PHILOSOPHY.md` | Modify | Add `realign` row to the verb table (:57-63): consumes a findings artifact produced by a sibling audit; drives human-gated realignment; mutation only behind explicit per-item user acceptance, never on bare invocation |
| `docs/CATALOG.md` | Regenerate | `node scripts/generate-catalog.mjs` (never hand-edit the block) |
| `docs/SKILL-CHEAT-SHEET.md` | Regenerate | `node scripts/generate-cheatsheet.mjs` |

**Sanity Check:**

- `grep -n "realign" docs/PLUGIN-PHILOSOPHY.md` — a row inside the verb table.
- `grep -n "overengineering" docs/CATALOG.md docs/SKILL-CHEAT-SHEET.md` — present in both generated blocks; generators exit 0.

### Phase 6: Verification + gate pass [TODO]

1. **Live audit run on this repo** (dispatch to a fresh-context subagent; this repo is the richest
   available fixture — ~120-item surface with known specimens):
   - Invocation mechanism: the plugin is not installed in the session — the subagent executes the
     skill by reading `plugins/overengineering/skills/audit/SKILL.md` by path and following it
     verbatim (its brief says so explicitly); where a local CLI is available, a `--plugin-dir`
     smoke run is the preferred upgrade.
   - Capture `git status --porcelain` before/after — identical (read-only proven).
   - Findings artifact emitted; the dead `.claude/hooks/pr-linkage-mcp-gate.sh` and the wired
     source-control copy get INDEPENDENT liveness reads; report rows carry evidence citations or
     UNPROVEN.
   - Layer-scoped passes are acceptable (the scope argument exists for exactly this); the full
     surface need not fit one subagent context.
   - Run the audited scope twice, with an explicit snapshot between: `cp` run 1's artifact to a
     scratch path BEFORE run 2 (run 2 overwrites in place per the re-run merge semantics). The
     diff asserts the **stable spine only** — extract and compare the line-formatted spine fields
     (id, layer, artifact path, verdict, status), NOT full prose: two independent prose passes
     will never be byte-identical, and live evidence sources (e.g. an appending telemetry log)
     move between runs by design.
   - **Carry-forward test**: between run 1 and run 2, hand-edit one finding's `status` to
     ACCEPTED; assert it survives run 2 (this exercises the merge semantics the spine diff alone
     cannot).
   - **Human spot-check**: the run-1 artifact is read against the Brief's acceptance-criteria
     list directly (evidence citations real? liveness questions independent? protected cap
     applied?) — the greps prove token presence, not behavior.
2. **Realign dry worked example**: feed the pr-linkage finding; walk to the per-item acceptance
   gate and STOP (no acceptance given) — `git status --porcelain` unchanged. The hook's actual
   disposition stays an audit outcome for the user, not a planning decision.
3. **Gate suite** (from EXPLORE-constraints): manifest presence/schema/duplicate-keys, changelog
   parity, `skill-quality-gate` incl. evals presence + orphaned-fixture, `portability-lint` +
   `shell-portability-lint`, `plugin-options-docs-gate`, comment-hygiene, leaf-names, source-drift.
   Run each locally where a script exists; fix findings.
4. Commit per phase (conventional commits); push `claude/overengineering-detection-skill-cf354r`.

**Sanity Check:**

- Step 1-2 probes above, each exit/diff-empty as stated.
- `bash scripts/check-skill-portability.sh` and `bash scripts/check-shell-portability.sh` — exit 0 for changed files.
- Issues #2897 and #2898 exist and reference the deferred lanes (forge API / GitHub MCP `issue_read`) — closes the Brief's last acceptance criterion with a probe instead of an assertion.
- All local gate scripts exit 0; branch pushed (`git log origin/claude/overengineering-detection-skill-cf354r --oneline -1` matches local HEAD).

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| One skill with `--realign` flag | Interview Q14 foreclosed it — verb contract clarity (audit = read-only) and single-purpose composition beat a mode flag |
| Findings as `type: review-findings` (fix-relay consumable) | The relay auto-applies by frontmatter type; realignment is consent-gated per item — routing it through the relay launders the human gate (detector-findings contract, explicitly) |
| Advisory scoring model instead of verdict ladder | Interview foreclosed; scores invite threshold-laundering the analogical-caveat forbids |
| HTML-first report | Interview foreclosed — Markdown SSOT, HTML presence-gated optional |
| Parallel authoring of the two SKILL.mds | Declined: the no-duplication acceptance criterion is a cross-file property between exactly those two files; parallel authors duplicate silently |

## Test strategy

No executable production code ships — the deliverables are prose skills plus JSON manifests. The
test pyramid for this repo's skill work: (1) **evals** per skill (eval-first: scenarios written
before/with the body; schema-valid; behavior-asserting per the exemplar shape); (2) **structural
gates** (the Phase 6 suite — deterministic CI checks standing in for unit tests); (3) **live
dry-run** (Phase 6's audit-on-this-repo + realign dry walk — the integration test, asserting the
Brief's acceptance criteria directly). `/tdd:principles` and `/testing:plan` classification apply
to code and are not in play here.

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Threshold analogies laundered into native facts in skill prose | Med | High (reproduces the failure the plugin exists to catch) | Single thresholds table with mandatory per-row labels (Phase 1); eval scenario 5 (Phase 3); Phase 1 sanity grep |
| SKILL.md line caps / skill-quality lint failures | Med | Low | Depth lives in context/ files; SKILL bodies stay routing-thin; gate run per phase, not only at the end |
| Portability lint flags repo-specific examples | Med | Low | Specimens described generically in shipped files; repo names only in PLAN/discovery corpus; `portability-ok:` escape only with in-file justification |
| Audit scope creep re-implements neighbor plugins | Low | Med | Routing table with presence gates is a Phase 3 body requirement + eval; Brief constraint |
| Findings artifact drifts from realign's expectations | Low | Med | One contract doc (Phase 1) both skills cite; neither restates it |
| `realign` verb semantics contested in review | Low | Low | Verb-table row documents the contract precisely (consumes findings; per-item gate); mirrors the sanctioned `audit`-override grammar |
| Contract-slice-prune gate on merge | Certain | Low | Close-out step: prune `docs/topics/overengineering-detection-skill/` before merge (PLAN.md pasted into PR body) |
| Discovery corpus lost if container reclaimed before implementation | Med | Med | This plan carries the load-bearing findings inline; operator may `git add -f` the corpus (open housekeeping decision, §Handoff) |
| Audit walk exhausts a session's context mid-run | Med | Med | Scope/layer argument + incremental per-layer artifact writes (a partial artifact is a checkpoint; resume via re-run merge) |
| Operator judgments lost with the ephemeral memory-tier artifact | Med | High | Tracked suppression entries in `.claude/overengineering.md` (policy-floor class) behind the per-item gate |

## Blast radius

MEDIUM. Additive new plugin (~20 new files) plus four shared-surface modifications (verb table,
marketplace catalog, leaf-name registry, regenerated docs); fully git-revertible; no existing
plugin's behavior changes. MEDIUM rather than LOW because the trigger "new conventions or
enforcement mechanisms" matches (a new marketplace verb + a new cross-skill artifact type
constrain future work), and the audit skill composes other skills. Formal stress-test: YES.

## Stress-test summary

Two fresh-context adversarial passes, both dispatched (never inline):

**Pass 1 — plan reviewer (Step 3):** 1 CRITICAL + 3 IMPORTANT + 4 SUGGESTION, all verified against
source and fixed — headline: the `reference/topic-docs.md` cluster DIFFERS by design (per-plugin
binding delta docs), so the plan's original byte-identical copy would have documented another
plugin's artifacts while leaving the findings home undefined; also leaf-name registry semantics,
re-run merge semantics, config-cascade-not-userConfig, `lifecycleProtocolCopies`, portable greps.

**Pass 2 — devils-advocate (Step 4):** 0 CRITICAL / 5 HIGH / 5 MEDIUM / 4 LOW; no finding attacked
a Brief-locked decision; all folded in. The five HIGHs and their resolutions: (1) the run-twice
byte-diff was unachievable against a correct implementation (prose recomputed fresh; live
telemetry moves — verified: the firings log grew 328→1,882 lines between sessions) → stable-spine
diff + explicit carry-forward test; (2) the ~120-item walk exceeds one subagent context → scope
argument + incremental per-layer artifact writes + layer-scoped verification; (3) a `.local.md`
overlay could silently empty the protected set under default cascade semantics → protected-set
keys declared policy-floor class (ratified #649); (4) operator judgments lived only in an
ephemeral branch-keyed memory file → tracked suppression entries per the finding-suppression
contract, behind the per-item gate; (5) evidence-desert consumers would get an untriaged UNPROVEN
wall → evidence-availability lead + carry-cost-ranked bounded ablation batches. MEDIUM/LOW fixes:
aggregated-lane sub-verdicts, `unattended` flag, DELEGATED-EXTERNAL disposition, protected
tie-break + default patterns, cascade Implementers registration, cap-vs-enum semantics,
shallow-clone probe, human spot-check in Phase 6, stable-spine as the delta lane's contract.
Elements that survived attack unchanged: the NOT-`review-findings` boundary, read-only proof
mechanics, declined parallelism, verb/artifact-protocol fit, the research-discipline transfer.
No research-iterate round needed — no contested external claims remained.

## Execution shape

Sequential, single-lane: 1 → 2 → 3 → 4 → 5 → 6. Phases 3 and 4 are file-disjoint and could run as
parallel scope-fenced workers, but parallelism is DECLINED: the shared-method-no-duplication
acceptance criterion is a cross-file property between exactly the two files parallel workers would
author blind to each other. The saving (~2 phases of markdown authoring) does not cover the
re-reconciliation risk. Phase 2 could run parallel to Phase 1 (disjoint files) — declined for the
same single-reviewer-thread economy; Phase 2 is small.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session (or single implementer dispatch) | Semantic heart; highest judgment density; everything downstream cites it |
| 2 | sub-agent worker OK | Mechanical scaffold against verifiable schemas/gates |
| 3 | main-session (or single implementer dispatch) | Judgment-heavy skill authoring; consumes Phase 1 |
| 4 | main-session (or single implementer dispatch) | Same; must stay voice-consistent with Phase 3 |
| 5 | sub-agent worker OK | One doc row + two generator runs |
| 6 | fresh-context subagent for the live audit run; gates main-session | The dry-run MUST be fresh-context (a session that just wrote the skill rubber-stamps it) |

Sequential fallback: not applicable (already sequential).

## Open questions

None unresolved. The nine carried open questions are resolved by adopting their recorded defaults
(re-confirmable at approval):

1. Branch protections → forge-API presence-gated, else OPEN-INTENT/unreadable rows (EXPLORE-OQ1).
2. CI granularity → lane-level verdicts, scripts/suppression files as lane evidence (EXPLORE-OQ2).
3. Firing telemetry → optional evidence source, detected generically; absence → UNPROVEN (EXPLORE-OQ3).
4. Machine-local evidence → operator-attested class, docs-are-claims discipline (EXPLORE-OQ4).
5. Dead pr-linkage hook → NOT resolved in planning; it is the audit's first worked test case (EXPLORE-OQ5).
6. Thresholds → analogical, labeled, consumer-configurable (RESEARCH-OQ1).
7. Never-fired controls → UNPROVEN → time-boxed ablation; protected/intentionally-dormant exempt (RESEARCH-OQ2).
8. Ownerless mechanisms → operator is owner of last resort (RESEARCH-OQ3).
9. Rollback → config-disable-first ladder, ~30-day/one-release observation window, configurable (RESEARCH-OQ4).

## Decisions made (gate-passed)

Every decision below is /planning:plan's discretion within briefed scope, surfaced for override at
approval; each traces to evidence read this session. Interviewed/briefed decisions do not appear.

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| Design gate satisfied by Tier B early-exit (`design/design-resolution.md`), no separate `/planning:design` run | Adds the design artifact; planning proceeded directly | The 14-decision interview locked every design thread (skill split Q14, ladder Q9, format Q12, protected classes Q13); the plugin is markdown-only with structure prescribed by marketplace conventions |
| Findings artifact typed `overengineering-findings`, never `review-findings` | Phase 1 contract + an Alternatives row | `docs/conventions/detector-findings/README.md`: the fix relay selects purely on frontmatter type; routing consent-gated realignment through it launders the per-item gate |
| Findings home: branch-keyed concern-scoped memory tier; tracked suppression entries carry operator judgments | Phase 1 contract; Phase 4 realign behavior; risk table | Topic-docs concern-home precedent (`.work/reviews/<branch-slug>/`); finding-suppression contract; devils-advocate #4 (ephemeral-home judgment loss) |
| Consumer config via config-cascade concern file `.claude/overengineering.md`; protected-set keys policy-floor class; no `userConfig` | Phase 2 scope + cascade registration; Brief's "consumer-configurable" lands team-tracked | Artifact protocol bars `userConfig` as a repo coordination surface; cascade README policy-floor class (ratified #649); reviewer #4 + devils-advocate #3 |
| All 9 carried open-question defaults adopted verbatim | §Open questions — no interview round needed | Defaults recorded in both open-questions files, produced under verification-PASSed discovery; prior session surfaced them to the user who pre-authorized proceeding |
| Sequential single-lane execution; parallel SKILL.md authoring declined; sub-topic promotion declined; eval-first authoring inside Phases 3-4 | §Execution shape; Phases 3-4 ordering | The no-duplication acceptance criterion is a cross-file property between exactly the files parallel workers would author blind; one plugin/one PR; evals are this repo's test-first analog for prose skills (skill-quality evals-presence gate) |
| Shipped files cite live literature; only PLAN cites the `.work/` corpus | Phase 1 authoring rule + sanity grep | Memory tier is machine-local and self-gitignored — a shipped `.work/` pointer dangles for every consumer (topic-docs pointer discipline) |
| Formal stress-test run (blast radius MEDIUM) | Steps 3 + 4 both dispatched; §Stress-test summary | Stress-test trigger table: "new conventions or enforcement mechanisms" + "new skill composing other skills" both match |

## Handoff to implementation

### User-approval gates

- This plan itself (Step 5 gate) — no code before approval.
- `[FALLBACK — confirm or override]` Housekeeping: whether to `git add -f` the uncommitted
  discovery corpus (`.work/overengineering-detection-skill/EXPLORE*.md`, `RESEARCH*.md`) onto the
  branch for cross-container durability. Default if unanswered: NOT committed; this plan carries
  the load-bearing findings inline, so implementation can proceed either way.
- Phase 6 realign dry-run stops at the acceptance gate by design; any actual disposition of the
  dead pr-linkage hook is a user decision made through the audit output, later.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Sequential single-lane ordering with the routing table above; Phase 6 audit dry-run
  dispatched fresh-context.
- [EXEC-SHAPE] Eval-first authoring inside Phases 3-4.
- [EXEC-SHAPE] Sub-topic promotion considered (Phases 3/4 each >300 lines of authored markdown)
  and DECLINED: one plugin, one PR, one shared contract — splitting forks the contract mid-flight.
- [EXEC-SHAPE] Findings artifact home: concern-scoped memory tier resolved through the plugin's
  `reference/topic-docs.md` binding (precedent: `.work/reviews/<branch-slug>/`), branch-keyed;
  re-run carries statuses forward by stable id; exact sub-path fixed in Phase 1's contract doc.
- [EXEC-SHAPE] Consumer config routed through the config-cascade concern file
  (`.claude/overengineering.md`), not `userConfig` — policy-class settings (the protected set)
  must be team-visible and tracked; `userConfig` is personal/enable-time and the artifact protocol
  bars it as a repo coordination surface.

### Mechanical work

- Conventional-commit per phase; plan-status tags advanced per phase ([TODO]→[DOING]→[DONE]) in
  the same commit as the phase's changes; push after each phase or at minimum after Phases 2, 4, 6.
- PR only when the user asks. Close-out via `/planning:plan close-out`: paste PLAN.md into the PR
  body, then prune `docs/topics/overengineering-detection-skill/` (contract-slice-prune gate
  red-lines it on main).
- If implementation diverges from this plan, chain back to `/planning:plan review` — no silent
  pivots.
