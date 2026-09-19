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
body's Verification section rendered by a new `ready` step, an advisory validator inside
`ci-status`, an advisory PreToolUse gate on the ready-for-review flip, a block read in the babysit
merge gate, and the ai-slop detector running as an advisory step of the lint job.

**Why**: of the last 40 merged PRs, 14 got no review-lane run at all and 1 was reviewed on the
commit that merged (baseline captured 2026-09-12, distilled in the Brief). The lanes trigger once
per PR and GitHub skips their runs while the PR conflicts with main, so the review surface is mostly
decorative while it bills the largest single line of the Actions spend and posts the review-count
comment on every PR.

### Standards grounding

No `docs/standards/README.md` index and no `.claude/standards.yaml` exist (resolution ladder rung
4: inferred from repository context). The plan was built against these surfaces:

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `REVIEW.md` | Code-review lane scope (the "security lane exists" clause adapts by workflow presence) | team |
| `docs/conventions/pre-pr-ordering/README.md` | The order; Who is bound; What is not configurable | team |
| `docs/conventions/hook-budget/README.md` | Rules 1 to 3 (measured share in the plugin README, budget never relaxes) | team (rule `.claude/rules/hook-budget.md`) |
| `docs/conventions/hook-precision/README.md` | Rules 2 and 5: match parsed argv, never a token co-occurrence | team |
| `.claude/rules/pr-body-contract.md` | body contract; the `ci-status` advisory linkage pattern the validator copies | team |
| `docs/conventions/pr-body-convention/README.md` | the reserved second consumer of the body key | team |
| `docs/conventions/loop-lane/README.md` | `do-not-merge` is the only cross-lane hold; no lane creates labels, the label set is IaC-owned | team |
| `docs/adr/0002`, `0003`, `0024` | check run canonical; measure before default-on; forgeability limit | team |
| `.claude/rules/skill-bodies-state-current-rules.md` | skill bodies state the rule, not the incident | team |
| `.claude/rules/vendor-docs-are-not-style.md` | house prose style for every instruction surface | team |
| `plugins/source-control/reference/config-resolution.md` | one H2 per key; per-key override; lane-1 portable default; drafting versus enforcement | team |

No personal overlay was found (`docs/standards/*.local.md`, `~/.claude/standards/` absent). Offer
recorded for the presentation: bootstrap the standards index from these surfaces via
`/planning:setup` so the next plan resolves at rung 3.

### Baseline

| Measure (last 40 merged PRs, read 2026-09-12) | Value |
|---|---|
| Review lane never succeeded on any commit | 14 |
| Review lane succeeded on the commit that merged | 1 |

Target after the promotion window (40 merged PRs or 30 days, whichever is later): every merged PR
whose diff touches a class in the mandatory map carried, at merge time, a block whose terminal row
equals the PR's `head.sha` (the squash commit on main never appears in a row, so the measurement
keys on the PR head, read over REST). `skill-evidence.sh report --repo` re-measures through that
route; record the comparison here.

### Deferred questions resolved (arbiter: this plan)

