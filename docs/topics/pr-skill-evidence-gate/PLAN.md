# pr-skill-evidence-gate

## Brief

### TLDR

- Mandatory pre-ready skills run on the operator's seat, inside the pull-request skill's prep step, routed by changed-file class; no review lane in GitHub Actions and no usage-credit review app.
- Both ci-workflows Claude lanes retire, with their evidence-guard jobs, the skip-actors read, and the review-count and last-reviewed-head comments.
- Evidence is a head-SHA-stamped skill-usage ledger row plus a machine-readable block under the PR body's Verification section, validated inside `ci-status` as an advisory check.
- A default-on advisory PreToolUse gate checks the ledger at the ready-for-review flip; the deterministic prose and skill detectors move into the CI lint job.
- One new ADR records the posture and the measured finding, and partially supersedes ADR 0002 for this repository; advisory gates promote only on a measured window.

### Goal

Every pull request that is flipped to ready-for-review or merged carries visible, machine-checkable evidence that the mandatory review, verification, simplify, and hygiene skills ran against the commit being reviewed, produced by the session that did the work rather than by a subscription-token CI lane. The measured baseline this replaces: of the last 40 merged PRs, 14 received no successful Claude review lane run on any commit and only 1 was reviewed on the commit that merged, because the lanes trigger once per PR and GitHub skips pull_request runs while a PR conflicts with main.

### Constraints

- The pre-PR step order in `docs/conventions/pre-pr-ordering/README.md` is fixed; the mandatory set is expressed as the implementing skills of its steps, never as a second list.
- Draft-first stays the convention (AGENTS.md); no gate fires at PR creation.
- `ci-status` remains the sole required check; every new CI step lives inside it or the lint job and satisfies the lane-coverage script.
- No review surface depends on `CLAUDE_CODE_OAUTH_TOKEN` in GitHub Actions, and none bills usage credits; the operator's seat is the only LLM auth in the mandatory path.
- Advisory before blocking, per ADR 0003: every new gate ships advisory and promotes only on the measured window below.
- Hook changes respect `.claude/rules/hook-budget.md` and the kill-switch hoist; the ready-flip gate consults ground truth (the ledger and HEAD), so it is not a behavioral-class nudge and may ship default-on.
- Agent-writable surfaces never supply a merge admission input (autonomy admission policy); the body block is evidence for humans and advisory CI, not a merge input, until autonomous merge is enabled.
- `.github/claude-security-paths` is retained as the path list that triggers the local security review; the CI lane that read it goes away.
- The skill-usage ledger keeps its three scope options (repo, user, data-dir); the gate resolves the store through the same configuration rather than a fixed path.
- Skill and agent bodies state the current rule only (`.claude/rules/skill-bodies-state-current-rules.md`); the incident numbers live in the ADR.
- Cloud sessions cannot use GraphQL; every gate and validator uses REST or the cloud proxy routes.

### Acceptance criteria

- The pull-request skill's prep reference routes by changed-file class: code runs verification:confirm, one fresh-context review (quality-gate under 50 changed lines, fanout above), and /simplify; markdown runs ai-slop:audit and docs-hygiene:audit-noise on the changed files, plus rename-references audit when the diff contains a rename; skills or agents run skill-quality:check; rules run instruction-placement:check; hooks or workflows run review:security-review locally, keyed on `.github/claude-security-paths`.
- The pull-request skill's create step opens PRs as drafts, and its ready step merges the base branch before flipping to ready-for-review.
- Every skill-usage ledger row written on a Skill call carries the head SHA at invocation and the PR number when one exists for the branch.
- The pull-request skill renders a machine-readable block under the PR body's Verification section listing, for HEAD, each mandatory skill that ran with its SHA and timestamp.
- A step inside `ci-status` validates that block against the changed-file classes of the diff and reports advisory only: a comment and a label, never a red check, until promoted.
- A PreToolUse hook matching `gh pr ready`, the GitHub MCP pull-request update call, and the cloud ready-for-review route reads the ledger and injects an advisory notice when any mandatory skill has no row at HEAD; it never blocks until promoted.
- IF the ledger carries no row for HEAD for a mandatory skill, THEN the ready flip is flagged by the hook and the ci-status validator reports the gap.
- WHILE a pull request is a draft, no gate fires and no validator reports.
- The deterministic detectors behind ai-slop, audit-noise, skill-quality check, and instruction-placement check run inside the existing CI lint job on changed files, with the same opt-in and skip behavior the lint job already uses.
- `claude-review.yml`, `claude-security-review.yml`, `scripts/verify-claude-review-skill.sh`, `scripts/verify-security-review-evidence.sh`, their tests, and `scripts/read-skip-actors.sh` with `.github/claude-skip-actors` are removed, and no tracked file cites them afterward (rename-references audit is clean).
- No PR opened after the change receives the review-count or last-reviewed-head comment.
- Each advisory gate records two counts, fired and fired-and-operator-agreed, readable from one place; promotion or deletion is decided after 40 merged PRs or 30 days, whichever comes second.
- A new ADR records the seat-based review posture, the lane retirement, the evidence carrier, the 40-PR measurement, and the promotion window, and marks the affected sections of ADR 0002 superseded for this repository; ADR 0002 gains a one-line pointer to it.
- The babysit worker and autopilot tiers read the Verification block and hold a merge when it is missing or stale for HEAD; the safe tier reports only.
- `scripts/affected-tests.sh --run` passes for the change, and every new script maps to a suite.

### Captured assumptions

- Same-name check-run forgeability by a write-access collaborator is acceptable: revisit if autonomous merge is enabled, at which point the evidence must move to an App-authored check.
- The Codex connector stays as configured today: revisit if it is asked to carry a mandatory review.
- Removing the two callers is enough to stop the count and last-head comments, because both are posted by the upstream reusable: revisit if any comment survives on a PR opened after the change.
- The ledger is written by a hook, so a session can only forge evidence by editing a JSONL file, which the guardrails write-bypass hook already fences: revisit if a forged row is observed.
- The pull-request skill is the entry point agents actually use to open and flip PRs in this repo: revisit if a sampled PR shows a different creation path with no ledger rows.
- Unwanted-behaviour and state-driven coverage were examined and both cases are included above.

### Out-of-scope

- Mergify Merge Protections, an org ruleset workflow, or any App-authored required check.
- The managed Claude Code Review app on usage credits.
- Restoring the synchronize trigger or changing the skip-actors list upstream.
- Enabling autonomous merge or changing the babysit tier that is active.
- Any change to the Codex connector's configuration.
- The code-metrics audits as gates; they emit no verdict by design.

### Deferred questions

- Q14: exact schema of the machine-readable block under the Verification section, defer until planning; **arbiter: /planning:plan**
- Q15: which deterministic detectors enter the CI lint job in the first slice and which wait, defer until planning; **arbiter: /planning:plan**

## Plan
