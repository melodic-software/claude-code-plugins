# Issue conventions

The shape of a well-formed tracker item — title, body, type, labels, close reason. This document is
the **single source of truth for the title convention**; for the other four it **points** at the
existing owner rather than restating it, so each of those rules stays in one place.

## Title

`<prefix>: <lowercase summary>` — no trailing period. Derived from established org usage. Two prefix
dialects are accepted:

- **Area / path form** — `<plugin>`, `<plugin>/<skill>`, or `<plugin>:<skill>`
  (e.g. `work-items/triage: reconcile state machine with live labels`).
- **Conventional-commit form** — `<type>(<scope>)`
  (e.g. `feat(toolchain): add pyright to python ecosystem check-cmd`).

Umbrella / epic items use an `Epic:` prefix or a trailing `(umbrella)`. A child-of relationship is
recorded as a native sub-issue edge, **never** as a title suffix.

Recurring maintenance items keep the `[Maintenance] {title}` shape owned by `track add --recurring`
(the due / work / recheck flows exact-match that prefix); they are exempt from the two prefix dialects.

## Body

Follows the `track add` "Build body" template — the default skeleton, or the agent-brief shape for
autonomous-eligible items. See [`../skills/track/actions/add.md`](../skills/track/actions/add.md)
"Build body" and [`agent-brief.md`](agent-brief.md); not restated here.

## Type and labels

The issue type resolves through `track add`'s type-resolution step (native Issue Type on org repos,
`type:` label otherwise) — see [`../skills/track/actions/add.md`](../skills/track/actions/add.md)
"Resolve the issue type". Label axes and their grammar live in [`label-taxonomy.md`](label-taxonomy.md).

## Close reason

`completed` vs `not planned` — decided-against and superseded items take `not planned`; a duplicate
takes the provider's native `duplicate` reason where it has one, `not planned` otherwise — follows the
`done` action's close discipline: [`../skills/track/actions/done.md`](../skills/track/actions/done.md).
