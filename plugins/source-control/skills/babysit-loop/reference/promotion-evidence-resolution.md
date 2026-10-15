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
The CI pr-merge lane uses [inline mode](#inline-mode-ci-pr-merge-lane) instead of an events file.
Whether the
repository's evidence predicates
([`loop-lane-prompts.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/prompts/loops/loop-lane-prompts.md)
merge-lane copy-blocks) are met is not settled here; the fail-closed table below is how this
paragraph is applied.

## Inline mode (CI pr-merge lane)

A hosted runner has no operator settings and no host an administrator owns, so the pr-merge lane
runs `scripts/resolve-promotion-evidence.mjs --inline` (arguments and reasons in its header
comment). Each call runs the publisher's report-mode GitHub reads in memory and pipes the events to
the checker as `--evidence -`: no events file, sidecar or artifact, so nothing can go stale between
publish and read. It reads merges from 5 days before the epoch, so a merge just before it whose
post-merge gate fails inside it still demotes; the checker ignores the pre-epoch events. A merge
older than those 5 days, still unverified at ratification, whose post-merge run goes red inside the
epoch yields no event. It refuses
a `--repo` other than the run's `GITHUB_REPOSITORY`. It prints the file mode's JSON.

Trust model: code at `refs/heads/main` plus the GitHub API. The helper, publisher, checker, binding
and probe evidence root all come from the job's checkout of the default-branch tip, and the events
come from GitHub through the lane token. No agent runs on the runner, so the argument paths are
trusted as given, and the settings, checkout and writability rules in
[`promotion-evidence-bootstrap.md`](promotion-evidence-bootstrap.md) do not apply. What keeps an
agent from changing those files is review: each path must sit under `merge.diff-check.denied-paths`
in the pipeline config, so the lane never merges a change to one. Inline mode never serves a local
lane. Unlike the published file, whose publish refuses to drop an earlier event, inline mode
rebuilds the events on every call, so deleted evidence would vanish unless the publisher notices
the deletion.

Deletion: inside the read window (5 days before the epoch through now) the publisher, in both
modes, fails closed instead of losing a contrary event:

- `run-deleted:`: a missing `run_number` between two runs of `pr-require-checks.yml` or
  `post-merge-detect-silent-revert.yml` created in the window. A re-run keeps its number, so it
  leaves no gap. Pointer: `github.run_number` in
  [Contexts reference](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts).
  As of 2026-10-15. Recheck trigger: that definition changes.
- `issue-deleted:` or `issue-missing:`: an issue or pull number missing between two created in the
  window that reads 410 Gone, or that does not read back as this repository's. Discussions share
  the number sequence and read 404 as issues: one is no gap unless `github-actions[bot]` or a
  `--lane-login` wrote it. Converting an issue keeps the issue under its number (closed and
  locked) and gives the discussion a new one, so a converted record still counts; the filer check
  only refuses on a discussion no filer should have opened, which fails closed and costs nothing.
- Every `babysit-merge-demotion` record `github-actions[bot]` or a `--lane-login` opened, open or
  closed, whose body or any revision carries the marker or whose edit history is not whole, is a
  gate-failure on every cell at its creation and at each repeat-failure comment one of those
  identities posted in the window; anyone else's comment counts for nothing. Records only add
  events, so a lookalike can only demote.

Residuals: a run or issue deleted or transferred while it is the newest in the window leaves no
gap until a later one is created, and a deleted run that is the oldest of its workflow in the
window leaves none at all; a red scheduled or canary run still counts through the demotion record
`post-merge-demotion-alert.yml` files when it completes. An in-window number that reads 404 and
is no discussion (an issue GitHub hid as spam, or one deleted without a 410) refuses with
`issue-missing:` for as long as it stays in the read window; in inline mode that window starts 5
days before the epoch, so the refusal holds until the cell is re-ratified or its epoch expires. An identity that can write issues can
delete a repeat-failure comment; the red run it names still counts unless also deleted. A
per-merge full run that pr-merge dispatches with its own `GITHUB_TOKEN` fires no `workflow_run`
listener, so no demotion record covers it; its deletion shows as a `run_number` gap, or as the
6-hour dispatch-deadline failure when it was the only lane dispatch. The admin operator account
(and any agent on its token) can still delete runs and issues, edit the workflows, or disable the
alert; that now fails closed rather than passing silently, but nothing stops it. Closing it needs a
reader of the `workflows.delete_workflow_run` audit-log event, which the API offers only on GitHub
Enterprise Cloud. Pointer:
[Reviewing the audit log for your organization](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/reviewing-the-audit-log-for-your-organization).
As of 2026-10-15. Recheck trigger: the organization moves to Enterprise Cloud or that page changes
which plans have the audit-log API.

Epoch guard: inline mode fails closed (`epoch-start-expired`) when the earliest `ratified_at` of a
cell bound promoted is more than 85 days old, since contrary evidence from before GitHub's
retention limit may already be gone. Pointer: the public-repository maximum in
[Configuring the retention period for checks, workflow runs, commit statuses, artifacts, and logs in your organization](https://docs.github.com/en/organizations/managing-organization-settings/configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-organization)
(applies to checks, workflow runs and commit statuses from 2026-10-01). As of 2026-10-15. Recheck
trigger: that page changes the public-repository maximum or what the policy covers. So a cell stays
inline-promoted at most 85 days after its `ratified_at`; re-ratifying it starts a new epoch.

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
