# overengineering-detection-skill

## Brief

> Status: DRAFT — interview in progress (round 2). Sections below reflect locked decisions only;
> placement/naming, neighbor boundaries, evidence bar, and checkpoint shape are still open
> (see `.work/overengineering-detection-skill/interview-checklist.md`).

### TLDR

A new marketplace capability that audits an existing **enforcement surface** — Claude Code
hooks/guards/standing instructions/component clutter, git hooks, CI/CD checks, branch protections,
GitHub apps and automation, external integrations — under an **evidence-earned-keep** verdict model,
and on explicit request starts a human-in-the-loop **realignment** process that peels back what no
longer earns its cost. The inverse of `claude-config:audit-automation-gaps`: that skill default-REJECTs
new automation; this one treats every incumbent as a retirement candidate until evidence says otherwise.

### Goal

Give the operator a repeatable, self-correcting course-correction process for accumulated
enforcement/automation clutter: detect it, reconstruct why it exists, re-derive the simplest adequate
solution, and (behind an explicit gate, with the user) realign to it.

### Constraints

- **Evidence-earned-keep.** Every artifact on the surface is scrutinized; KEEP must be earned by
  empirical evidence (history, firings, catches, friction/heat-map signals), never asserted.
- **Docs are claims, not evidence.** Existing markdown, comments, and rationale text are treated as
  claims to verify — they may be misleading or AI-generated; verdicts cite empirical sources.
- **Rediscovery over critique.** For each artifact: reverse-engineer the original problem, then
  re-solve it fresh with a bias toward simpler/native/built-in mechanisms; only uncovered use cases
  justify bespoke enforcement. Account for tech drift (a native solution may exist now that didn't).
- **Refactoring cost is weighed.** Verdicts weigh removal/refactor pain and testing cost; "wrong or
  overengineered" still leans toward fixing it, but the cost enters the verdict.
- **Read-only by default.** Bare invocation audits and reports (marketplace `audit` verb contract).
  Mutation only via a separate explicit action that starts the realignment process — which itself
  runs through the discovery/planning skills (interview, explore, research) with the user. Never
  applied on a whim.
- **Consumer-agnostic** per `docs/PLUGIN-PHILOSOPHY.md`: no org/repo/machine/user assumptions;
  synced/managed-file routing (e.g. a standards-sync upstream) detected generically from the
  consumer's own declarations, presence-gated cross-plugin composition with documented fallbacks.
- **Lane-reusable core.** The scrutiny method (evidence → intent reconstruction → rediscovery →
  verdict) is written so a future product-code overengineering lane can reuse it; V1 ships only the
  enforcement-surface lane.

### Acceptance criteria

*(to be completed as remaining rounds lock)*

### Captured assumptions

*(none yet — `me` mode drives assumptions to decisions)*

### Out-of-scope (V1)

- Code-level overengineering in product code (separate deferred lane; follow-up tracked per Q11).
- Scheduled/daily autonomous runs (deferred; V1 persists diffable findings so a later scheduled lane
  can report deltas).
- Fleet-native multi-repo scanning (fleet coverage composes per-repo via existing fleet machinery).

### Deferred questions

*(to be completed at lock; Q-ids tie to the interview register)*

## Plan

*(empty — `/planning:plan` fills this)*
