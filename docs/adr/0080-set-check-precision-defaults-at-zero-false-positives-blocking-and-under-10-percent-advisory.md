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

Google's published bar for static analysis ([Tricorder](#sources)) is the model here: a check that blocks a change is held
to no tolerated false positives, and a check that only advises is held to a small, stated
ceiling. This repository needs the same two numbers, plus the rules for the cases a number cannot
cover.

## Decision

A check's precision default depends on whether it blocks or advises.

- **A blocking check ships with 0 effective false positives on its corpus.** An effective false
  positive is any finding the author does not act on to resolve: a finding the author dismisses,
  or clears with an exception instead of fixing, counts as one. On the corpus sweep, that is any
  finding the check's owner would not fix in the code it flags.
- **An advisory check stays under 10% false positives.** The 10% is a corpus-precision proxy, not a
  measured per-guard rate: it is read off the corpus sweep ADR 0003 requires before shipping, and
  says nothing about how often a reader acts on the advisory in use.
- **`feedback.disable_not_useful_ratio` is not adopted** until #3756 produces a per-guard signal.
  Without that signal the ratio has nothing to read, so the setting is left out rather than shipped
  inert.
- **Exceptions expire after 90 days by default**, as a team setting. A team may set another value;
  the default is the judgment recorded here.
- **Break glass is an inline exception that carries a reason, an expiry and a person's approval.**
  An exception missing any of the three does not count as one. Break glass stays available for
  any finding, and each break-glass exception filed against a blocking check counts as an
  effective false positive, so a blocking check that needs one does not meet the 0 bar.
- **Existing guards keep their recorded justification.** Nothing is re-graded by this ADR; a guard
  that shipped under ADR 0003's judgment keeps that record until it is graded on its own evidence.

This ADR records defaults only. It adds no setting to a plugin and edits no guard.

## Consequences

- The enforcement ladder's guardrail criterion (`docs/conventions/enforcement-ladder/README.md`)
  will read these numbers once that criterion lands (the ladder-v2 slice under #7572): it will
  decide whether a rule earns a blocking or an advisory check, and cite the bar that check must
  meet. The ladder has no guardrail criterion yet.
- #3756 is the open work that grades guards. Until it lands, the 10% stays a proxy and
  `feedback.disable_not_useful_ratio` stays out.
- ADR 0003's remaining rules (measure before shipping, report the number in the PR, the zero-finding
  treatment, one mechanism per concern) stand unchanged. Only its choice not to fix a threshold is
  amended.
- No plugin setting or script reads `feedback.disable_not_useful_ratio` or `exceptions.max_days`
  yet. A later change adds the exception setting; the ratio waits on #3756.

## Sources

- [Sadowski et al., "Tricorder: Building a Program Analysis Ecosystem", ICSE 2015](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/43322.pdf):
  defines an effective false positive as "any report from the tool where a user chooses not to
  take action to resolve the report". For analyses that break the build, "the effective false
  positive rate must be essentially zero"; at code review, "We still enforce a very low effective
  false positive rate here (< 10%)". The paper measures its 10% in use, as a not-useful click
  rate; this ADR's 10% is a corpus proxy until #3756 gives a per-guard signal.
- [#8537](https://github.com/melodic-software/claude-code-plugins/issues/8537): the slice that
  specifies these defaults and the decisions behind each.
