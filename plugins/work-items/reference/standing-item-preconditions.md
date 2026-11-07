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
| `requires_operator_confirmation` | boolean | When true, only an explicit operator confirmation satisfies the check, so autonomous lanes must skip the row |

Rows without `precondition` behave as today.

## Supported `id` values

### `frontier-release-since-last-checked`

The standing item fires on model releases, not on quarterly cadence alone. The row's
`prompt` sets which release class counts; the id still says "frontier" only because
renaming it would break the schedule rows and scripts that match it.
Before claiming (tier 4) or recheck-closing:

1. Read the row's `last_checked` date.
2. Read the official release notes page the row's `prompt` names for a Claude model
   release of the class it names **after** that date.
3. If **no**: run nothing and recheck-close. Cite the page and its newest model entry,
   set `last_checked` to the date you read it, and advance `next_due` by the cadence.
4. If **yes**: run the pass, and cite the release in the claim and recheck comments.
5. If the page cannot be read: do not claim and do not recheck-close. Leave the
   issue open and report why.

The release notes page is the release oracle, so an agent can settle the check. A row
sets `requires_operator_confirmation: true` only when a person must confirm it.

## Seam helper

`plugins/work-items/scripts/evaluate-schedule-precondition.sh` prints `met`,
`unmet`, or `needs-confirmation` for a schedule row id. Pass
`--operator-confirmed` when the operator has affirmed a confirmation-style
precondition. For a row with no operator gate, `met` means only that nothing
holds the row: the script prints the row's `prompt` ahead of it, and the caller
settles the check with the `id` steps above before running the pass.
