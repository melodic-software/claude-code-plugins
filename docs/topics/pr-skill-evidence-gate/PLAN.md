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

### Goal

**What**: retire the two OAuth-token review lanes and replace them with evidence that the mandatory
pre-PR skills ran on the operator's seat: a head-SHA-stamped ledger row, a fenced block under the PR
body's Verification section, an advisory validator inside `ci-status`, an advisory PreToolUse gate
on the ready-for-review flip, a label the babysit merge gate honors, and the two prose detectors
running as an advisory step of the lint job.

**Why**: of the last 40 merged PRs, 14 got no review-lane run at all and 1 was reviewed on the
commit that merged (baseline captured 2026-09-12, distilled in the Brief). The lanes trigger once
per PR and GitHub skips their runs while the PR conflicts with main, so the review surface is mostly
decorative while it bills the largest single line of the Actions spend and the review-count comment
on every PR.

### Standards grounding

No `docs/standards/README.md` index and no `.claude/standards.yaml` exist (resolution ladder rung
4: inferred from repository context). The plan was built against these surfaces:

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `REVIEW.md` | Code-review lane scope (the "security lane exists" clause adapts by workflow presence) | team |
| `docs/conventions/pre-pr-ordering/README.md` | The order; Who is bound; What is not configurable | team |
| `docs/conventions/hook-budget/README.md` | Rules 1 to 3 (measured share in the plugin README, budget never relaxes) | team (rule `.claude/rules/hook-budget.md`) |
| `.claude/rules/pr-body-contract.md` | body contract; `ci-status` advisory linkage pattern the validator copies | team |
| `docs/conventions/pr-body-convention/README.md` | the reserved second consumer of the body key | team |
| `docs/adr/0002`, `0003`, `0024` | check run canonical; measure before default-on; forgeability limit | team |
| `.claude/rules/skill-bodies-state-current-rules.md` | skill bodies state the rule, not the incident | team |
| `.claude/rules/vendor-docs-are-not-style.md` | house prose style for every instruction surface | team |
| `plugins/source-control/reference/config-resolution.md` | one H2 per key; per-key override; lane-1 portable default | team |

No personal overlay was found (`docs/standards/*.local.md`, `~/.claude/standards/` absent). Offer
recorded for the presentation: bootstrap the standards index from these surfaces via
`/planning:setup` so the next plan resolves at rung 3.

### Baseline

| Measure (last 40 merged PRs, read 2026-09-12) | Value |
|---|---|
| Review lane never succeeded on any commit | 14 |
| Review lane succeeded on the commit that merged | 1 |

Target after the promotion window (40 merged PRs or 30 days, whichever is later): every merged PR
whose diff touches a class in the mandatory map carries a fresh block for its merged head, read
from the PR body over REST by the `report` subcommand. Re-measure through that route and record the
comparison here.

### Deferred questions resolved (arbiter: this plan)

- **Q14, block schema**: a fenced block with info string `skill-evidence`, one `<skill> <sha>
  <utc-timestamp>` row per skill, latest row per skill wins, freshness by the ancestry rule.
  Recorded in `design/design-resolution.md`. Basis: the body already passes through the pr-contract
  composite, which strips HTML comments before counting section content, so a comment-borne block
  would not count as Verification content and would be invisible to humans; a table is fragile under
  markdownlint's table rules; a fenced block is visible, survives the composite untouched, and parses
  with one `awk` range.
- **Q15, first detector slice**: `ai-slop` `detect.sh` and `docs-hygiene` `audit-noise`
  `detect.sh` on changed markdown, as one advisory lint-job step that emits `::warning` annotations
  and exits 0. Basis: both accept a path list and never fail their caller; the ai-slop corpus was
  purged in #3988 so a zero finding baseline exists (probe this session: 0 findings on two tracked
  files); audit-noise has no zero baseline (40 findings on the same two files), so it can only be
  advisory. `skill-quality:check` already runs in the lint job as the `changed-skills` step, so it
  needs nothing. `instruction-placement` `detect.sh` emits facts and adjudicates nothing, so it waits
  until it grows a verdict.

### Approach

Integration-first: Phase 2 is the tracer bullet. It ships the one script every other reader uses,
and its sanity check proves ledger row to rendered block to validator verdict end to end on a git
fixture before any skill prose, hook, or workflow is touched.

Build technique: kept tracer bullet (Phase 2), then horizontal wiring. No throwaway spike: the
feasibility questions (forgeability, trigger behaviour, hook events) were settled by research.

#### Phase 1: Ledger rows carry the head SHA and the PR number [TODO]

Plugin: claude-ops (0.49.0 to 0.50.0).

1. **Pre-flight, identify consumers** (first work item): the readers of `skill-usage.jsonl` are
   `skills/audit-skill-visibility/scripts/audit_skill_visibility.py`,
   `skills/audit-skill-visibility/scripts/skill-pair-cooccurrence.sh` (filters on
   `event == "SkillUse"`), and `skills/observability/scripts/clean.sh`. Confirm each tolerates
   unknown fields and non-`SkillUse` events (the gate row of Phase 4 lands in the same file).
