# Authoring-formats convention — changelog

Notable changes to the authoring-formats contract. Per the README's Versioning section, removing a
key, removing an allowed value, or changing a default is a major change; adding a key or an allowed
value is minor; clarification is a patch. Recheck-trigger firings on the Mermaid-C4 record land
here with their outcome, drift or no drift.

## 1.0.0 — 2026-09-06

First release. Registers the concern, declares both keys, and states the resolution ladder
consuming skills restate.

- **`acceptance_criteria_format`** — `free-text` (default) or `ears`. `free-text` is today's
  behaviour; `ears` selects the five EARS patterns as the shape emitted criteria are tagged with.
- **`diagram_dialect`, split by artifact kind.** `data` takes `mermaid` (default) or `dbml`;
  `system` takes `likec4` or `c4-plantuml` and has **no default**. The system key is deliberately
  defaultless: a default would make a consumer who never opted in start emitting a C4 container
  view they did not ask for. Unset, no C4 view is emitted and the design skill behaves exactly as
  it does today. The `data` key can carry a default because `mermaid` is already what those
  artifacts are emitted in, so the default adds no output.
- **Mermaid is not offered for the system key**, carrying a four-part upstream-drift record —
  claim (Mermaid documents its C4 diagram type as experimental), basis
  (<https://mermaid.js.org/syntax/c4.html>, rung-2 `curl` read, 111,058 bytes, page arrived whole),
  as-of date (2026-09-06), and recheck trigger (that page dropping the experimental banner).
- **Consumer surface in convention-doc expression** — `<home>/authoring-formats/README.md`, one
  layer (team, via the pointer line), no overlay channel, unknown keys inert. Neither key is a
  plugin-manifest option: a team-shared format choice has no per-operator axis, per
  `docs/PLUGIN-PHILOSOPHY.md` § Configuration ownership and scope.
- **Resolution ladder** stated in a copyable block: anchor, home resolution, read, layer order,
  defaults, soft degrade, provenance reporting. A consuming skill restates it rather than citing
  this file, because an installed plugin never sees this repository's `docs/conventions/`.
- **Registered** in the convention registry in `docs/PLUGIN-PHILOSOPHY.md` and in the
  [config-cascade](../config-cascade/README.md) Implementers table.

No skill reads either key on `main` at this release. The consuming changes are separate slices,
each of which adds its own reading and updates the Consumers table in the same change.
