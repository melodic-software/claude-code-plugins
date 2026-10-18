# Promotion-evidence resolution (merge lane)

This lane's binding of the guardrail contract's promotion-state ceiling for the rung partition
(`SKILL.md` cycle-shape step 3). The bound `promotion_state` on a security binding is a **ceiling
only**. Consumers must resolve each promotable cell's **effective** state against live
promotion-evidence telemetry before every autonomous merge decision, fail-closing to unpromoted
when evidence is unavailable, untrusted, partial, or forgeable
(`/autonomy:setup` owns the security binding and the `promotion_state` field this reads;
[`verification-topology.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/autonomy/reference/guardrails/verification-topology.md)
"Consumers resolve both"). Reading the bound state alone is non-conforming.

## Promotable cells and rung mapping

| Effective merge rung | Work classes the rung admits | Promotable cell(s) that must be effective-promoted |
|---|---|---|
| `c2-mechanical` | C2 mechanical only | `C2-auto-merge` |
| `c3-autonomous` | C2 and C3 | `C2-auto-merge`, `C3-auto-merge` (and `C3-ai-review-blocking` as a prerequisite of `C3-auto-merge`) |
| `full-autonomy` | every class up to C3 | same as `c3-autonomous` for C2/C3; still never C4/C5 |
| `human-only` | none | none. Promotion resolution is skipped (eligible set empty) |

`C4/C5` merge never promotes; no cell covers them.

## Trusted seam (required)

Promotion evidence MUST be resolved through a **trusted seam**: an agent-unwritable bootstrap
outside the target repository's blast radius, the same class of surface the autonomy setup skill
names for security-binding resolution
([`setup/SKILL.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/autonomy/skills/setup/SKILL.md) "Agent-unwritable bootstrap for
security resolution"). Evidence read from repo-local, agent-writable, or otherwise forgeable
surfaces does **not** qualify: partial reads, stale snapshots, and operator-supplied JSON without
provenance are treated as **unavailable** and fail-closed.

[`check-security-binding.mjs`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/autonomy/skills/setup/scripts/check-security-binding.mjs)
evaluation mode (`--evidence`) owns the canonical resolution algorithm: bound ceiling, epoch-scoped
contrary events (`gate-failure`, `reverted-merge`, `verification-divergence`), and prerequisite
propagation. The loop lane invokes that resolution **through the trusted seam
only**, never by re-deriving a subset in prose.

**Current seam state.** A compliant bootstrap lets the seam return a qualified read.
[`cycle-shape.md`](cycle-shape.md) step 3 runs `scripts/resolve-promotion-evidence.mjs` once per
cycle; it runs the operator-supplied checker on the three evidence surfaces
(`check-security-binding.mjs --evidence`) and
reports each promotable cell's bound and effective state as the checker printed them, which is
how a cell resolves effective-promoted or demoted. With no compliant bootstrap, a step 0 problem,
any fail-closed reason, or a helper failure, **every promotable cell resolves
effective-unpromoted** and autonomous merge stays off for C2/C3 classes regardless of tracked rung.
Operators keep `--merge human-only` on launch lines; lifting it is the owner's call.
The resolver passes `--credential-roots` to the checker when the operator sets
`promotion_evidence_credential_roots`; unset, a binding whose L2 proof rests on a filesystem
credential probe fails closed even with a compliant bootstrap. Remaining work is tracked in [#4588](https://github.com/melodic-software/claude-code-plugins/issues/4588). The unattended
merge path (`babysit_merge_policy.read_promotion`) additionally refuses any option value or
settings file the lane can write, so on a single-user
host user-scope settings never qualify there; only managed settings and surfaces owned by someone
other than the lane identity can.
What an operator supplies for the seam is in
[`promotion-evidence-bootstrap.md`](promotion-evidence-bootstrap.md), and the lane-start preflight
in [`cycle-shape.md`](cycle-shape.md) step 0 reports each missing or non-compliant surface by
option name. The implementation checklist and phased plan are in
[`promotion-evidence-implementation-plan.md`](promotion-evidence-implementation-plan.md).
Whether the
repository's evidence predicates
([`loop-lane-prompts.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/prompts/loops/loop-lane-prompts.md)
merge-lane copy-blocks) are met is not settled here; the fail-closed table below is how this
paragraph is applied.

## Deletion

Inside the read window (5 days before the epoch through now) the publisher fails closed instead of losing a contrary event:

- `run-deleted:`: the runs of `pr-require-checks.yml` and `post-merge-detect-silent-revert.yml`
  created in the window, every event and branch, must carry consecutive `run_number` values, a
  re-run included; a gap refuses. Pointer: `run_number` under
  [github context](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#github-context).
  As of 2026-10-15. Recheck trigger: that entry changes how numbers are assigned or kept on re-run.
- `issue-deleted:` or `issue-missing:`: a number missing from the issue listing between two items
  created in the window is read on its own. Read as deleted, it refuses with `issue-deleted:`;
  read as anything but this repository's issue or pull, `issue-missing:`. A discussion holding the
  number is skipped unless `github-actions[bot]` or a `--lane-login` wrote it, which refuses.
  Pointers: status codes under
  [Get an issue](https://docs.github.com/en/rest/issues/issues#get-an-issue--status-codes) and
  [Converting an issue to a discussion](https://docs.github.com/en/discussions/managing-discussions-for-your-community/moderating-discussions#converting-an-issue-to-a-discussion);
  probe: `gh api repos/cli/cli/issues/14698` against a discussion number, 2026-10-15. Recheck trigger: either section changes, or a live run refuses on a
  number that holds a discussion.
- Every `babysit-merge-demotion` record `github-actions[bot]` or a `--lane-login` opened, open or
  closed, whose body or any revision carries the marker or whose edit history is not whole, is a
  gate-failure on every cell at its creation and at each repeat-failure comment one of those
  identities posted in the window; anyone else's comment counts for nothing. Records only add
  events, so a lookalike can only demote.

Residuals: a run or issue removed while it is the newest in the window leaves no gap until a later
one is created, and a deleted run that is the oldest of its workflow in the window leaves none at
all; a red scheduled or canary run still counts through the demotion record
`post-merge-demotion-alert.yml` files when it completes. A number in the window that reads as
neither an issue nor a discussion refuses with `issue-missing:` for as long as it stays in the
read window. An identity that can write issues can delete a
repeat-failure comment; the red run it names still counts unless also deleted. No demotion record
covers a per-merge full run pr-merge dispatches with its own `GITHUB_TOKEN`; its deletion shows as
a `run_number` gap, or as the 6-hour dispatch-deadline failure when it was the only lane dispatch.
Pointer:
[Triggering a workflow from a workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#triggering-a-workflow-from-a-workflow).
As of 2026-10-15. Recheck trigger: that section changes which tokens start new runs. The admin
operator account (and any agent on its token) can still delete runs and issues, edit the
workflows, or disable the alert; that now fails closed rather than passing silently, but nothing
stops it. Closing it needs a reader of run-deletion events in the organization audit log, which
this organization cannot read through the API today. Pointer:
[Using the audit log API](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/reviewing-the-audit-log-for-your-organization#using-the-audit-log-api).
As of 2026-10-15. Recheck trigger: the organization changes plan or that section changes which
plans have the audit-log API.

## Fail-closed rules

Resolve once per cycle immediately before the work-class rung comparison, after the effective merge
rung is known and before any PR enters the merge-eligible set.

| Condition | Effective state | Partition effect |
|---|---|---|
| Trusted seam unavailable (no bootstrap, read error, timeout) | every cell → unpromoted | no C2/C3 PR is merge-eligible on promotion grounds |
| Evidence untrusted, partial, or forgeable | every cell → unpromoted | same |
| Contrary event in epoch for a cell | that cell → unpromoted | classes requiring that cell excluded on the **next** cycle without config change |
| Prerequisite cell unpromoted | dependent cell → unpromoted | e.g. C3 excluded when `C2-auto-merge` demoted |
| Cell bound unpromoted with clean evidence | unpromoted | class excluded |
| Cell bound promoted, no contrary in-epoch evidence | promoted | class may proceed to work-class + other withholdings |

Report the resolution source, each cell's bound→effective pair, and any fail-closed reason in the
cycle-start config report. Never treat a demotion as a standing rung lower. It is telemetry-driven
exclusion for the affected class only.

## Partition interaction

Promotion resolution is a **gate on top of** the existing rung partition, not a substitute for it.
A PR still requires close-linked work item, label-enforced class, C4/C5 floor, do-not-merge veto,
human blocking feedback withholdings, and every other step-3 rule. Effective-unpromoted
`C2-auto-merge` makes a C2-mechanical PR ineligible exactly as if the rung were too low. The PR is
routed to the `safe` per-PR pass, never a merge-capable invocation.
