# Deviations log: pr-skill-evidence-gate

Append-only. One entry per decision, typed plan-confirmed, discovery, deviation, or human-decision.
A deviation carries four fields: plan said, found, chose, revisit.

## 2026-09-19

- **deviation (Phase 6)**. Plan said: delete nine files (two workflows, six scripts and tests, the
  skip-actors list). Found: `scripts/lib/review-lane-guard.sh` was sourced only by the two deleted
  guard scripts and executes the deleted `read-skip-actors.sh` at source time; no other file names
  it (grep over the tree, excluding `.git`, `.work`, `node_modules`). Chose: delete it as a tenth
  file in the Phase 6 commit. Revisit: never; evidence is the Phase 6 commit's stat line.
- **plan-confirmed (Phase 6)**. `.github/claude-security-paths` stays: the Brief retains it as
  the path list the local security review reads through the `pr_skill_evidence` key (Phase 2
  rewrites its header). The Phase 6 worker flagged it as orphaned because it read only the
  inventory; the Brief constraint decides.
- **discovery (Phase 6)**. Regenerating `docs/architecture/landscape.json` with its producer
  (`landscape-record.sh`) swept in pre-existing drift unrelated to this change (three new `cites`
  edges from code-metrics, the `plugins/miro/server/` path move, count changes), because the
  committed record was stale against main. The record is generated, never hand-edited (ADR 0032),
  so the whole regeneration lands; `landscape.md` and `portfolio.md` were re-rendered from it with
  `render-landscape.sh` in the same commit. Outcome: two producer runs were byte-identical.
- **discovery (Phase 6)**. `.claude/unhobble/.../evidence/research-D2-conventions.md` cites the
  deleted workflows as observed state during a past experiment. It is a frozen evidence record and
  stays unchanged; the plan's citation sweep excludes `.claude/`.
- **discovery (Phase 6)**. The runner label `melodic-review-ubuntu-24.04-x64` is now used by no
  workflow here; it stays declared in `.github/actionlint.yaml` and the upstream-managed
  runner-policy files, and the analyzer passes. No action.
- **deviation (orchestration)**. Plan said: one commit per phase. Found: the Phase 1 commit swept
  in the Phase 6 worker's staged deletions because `git commit` took the whole shared index. Chose:
  split the commit before any PR existed (soft reset, recommit Phase 1 from its own paths, commit
  Phase 6 separately, leased force push on this session's own branch). Revisit: never; later
  phases stage nothing until the orchestrator commits.
