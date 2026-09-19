# Seat the mandatory reviews on the operator's session and retire the OAuth lanes

- Status: accepted
- Date: 2026-09-19
- Supersedes, for this repository: the lane wiring, the skip-actor exception, and the once-per-PR
  trigger set recorded in ADR 0002. ADR 0002's posture of advisory before blocking and earned
  promotion still stands and this record applies it.

## Context

Two GitHub Actions lanes ran the Claude code review and security review on every pull request
through a subscription OAuth token (`CLAUDE_CODE_OAUTH_TOKEN`). Both triggered once per pull
request, on open, ready-for-review, and reopen, and GitHub skips a `pull_request` run while the
pull request conflicts with its base. Agent branches here are routinely opened or flipped while
main has moved, so the one trigger that would have reviewed them was swallowed, and a later push
never re-triggered a review.

Measured over the last 40 merged pull requests (read over REST on 2026-09-12): 14 received no
successful code-review run on any commit, and 1 was reviewed on the commit that merged. The lanes
were the largest single line of the Actions spend, they posted a review-count comment on every
pull request, and the operator cannot use API keys, so every review in CI drew on the same
subscription window the interactive sessions use.

The repository already had the pieces of a different posture: a fixed pre-PR order
(`docs/conventions/pre-pr-ordering/README.md`) whose steps are implemented by installed skills,
a hook-written ledger of every Skill tool call (claude-ops `skill-usage.jsonl`), a pull-request
skill that owns creation and merge, a required `ci-status` check that already carries the body
contract as advisory steps, and a babysit merge gate that reads pull-request state over REST.

## Decision

**The mandatory reviews run on the operator's seat, and the pull request carries the evidence.**

1. **The mandatory set is the pre-PR order's implementing skills, routed by changed-file class.**
   The map is the `pr_skill_evidence` key of `.claude/source-control.md`: code owes
   `verification:confirm` (the terminal skill), one fresh-context review (`review:quality-gate`
   under 50 changed lines, `review:fanout` above), and `simplify`; markdown owes `ai-slop:audit` and
   `docs-hygiene:audit-noise`; renames owe `docs-hygiene:rename-references`; skills and agents
   owe `skill-quality:check`; rules owe `instruction-placement:check`; the security surfaces listed
   in `.github/claude-security-paths` owe `review:security-review`, run locally over the draft's
   diff at the retired lane's breadth. A map absent from every layer is inert, so the mechanism
   presumes nothing about another repository.
2. **Both OAuth lanes retire**, with their evidence guards, the shared guard library, the
   skip-actors reader and list, and the review-count and last-reviewed-head comments. No review
   surface in GitHub Actions depends on the subscription token, and none bills usage credits.
3. **Evidence is a ledger row plus a body block.** Every skill-usage row now carries the commit
   the skill was invoked at and the pull request number when the branch records one. The
   pull-request skill renders a fenced `skill-evidence` block under the body's Verification
   section, one `<skill> <sha> <utc-timestamp>` row per skill. One script,
   `plugins/source-control/scripts/skill-evidence.sh`, is the only reader and renderer.
4. **Freshness has two tiers.** A row is stamped when a skill is invoked, before any edit the
   skill goes on to make, so the terminal skill's row must equal HEAD exactly and every other
   skill's row must sit on HEAD's history. A base refresh by merge keeps every non-terminal row
   and re-runs the terminal skill; a rebase or amend rewrites the SHAs and invalidates every row,
   so once a pull request exists the ready step merges and never rebases.
5. **The ready flip is the evidence-bearing run.** `/source-control:pull-request ready` refuses
   without a pull request, merges the base, runs whatever the head still owes in the convention's
   order with the terminal skill last, renders the block, and flips. Every pull request opens as
   a draft.
