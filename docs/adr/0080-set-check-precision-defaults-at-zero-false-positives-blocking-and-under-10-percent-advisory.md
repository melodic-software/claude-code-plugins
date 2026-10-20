# Set check precision defaults at zero false positives blocking and under 10% advisory

- Status: accepted
- Date: 2026-10-20
- Amends: [ADR 0003](0003-verification-guards-earn-default-on-by-measured-precision.md)
- Refs: [#7572](https://github.com/melodic-software/claude-code-plugins/issues/7572)

## Context

[ADR 0003](0003-verification-guards-earn-default-on-by-measured-precision.md) says a guard earns
default-on by measured precision, and deliberately states no number: "acceptable precision" is a
judgment, and its reference guard shipped at 57% precision. That left every guard author to name a
ratio and justify it alone, and left a reviewer nothing to hold the claim against.

Google's published bar for static analysis is the model here: a check that blocks a change is held
to no tolerated false positives, and a check that only advises is held to a small, stated
ceiling. This repository needs the same two numbers, plus the rules for the cases a number cannot
cover.

## Decision

A check's precision default depends on whether it blocks or advises.

- **A blocking check ships with 0 effective false positives on its corpus.** "Effective" means a
  finding that survives the check's own exception rules: a finding an author can clear with a
  recorded exception is not counted, one they cannot clear is.
- **An advisory check stays under 10% false positives.** The 10% is a corpus-precision proxy, not a
  measured per-guard rate: it is read off the corpus sweep ADR 0003 requires before shipping, and
  says nothing about how often a reader acts on the advisory in use.
- **`feedback.disable_not_useful_ratio` is not adopted** until #3756 produces a per-guard signal.
  Without that signal the ratio has nothing to read, so the setting is left out rather than shipped
  inert.
- **Exceptions expire after 90 days by default**, as a team setting. A team may set another value;
  the default is the judgment recorded here.
- **Break glass is an inline exception that carries a reason, an expiry and a person's approval.**
  An exception missing any of the three does not count as one.
- **Existing guards keep their recorded justification.** Nothing is re-graded by this ADR; a guard
  that shipped under ADR 0003's judgment keeps that record until it is graded on its own evidence.

This ADR records defaults only. It adds no setting to a plugin and edits no guard.

## Consequences

- The enforcement ladder's guardrail criterion (`docs/conventions/enforcement-ladder/README.md`)
  is the reader of these numbers: it decides whether a rule earns a blocking or an advisory check,
  and cites the bar that check must meet.
- #3756 is the open work that grades guards. Until it lands, the 10% stays a proxy and
  `feedback.disable_not_useful_ratio` stays out.
- ADR 0003's remaining rules (measure before shipping, report the number in the PR, the zero-finding
  treatment, one mechanism per concern) stand unchanged. Only its choice not to fix a threshold is
  amended.
- `feedback.disable_not_useful_ratio` and the 90-day exception setting exist only in this decision
  record; no file under `docs`, `plugins` or `scripts` carries either until a later change adds
  them.