2. In `hooks/claude-ops-paths.sh` `claude_ops::record_skill_use`, replace the
   `git rev-parse --abbrev-ref HEAD` call with `git rev-parse --abbrev-ref HEAD HEAD` (two lines,
   same one spawn) and add `sha`; add `pr` from `git config --get branch.<branch>.pr-number` when
   set (one added spawn, stated in the README budget line for `skill-usage-audit`).
3. Extend `hooks/claude-ops-paths.test.sh` and `hooks/skill-usage-audit.test.sh`: a row inside a
   git fixture carries `sha` (40 hex matching `git rev-parse HEAD`); `pr` present only when the
   config key is set; outside a repository neither field breaks the row.
4. README row-field table, options table unchanged, CHANGELOG entry, `plugin.json` version bump.

| File | Action | What changes |
|---|---|---|
| `plugins/claude-ops/hooks/claude-ops-paths.sh` | Modify | `sha` and `pr` fields |
| `plugins/claude-ops/hooks/claude-ops-paths.test.sh` | Modify | field assertions |
| `plugins/claude-ops/hooks/skill-usage-audit.test.sh` | Modify | end-to-end row shape |
| `plugins/claude-ops/README.md` | Modify | field table, budget line |
| `plugins/claude-ops/CHANGELOG.md`, `.claude-plugin/plugin.json` | Modify | 0.50.0 |
| `plugins/claude-ops/skills/audit-skill-visibility/scripts/*` | KEEP | audited tolerant readers |

**Sanity Check:**

- `bash plugins/claude-ops/hooks/claude-ops-paths.test.sh` exit 0 and
  `bash plugins/claude-ops/hooks/skill-usage-audit.test.sh` exit 0.
- In a throwaway git fixture, a simulated Skill call appends a row where
  `jq -r .sha` matches `^[0-9a-f]{40}$` and equals `git rev-parse HEAD`.
- `scripts/check-changelog-parity.sh --check` exit 0.

#### Phase 2: The evidence script, config key, and this repo's mandatory map [TODO]

Plugin: source-control (0.55.74 to 0.56.0). This is the integration slice.

1. Create `plugins/source-control/scripts/skill-evidence.sh` with the four subcommands of
   `design/design-resolution.md` (`classes`, `check`, `render`, `report`), `--help`, exit 0 on
   audit paths and 2 on usage error, `LC_ALL=C`, no GNU-only constructs (shell-portability lint).
   Pattern matching through `git -c core.excludesFile=<tmp> check-ignore --no-index --stdin`, the
   same mechanism the security lane used for `.github/claude-security-paths`. `@renamed` reads
   `git diff --name-status -M --diff-filter=R`.
2. Config key `pr_skill_evidence` in `reference/config-resolution.md` (grammar from the design
   resolution; closed list; `none` and absent both mean inert), and `pr_skill_evidence` in the
   `/source-control:setup` key inventory if that skill enumerates keys (pre-flight: grep
   `pr_body_required_sections` under `skills/setup/`).
3. Ledger location for the source-control readers: new plugin option `skill_evidence_store`
   (default `.claude/observability/skill-usage.jsonl`, repo-relative; a leading `~/` resolves under
   `$HOME`), documented beside the claude-ops `skill_usage_scope` pairing. `[EXEC-SHAPE]`: plugin
   options are per plugin, so source-control cannot read claude-ops' option; a paired default is
   the cheapest honest resolution.
4. This repo's map in `.claude/source-control.md`:

   ```text
   ## pr_skill_evidence

   - code | **/*.sh **/*.bash **/*.py **/*.mjs **/*.js **/*.cjs **/*.ts **/*.ps1 | verification:confirm review:quality-gate,review:fanout simplify
   - markdown | **/*.md | ai-slop:audit docs-hygiene:audit-noise
   - renames | @renamed | docs-hygiene:rename-references
   - skills | plugins/*/skills/** plugins/*/agents/** | skill-quality:check
   - rules | .claude/rules/** | instruction-placement:check
   - security | @file:.github/claude-security-paths | review:security-review
   ```

   The header comment of `.github/claude-security-paths` is rewritten: it is now read by the
   local security review through this key, not by a CI lane.
5. `plugins/source-control/scripts/skill-evidence.test.sh` on real git fixtures: class
   detection per pattern kind; `check --ledger` reports `missing=` per class; freshness passes on
   exact head and on merge-only ancestry, fails on a non-merge commit after the row; `check --body`
   parses the fenced block and ignores HTML comments and prose; `render` emits sorted rows, latest
   per skill; `report` counts gate rows and later same-SHA skill rows; no config means every
   subcommand is inert and exit 0.

