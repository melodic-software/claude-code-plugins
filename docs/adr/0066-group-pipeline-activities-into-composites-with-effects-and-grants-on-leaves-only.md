# Group pipeline activities into composites with effects and grants on leaves only

- Status: accepted
- Date: 2026-10-12

## Context

A lane in `pr-pipeline.yaml` was a list of slots, each naming one activity. The pr-unblock lane is
meant to grow groups of related activities (a `fix-ci` group of lint, format, type, build and test
fixes, then address-feedback) that a lane enables, orders and gates as one unit, while each member
still runs as its own job with its own App token
([ADR 0053](0053-run-each-pipeline-activity-as-a-model-job-and-a-scripted-report-job.md),
[ADR 0058](0058-mint-lane-app-tokens-through-an-oidc-broker.md)). The schema, the config reader,
the token broker and the report job all key on an activity name, so the shape of a group is a
contract every one of them reads.

## Decision

An activity is either a leaf or a composite
([`pr-pipeline.schema.json:150-183`](../conventions/pr-pipeline/pr-pipeline.schema.json)):

1. **One flat map.** `activities:` stays a single map keyed by unique names. A leaf has `skill` or
   `script`, `effect`, `gating`, `reads-untrusted`, `inputs` and `applies-when`. A composite has
   `children:`, a list in the same slot shape a lane's `slots:` uses (`activity`, `needs`,
   `applies-when`, `enabled`), so a lane is the root composite, and an optional `applies-when`
   that gates every child. Basis: `pr-pipeline.schema.json:150-186`;
   [pr-pipeline README, "Activities"](../conventions/pr-pipeline/README.md#activities).
2. **Effects, inputs and grants belong to leaves.** A composite declares none. Lane rules are
   checked over every leaf a lane expands to, and `resolveGrant`, the broker's entry point,
   resolves only leaf keys, because the lane is expanded to its leaves before an activity is looked
   up. One job runs one leaf, gets one grant and posts one check; a composite has no job, grant or
   check of its own. Basis:
   [`resolve.mjs:293-323,346-375,577-596`](../../.github/actions/resolve-config/resolve.mjs).
3. **The path decides.** A leaf runs only when the lane, every ancestor composite and its own slot
   are enabled, and only when every ancestor's `applies-when` and its own match. Basis:
   `resolve.mjs:346-376`.
4. **What the reader checks that the schema cannot**: every child is defined, `needs:` names only
   siblings, no composite contains itself, a composite holds only leaves, and a leaf appears at
   most once in a lane. Basis: `resolve.mjs:111-166,293-303`. The depth limit of two layers below
   the lane: judgment, held until a third layer is needed.

## Alternatives considered

- **Nested definitions** (children defined inline, a leaf identified by its path). Rejected: a leaf
  under two composites is defined twice, and the resolver, broker and report job would all have
  to carry paths instead of one key. Basis: judgment, from the activity-name keying in
  `resolve.mjs:577-596` and the check name `<lane> / <activity>` in
  [ADR 0053](0053-run-each-pipeline-activity-as-a-model-job-and-a-scripted-report-job.md) point 2.
- **No composites; group by name prefix only.** Rejected: nothing could enable, order or gate a
  group as one unit, which is what the later pr-unblock groups need. Basis: judgment.
- **An effect on the composite.** Rejected: a token is minted per job and a job runs one leaf, so
  a composite-level effect would either widen every member's grant or be ignored. Basis:
  [ADR 0058](0058-mint-lane-app-tokens-through-an-oidc-broker.md) point 3 (one mint per job).

## Consequences

- Leaf names are unique config-wide, so two composites cannot each own a leaf called `fix-tests`.
- A third layer, or a leaf shared by two parents in one lane, needs a reader change.
- The live config slots no composite yet
  ([`pr-pipeline.yaml:41-51`](../conventions/pr-pipeline.yaml)); the first one arrives with the
  `fix-ci` leaves.
- Per-leaf never-rules live outside this config:
  [ADR 0067](0067-hold-per-activity-never-rules-in-a-trust-root-file.md).
