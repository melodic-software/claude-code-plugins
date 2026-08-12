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
