# Narrow D100 to pull requests tidied in their own run

- Status: accepted
- Date: 2026-11-06
- Amends: [ADR 0075](0075-resolve-plugin-settings-through-one-four-layer-cascade-and-a-bound-convention-home.md),
  the policy-floor rule's D100 floor

## Context

D100 (#7576) turned CI `fix-docs` off (`limits.fix-docs-per-run: 0`), and ADR 0075 lists it among
the fixed floors that may only be tightened. #13717 moves tidying before review as a Refine stage.
A work-resolve-issue run already tidies its own change when the change is within resolve-issue's
tidy cutoffs (#8485); other pull requests get no tidy before review. In the 10-30 to 11-06 sample,
fix-docs pushed a patch on 0 of 55 lane pull request runs and on 2 of 95 others
([#8485](https://github.com/melodic-software/claude-code-plugins/issues/8485#issuecomment-6685275672)).

## Decision

The owner approved this on 2026-11-06, verbatim: "Approve D100 reversal: CI fix-docs on for PRs not
tidied in their own run (#13818)".

- CI `fix-docs` runs on every ready pull request whose tidy did not run inside its own run
  (`limits.fix-docs-per-run: 2`).
- It skips a work-resolve-issue pull request whose head is still the lane run's one API commit and
  whose change is within the tidy cutoffs.
- D100 stays a fixed floor for that skip: it may only be tightened from here.

## Consequences

- Human pull requests get a tidy pass before review; resolve-issue pull requests do not get a
  second one.
- The skip reads the cutoffs in the base config when it dispatches, not the ones the lane run
  used, so a lane pull request over the cutoffs when it ran can be skipped after the cutoffs rise.
