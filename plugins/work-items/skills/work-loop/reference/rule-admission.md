# Rule admission

A second admission path in [`../SKILL.md`](../SKILL.md)'s admission gate, run after the labeler
precondition. A snapshot item that is not in flight and carries no admitted autonomous-eligible role
label (absent, or refused by the labeler precondition) may still be admitted by the owner's C2 rules
in the security binding's `admission.rule_admission[]`; the `autonomy` plugin's
`admission-policy.md` ("Rule admission") owns their meaning.

Resolve the security binding as `/autonomy:setup` "Guardrail binding resolution" defines it, never
from a repo-local file; when none resolves, or the tracker is not GitHub-bound, skip this path. Run
`rule-admit.sh` at the path the SKILL.md pointer to this file names, as
`bash <that path> --repo <owner/name> --binding <path> --issue <n> [--issue <n> ...]`
and admit an item only on its `"verdict": "admit"` row from an exit-`0` run; any other exit admits
nothing (exit `4` also covers a binding whose posture or decision table does not allow rule
admission).

Neither the script nor this lane writes a label: a rule-admitted item gets no autonomous-eligible
role label and no `work-class:` label, and the row's `admitted-by-rule: <id>@<binding sha>` reason
goes into the cycle report as the admission of record.

It dispatches under the row's `human-merge` constraint: the `/work-items:work` invocation states
the PR body carries `Hold: a human merges this`, beside any hold `merge-hold.sh` reports. A `Hold:`
line holds the merge only: `ready` still flips the PR out of draft, and the merge gate, which reads
the live body, refuses it, so a person merges.

C1 rule admission is not enabled: `/work-items:work` always pushes, so a C1 no-push constraint would
rest on prose alone, and the script refuses every C1 rule match until a mechanical no-push exists.
A refuse row changes nothing; the cycle report gives only the refused count. Rule-admitted items
still pass the hard gates and the item cap.
