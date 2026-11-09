# Work-class labels

The `work-class:` labels record an item's risk class (C1 to C4). No work-items skill stamps,
reads or gates on them: triage, the work-loop drain, the attended queue and setup ignore them, and
an item may carry one or none. CI intake no longer applies one; a shared intake reusable may still
print a proposed class in its triage comment, and nothing applies or reads it. C5 is marked on the provenance axis, with `provenance: untrusted`. Of the class and
provenance labels, only `provenance: untrusted` and `provenance: signal` hold an item for a
person, as a provenance hold.
Classification criteria (the risk-property bundles behind C1–C5) live in the `autonomy`
plugin's [`work-classes.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/autonomy/reference/guardrails/work-classes.md).

## Members

| Label | Class | Description |
|-------|-------|-------------|
| `work-class: read-only` | C1 | Audits, research, reports. No repository mutation; tracker and queue writes only. |
| `work-class: mechanical` | C2 | Deterministic, trivially reversible maintenance: dependency bumps, lint/format, sync. |
| `work-class: scoped` | C3 | A briefed fix or small feature; blast radius bounded by the brief, tests exist. |
| `work-class: structural` | C4 | Refactors, migrations, contract changes; cross-cutting and hard to reverse. |
| `provenance: untrusted` | C5 | Outside the org's trust boundary (fork PR, external contribution, or an item filed from a signal and labeled `provenance: signal`); isolated, human-merged. |

`provenance: untrusted` is the one canonical member: triage applies it and `/work-items:setup`
provisions it.

The frontier floor reads labels only, never a `Work-class: C<n>` body trailer.

## Who applied the role label

Admission checks who applied the autonomous-eligible role label: the
role label counts only when its latest application came from an actor with
`write`, `maintain` or `admin` on the repository. GitHub's triage role can apply labels while
holding only `read` (pointer:
[Get repository permissions for a user](https://docs.github.com/en/rest/collaborators/collaborators#get-repository-permissions-for-a-user),
as of 2026-10-04, recheck trigger: the endpoint's role mapping changes), so before admitting an item the work-loop drain runs the adapter's
`label-provenance` operation over the item's autonomous-eligible role
label, and refuses the item for that cycle on a triage or read labeler, a missing `labeled` event,
or a failed read ([`../skills/work-loop/SKILL.md`](../skills/work-loop/SKILL.md) "Admission gate",
labeler precondition); a refusal only on the body edit time, edited after admission or unread, is
escalated once instead. A provider adapter without that operation refuses every labeled item, so
triage on such a tracker leaves the drain idle rather than trusting labels it cannot attribute.

The precondition cannot tell the lane's own identity from a person with `write`, so the
work-loop's intake sweep writes neither the role label nor `provenance: untrusted` by default: it
escalates with a proposed role-label swap instead
([`../skills/triage/context/apply-outcome.md`](../skills/triage/context/apply-outcome.md),
"Work-loop intake sweep: propose, never admit"). A label the lane applied itself admits an item
only when the lane's launch prompt explicitly opts the sweep into writing it.

## The human-floor class excludes the autonomous-eligible role label

`provenance: untrusted` (C5), and the `provenance: signal` label, are human-gated
**regardless of any other signal** ([`../skills/work-loop/SKILL.md`](../skills/work-loop/SKILL.md)
"Admission gate", which binds whether or not the `autonomy` plugin is enabled). No other class
floors an item, and neither does a missing class. The autonomous-eligible role label
(default `agent-ready`) asserts the opposite, so **an item must never carry both**. Applying
that role label to a C5 item is a triage defect, not an operator override: no label
lifts the floor.

Enforcement, so the rule is not merely written down:

- **`list-frontier --autonomous` drops human-floor items** even when the autonomous-eligible
  role label is present ([`../tools/work-item-tracker/lib/frontier.sh`](../tools/work-item-tracker/lib/frontier.sh);
  the floor strings are
  `WIT_HUMAN_FLOOR_PROVENANCE_LABELS` in
  [`../tools/work-item-tracker/lib/labels.sh`](../tools/work-item-tracker/lib/labels.sh), so a
  `provenance: untrusted` or `provenance: signal` item is dropped whatever its other labels).
  Without that exclusion the contradictory item stays frontier-available, so each lane
  instance in turn claims it, hits the admission gate's provenance hold, and escalates, burning a
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
  item unless the same edit removes its provenance labels
  ([`../skills/attend-queue/SKILL.md`](../skills/attend-queue/SKILL.md), "Untrusted provenance:
  reclassify or stay gated").

Remediation when the pair is found on an existing item: remove the
autonomous-eligible role label, and apply the human-gated role label (default `needs-human`)
so the item routes to the attended lane. Resolving the escalation that follows does **not**
lift the floor: the attended lane either removes the provenance labels in the same edit as the
role-label flip, once a person with `write` establishes the item is trusted, or leaves it
human-gated with its completion route recorded as a comment. A floor-class item never leaves the
attended lane carrying the autonomous-eligible role label alone.

## Migration

Triage needs `provenance: untrusted` before it labels an untrusted or signal-marked item.

1. **Label-as-code owner declared.** Route provisioning to that system; `/work-items:setup`
   validates presence only and never writes labels ad hoc.
2. **No label-as-code owner.** `/work-items:setup apply` is the migration path: it discovers a
   missing `provenance: untrusted` and, with an interactive user present, creates it via the
   GitHub adapter's label-creation mechanics using the description above. An unattended `apply`
   stops with an explicit remediation instead of guessing.

Setup fails closed when `provenance: untrusted` is absent, in `check` and at the start of
`apply`'s migration pass. It neither checks nor creates the four `work-class:` labels. Triage
stops before mutating an item only when the label its edit would apply is absent.
