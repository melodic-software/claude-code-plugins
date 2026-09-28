# native-overlap: store `integration` axis and wrap/suggest grammars

Recorded park for
[#4049](https://github.com/melodic-software/claude-code-plugins/issues/4049),
unit 2 of the native-overlap effort (parent [#4047](https://github.com/melodic-software/claude-code-plugins/issues/4047)).

## Decision

**Parked, unpaid.** This repository does not add a required `integration` field
to the native-surfaces store, and does not take a major version of the
native-references convention for wrap and suggest grammars.

**Claim:** the store stays schema 1 without `integration`; native-references
stays 1.1.0 with the route phrase and Boundary section only. Skill-body Native
step and suggest sentences already shipped by later units stand. The contract
expansion those units wait on does not ship until funded.
**Basis:** #4049 (C4; `work-class: structural`, `needs-human`);
`docs/specs/native-overlap-integration-design.md` type sketch;
`docs/native-surfaces/records.json` on origin/main (schema 1, 22 rows, no
`integration` key; `baked.native_step` true on `testing:run-e2e`;
`baked.suggest_sentence` true on the three `session-flow` `/export` rows);
`docs/conventions/native-references/CHANGELOG.md` newest heading 1.1.0.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds the store field plus the native-references
major bump (enforceability row and second gate token, per the convention's
Versioning section) and unparks #4049.

## What stays

- Unit 1 tooling (#4048 / #4092).
- Boundary sections required on non-`defer` extraction rows (native-references
  1.1.0).
- Native step and suggest sentences already baked into skill bodies by later
  sweep units. Those are skill text, not store-required `integration` values
  and not convention grammars.

## What does not ship

- Required `row.integration` in `{route, wrap, suggest}` and the overlap
  self-check rules that reject illegal combinations.
- `baked.native_step` / `baked.suggest_sentence` as flags that are true only
  with matching `integration` (the flags exist; the coupling does not).
- native-references wrap grammar (`## Native step: <name> (<class>)`) and
  suggest grammar (`If /<name> is available in your session (`), as contract.
- Treating the two extra `export` store rows (already present from #4056) as
  the #4049 schema expansion. Their `suggest_sentence` flags are skill-body
  parity, not a required `integration` value.
- An apply-step rewrite of `/claude-ops:audit-native-overlap` that emits Native
  step sections and suggest sentences from `integration`.

## Rationale

- The unit is a contract change: a required store field and a major convention
  bump. C4 work stays human-gated and unpaid on this lane.
- Later units already wrote skill-body text around the missing field. Filling
  the schema from those bodies without the funded convention bump would invent
  a contract the Versioning section does not yet carry.
- Parent #4047 remains the epic. This file parks unit 2 only.

## Revisit when

- A maintainer unparks #4049 and funds the schema plus convention change, or
- native-references takes a major bump for another reason and the wrap/suggest
  grammars are in that bump's scope.

## Prior requests

- #4049 (2026-09-28): policy unit of the native-overlap sweep; drain shipper
  parks the unpaid store and grammar expansion.
