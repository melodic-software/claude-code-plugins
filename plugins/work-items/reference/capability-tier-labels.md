# Capability-tier labels

Canonical `capability-tier:` axis members for the work-loop frontier-tier quota guard and
triage stamping. Dispatch model selection (frontier / strong / fast) is owned by the loop-lane
convention and agent frontmatter bindings; this leaf owns the **label strings** triage stamps
when an item needs the frontier tier's throughput bound.

## Canonical members

| Label | Tier | When to apply |
|-------|------|---------------|
| `capability-tier: frontier` | frontier | Item needs the work-loop frontier quota guard (concurrency 1, separate adaptive cap ceiling) |

Discover live members through the bound adapter's label listing (GitHub:
`gh label list --search 'capability-tier:'`). An item carries **at most one**
`capability-tier:` label. The work-loop adaptive cap reads the label only — never body prose
claiming a tier.

**Absent label = general tier (fail-closed).** Items with no `capability-tier:` label run under
the general adaptive cap ceiling. A body or brief that mentions frontier tier is context for the
operator; it does not select the quota guard.

**Security-surface dispatch is separate.** Security-surface work still routes to the frontier
capability tier for model selection via work-class rules in the admission gate — that path does
not substitute for the label when the quota guard needs to bind.

## Escalation

When an item genuinely needs the frontier quota guard and lacks the label:

1. **Interactive triage** — apply `capability-tier: frontier` in the outcome edit when the
   label exists in the repo.
2. **Autonomous lane** — note the need in the triage comment and leave the label unstamped when
   the repo cannot provision it; the work-loop lane treats the item as general tier until triage
   (or an operator) applies the label.
3. **Label-as-code owner** — route provisioning to that system (`melodic-software/github-iac` for
   org repos). This plugin never creates the label ad hoc when label-as-code owns writes.

## Migration

Repos adopting the frontier-tier quota guard need `capability-tier: frontier` present **before**
triage stamps it.

1. **Label-as-code owner declared** — route provisioning to that system; `/work-items:setup`
   validates presence only and never writes labels ad hoc.
2. **No label-as-code owner** — `/work-items:setup apply` may create the label with an
   interactive user present, using the same mechanics as the work-class axis migration. An
   unattended `apply` stops with explicit remediation instead of guessing.

Triage preflights the label before stamping; when absent, it reports remediation and omits the
label rather than inventing one.
