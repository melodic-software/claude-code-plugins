# overengineering-detection-skill

## Brief

> Status: LOCKED PENDING CONFIRMATION — all 14 interview questions answered
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
  lane-reusable; tracked by follow-up issue (filed at handoff).
- Scheduled/daily autonomous runs — deferred; V1's diffable findings enable a later delta lane;
  tracked by follow-up issue (filed at handoff).
- Fleet-native multi-repo scanning — fleet coverage composes per-repo via existing fleet machinery.

### Deferred questions

*(none — the register holds no deferred or blocked rows)*

## Plan

*(empty — `/planning:plan` fills this)*