- **Q14, block schema**: a fenced block with info string `skill-evidence`, one `<skill> <sha>
  <utc-timestamp>` row per skill, latest row per skill wins; two-tier freshness (terminal skill at
  HEAD exactly, every other skill on HEAD's history). Recorded in `design/design-resolution.md`.
  Basis: the body already passes through the pr-contract composite, which strips HTML comments
  before counting section content, so a comment-borne block would not count as Verification content
  and would be invisible to humans; a table is fragile under markdownlint's table rules; a fenced
  block is visible, survives the composite untouched, and parses with one `awk` range. Rows are
  stamped at skill invocation, so a rule that demanded every row at HEAD would mark every mutating
  skill stale by construction; the terminal-seal rule is what the pre-PR order already says.
- **Q15, first detector slice**: `ai-slop` `detect.sh` on changed markdown, as one advisory
  lint-job step that emits `::warning` annotations and exits 0. Basis: it accepts a path list,
  never fails its caller, prints one `Finding:` line per finding, and the corpus was purged in
  #3988 so a zero baseline exists (probe this session: 0 findings on two tracked files).
  `docs-hygiene` `audit-noise` waits: it has no zero baseline (40 findings on the same two files)
  and prints four-line records, so it would only flood annotations (ADR 0003 rule 3).
  `skill-quality:check` already runs in the lint job as the `changed-skills` step, so it needs
  nothing. `instruction-placement` `detect.sh` emits facts and adjudicates nothing, so it waits
  until it grows a verdict.

### Approach

Integration-first: Phase 2 is the tracer bullet. It ships the one script every other reader uses,
and its sanity check proves ledger row to rendered block to validator verdict end to end on a git
fixture before any skill prose, hook, or workflow is touched.

The evidence-bearing run is the new `ready` step, on a committed, base-merged HEAD. Prep before
`create` stays the developer loop and may leave rows behind; create's own rebase before the first
push (create.md §2.2) may invalidate them, and that is fine, because no PR exists yet and no
evidence is owed. Once a PR exists, every base refresh is a merge, never a rebase.

Build technique: kept tracer bullet (Phase 2), then horizontal wiring. No throwaway spike: the
feasibility questions (forgeability, trigger behaviour, hook events) were settled by research.

#### Phase 1: Ledger rows carry the head SHA and the PR number [DONE]

Plugin: claude-ops (0.56.17 to 0.57.0).

1. **Pre-flight, identify consumers** (first work item): the readers of `skill-usage.jsonl` are
   `skills/audit-skill-visibility/scripts/audit_skill_visibility.py` (skips rows without `skill`
   and `ts`), `skills/audit-skill-visibility/scripts/skill-pair-cooccurrence.sh` (filters on
   `event == "SkillUse"`), and `skills/observability/scripts/clean.sh` (prunes by age). Confirm
   each tolerates the two new fields.
2. In `hooks/claude-ops-paths.sh` `claude_ops::record_skill_use`, replace the
   `git rev-parse --abbrev-ref HEAD` call with `git rev-parse HEAD --abbrev-ref HEAD` (SHA first,
   then the branch; the option applies to the arguments after it; one spawn as before) and add
   `sha`; add `pr` from `git config --get branch.<branch>.pr-number` when set (one added spawn,
   stated in the README budget line for `skill-usage-audit`).
3. Extend `hooks/claude-ops-paths.test.sh` and `hooks/skill-usage-audit.test.sh`: a row inside a
   git fixture carries `sha` (40 hex matching `git rev-parse HEAD`); `pr` present only when the
   config key is set; outside a repository neither field breaks the row.
4. README row-field table and budget line, CHANGELOG entry, `plugin.json` version bump.

| File | Action | What changes |
|---|---|---|
| `plugins/claude-ops/hooks/claude-ops-paths.sh` | Modify | `sha` and `pr` fields |
| `plugins/claude-ops/hooks/claude-ops-paths.test.sh` | Modify | field assertions |
| `plugins/claude-ops/hooks/skill-usage-audit.test.sh` | Modify | end-to-end row shape |
| `plugins/claude-ops/README.md` | Modify | field table, budget line |
| `plugins/claude-ops/CHANGELOG.md`, `.claude-plugin/plugin.json` | Modify | 0.57.0 |
| `plugins/claude-ops/skills/audit-skill-visibility/scripts/*`, `skills/observability/scripts/clean.sh` | KEEP | audited tolerant readers |

**Sanity Check:**

- `bash plugins/claude-ops/hooks/claude-ops-paths.test.sh` exit 0 and
  `bash plugins/claude-ops/hooks/skill-usage-audit.test.sh` exit 0.
- In a throwaway git fixture, a simulated Skill call appends a row where
  `jq -r .sha` matches `^[0-9a-f]{40}$` and equals `git rev-parse HEAD`.
- `scripts/check-changelog-parity.sh --check` exit 0.

#### Phase 2: The evidence script, config key, and this repo's mandatory map [DONE]

Plugin: source-control (0.55.89 to 0.56.0). This is the integration slice.

1. Create `plugins/source-control/scripts/skill-evidence.sh` with the four subcommands of
   `design/design-resolution.md` (`classes`, `check`, `render`, `report`), `--help`, exit 0 on
   audit paths and 2 on usage error, `LC_ALL=C`, CR-tolerant line reads, no GNU-only constructs
   (shell-portability lint). Pattern matching through
   `git -c core.excludesFile=<patterns file> check-ignore --no-index -v`, keeping only matches whose
   source is the patterns file (with `--no-index` the repository's own ignore rules still apply,
   verified this session). `@renamed` reads `git diff --name-status -M --diff-filter=R`.
   `check` takes `--base <ref>` (git ancestry) or `--compare <json>` (a REST compare result) so CI
   and the babysit gate never need history on disk; the terminal row is string-compared to
   `--head`.
2. Config key `pr_skill_evidence` in `reference/config-resolution.md` (grammar from the design
   resolution; closed list; `none` and absent both mean inert; the local-overlay note), and in the
   `/source-control:setup` key inventory if that skill enumerates keys (pre-flight: grep
   `pr_body_required_sections` under `skills/setup/`).
3. New plugin option `skill_evidence_store` (`repo` default, `user`, or a path; `data-dir`
   documented as unsupported), resolved against the checkout the skill runs in, which in
   `create --pushed --worktree` mode is the target worktree. `[EXEC-SHAPE]`: plugin options are per
   plugin, so source-control cannot read claude-ops' scope option; a paired default is the cheapest
   honest resolution, and the README states the pairing.
4. This repo's map in `.claude/source-control.md`:

   ```text
   ## pr_skill_evidence

   - code | **/*.sh **/*.bash **/*.py **/*.mjs **/*.js **/*.cjs **/*.ts **/*.ps1 | verification:confirm! review:quality-gate,review:fanout simplify
   - markdown | **/*.md | ai-slop:audit docs-hygiene:audit-noise
   - renames | @renamed | docs-hygiene:rename-references
   - skills | plugins/*/skills/** plugins/*/agents/** | skill-quality:check
   - rules | .claude/rules/** | instruction-placement:check
   - security | @file:.github/claude-security-paths | review:security-review
   ```

   Stated plainly: `.github/claude-security-paths` lists `scripts/**`, `.claude/**`, every
   `plugins/*/skills/**` and every `**/*.sh`, so the `security` class fires on nearly every
   non-docs PR, exactly as the retired lane did; the local review replaces the lane at the same
   breadth. The `markdown` class matches `docs/topics/**` too, so a docs-only PR is not inert: it
   owes the two prose audits. The file's header comment is rewritten: it is now read by the local
   security review through this key, not by a CI lane.
5. `plugins/source-control/scripts/skill-evidence.test.sh` on real git fixtures: class
   detection per pattern kind, including a tracked path the repository's own `.gitignore` would
   match (must not count); `check --ledger` reports `missing=` per class; the terminal row passes
   only at HEAD exactly; a non-terminal row passes at HEAD and at an ancestor and reports
   `commits-since`; a row on a rebased-away commit is stale; `check --body` parses the fenced block,
   ignores HTML comments and prose, and warns on a second block; `check --compare` on a saved REST
   payload gives the same verdicts; `render` emits sorted rows, latest per skill; `report` with a
   stubbed `gh` counts a flagged flip and a later cleared head; no config means every subcommand is
   inert and exit 0.

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
  that `check --body` accepts (`missing=` and `stale=` empty); dropping one row makes
  `check --ledger` and `check --body` both name that skill; a base merge after the rows keeps every
  non-terminal row fresh and reports the terminal row stale.
- `plugins/source-control/scripts/skill-evidence.sh classes --base origin/main` on this branch lists
  `markdown` and exits 0.
- `python3 scripts/sync-plugin-options-docs.py --check` exit 0.

#### Phase 3: The pull-request skill routes prep by class, creates drafts, and owns the ready step [TODO]

Plugin: source-control (same version bump as Phase 2).

1. `reference/prep.md` §1.1: classify with `skill-evidence.sh classes`; §1.2 to §1.5 become the
   implementing skills of the pre-PR order per class, each presence-gated with the inline fallback
   (seam-phrasing): code runs one fresh-context review (`review:quality-gate` under 50 changed
   lines, `review:fanout` above), then `simplify`, then `verification:confirm` last; markdown runs
   `ai-slop:audit` and `docs-hygiene:audit-noise` on the changed files, and
   `docs-hygiene:rename-references` when `renames` is listed; skills run `skill-quality:check`;
   rules run `instruction-placement:check`; security runs `review:security-review` over the draft
   PR's diff (`gh pr diff`), so that class runs in the ready step, where a PR exists. Audits that
   persist findings feed one `review:fanout fix` pass. The order stays the convention's order; the
   doc cites `docs/conventions/pre-pr-ordering/README.md` and does not restate it. Prep before
   create is the developer loop; the section says which rows it leaves and that create's rebase may
   invalidate them.
2. `reference/create.md` §2.4.3: `gh pr create --draft`, then
   `git config branch.<branch>.pr-number <N>`; §2.4.1 renders the block from
   `skill-evidence.sh render` under `## Verification` when the ledger has rows; the REST path (cloud
   sessions) passes `"draft": true` and renders the same block; §2.7 (`--pushed --worktree`) reads
   the store under the target worktree. §2.2 keeps its rebase: it runs before the first push.
3. New `reference/ready-for-review.md` (named for the flip; `readiness.md` is the merge checklist)
   and a `ready` action row in `SKILL.md`: refuse on a branch with no PR; merge the base branch
   (`gh pr update-branch` or `git merge origin/<base>`, never a rebase); run
   `skill-evidence.sh check --ledger` for HEAD; run the missing or stale skills in the convention's
   order, committing any edits a mutating skill makes, with `verification:confirm` last so the
   terminal row lands on the final HEAD; re-render the block into the body (`gh pr edit --body-file`,
   the MCP update call, or the REST patch); then flip: `gh pr ready` locally, the MCP
   `update_pull_request` call with `draft: false` in cloud sessions (the flip is a GraphQL mutation,
   which the REST patch cannot perform and the cloud proxy serves only through its pinned set;
   pre-flight confirms whether a proxy route exists and documents it if so).
4. `SKILL.md` Phase 0 smart default: an open draft routes to `ready`, not to monitor;
   `templates/checklist.md` gains the ready tick; `reference/full-lifecycle.md` places `ready`
   between create and monitor.
5. `evals/evals.json` gains one case for the ready action and one for a docs-only branch (markdown
   class only).

| File | Action | What changes |
|---|---|---|
| `plugins/source-control/skills/pull-request/SKILL.md` | Modify | `ready` action, draft default, Phase 0 |
| `plugins/source-control/skills/pull-request/reference/prep.md` | Modify | class routing |
| `plugins/source-control/skills/pull-request/reference/create.md` | Modify | `--draft`, pr-number, block, §2.7 store |
| `plugins/source-control/skills/pull-request/reference/ready-for-review.md` | Create | the ready step |
| `plugins/source-control/skills/pull-request/reference/full-lifecycle.md` | Modify | sequence |
| `plugins/source-control/skills/pull-request/templates/checklist.md` | Modify | ready tick |
| `plugins/source-control/skills/pull-request/evals/evals.json` | Modify | two cases |
| `.github/pull_request_template.md` | Modify | the Verification guidance names the block |

**Sanity Check:**

- `grep -n 'gh pr create --draft' plugins/source-control/skills/pull-request/reference/create.md`
  returns at least one line and `grep -c 'ready-for-review.md' plugins/source-control/skills/pull-request/SKILL.md`
  is at least 1.
- `grep -c 'rebase' plugins/source-control/skills/pull-request/reference/ready-for-review.md` is 0
  outside the sentence that forbids it (read assertion).
- `CHECK_SKILL_SKILLS_ROOT=plugins/source-control/skills bash plugins/skill-quality/scripts/check-skill.sh pull-request`
  exit 0; `scripts/check-changed-skills.sh origin/main` exit 0.

#### Phase 4: Advisory PreToolUse gate on the ready flip [TODO]

Review: security

Plugin: source-control (the PR-body gates already live here under the `Bash(*gh *)` matcher, so
no new guardrails budget line). `[EXEC-SHAPE]`: the Brief left guardrails or source-control open;
co-location with the sibling PR-body gates wins on budget and on one hooks.json to read.

Briefed as default-on (Q5). The stress test recommends cutting this phase: the `ready` step runs
the same check in-process, the validator catches every flip regardless, and ADR 0003 asks for a
measured firing rate before default-on. Kept as briefed; the flip line at presentation removes it.

1. Create `hooks/pr-ready-evidence-gate.sh`: kill switch first
   (`CLAUDE_PLUGIN_OPTION_PR_READY_EVIDENCE_GATE_ENABLED`, default true), then match on parsed
   argv (`hook::bash_parse_segments`, the linkage gate's pattern, per hook-precision rules 2 and
   5): `gh pr ready`, or `gh api graphql` whose `-f query=` operand names
   `markPullRequestReadyForReview`, or a `gh api` path whose last segment is `ready_for_review`
   (kept only if Phase 3's pre-flight finds such a proxy route; deleted otherwise). Out of scope
   when a `cd` precedes the segment or `--repo` targets another repository. Resolve HEAD and the
   base (`refs/remotes/origin/HEAD`, fallback `main`), run `skill-evidence.sh check --ledger`, and on
   any `missing=` or `stale=` emit `additionalContext` naming the skills and
   `/source-control:pull-request ready`; never block; record nothing (the validator's marker is
   the count of record). Ledger absent: one-time notice, then silent.
2. Create `hooks/pr-ready-evidence-mcp-gate.sh` for `mcp__github__update_pull_request` with
   `draft: false` in `tool_input`, same verdict path (out of scope when owner and repo do not match
   the origin remote, as the linkage MCP gate does).
3. Register both in `hooks/hooks.json`: the Bash hook inside the existing `Bash` matcher block
   with `"if": "Bash(*gh *)"`, the MCP hook under a matcher for `update_pull_request`.
4. Tests: `hooks/pr-ready-evidence-gate.test.sh` and `hooks/pr-ready-evidence-mcp-gate.test.sh`
   on a git fixture with a fake ledger: fires on missing, fires on a stale terminal row, silent on
   complete, silent on a draft conversion that is not a ready flip, silent with the kill switch
   off, silent and noticed once with no ledger, silent under a `cd` prefix;
   `hooks/pr-linkage-spawn-budget.test.sh` extended with the new hooks' ceilings.
5. README hook table rows and budget share; `plugin.json` option `pr_ready_evidence_gate_enabled`.

**Sanity Check:**

- Both new test suites exit 0; `bash plugins/source-control/hooks/pr-linkage-spawn-budget.test.sh`
  exit 0.
- `scripts/check-killswitch-hoist.sh`, `scripts/check-hook-exec-form.sh`,
  `scripts/check-hooks-description.sh`, and `scripts/check-hook-userconfig-argv.sh` exit 0.
- A hook payload for `gh pr ready 1` against a fixture with an empty ledger prints JSON containing
  `additionalContext` and exits 0.

#### Phase 5: The `ci-status` validator and the lint job's prose-detector step [TODO]

Review: security

1. `ci-status` job in `.github/workflows/ci.yml` gains, **after** the aggregate step (so it never
   eats the 60-second margin the 540-second carry-forward wait leaves): a sparse, depth-1 checkout
   of `scripts/pr-skill-evidence-ci.sh`, `scripts/lib/`, and
   `plugins/source-control/scripts/skill-evidence.sh` (`persist-credentials: false`), then a step
   `Report the PR skill-evidence block` (id `skill_evidence`, `if: always()`,
   `continue-on-error: true`, with a reasoned entry in `scripts/lane-coverage-step-opt-outs.txt`:
   this is a fall-through step by design, the exact shape that list exists for). The script exits 0
   on every path (`trap` plus a test with a failing stubbed `gh`), returns early on a push event, a
   draft, or a fork head (read-only token), fetches the body and the PR files over REST, evaluates
   `--head ${{ github.event.pull_request.head.sha }}` (never the checkout's `refs/pull/N/merge`
   commit) with `--compare` payloads from REST, and on a gap upserts one comment (marker
   `<!-- pr-skill-evidence head=<sha> verdict=<gap|clean> -->`) and adds the `needs-skill-evidence`
   label; on a clean verdict it removes the label and rewrites the comment to the clean form. Label
   calls are state-diffed (no API call when already in the target state), because `labeled` and
   `unlabeled` re-run `ci-status`. A missing label (not yet provisioned) is a notice, not an error.
2. The label is IaC-owned (loop-lane README: no lane creates labels): file the request in
   github-iac as a work item (`/work-items:track`) and record the label beside
   `needs-issue-linkage` in `.github/pull_request_template.md` and ADR 0035. `[FALLBACK, confirm
   or override]`: until github-iac provisions it, the validator comments only.
3. Lint job step `Report ai-slop findings on changed markdown` (id `ai_slop_report`): after the
   docs-only resolver, list changed `.md` files against `origin/$BASE_REF`, write them to a paths
   file, run `plugins/ai-slop/skills/audit/scripts/detect.sh --paths-file`, turn each `Finding:`
   line into a `::warning file=,line=::` annotation (capped at 50 with a summary line), exit 0. No
   `continue-on-error`, no feed row, returns early on a push event.
4. `scripts/check-docs-only-gate.sh --check` and `scripts/check-lane-coverage.sh --check` keep
   passing.
5. `.github/workflows/ci.yml` `workflow_schema` file list drops the two retired callers (also done
   in Phase 6; whichever lands first carries it).

| File | Action | What changes |
|---|---|---|
| `.github/workflows/ci.yml` | Modify | two steps, one sparse checkout |
| `scripts/pr-skill-evidence-ci.sh` | Create | REST body and files fetch, compare calls, comment upsert, label move |
| `scripts/pr-skill-evidence-ci.test.sh` | Create | stubbed `gh`; comment and label transitions; exit 0 on a failing `gh`; idempotent label calls |
| `scripts/lane-coverage-step-opt-outs.txt` | Modify | `ci-status/skill_evidence` entry with its reason |
| `.github/pull_request_template.md` | Modify | label mention (with Phase 3's block guidance) |

**Sanity Check:**

- `bash scripts/pr-skill-evidence-ci.test.sh` exit 0; `scripts/check-lane-coverage.sh --check`
  exit 0; `scripts/check-docs-only-gate.sh --check` exit 0; `actionlint` on `ci.yml` exit 0;
  `zizmor` on `ci.yml` reports nothing new.
- On the PR that ships this change, the `ci-status` run log shows the step after the aggregate,
  and the PR carries either a fresh block and no label, or one marker comment.

#### Phase 6: Retire both lanes and sweep every citation [DONE]

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
| [ ] `.github/standards/runner-policy/policy.json` | KEEP | upstream-managed for this repo (ADR 0002, 2026-08-03 addendum); first item: run `node .github/standards/runner-policy/runner-policy.mjs --root .` after the deletions; if it rejects the now-unused pinned entries, file the upstream sync as a work item and record it in the ADR rather than editing the file here |
| [ ] `.github/standards/runner-policy/runner-policy.mjs` | KEEP | the visibility-scoped set stays valid for a future caller; audited |
| [ ] `REVIEW.md` | MODIFY | the code-review lane scope clause: no security workflow exists here, so the general review reports security findings too |
| [ ] `docs/SKILL-CHEAT-SHEET.md` | MODIFY | rows 115 and 118 no longer name the workflows |
| [ ] `plugins/review/README.md` | MODIFY | lines 49 to 52 |
| [ ] `plugins/review/skills/code-review/SKILL.md` | MODIFY | metadata summary and the body clauses at lines 56 and 75 that key on the workflow's presence |
| [ ] `plugins/review/skills/security-review/SKILL.md` | MODIFY | metadata summary; the body's local-run path stays |
| [ ] `plugins/review/skills/code-review/evals/evals.json` | KEEP | the fixture repo `acme/app` may carry any workflow |
| [ ] `plugins/review/CHANGELOG.md`, `.claude-plugin/plugin.json` | MODIFY | patch bump for the wording |
| [ ] `docs/architecture/landscape.json` | MODIFY | regenerate with `plugins/architecture/skills/map-landscape/scripts/render-landscape.sh`, never by hand |
| [ ] `docs/adr/0002-default-on-ai-review-advisory-with-earned-promotion.md` | MODIFY | one-line pointer under Status to the new ADR (Phase 8 writes the ADR; this phase adds the pointer once its number is fixed) |
| [ ] `scripts/affected-tests.sh` mapping rules | KEEP | audited: deleted suites need no rule; a changed `ci.yml` maps to `check-lane-coverage.test.sh` and `check-docs-only-gate.test.sh` |

**Sanity Check:**

- `grep -rln 'claude-review\.yml\|claude-security-review\.yml\|verify-claude-review-skill\|verify-security-review-evidence\|read-skip-actors\|claude-skip-actors' --exclude-dir=.git --exclude-dir=.work --exclude-dir=node_modules .`
  lists only files under `docs/adr/`, `docs/topics/pr-skill-evidence-gate/`,
  `plugins/review/skills/code-review/evals/evals.json`, and
  `.github/standards/runner-policy/` (the two KEEP rows).
- `node .github/standards/runner-policy/runner-policy.mjs --root .` exit 0, or the work item
  number for the upstream sync recorded in this phase's notes.
- `bash plugins/architecture/skills/map-landscape/scripts/render-landscape.sh` reproduces
  `docs/architecture/landscape.json` byte for byte (`git diff --exit-code docs/architecture/landscape.json`
  after a second run).
- `/docs-hygiene:rename-references` audit over the deleted paths reports zero dangling references.

#### Phase 7: The babysit merge gate reads the block [TODO]

`[FALLBACK, confirm or override]` (flagged close call, both reviews raised it): the Brief's
constraint "advisory before blocking" and its acceptance criterion "hold a merge" pull against each
other, and this repo's tracked config already selects the `worker` tier with `c3-autonomous` merge
(effective-unpromoted today through the promotion-evidence seam). Recommended shape, below: the
deterministic gate reads the block and **routes**, it does not hold, during the promotion window.
The flip line at presentation turns the route into a hold.

1. Pre-flight: `babysit_merge.py` `evaluate()` surfaces `labels` for agent reasoning with no
   hold list, and `--block-labels` is confined to the autopilot tier
   (`plugins/source-control/skills/babysit-loop/reference/cycle-shape.md` line 56). Read both,
   and `reference/safety.md`'s merge-gate sections, before changing.
2. `babysit_merge.py` gains a `skillEvidence` criterion in `evaluate()` for every tier: parse the
   fenced block from the PR body (already fetched), compare the terminal row to `headRefOid`, and
   check non-terminal rows with one REST `compare` call each (paginated helpers already in
   `babysit_gh.py`). The result is a self-documenting record (`missing`, `stale`, `commits-since`)
   in the gate's JSON, and a `needs_worker` reason `skill_evidence_gap` in `babysit_delta.py`,
   so the worker tier dispatches a worker whose brief is `/source-control:pull-request ready`.
   No blocker is raised until promotion; the safe tier reports the record only.
3. Autopilot's own draft flip (`SKILL.md` lines 131 to 133) routes through
   `/source-control:pull-request ready` instead of a bare `gh pr ready`.
4. Tests: `scripts/tests/test_guards.py` covers a clean block, a missing block, a stale terminal
   row, and an unparsable block (reported, never fatal); `test_babysit_delta.py` covers the new
   reason; `test_skill_contract.py` asserts the routing paragraph.

**Sanity Check:**

- `python -m pytest plugins/source-control/skills/babysit-prs/scripts/tests -q` exit 0.
- `grep -c 'skill_evidence_gap' plugins/source-control/skills/babysit-prs/scripts/babysit_delta.py`
  is at least 1; `grep -c 'pull-request ready' plugins/source-control/skills/babysit-prs/SKILL.md`
  is at least 1.

#### Phase 8: ADR 0035, ADR 0002 pointer, and the promotion record [TODO]

1. Create `docs/adr/0035-seat-mandatory-reviews-on-the-operator-session-and-retire-the-oauth-lanes.md`
   in the house ADR shape (`- Status: accepted`, `- Date:`, Context, Decision, Consequences,
   Revisit triggers). Decision records: the seat-based posture; the retirement of both lanes,
   their evidence guards, the skip-actors read, and the count and last-head comments; the evidence
   carrier (ledger row, block, two-tier freshness, validator, hook, babysit route); the 40-PR
   measurement and the `head.sha` measurement key; the promotion window and the two counts read from
   the validator's markers; which sections of ADR 0002 are superseded for this repository (the lane
   wiring, the skip-actor exception, the 2026-09-07 trigger set) and which stand (advisory before
   blocking, earned promotion). Consequences state plainly: the evidence is self-reported and a
   plain Write can forge it (accepted per ADR 0024; the Brief's "fenced by the write-bypass hook"
   assumption does not hold and is corrected here); PRs opened outside the skill (the UI, a bare
   REST call, a bot) receive no review and only the advisory label; the security review now runs on
   the seat at the lane's former breadth.
2. ADR 0002: one line under its Status line pointing at 0035 for the superseded sections.
   Re-check `ls docs/adr/0035-*` at merge time (0033 and 0034 landed on main while this plan was drafted, so re-check the number at merge time; two numbers are already duplicated in that
   directory).
3. `AGENTS.md` "Open a pull request as a draft" gains the sentence that the ready flip runs
   `/source-control:pull-request ready`, which renders the evidence block.
4. `docs/CLOUD-FLEET-SETUP.md`: KEEP (grep this session: it names neither lane nor the flip).

**Sanity Check:**

- `ls docs/adr/0035-*.md` lists exactly one file; `grep -c '0035' docs/adr/0002-*.md` is 1.
- `/ai-slop:audit` on the new ADR and every markdown file this branch changed reports zero
  findings; `grep -c $'\xe2\x80\x94' docs/adr/0035-*.md` is 0.

#### Phase 9: Verification and the pull request [TODO]

1. `scripts/affected-tests.sh --run --explain` exit 0 (every new script maps to a suite: the new
   `*.test.sh` files sit beside their scripts, so the co-location rule maps them).
2. `scripts/check-changelog-parity.sh --check`, `--check-bump origin/main` exit 0.
3. Run this repository's own mandatory map on this branch through the new `ready` step:
   `skill-evidence.sh classes` lists `code`, `markdown`, `skills`, `security` (and `rules` if a
   rule changed); the step runs each mandatory skill and the ledger carries the terminal row at HEAD.
4. Open the PR as a draft with the body contract (`Closes #<issue>` or `No related issue:`,
   Summary, Fix, Verification with the rendered block, Related), then `pull-request ready`.
5. After merge: on the first PR opened afterwards, `gh api --paginate
   repos/{owner}/{repo}/issues/<n>/comments?per_page=100` filtered on `claude-review-count` and
   `claude-security-review-last-head` returns nothing (the captured assumption gets its check).

**Sanity Check:**

- `scripts/affected-tests.sh --run` exit 0.
- The PR body's Verification section contains a ```` ```skill-evidence ```` block whose terminal
  row carries the PR head SHA; the `ci-status` run on that head posts no gap comment.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Keep the lanes and restore `synchronize` with the upstream cap | Still bills the OAuth seat per push, keeps the count comment, and reviews at most five heads per PR | The operator gets an API-key or App-billed seat that makes CI review free of the subscription window |
| Managed Claude Code Review app | Bills usage credits; its check is always neutral; no evidence the skill set ran | Usage credits become available and an App-authored check becomes load-bearing (autonomous merge on) |
| Mergify Merge Protections as an App-authored required check | Unforgeable, but a third-party App for a gate that is advisory today | Autonomous merge is switched on and same-name forgeability stops being acceptable |
| HTML-comment evidence block | Invisible to humans; stripped by the pr-contract composite before section counting | Never, while the block is meant to be read by people |
| Every mandatory row at HEAD exactly | Rows are stamped at invocation, so every mutating skill would read stale by construction and the set would run twice per PR | A row can be stamped after the skill's edits land (a hook event at skill completion) |
| Merge-only ancestry as the freshness rule | Admits conflict-resolution merges with arbitrary content; needs history on disk in CI | Never; the two-tier rule dominates it |
| A `needs-skill-evidence` label as the babysit merge input | A second cross-lane hold the loop-lane convention forbids; unenforced in the worker gate; removable by the same agent | Never; the gate reads the block |
| Validator as its own informational job | Cleaner isolation, but the Brief constrains new CI steps to `ci-status` or the lint job | The step after the aggregate is measured to threaten the job timeout, or the Brief constraint is lifted |
| Validator step in the lint job | The lint job does not run on contract-only events (a body edit), which is exactly when the block changes | `ci-status` stops being the only job on contract-only events |
| Full-history checkout in CI for ancestry | Eats the carry-forward margin of the required job | Never; REST `compare` answers ancestry in one call |
| audit-noise in the first lint slice | No zero baseline (40 findings on two tracked files); four-line records | The audit-noise corpus reaches zero findings on main |

### Test strategy

TDD, red then green, per phase. Test boundaries (each is the public interface a suite drives):

| Boundary | Exists | Driven by |
|---|---|---|
| `claude_ops::record_skill_use` row shape via the hook CLI | existing | `skill-usage-audit.test.sh` |
| `skill-evidence.sh` CLI (classes, check, render, report) | new | `skill-evidence.test.sh` on git fixtures and saved REST payloads |
| `pr-ready-evidence-gate.sh` and the MCP twin via hook stdin JSON | new | their `*.test.sh` |
| `scripts/pr-skill-evidence-ci.sh` via a stubbed `gh` on PATH | new | `pr-skill-evidence-ci.test.sh` |
| `babysit_merge.py` `evaluate()` JSON record and the skill contract paragraphs | existing | `scripts/tests/*.py` |
| `ci.yml` invariants | existing | `check-lane-coverage.test.sh`, `check-docs-only-gate.test.sh` |
| pull-request skill body | existing | `check-skill.sh`, `evals.json` |

Edge cases the suites name: a row on a rebased-away commit (stale); a terminal row one commit
behind HEAD (stale) beside a non-terminal row at the same commit (fresh, `commits-since=1`); a body
with two blocks (first read, warning); a `gh pr ready` inside a `cd` chain (out of scope, silent); a
PR whose diff touches no class (validator inert, no comment); a tracked path the repository's own
`.gitignore` matches (not a class match); a failing stubbed `gh` (validator still exits 0); a
label already in its target state (no API call); Windows Git Bash path for the store option and
CRLF ledger rows.

Existing tests to update: `pr-linkage-spawn-budget.test.sh` (new hook ceilings),
`test_skill_contract.py`, `test_guards.py`, `test_babysit_delta.py`.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The ledger is written by claude-ops and read by source-control; a consumer with one plugin and not the other sees a silent gate | Med | Low | Ledger absent: one-time notice naming the pairing, then "no rows"; README states the pairing; `data-dir` scope documented unsupported |
| The validator step lengthens the required job | Low | Med | Sparse depth-1 checkout after the aggregate; measured on the first run; separate-job switch condition recorded |
| A wrapper failure reds the required check | Low | High | `continue-on-error: true` with a reasoned opt-out entry, `trap` exit 0, and a suite case with a failing `gh` |
| The block is edited by hand to force a clean verdict | Low | Low (advisory phase) | Accepted per ADR 0024 and stated in ADR 0035; the promotion review samples blocks against ledger rows |
| Cloud sessions flip ready through a route the hook does not match | Med | Low | The MCP twin covers `update_pull_request`; the validator catches every flip regardless |
| Every base refresh re-runs `verification:confirm` | High | Low | That is the honest cost of refreshing; non-terminal rows survive a merge; the ready step merges, never rebases |
| The security class fires on nearly every non-docs PR | High | Med | Same breadth as the retired lane; stated in the map's comment and the ADR; the operator can narrow the patterns file |
| Removing the callers leaves unused runner-policy entries the analyzer rejects | Med | Low | Phase 6 runs the analyzer first; the file is upstream-managed, so a rejection becomes a work item, not a local edit |
| Skill prose grows past `check-skill.sh` line caps | Med | Low | `ready-for-review.md` is a new reference file; SKILL.md gains one table row |

## Blast radius

HIGH. The change deletes two CI workflows and their guards, adds a step to the single required
check, adds two always-on hooks, changes a ledger contract three readers consume, and touches four
plugins (claude-ops, source-control, review, architecture's generated landscape) plus an ADR.
Stress-test triggers matched: infrastructure (hooks, CI), new enforcement mechanism, breaking
change (workflow removal), security-sensitive (workflow permissions, hook on a GitHub mutation).
Reversible by git revert; no data migration.

Stress-test needed: yes, `/planning:devils-advocate` dispatched to a fresh-context subagent.

## Stress-test summary

Two fresh-context reviews ran on the first draft (a plan reviewer per `context/plan-reviewer.md`
and `/planning:devils-advocate`). Findings verified against the files and applied:

- **Confirmed critical, fixed**: rows are stamped at skill invocation and prep precedes the commit
  (`prep.md` §1.2 to §1.5, `create.md` §2.3.2), so the draft's "merge-only ancestry" rule marked
  every row stale by construction; create §2.2 rebases before the first push and would have
  invalidated every row too. Replaced by the two-tier rule (terminal skill at HEAD, others on
  HEAD's history), the `ready` step as the evidence-bearing run, and merge-never-rebase once a PR
  exists.
- **Confirmed high, fixed**: a full-history checkout before the pr-contract step would have eaten
  the 60-second margin the 540-second carry-forward wait leaves (`ci.yml` `ci-status`); a step with
  no `continue-on-error` in the required job can go red on a fork's read-only token or any bash slip;
  `actions/checkout` on `pull_request` yields `refs/pull/N/merge`, not the head. Replaced by a
  sparse depth-1 checkout after the aggregate, `continue-on-error` with an opt-out entry, `trap`
  exit 0, `--head` from the event payload, and REST `compare` for ancestry.
- **Confirmed high, fixed**: the label as a babysit merge input contradicted the loop-lane
  single-hold rule and the admission policy, and the worker gate has no label veto. Replaced by a
  block read in the deterministic gate that routes to a worker during the window.
- **Confirmed high, fixed**: claude-ops' `user` and `data-dir` scopes and per-worktree stores
  diverge from a fixed reader path. The option now mirrors the scope words, `data-dir` is
  documented unsupported, and `--pushed --worktree` reads under the target worktree.
- **Confirmed medium, fixed**: two promotion counts had no single home (per-checkout ledgers,
  cloud containers); they now read from the validator's comment markers over REST through
  `report --repo`, and the hook records nothing. `git rev-parse --abbrev-ref HEAD HEAD` prints the
  branch twice (probe); corrected. `--no-index` still applies the repository's own ignore rules
  (probe); matches are filtered by source. audit-noise dropped from the first lint slice. The
  security class breadth, the squash-merge measurement key, the forgery wording, and the
  coverage loss for non-skill PRs are stated in the plan and routed to the ADR. Divergent paths
  corrected: `babysit-loop/reference/cycle-shape.md`, `scripts/sync-plugin-options-docs.py
  --check`, the plugin-hook gate scripts, the PR template as the label's documentation home, the
  smart default in `SKILL.md` Phase 0, `ready-for-review.md` beside `readiness.md`,
  `runner-policy/policy.json` as upstream-managed.
- **Raised, kept as briefed, flagged for the operator**: the default-on PreToolUse hook (ADR
  0003 asks for a measured firing rate; the `ready` step and the validator already cover the flip).
- **Not applied**: one review suggested excluding `docs/topics/**` from the markdown class; a
  docs-only PR owing the two prose audits is the intended behaviour, so the plan states it instead.

Confidence after the round: HIGH on every mechanism claim (each verified by a probe or a file
read this session); MEDIUM on cost (the security class breadth and the terminal re-run after each
base refresh are stated, not measured; the promotion window measures them).

## Execution shape

### Phase file-overlap matrix

| Phase | Files | Overlaps with |
|---|---|---|
| 1 | `plugins/claude-ops/**` | none |
| 2 | `plugins/source-control/scripts/skill-evidence*`, `reference/config-resolution.md`, `plugin.json`, `README.md`, `CHANGELOG.md`, `.claude/source-control.md`, `.github/claude-security-paths` | 3, 4 (version files) |
| 3 | `plugins/source-control/skills/pull-request/**`, `.github/pull_request_template.md` | 2 (version files), 5 (template) |
| 4 | `plugins/source-control/hooks/pr-ready-evidence*`, `hooks/hooks.json`, `hooks/pr-linkage-spawn-budget.test.sh` | 2 (version files) |
| 5 | `.github/workflows/ci.yml`, `scripts/pr-skill-evidence-ci*`, `scripts/lane-coverage-step-opt-outs.txt`, `.github/pull_request_template.md` | 6 (ci.yml), 3 (template) |
| 6 | the deletions, `ci.yml` schema list, `REVIEW.md`, cheat sheet, review plugin, `landscape.json`, ADR 0002 pointer | 5 (ci.yml), 8 (ADR 0002) |
| 7 | `plugins/source-control/skills/babysit-prs/**` | none |
| 8 | `docs/adr/0035-*.md`, `docs/adr/0002-*.md`, `AGENTS.md` | 6 (ADR 0002) |
| 9 | none (verification, PR) | all (reads) |

### Dependency graph

- 2 → 3, 4, 5, 7: every reader consumes the script and the config key Phase 2 defines.
- 1 → 9 only: Phase 2 develops against fixture rows that already carry `sha`; the live ledger
  needs Phase 1 before the end-to-end check on this branch.
- 6 → 5 on `ci.yml` (the schema-list edit lands in 6; 5 adds steps to the same file after).
- 3 → 5 on the PR template (3 writes the block guidance; 5 appends the label sentence).
- 6 → 8 on the ADR 0002 pointer line (8 fixes the ADR number; 6 writes the pointer after).
- Integration-first: Phase 2 opens Wave A.

### Recommended shape

Parallel, three waves:

> Wave A (three sub-agent workers, one message): Phase 1, Phase 2, Phase 6.
> Wave B (after Wave A returns): Phase 3, Phase 4, Phase 7 as sub-agent workers in one message;
> Phase 5 follows 3 in the same wave once 3 reports (template ordering). The version-file overlap
> between 3 and 4 is resolved by giving the `plugin.json`, `README.md`, and `CHANGELOG.md` edits to
> Phase 2's worker in Wave A, with 3 and 4 appending CHANGELOG lines only under their own headings.
> Wave C (main session): Phase 8, then Phase 9.
> Cost note: 3 + 4 parallel agents versus sequential; the independent work in Wave A is well
> above 100 LOC (the script and suite, the sweep), so the saving is material.

### Scope-fencing tables

| Agent | Phase | ALLOWED files | LOC |
|---|---|---|---|
| A1 | 1 | `plugins/claude-ops/hooks/claude-ops-paths.sh`, its test, `hooks/skill-usage-audit.test.sh`, `plugins/claude-ops/README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json` | ~80 |
| A2 | 2 | `plugins/source-control/scripts/skill-evidence.sh`, its test, `reference/config-resolution.md`, `.claude-plugin/plugin.json`, `README.md`, `CHANGELOG.md`, `.claude/source-control.md`, `.github/claude-security-paths` | ~500 |
| A3 | 6 | the Phase 6 inventory (deletions, `ci.yml` schema list only, `REVIEW.md`, `docs/SKILL-CHEAT-SHEET.md`, `plugins/review/**`, `docs/architecture/landscape.json`) | ~-900 |
| B1 | 3 | `plugins/source-control/skills/pull-request/**`, `.github/pull_request_template.md`, `plugins/source-control/CHANGELOG.md` (append only) | ~280 |
| B2 | 4 | `plugins/source-control/hooks/pr-ready-evidence-gate.sh`, `pr-ready-evidence-mcp-gate.sh`, both tests, `hooks/hooks.json`, `hooks/pr-linkage-spawn-budget.test.sh`, `plugins/source-control/README.md` (hook table rows), `.claude-plugin/plugin.json` (one option), `CHANGELOG.md` (append only) | ~300 |
| B3 | 5 | `.github/workflows/ci.yml` (steps only), `scripts/pr-skill-evidence-ci.sh`, its test, `scripts/lane-coverage-step-opt-outs.txt`, `.github/pull_request_template.md` (one sentence) | ~280 |
| B4 | 7 | `plugins/source-control/skills/babysit-prs/**` | ~150 |

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
| 7 | sub-agent worker | self-contained, own test suite |
| 8 | main session | the ADR is judgment-heavy and cites the session's measurements |
| 9 | main session | verification, the PR, user interaction |

## Open questions

None at approval time beyond the flagged decisions in the handoff section.

## Handoff to implementation

### User-approval gates

- Phase 7 routes instead of holding during the window (`[FALLBACK, confirm or override]`,
  deviates from the Brief's "hold a merge" criterion in favour of its "advisory before blocking"
  constraint). Confirm, or flip to a hold.
- Phase 5's label provisioning goes through github-iac (`[FALLBACK, confirm or override]`); the
  validator comments only until the label exists.
- Phase 4 is kept as briefed although both reviews recommend cutting it; confirm, or cut.
- Any mid-flight change to the mandatory map in `.claude/source-control.md` (it is the contract
  the Brief's first acceptance criterion states).

### Execution shape ([EXEC-SHAPE] tagged)

- Three waves as above; sub-agent workers for Phases 1 to 7; main session for 8 and 9.
- Phase 4 lives in source-control, not guardrails.
- Phase 2's `skill_evidence_store` option pairs with claude-ops' scope words by documented
  default rather than shared configuration.
- The security class runs in the `ready` step over the draft PR's diff, at the retired lane's
  breadth.
- One PR on this branch, one commit per phase, Phase 6 as the structural commit (Tidy First).
  Flip line: split into three PRs (claude-ops; retirement and ADR; source-control and CI).

### Mechanical work

- Commit boundaries: one commit per phase, conventional subject
  (`feat(source-control): …`, `chore(ci): retire the claude review lanes`, `docs(adr): …`).
- Verification checkpoints: each phase's Sanity Check before its commit;
  `scripts/affected-tests.sh --run` at Phase 9; `/ai-slop:audit` on every changed markdown file.
- Sequential fallback as stated above.
