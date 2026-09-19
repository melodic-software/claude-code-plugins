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
- **deviation (Phase 2)**. Plan said: map bullets `- <class> | <patterns> | <skills>` written
  literally. Found: `**/*.sh **/*.py` is a strong-emphasis pair to markdownlint (MD037), which
  rewrote the map on save. Chose: the reader strips one pair of wrapping backticks per field and
  this repo's map writes the patterns field as a code span; recorded in the design resolution.
  Revisit: never; pinned by the Phase 2 suite.
- **discovery (Phase 2)**. Unquoted pattern fields were pathname-expanded by bash, so
  `**/*.sh` matched whatever sat two levels below the working directory. Fixed with `set -f` for
  the whole script and pinned by a regression case; mutant-verified by the worker (flipping it
  fails exactly that case).
- **discovery (Phase 2, for Phase 5)**. `report` counts fired and agreed from
  `<!-- pr-skill-evidence head=<sha> verdict=<v> -->` markers; an upserted comment that rewrites
  its marker loses the pair. Phase 5 appends one marker line per head inside the single
  upserted comment instead of replacing it.
- **deviation (Phases 3 and 5)**. Plan said: edit `.github/pull_request_template.md` (block
  guidance, label mention). Found: the file was deleted on main (#4177) so the repository inherits
  the org template. Chose: the guidance goes into `.claude/rules/pr-body-contract.md`, the
  agent-facing owner of the body contract, in Phase 5; the org template is a follow-up request
  against melodic-software/.github, named in ADR 0035. Revisit: when the org template gains the
  wording.
- **plan-confirmed (Phase 3)**. No cloud proxy ready route exists in docs/ or
  plugins/source-control; the cloud flip is the MCP `update_pull_request` call with `draft:false`,
  so Phase 4 drops the `gh api .../ready_for_review` matcher its brief made conditional.
- **discovery (Phase 5)**. The evidence script detects the `renames` class only in `--base`
  mode (the local hook, prep, and ready); in the validator's `--files` mode it never fires, so CI
  under-reports `docs-hygiene:rename-references` and never over-reports. Accepted for the
  advisory window; the follow-up is a `--renamed <list>` input on `classes` and `check`, fed from
  the pull request's `previous_filename` entries the validator already fetches. Outcome:
  unverified in CI until the first renamed-file pull request lands.
- **discovery (Phase 5)**. `report` already reads every marker in a comment, so appending one
  marker per evaluated head to the single upserted comment needed no parser change; that
  behaviour is not yet pinned by the Phase 2 suite (follow-up: one `report` case with two markers
  in one comment).
- **deviation (orchestration, second occurrence)**. The Phase 8 commit swept in two hook
  scripts the Phase 4 worker had staged for their exec bit. Chose: soft-reset the two commits
  before any PR existed and recommit with `git commit --only -- <paths>`, which ignores the rest
  of the index; every later commit uses that form. Evidence: the recommitted Phase 8 stat lists
  four files.
- **deviation (orchestration)**. Plan said: one commit per phase. Found: the Phase 1 commit swept
  in the Phase 6 worker's staged deletions because `git commit` took the whole shared index. Chose:
  split the commit before any PR existed (soft reset, recommit Phase 1 from its own paths, commit
  Phase 6 separately, leased force push on this session's own branch). Revisit: never; later
  phases stage nothing until the orchestrator commits.
