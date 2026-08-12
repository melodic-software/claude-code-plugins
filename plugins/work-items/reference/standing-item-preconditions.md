# Standing-item preconditions

Machine-readable guards on `.github/recurring-schedule.json` rows. The schedule
`notes` field remains defense-in-depth; these fields are what `/work-items:work`
tier-4 selection and `/work-items:track recheck` consult before claiming or
closing (#2052).

## Field shape

Optional `precondition` object on a schedule row:

| Key | Type | Meaning |
|-----|------|---------|
| `id` | string | Stable identifier for the check (`frontier-release-since-last-checked`, …) |
| `prompt` | string | Inline guidance to surface when the precondition is not yet satisfied |
| `requires_operator_confirmation` | boolean | When true, only an explicit operator confirmation satisfies the check — autonomous lanes must skip the row |

Rows without `precondition` behave as today.

## Supported `id` values

### `frontier-release-since-last-checked`

The standing item fires on frontier model releases, not on quarterly cadence alone.
Before claiming (tier 4) or recheck-closing:

1. Read the row's `last_checked` date.
2. Ask whether a **frontier Claude model release** occurred **after** that date.
3. If **no** (or unknown): **do not claim, do not recheck-close** — leave the open
   `[Maintenance]` issue open and report the `prompt` text inline.
4. If **yes**: proceed, and record in the claim/recheck comment that the operator
   confirmed a post-`last_checked` frontier release.

There is no automated release oracle in-repo; `requires_operator_confirmation: true`
makes the confirmation explicit rather than inferred from cadence.

## Seam helper

`plugins/work-items/scripts/evaluate-schedule-precondition.sh` prints `met`,
`unmet`, or `needs-confirmation` for a schedule row id. Pass
`--operator-confirmed` when the operator has affirmed a confirmation-style
precondition.