| File | Action | What changes |
|---|---|---|
| `plugins/source-control/scripts/skill-evidence.sh` | Create | the one reader and renderer |
| `plugins/source-control/scripts/skill-evidence.test.sh` | Create | black-box suite |
| `plugins/source-control/reference/config-resolution.md` | Modify | `pr_skill_evidence` key |
| `plugins/source-control/.claude-plugin/plugin.json` | Modify | `skill_evidence_store` option, 0.56.0 |
| `plugins/source-control/README.md`, `CHANGELOG.md` | Modify | option, script, version |
| `.claude/source-control.md` | Modify | the mandatory map above |
| `.github/claude-security-paths` | Modify | header comment only |

**Sanity Check:**

- `bash plugins/source-control/scripts/skill-evidence.test.sh` exit 0.
- End to end in a fixture: a ledger with rows for every class at HEAD makes `render` emit a block
  that `check --body` accepts (`missing=` empty); dropping one row makes `check --ledger` and
  `check --body` both name that skill.
- `plugins/source-control/scripts/skill-evidence.sh classes --base origin/main` on this branch lists
  `markdown` (this plan) and exits 0.
- `scripts/check-plugin-options-docs.sh` (or the lint job's `plugin-options-docs` step script)
  exit 0.

#### Phase 3: The pull-request skill routes prep by class, creates drafts, and renders the block [TODO]

Plugin: source-control (same version bump as Phase 2).

1. `reference/prep.md` §1.1: classify with `skill-evidence.sh classes`; §1.2 to §1.5 become the
   implementing skills of the pre-PR order per class, each presence-gated with the inline fallback
   (seam-phrasing): code runs `verification:confirm`, one fresh-context review
   (`review:quality-gate` under 50 changed lines, `review:fanout` above), then `simplify`; markdown
   runs `ai-slop:audit` and `docs-hygiene:audit-noise` on the changed files, and
   `docs-hygiene:rename-references` when `renames` is listed; skills run `skill-quality:check`;
   rules run `instruction-placement:check`; security runs `review:security-review` locally.
   Audits that persist findings feed one `review:fanout fix` pass. The order stays the convention's
   order; the doc cites `docs/conventions/pre-pr-ordering/README.md` and does not restate it.
2. `reference/create.md` §2.4.3: `gh pr create --draft`, then
   `git config branch.<branch>.pr-number <N>`; §2.4.1 renders the block from
   `skill-evidence.sh render` under `## Verification` when the ledger has rows; the REST path (cloud
   sessions) passes `"draft": true` and renders the same block.
3. New `reference/ready.md` and a `ready` action row in `SKILL.md`: merge the base branch (or
   `gh pr update-branch`), run `skill-evidence.sh check --ledger` for HEAD, run the missing skills
   through prep, re-render the block into the body (`gh pr edit --body-file`, the MCP update call,
   or the REST patch), then flip (`gh pr ready`, or the MCP update with `draft: false`).
4. `templates/checklist.md` gains the ready step; `reference/full-lifecycle.md` places `ready`
   between create and monitor; `reference/monitor.md` smart default treats a draft as "not yet
   ready" rather than "monitor".
5. `evals/evals.json` gains one case for the ready action and one for a docs-only branch (markdown
   class only).

| File | Action | What changes |
|---|---|---|
| `plugins/source-control/skills/pull-request/SKILL.md` | Modify | `ready` action, draft default |
| `plugins/source-control/skills/pull-request/reference/prep.md` | Modify | class routing |
| `plugins/source-control/skills/pull-request/reference/create.md` | Modify | `--draft`, pr-number, block |
| `plugins/source-control/skills/pull-request/reference/ready.md` | Create | the ready step |
| `plugins/source-control/skills/pull-request/reference/full-lifecycle.md` | Modify | sequence |
| `plugins/source-control/skills/pull-request/reference/monitor.md` | Modify | draft handling |
| `plugins/source-control/skills/pull-request/templates/checklist.md` | Modify | ready tick |
| `plugins/source-control/skills/pull-request/evals/evals.json` | Modify | two cases |

**Sanity Check:**

- `grep -n 'gh pr create --draft' plugins/source-control/skills/pull-request/reference/create.md`
  returns at least one line and `grep -c 'ready.md' plugins/source-control/skills/pull-request/SKILL.md`
  is at least 1.
- `bash plugins/skill-quality/scripts/check-skill.sh pull-request` (with
  `CHECK_SKILL_SKILLS_ROOT=plugins/source-control/skills`) exit 0.
- `scripts/check-changed-skills.sh origin/main` exit 0.

#### Phase 4: Advisory PreToolUse gate on the ready flip [TODO]

Review: security

Plugin: source-control (the PR-body gates already live here under the `Bash(*gh *)` matcher, so
no new guardrails budget line). `[EXEC-SHAPE]`: the Brief left guardrails or source-control open;
co-location with the sibling PR-body gates wins on budget and on one hooks.json to read.

1. Create `hooks/pr-ready-evidence-gate.sh`: kill switch first
   (`CLAUDE_PLUGIN_OPTION_PR_READY_EVIDENCE_GATE_ENABLED`, default true), then match on the
   command: `gh pr ready`, or `gh api` whose path ends in `/ready_for_review` or whose body carries
   `markPullRequestReadyForReview` (the cloud proxy and GraphQL routes). Resolve HEAD and the base
   (`refs/remotes/origin/HEAD`, fallback `main`), run `skill-evidence.sh check --ledger`, and on any
   `missing=` or `stale=` emit `additionalContext` naming the skills and the command to run; never
   block. Append one `SkillEvidenceGate` row (`missing`, `sha`) to the store so `report` can count.
   Ledger absent: one-time notice, then silent.
2. Create `hooks/pr-ready-evidence-mcp-gate.sh` for `mcp__github__update_pull_request` with
   `draft: false` in `tool_input`, same verdict path (the MCP payload carries owner and repo; out of
   scope when they do not match the origin remote, as the linkage MCP gate does).
3. Register both in `hooks/hooks.json`: the Bash hook inside the existing `Bash` matcher block
   with `"if": "Bash(*gh *)"`, the MCP hook under a matcher for `update_pull_request`.
4. Tests: `hooks/pr-ready-evidence-gate.test.sh` and `hooks/pr-ready-evidence-mcp-gate.test.sh`
   on a git fixture with a fake ledger: fires on missing, silent on complete, silent on a draft
   flip that is not a ready flip, silent with the kill switch off, silent and noticed once with no
   ledger; `hooks/pr-linkage-spawn-budget.test.sh` extended with the new hook's ceiling.
5. README hook table row and budget share; `plugin.json` option `pr_ready_evidence_gate_enabled`.

**Sanity Check:**

- Both new test suites exit 0; `bash plugins/source-control/hooks/pr-linkage-spawn-budget.test.sh`
  exit 0.
- `scripts/check-killswitch-hoist.sh` and `scripts/check-hook-wiring-liveness.sh` exit 0.
- A hook payload for `gh pr ready 1` against a fixture with an empty ledger prints JSON containing
  `additionalContext` and exits 0.

#### Phase 5: The `ci-status` validator and the lint job's prose-detector step [TODO]

Review: security

1. `ci-status` job in `.github/workflows/ci.yml` gains, before the pr-contract step: a checkout
   with `fetch-depth: 0` and `persist-credentials: false` `[EXEC-SHAPE]` (the ancestry rule needs
   history; switch to a REST commit walk if the checkout adds more than 30 seconds to the job), then
   a step `Check the PR skill-evidence block` (id `skill_evidence`) that runs only on
   `pull_request` events with `draft == false`, fetches the body over REST, runs
   `plugins/source-control/scripts/skill-evidence.sh check --body`, and on a gap upserts one
   comment (marker `<!-- pr-skill-evidence -->`) and adds the `needs-skill-evidence` label;
   on a clean verdict it removes the label and resolves the comment text. Exit 0 always. The step
   carries no `continue-on-error` and is not fed to the aggregate, so `check-lane-coverage.sh`
   needs no opt-out entry; a docs-only diff reports no class, so the step is inert there.
2. Create the label `needs-skill-evidence` in the repository (REST `labels` endpoint) and record it
   in `docs/conventions/loop-lane/README.md`'s label table beside `needs-issue-linkage`.
3. Lint job step `Report prose-detector findings on changed markdown` (id `prose_detectors`):
   after the docs-only resolver, list changed `.md` files against `origin/$BASE_REF`, write them to
   a paths file, run both detectors with `--paths-file`, turn each `Finding` line into a
   `::warning file=,line=::` annotation, exit 0. No `continue-on-error`, no feed row.
4. `scripts/check-docs-only-gate.sh --check` and `scripts/check-lane-coverage.sh --check` keep
   passing (both new steps are ungated shell steps that branch on the event inside the script).
5. `.github/workflows/ci.yml` `workflow_schema` file list drops the two retired callers (also done
   in Phase 6; whichever lands first carries it).

| File | Action | What changes |
|---|---|---|
| `.github/workflows/ci.yml` | Modify | two steps, one checkout |
| `scripts/pr-skill-evidence-ci.sh` | Create | REST body fetch, comment upsert, label move around the plugin script |
| `scripts/pr-skill-evidence-ci.test.sh` | Create | stubbed `gh`; comment and label transitions |
| `docs/conventions/loop-lane/README.md` | Modify | label row |

**Sanity Check:**

- `bash scripts/pr-skill-evidence-ci.test.sh` exit 0; `scripts/check-lane-coverage.sh --check`
  exit 0; `scripts/check-docs-only-gate.sh --check` exit 0; `actionlint` on `ci.yml` exit 0.
- On the PR that ships this change, the `ci-status` run log shows the step and the PR carries
  either a fresh block and no label, or the label and one comment.

#### Phase 6: Retire both lanes and sweep every citation [TODO]

Structural commit (Tidy First: deletions and citation updates only, no behaviour change elsewhere).

**File inventory:**

| File | Action | Rationale |
|---|---|---|
| [ ] `.github/workflows/claude-review.yml` | DELETE | lane retired |
| [ ] `.github/workflows/claude-security-review.yml` | DELETE | lane retired |
| [ ] `scripts/verify-claude-review-skill.sh` | DELETE | evidence guard of a deleted lane |
| [ ] `scripts/verify-claude-review-skill.sh.test.sh` | DELETE | its suite |
| [ ] `scripts/verify-security-review-evidence.sh` | DELETE | evidence guard of a deleted lane |
| [ ] `scripts/verify-security-review-evidence.sh.test.sh` | DELETE | its suite |
| [ ] `scripts/read-skip-actors.sh` | DELETE | no reader remains |
| [ ] `scripts/read-skip-actors.test.sh` | DELETE | its suite |
| [ ] `.github/claude-skip-actors` | DELETE | list of a deleted lane |
| [ ] `.github/workflows/ci.yml` | MODIFY | drop both callers from the `workflow_schema` list |
| [ ] `.github/standards/runner-policy/policy.json` | MODIFY | prune every pinned `claude-review.yml` and `claude-security-review.yml` entry the analyzer reports unused after the callers are gone; first item: run `node .github/standards/runner-policy/runner-policy.mjs --root .` and act on its output |
| [ ] `.github/standards/runner-policy/runner-policy.mjs` | KEEP | the visibility-scoped set stays valid for a future caller; audited |
| [ ] `REVIEW.md` | MODIFY | the code-review lane scope clause: no security workflow exists here, so the general review reports security findings too |
| [ ] `docs/SKILL-CHEAT-SHEET.md` | MODIFY | rows 115 and 118 no longer name the workflows |
| [ ] `plugins/review/README.md` | MODIFY | lines 49 to 52 |
| [ ] `plugins/review/skills/code-review/SKILL.md` | MODIFY | metadata summary |
| [ ] `plugins/review/skills/security-review/SKILL.md` | MODIFY | metadata summary; the body's "how to run this locally" stays |
| [ ] `plugins/review/skills/code-review/evals/evals.json` | KEEP | the fixture repo `acme/app` may carry any workflow |
| [ ] `plugins/review/CHANGELOG.md`, `.claude-plugin/plugin.json` | MODIFY | patch bump for the wording |
| [ ] `docs/architecture/landscape.json` | MODIFY | regenerate with `plugins/architecture/skills/map-landscape/scripts/render-landscape.sh`, never by hand |
| [ ] `docs/adr/0002-default-on-ai-review-advisory-with-earned-promotion.md` | MODIFY | one-line pointer at the top of Decision to the new ADR (Phase 8 writes the ADR; this phase adds the pointer once its number is fixed) |
| [ ] `scripts/affected-tests.sh` mapping rules | KEEP | audited: deleted suites need no rule; a changed `ci.yml` maps to `check-lane-coverage.test.sh` and `check-docs-only-gate.test.sh` |

**Sanity Check:**

- `grep -rn 'claude-review\.yml\|claude-security-review\.yml\|verify-claude-review-skill\|verify-security-review-evidence\|read-skip-actors\|claude-skip-actors' --exclude-dir=.git --exclude-dir=.work --exclude-dir=node_modules .`
  returns only `docs/adr/` lines and `docs/topics/pr-skill-evidence-gate/`.
- `node .github/standards/runner-policy/runner-policy.mjs --root .` exit 0.
- `bash plugins/architecture/skills/map-landscape/scripts/render-landscape.sh` reproduces
  `docs/architecture/landscape.json` byte for byte (`git diff --exit-code docs/architecture/landscape.json`
  after a second run).
- `/docs-hygiene:rename-references` audit over the deleted paths reports zero dangling references.

#### Phase 7: The babysit merge gate honors the evidence label [TODO]

`[EXEC-SHAPE]` (flagged close call): the gate reads the `needs-skill-evidence` label the
`ci-status` validator maintains, not the block itself. One judge (the validator) and zero new
parsing in Python; the label is a rendering of the validator's verdict, the same shape as
`needs-issue-linkage`. The flip line at presentation switches this to an in-process block parser
with a REST commit walk.

1. Pre-flight: `babysit_merge.py` `evaluate()` surfaces `labels` for agent reasoning with no
   hard-coded hold list, and `--block-labels` is confined to the autopilot tier
   (`reference/cycle-shape.md` line 56). Read both before changing.
2. Worker tier: `babysit-prs/SKILL.md` and `reference/safety.md` state that a PR carrying
   `needs-skill-evidence` is not merge-ready in the worker tier and routes to a worker whose brief
   is "run `/source-control:pull-request ready`". Autopilot tier: `babysit_merge_block_labels`
   default gains `needs-skill-evidence` (plugin.json option default, README, `bin` wrapper).
   Safe tier reports the label as a blocker and takes no action (already its posture).
3. `scripts/tests/test_skill_contract.py` gains the paragraph assertion; `test_guards.py` gains
   the autopilot default; `babysit_delta.py` treats a label change on this label as material
   feedback if its label rules enumerate labels (pre-flight decides).

**Sanity Check:**

- `python -m pytest plugins/source-control/skills/babysit-prs/scripts/tests -q` exit 0.
- `grep -c 'needs-skill-evidence' plugins/source-control/skills/babysit-prs/SKILL.md` is at least 1.

#### Phase 8: ADR 0033, ADR 0002 pointer, and the promotion record [TODO]

1. Create `docs/adr/0033-seat-mandatory-reviews-on-the-operator-session-and-retire-the-oauth-lanes.md`
   in the house ADR shape (`- Status: accepted`, `- Date:`, Context, Decision, Consequences,
   Revisit triggers). Decision records: the seat-based posture; the retirement of both lanes,
   their evidence guards, the skip-actors read, and the count and last-head comments; the evidence
   carrier (ledger row, block, validator, hook, label); the 40-PR measurement; the promotion
   window and the two counts; the accepted forgeability (ADR 0024); which sections of ADR 0002
   are superseded for this repository (the lane wiring, the skip-actor exception, the 2026-09-07
   trigger set) and which stand (advisory before blocking, earned promotion).
2. ADR 0002: one line under its Status line pointing at 0033 for the superseded sections.
3. `AGENTS.md` "Open a pull request as a draft" gains the sentence that the ready flip runs
   `/source-control:pull-request ready`, which renders the evidence block.
4. `docs/CLOUD-FLEET-SETUP.md`: if it names the review lanes or the ready flip (pre-flight grep),
   align the wording; otherwise KEEP.

**Sanity Check:**

- `ls docs/adr/0033-*.md` lists exactly one file; `grep -c '0033' docs/adr/0002-*.md` is 1.
- `/ai-slop:audit` on the new ADR and every markdown file this branch changed reports zero
  findings; `grep -c $'\xe2\x80\x94' docs/adr/0033-*.md` is 0.

#### Phase 9: Verification and the pull request [TODO]

1. `scripts/affected-tests.sh --run --explain` exit 0 (every new script maps to a suite: the new
   `*.test.sh` files sit beside their scripts, so the co-location rule maps them).
2. `scripts/check-changelog-parity.sh --check`, `--check-bump origin/main` exit 0.
3. Run this repository's own mandatory map on this branch: `skill-evidence.sh classes` lists
   `code`, `markdown`, `skills`, `rules` (if any rule changed), `security` (hooks and workflows);
   run each mandatory skill; confirm the ledger carries rows at HEAD.
4. Open the PR as a draft with the body contract (`Closes #<issue>` or `No related issue:`,
   Summary, Fix, Verification with the rendered block, Related), then `pull-request ready`.

**Sanity Check:**

- `scripts/affected-tests.sh --run` exit 0.
- The PR body's Verification section contains a ```` ```skill-evidence ```` block whose rows carry
  the PR head SHA; the `ci-status` run on that head adds no `needs-skill-evidence` label.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Keep the lanes and restore `synchronize` with the upstream cap | Still bills the OAuth seat per push, keeps the count comment, and reviews at most five heads per PR | The operator gets an API-key or App-billed seat that makes CI review free of the subscription window |
| Managed Claude Code Review app | Bills usage credits; its check is always neutral; no evidence the skill set ran | Usage credits become available and an App-authored check becomes load-bearing (autonomous merge on) |
| Mergify Merge Protections as an App-authored required check | Unforgeable, but a third-party App for a gate that is advisory today | Autonomous merge is switched on and same-name forgeability stops being acceptable |
| HTML-comment evidence block | Invisible to humans; stripped by the pr-contract composite before section counting | Never, while the block is meant to be read by people |
| Block parser in `babysit_merge.py` reading the body and walking commits over REST | Two parsers of one format in two languages; the validator already renders the verdict as a label | The label is observed removed by hand to force a merge, or the validator is promoted to blocking and the gate must judge independently |
| Validator step in the lint job instead of `ci-status` | The lint job does not run on contract-only events (a body edit), which is exactly when the block changes | `ci-status` stops being the only job on contract-only events |
| REST commit walk in CI instead of `fetch-depth: 0` | Second freshness implementation | The full-history checkout adds more than 30 s to the `ci-status` job |

### Test strategy

TDD, red then green, per phase. Test boundaries (each is the public interface a suite drives):

| Boundary | Exists | Driven by |
|---|---|---|
| `claude_ops::record_skill_use` row shape via the hook CLI | existing | `skill-usage-audit.test.sh` |
| `skill-evidence.sh` CLI (classes, check, render, report) | new | `skill-evidence.test.sh` on git fixtures |
| `pr-ready-evidence-gate.sh` and the MCP twin via hook stdin JSON | new | their `*.test.sh` |
| `scripts/pr-skill-evidence-ci.sh` via a stubbed `gh` on PATH | new | `pr-skill-evidence-ci.test.sh` |
| `babysit_merge.py` `evaluate()` and the skill contract paragraphs | existing | `scripts/tests/*.py` |
| `ci.yml` invariants | existing | `check-lane-coverage.test.sh`, `check-docs-only-gate.test.sh` |
| pull-request skill body | existing | `check-skill.sh`, `evals.json` |

Edge cases the suites name: a ledger row whose SHA is unreachable from HEAD (stale); a body with two
blocks (first wins, warning); a `gh pr ready` inside a `cd` chain (out of scope, silent); a PR
whose diff touches no class (validator inert, no label); a ledger with rows from another branch at
the same SHA (accepted, evidence is per commit); Windows Git Bash path for the store option.

Existing tests to update: `pr-linkage-spawn-budget.test.sh` (new hook ceiling),
`test_skill_contract.py`, `check-lane-coverage.test.sh` only if a fixture enumerates ci.yml steps.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The ledger is written by claude-ops and read by source-control; a consumer with one plugin and not the other sees a silent gate | Med | Low | Ledger absent: one-time notice naming the pairing, then silent; README states the pairing |
| Full-history checkout slows `ci-status` past its carry-forward budget | Low | Med | Measure on the first run; switch condition recorded (REST commit walk) |
| The label is removed by hand to force a merge | Low | Low (advisory phase) | Accepted per ADR 0024; the promotion review counts label removals without a later fresh block |
| Cloud sessions flip ready through a route the hook does not match | Med | Low | The MCP twin covers `update_pull_request`; `gh api` forms match on path suffix and mutation name; the validator catches every flip regardless |
| The prose-detector step floods annotations on a large docs PR | Med | Low | Cap at 50 annotations per detector with a summary line; advisory only |
| Removing the callers leaves unused runner-policy entries that the analyzer rejects | High | Low | Phase 6 runs the analyzer first and prunes on its report |
| Skill prose grows past `check-skill.sh` line caps | Med | Low | `ready.md` is a new reference file; SKILL.md gains one table row |

## Blast radius

HIGH. The change deletes two CI workflows and their guards, adds a step to the single required
check, adds two always-on hooks, changes a ledger contract three readers consume, and touches four
plugins (claude-ops, source-control, review, architecture's generated landscape) plus an ADR.
Stress-test triggers matched: infrastructure (hooks, CI), new enforcement mechanism, breaking
change (workflow removal), security-sensitive (workflow permissions, hook on a GitHub mutation).
Reversible by git revert; no data migration.

Stress-test needed: yes, `/planning:devils-advocate` dispatched to a fresh-context subagent.

## Stress-test summary

Pending: the plan-reviewer and devils-advocate reports are being verified against the files; this
section is rewritten with the confirmed findings and the fixes applied before presentation.

## Execution shape

### Phase file-overlap matrix

| Phase | Files | Overlaps with |
|---|---|---|
| 1 | `plugins/claude-ops/**` | none |
| 2 | `plugins/source-control/scripts/skill-evidence*`, `reference/config-resolution.md`, `plugin.json`, `README.md`, `CHANGELOG.md`, `.claude/source-control.md`, `.github/claude-security-paths` | 3, 4 (plugin.json, README, CHANGELOG) |
| 3 | `plugins/source-control/skills/pull-request/**` | 2 (version files) |
| 4 | `plugins/source-control/hooks/pr-ready-evidence*`, `hooks/hooks.json`, `hooks/pr-linkage-spawn-budget.test.sh` | 2 (version files) |
| 5 | `.github/workflows/ci.yml`, `scripts/pr-skill-evidence-ci*`, `docs/conventions/loop-lane/README.md` | 6 (ci.yml) |
| 6 | the deletions, `ci.yml` schema list, runner-policy `policy.json`, `REVIEW.md`, cheat sheet, review plugin, `landscape.json`, ADR 0002 pointer | 5 (ci.yml), 8 (ADR 0002) |
| 7 | `plugins/source-control/skills/babysit-prs/**` | none |
| 8 | `docs/adr/0033-*.md`, `docs/adr/0002-*.md`, `AGENTS.md`, `docs/CLOUD-FLEET-SETUP.md` | 6 (ADR 0002) |
| 9 | none (verification, PR) | all (reads) |

### Dependency graph

- 2 → 3, 4, 5, 7: every reader consumes the script and the config key Phase 2 defines.
- 1 → 9 only: Phase 2 develops against fixture rows that already carry `sha`; the live ledger
  needs Phase 1 before the end-to-end check on this branch.
- 6 → 5 on `ci.yml` (the schema-list edit lands in 6; 5 adds steps to the same file after).
- 6 → 8 on the ADR 0002 pointer line (8 fixes the ADR number; 6 writes the pointer after).
- Integration-first: Phase 2 opens Wave A.

### Recommended shape

Parallel, three waves:

> Wave A (three sub-agent workers, one message): Phase 1, Phase 2, Phase 6.
> Wave B (after Wave A returns): Phase 3, Phase 4, Phase 5, Phase 7 as sub-agent workers in one
> message; the version-file overlap between 3 and 4 is resolved by giving the `plugin.json`,
> `README.md`, and `CHANGELOG.md` edits to Phase 2's worker in Wave A, with 3 and 4 appending
> CHANGELOG lines only under their own headings.
> Wave C (main session): Phase 8, then Phase 9.
> Cost note: 3 + 4 parallel agents versus sequential; the independent work in Wave A is well
> above 100 LOC (the script and suite, the sweep), so the saving is material.

### Scope-fencing tables

| Agent | Phase | ALLOWED files | LOC |
|---|---|---|---|
| A1 | 1 | `plugins/claude-ops/hooks/claude-ops-paths.sh`, its test, `hooks/skill-usage-audit.test.sh`, `plugins/claude-ops/README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json` | ~80 |
| A2 | 2 | `plugins/source-control/scripts/skill-evidence.sh`, its test, `reference/config-resolution.md`, `.claude-plugin/plugin.json`, `README.md`, `CHANGELOG.md`, `.claude/source-control.md`, `.github/claude-security-paths` | ~450 |
| A3 | 6 | the Phase 6 inventory (deletions, `ci.yml` schema list only, `policy.json`, `REVIEW.md`, `docs/SKILL-CHEAT-SHEET.md`, `plugins/review/**`, `docs/architecture/landscape.json`) | ~-900 |
| B1 | 3 | `plugins/source-control/skills/pull-request/**`, `plugins/source-control/CHANGELOG.md` (append only) | ~250 |
| B2 | 4 | `plugins/source-control/hooks/pr-ready-evidence-gate.sh`, `pr-ready-evidence-mcp-gate.sh`, both tests, `hooks/hooks.json`, `hooks/pr-linkage-spawn-budget.test.sh`, `plugins/source-control/README.md` (hook table rows), `.claude-plugin/plugin.json` (one option), `CHANGELOG.md` (append only) | ~300 |
| B3 | 5 | `.github/workflows/ci.yml` (steps only), `scripts/pr-skill-evidence-ci.sh`, its test, `docs/conventions/loop-lane/README.md` | ~250 |
| B4 | 7 | `plugins/source-control/skills/babysit-prs/**` | ~60 |

**Each agent FORBIDDEN:** any file outside its ALLOWED list; `docs/topics/**` (main session
edits status only); other agents' territory; commit and push (the main session commits per phase).

**Each agent reports at end:** work items completed, per-criterion Sanity Check verdict, actual
LOC delta.

**Divergence escalation (copied into every worker brief verbatim):**

```text
DIVERGENCE ESCALATION (mandatory): if reality diverges from this brief, so
a precondition fails, a file/symbol named here is absent or different than
described, scope is blocked, or a design question arises mid-task, STOP.
Do not improvise, fix forward, or expand scope. Report to the orchestrator:
what you found, what the brief expected, and the exact state of your work
(files touched, edits applied / not applied). Await a revised brief.
```

### Sequential fallback

> If a scope-fence violation, a concurrent-edit race, or a cannot-complete report occurs, abort
> that agent and run its phase sequentially in the main session after the wave returns:
> 1 → 2 → 6 → 3 → 4 → 5 → 7 → 8 → 9. Other agents in the wave continue.

### Per-phase routing table

| Phase | Surface | Basis |
|---|---|---|
| 1 | sub-agent worker | mechanical, one plugin, black-box suite |
| 2 | sub-agent worker | one new script and suite, file-disjoint; the contract is fixed in the design resolution |
| 3 | sub-agent worker | prose edits inside one skill directory against a written routing table |
| 4 | sub-agent worker | two hooks modelled on the sibling PR-body gates |
| 5 | sub-agent worker | one CI script and two workflow steps; invariant scripts verify the result |
| 6 | sub-agent worker | inventory-driven sweep with grep-verified completion |
| 7 | sub-agent worker | small, self-contained, own test suite |
| 8 | main session | the ADR is judgment-heavy and cites the session's measurements |
| 9 | main session | verification, the PR, user interaction |

## Open questions

None at approval time beyond the flagged close calls in the decisions table.

## Handoff to implementation

### User-approval gates

- Phase 7's label-based merge input (flagged `[EXEC-SHAPE]` close call): confirm or flip to an
  in-process block parser before Wave B dispatches.
- Phase 5's full-history checkout in `ci-status` (`[EXEC-SHAPE]`): confirm; the switch condition
  is a measured 30 s.
- Any mid-flight change to the mandatory map in `.claude/source-control.md` (it is the contract
  the Brief's first acceptance criterion states).

### Execution shape ([EXEC-SHAPE] tagged)

- Three waves as above; sub-agent workers for Phases 1 to 7; main session for 8 and 9.
- Phase 4 lives in source-control, not guardrails.
- Phase 2's `skill_evidence_store` option pairs with claude-ops' scope option by documented
  default rather than shared configuration.
- One PR on this branch, one commit per phase, Phase 6 as the structural commit (Tidy First).
  Flip line: split into three PRs (claude-ops; retirement and ADR; source-control and CI).

### Mechanical work

- Commit boundaries: one commit per phase, conventional subject
  (`feat(source-control): …`, `chore(ci): retire the claude review lanes`, `docs(adr): …`).
- Verification checkpoints: each phase's Sanity Check before its commit;
  `scripts/affected-tests.sh --run` at Phase 9; `/ai-slop:audit` on every changed markdown file.
- Sequential fallback as stated above.
