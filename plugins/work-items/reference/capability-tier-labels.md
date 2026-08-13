# Capability-tier labels

Canonical `capability-tier:` axis members for the work-loop frontier-tier quota guard and
triage stamping. Dispatch model selection (frontier / strong / fast) is owned by the loop-lane
convention and agent frontmatter bindings; this leaf owns the **label strings** triage stamps
when an item needs the frontier tier's throughput bound.

## Canonical members

| Label | Tier | Description | Color (GitHub) |
|-------|------|-------------|----------------|
| `capability-tier: frontier` | frontier | Work-loop frontier quota guard (concurrency 1, separate adaptive cap ceiling) | `5319E7` |

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

### Legacy body stamps (pre-#1716 backfill)

Before the label reader flip, `work-loop` read frontier tier from triage-briefing body prose.
Triage refuses to re-triage already-triaged output, so `/work-items:setup apply` runs a one-shot
backfill after the label axis is provisioned. A body matches the legacy signal when it carries
any of these **stamp** patterns (generic security-surface dispatch prose does not match):

- `Capability tier: frontier` or `capability-tier: frontier` in the briefing body
- `stamped for the frontier capability tier`
- `frontier-tier quota guard` as an item-level stamp (not dispatch-policy prose)
- `**Capability tier:** frontier` in an agent brief

Detection and apply mechanics live in
[`${CLAUDE_PLUGIN_ROOT}/scripts/backfill-capability-tier-labels.sh`](${CLAUDE_PLUGIN_ROOT}/scripts/backfill-capability-tier-labels.sh)
(with pattern helpers in `scripts/lib/legacy-frontier-tier-signal.sh`). The backfill pass:

1. **Skips** when the bound provider is not GitHub (no label listing / bulk listing) — report INFO.
2. **Skips** when `capability-tier: frontier` is absent from the repo — the label axis pass must
   run first.
3. **Reports** candidates via `backfill-capability-tier-labels.sh check` (read-only).
4. **Applies** with an interactive user present: offer to run `backfill-capability-tier-labels.sh apply`
   (RECOMMENDED: apply all candidates). Unattended `apply` runs `check` only and names the command
   to run with a user present — never mutates items without confirmation.
5. **Label-as-code owner** — when declared, setup validates and reports candidates only; the owner
   applies labels (or the operator runs backfill after IaC lands the label).