6. **Three advisory readers, none of them a gate.** A PreToolUse hook on the ready flip
   (`gh pr ready`, the GraphQL mutation through `gh api`, the GitHub MCP update with
   `draft:false`) injects a notice naming the missing skills and never blocks. A step inside
   `ci-status`, after the aggregate and as a fall-through step, reads the block over REST and
   upserts one comment carrying one marker line per evaluated head, adding the
   `needs-skill-evidence` label where github-iac has provisioned it; it never turns the required
   check red. The babysit merge gate reports a `skillEvidence` record for every tier and routes a
   gap to a worker that runs the ready step; no tier holds a merge on it.
7. **One deterministic detector enters CI now.** The ai-slop detector reports on changed
   markdown as lint-job warnings. Audit-noise waits for a zero baseline, instruction-placement
   waits for a verdict, and skill-quality already ran there.
8. **Promotion is earned on a measured window.** After 40 merged pull requests or 30 days,
   whichever comes second, `skill-evidence.sh report` reads the validator's markers over REST and
   returns, per gate, how often it fired and how often a later head carried a clean block. Each
   advisory reader is then promoted or deleted on that data, per ADR 0003.

## Evidence

- Coverage baseline: 40 merged pull requests read over REST on 2026-09-12, 14 with no successful
  review-lane run, 1 reviewed on the merged head. Pull request #4210 carried the plan for this
  change.
- GitHub skips `pull_request` runs while the pull request has a merge conflict (the events
  reference, fetched 2026-09-12).
- Two fresh-context reviews of the plan found that a rule demanding every row at HEAD marks every
  mutating skill stale by construction, because rows are stamped at invocation; the two-tier rule
  above is the repair, pinned by the script's suite.
- `git check-ignore --no-index` still consults the repository's own ignore rules, so the class
  matcher keeps only matches whose source is its own patterns file (probe, 2026-09-13).

## Consequences

- The evidence is self-reported. A plain file write can forge a ledger row or a body block; the
  guardrails write-bypass hook fences shell redirect forms only. This is the same-name
  forgeability ADR 0024 already accepts for every GitHub-account action here, and it holds while
  the readers are advisory. If autonomous merge is enabled, the evidence must move to an
  App-authored check.
- Pull requests opened outside the pull-request skill (the GitHub UI, a bare REST call, a bot)
  receive no review at all and only the advisory comment. The retired lanes reviewed those
  operator-account pull requests when their one trigger fired; that coverage is gone.
- Every base refresh re-runs the terminal skill on the seat. That is the cost of refreshing, and
  it replaces the lanes' cost of one review per pull request at most.
- The security class fires on nearly every non-docs pull request, at the breadth
  `.github/claude-security-paths` declares. Narrowing the list narrows the class.
- The measurement keys on the pull request's head SHA at merge time, read over REST, because the
  base ruleset squash-merges and the squash commit never appears in a row.
- The `needs-skill-evidence` label is IaC-owned and provisioned through github-iac; until then
  the validator comments only. The org pull-request template
  (`melodic-software/.github`) should name the block; this repository deleted its local template
  to inherit the org default, so that wording is a request against the org repository.
- The claude-ops writer and the source-control readers resolve the ledger path by paired
  defaults (`skill_usage_scope` and `skill_evidence_store`); claude-ops' `data-dir` scope is
  unsupported for evidence.

## Revisit triggers

- The promotion window closes → run `skill-evidence.sh report --repo` and promote or delete each
  advisory reader on its fired and agreed counts.
- Autonomous merge is enabled in effect → move the evidence to an App-authored check before any
  reader may hold a merge.
- A sampled pull request shows a creation path with no ledger rows → the pull-request skill is
  not the entry point agents use; widen the readers or route that path through it.
- The review-count or last-reviewed-head comment appears on a pull request opened after this
  change → an upstream caller still runs; find and retire it.
- The audit-noise corpus reaches zero findings on main → add its detector to the lint job's
  warning step.
- A forged row or block is observed → the readers stop being advisory on trust alone; revisit the
  App-authored check.
