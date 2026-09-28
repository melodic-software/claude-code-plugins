# Native-overlap integration axis

Park for [#4049](https://github.com/melodic-software/claude-code-plugins/issues/4049).

## Decision

**Do not add an integration axis to the native-overlap store, and do not add
`wrap` and `suggest` grammars, in this session.** The issue is `needs-human`
and `work-class: structural`. The store verdict is human-written. Parent epic
#4047.

**Claim:** The integration axis and the two grammars are a schema change to
the overlap store plus every consumer of `native-references`. That is not a
scoped fix on top of the current rows.
**Basis:** #4049 "What to build" and "Blocked by". #4048 (the bundled-skill
lane recovery) is closed. No origin/main change adds the integration axis.
The native nomination in #4027 also says no row is written to
`docs/native-surfaces/records.json` without a human verdict.
**As of:** 2026-09-28.
**Recheck:** A maintainer writes the store verdict for the integration axis
and names the `wrap` and `suggest` grammar. Until that verdict exists, do not
grow the store.

## What this close is not

Not a close of sweep units #4050 and #4051. Those stay open.
