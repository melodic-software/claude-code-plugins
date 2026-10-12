# Escalate through a scripted report-escalation leaf and a runner-computed reason

- Status: accepted
- Date: 2026-10-12

## Context

When `resolve-conflicts` cannot finish a merge, the PR goes to a person through the loop-lane
contract: the human-gated role label plus a machine-marked comment
([loop-lane README, "2. Escalation contract"](../conventions/loop-lane/README.md#2-escalation-contract)). The leaf's
`mutate-branch` grant holds `pull-requests: read` and `issues: read`, so it cannot label or comment
([`effect-grants.json`](../../.github/actions/resolve-config/effect-grants.json)). The activity's
`verdict.json` is written after untrusted processing in the same job and is never trusted
([ADR 0053](0053-run-each-pipeline-activity-as-a-model-job-and-a-scripted-report-job.md),
point 4).

## Decision

1. **A separate scripted leaf.** `report-escalation` is a script leaf with effect
   `publish-artifact`, no model, `reads-untrusted: false`
   ([`pr-pipeline.yaml:33-39`](../conventions/pr-pipeline.yaml)). Its row in `activity-rules.json`
   forbids `mutate-branch` and `merge`
   ([ADR 0067](0067-hold-per-activity-never-rules-in-a-trust-root-file.md)). The pr-unblock caller
   runs it as its own job after `resolve-conflicts`, only when that job set a reason and was not
   cancelled ([`pr-unblock.yml:61-81`](../../.github/workflows/pr-unblock.yml)).
2. **The reason comes from runner steps only.** The write runner's `escalation-reason` output is
   one of `protected-path-conflict`, `workflow-staged`, `repeat-cap` or `unresolved-conflict`, set
   by `prepare.sh` before any model turn or by `post.sh` after it, never from model text
   ([`pr-run-activity-write.yml:80-85,128`](../../.github/workflows/pr-run-activity-write.yml)).
   The skill escalates by leaving the conflict unresolved. The caller passes the value as the
   escalation job's `escalation-reason` input, which the runner checks against that enum before
   anything else (`pr-run-activity-write.yml:153-173`) and hands the script as `ESCALATION_REASON`.
3. **The script writes nothing from the model.** It reads only the trusted base and the API,
   adds the label before the comment, keys the comment's resume marker to the gated head SHA,
   tries the comment three times, and writes nothing when the label and a lanes-bot marker for the
   same head are already there
   ([`report-escalation.sh:1-30,59`](../../.github/scripts/pr-unblock/report-escalation.sh)).

## Alternatives considered

- **Widen `mutate-branch` with PR and issue write.** Rejected: every branch-writing activity would
  gain the grant, and `effect-grants.json` is trust root.
- **Escalate through the check run only.** Rejected: no label means the attend-queue never sees
  the item, so the loop-lane contract is not met.
- **An `escalation` object in `verdict.json`.** Rejected: the verdict is untrusted, so its reason
  and resume key would be model-influenced text in a comment.

## Consequences

- Each escalation costs a second job and a second mint.
- A forged reason can only cause an escalation, which is the fail-safe direction.
- The resume key is the gated head SHA alone. The script always escalates on that head: dropping
  an escalation whose PR head moved could strand a conflicted PR, because pr-unblock has no `pull_request`
  trigger to start a run on the new head
  ([#7172](https://github.com/melodic-software/claude-code-plugins/pull/7172)).
- The job runs under `!cancelled()`, not the default `success()`, so a later red step in the
  `resolve-conflicts` run, such as the revoke step, still escalates
  ([#7227](https://github.com/melodic-software/claude-code-plugins/pull/7227)).
