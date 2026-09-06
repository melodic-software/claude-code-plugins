# Work-class labels

Canonical `work-class:` axis members for the fail-closed admission gate and merge partition.
Classification criteria (the risk-property bundles behind C1–C5) live in the `autonomy`
plugin's [`work-classes.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/autonomy/reference/guardrails/work-classes.md);
this leaf owns the **label strings** triage stamps and setup migrates.

## Canonical members

| Label | Class | Description |
|-------|-------|-------------|
| `work-class: read-only` | C1 | Audits, research, reports. No repository mutation; tracker and queue writes only. |
| `work-class: mechanical` | C2 | Deterministic, trivially reversible maintenance: dependency bumps, lint/format, sync. |
| `work-class: scoped` | C3 | A briefed fix or small feature; blast radius bounded by the brief, tests exist. |
| `work-class: structural` | C4 | Refactors, migrations, contract changes; cross-cutting and hard to reverse. |
| `work-class: untrusted-provenance` | C5 | Outside the org's trust boundary (fork PR, external contribution); isolated, human-merged. |

Discover live members through the bound adapter's label listing (GitHub:
`gh label list --limit 200 | grep -i work-class`). An item carries **exactly one**
`work-class:` label; the merge partition and admission gate read the label only — never a
`Work-class: C<n>` body trailer.

## Human-floor classes exclude the autonomous-eligible role label

`work-class: structural` (C4) and `work-class: untrusted-provenance` (C5) are human-gated
**regardless of any other signal** (the admission-gate table in
[`../skills/work-loop/SKILL.md`](../skills/work-loop/SKILL.md) "Admission gate", which binds
whether or not the `autonomy` plugin is installed). The autonomous-eligible role label
(default `agent-ready`) asserts the opposite, so **an item must never carry both**. Applying
that role label to a C4 or C5 item is a triage defect, not an operator override: no label
lifts the floor.

Enforcement, so the rule is not merely written down:

- **`list-frontier --autonomous` drops human-floor items** even when the autonomous-eligible
  role label is present ([`../tools/work-item-tracker/lib/frontier.sh`](../tools/work-item-tracker/lib/frontier.sh);
  the floor strings are `WIT_HUMAN_FLOOR_WORK_CLASS_LABELS` in
  [`../tools/work-item-tracker/lib/labels.sh`](../tools/work-item-tracker/lib/labels.sh)).
  Without that exclusion the contradictory item stays frontier-available, so each lane
  instance in turn claims it, hits the fail-closed admission gate, and escalates — burning a
  worker every pass while the item never moves.
- **The attended frontier still shows it.** The exclusion is autonomous-only, so `list-frontier`
  without `--autonomous` (operator listings, container-scoped views) still returns a mislabeled
  item instead of it vanishing from every derived view.
- **The human-gated role label is what keeps it in the attended queue.**
  `/work-items:attend-queue` builds its attention view from the human-gated role label plus a
  machine-marked comment, not from the frontier, so the attended frontier above is not a
  substitute for that label. An item carrying a floor class but neither the human-gated role
  label nor an intake condition matches no row in that view and is floored out of the
  autonomous frontier, which leaves it reachable by no lane. That is why the attended lane's
  "Flip to agent-ready" transition refuses to strip the human-gated role label off a floor-class
  item unless the same edit reclassifies it to C1-C3
  ([`../skills/attend-queue/SKILL.md`](../skills/attend-queue/SKILL.md), "Human-floor work class:
  reclassify or stay gated").

C3 `scoped` is deliberately **not** floored at the frontier: its disposition turns on
bug-fix-vs-feature shape and first-drain ratification, neither readable from a label, so the
work-loop admission gate owns it.

Remediation when the pair is found on an existing item: keep the work class, remove the
autonomous-eligible role label, and apply the human-gated role label (default `needs-human`)
so the item routes to the attended lane. Resolving the escalation that follows does **not**
lift the floor: the attended lane either reclassifies the item to an autonomously dispatchable
class in the same edit as the role-label flip, or leaves it human-gated with its completion
route recorded as a comment. A floor-class item never leaves the attended lane carrying the
autonomous-eligible role label alone.

## Migration

Repos adopting triage's autonomous-eligible outcomes or the work-loop admission gate need all
five labels present **before** triage applies `agent-ready`.

1. **Label-as-code owner declared** — route provisioning to that system; `/work-items:setup`
   validates presence only and never writes labels ad hoc.
2. **No label-as-code owner** — `/work-items:setup apply` is the migration path: it discovers
   missing members and, with an interactive user present, creates them via the GitHub adapter's
   label-creation mechanics using the descriptions above. An unattended `apply` stops with an
   explicit remediation instead of guessing.

Triage and setup both fail closed when any canonical member is absent — triage before mutating
an item, setup in `check` and at the start of `apply`'s migration pass.
