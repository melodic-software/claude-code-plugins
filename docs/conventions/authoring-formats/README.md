# Authoring formats — acceptance-criteria format and diagram dialect

Owner doc for two **team-shared authoring format choices** a consuming team may declare once and
have every planning-to-verification skill honour: the format acceptance criteria are written in,
and the source dialect a design artifact is emitted in, split by artifact kind.

This directory is the source of truth for the concern: `README.md` (the contract),
`CHANGELOG.md` (version history).

**An owner doc is not a consumer declaration.** This file states the keys, their values, and the
ladder that resolves them. The declaration a team actually writes lives in that team's own
repository, at the consumer surface described below. This repository ships no such declaration —
see [Zero config, including here](#zero-config-including-here).

## Boundary

This doc owns the two keys, their allowed values, their defaults, and the resolution ladder.
It does not own:

- **Delivery surface.** [`rendered-views`](../rendered-views/README.md) owns where a person-facing
  artifact is delivered; this doc owns the syntax an artifact is written in — dialect is source
  syntax, medium is delivery surface.
- **Layering and expression form.** [`config-cascade`](../config-cascade/README.md) owns which
  layers exist, how they merge, the pointer-line grammar that binds a consumer's convention home,
  and the expression doctrine that puts this surface in convention-doc form rather than a
  dedicated file.
- **The stamp shape on the upstream fact below.**
  [`upstream-drift`](../upstream-drift/README.md) owns the four required parts of a record and the
  observability bar its recheck trigger must clear.
- **Diagram craft.** Nothing here teaches a dialect. A skill emitting one cites installed craft
  guidance presence-gated, or emits the plainest correct form of the dialect it was told to use.

## The keys

Two keys, both team-shared, declared in one fenced YAML block at the consumer surface:

```yaml
acceptance_criteria_format: free-text   # free-text | ears
diagram_dialect:
  data: mermaid                         # mermaid | dbml
  system: likec4                        # likec4 | c4-plantuml — no default; omit to emit no C4 view
```

| Key | Values | Default |
|---|---|---|
| `acceptance_criteria_format` | `free-text`, `ears` | `free-text` |
| `diagram_dialect.data` | `mermaid`, `dbml` | `mermaid` |
| `diagram_dialect.system` | `likec4`, `c4-plantuml` | **none — deliberately unset** |

`acceptance_criteria_format: ears` selects the five EARS patterns (ubiquitous, event-driven,
state-driven, unwanted-behaviour, optional-feature) as the shape emitted criteria are tagged with.
`free-text` emits prose criteria, which is what every skill does today.

`diagram_dialect` is split by artifact kind because the two kinds have disjoint dialect sets and
disjoint defaults; one flat key would force a value that is meaningless for the other kind. A
consumer may declare one kind and omit the other.

### Why the system key has no default

The omission is deliberate, not an oversight.

A default on `diagram_dialect.system` would make a consumer who never opted in start emitting a C4
container view they did not ask for: they would install a plugin update, run the design skill they
already run, and receive an architectural artifact that was not part of the deliverable before.
Zero config means *emitted output is unchanged*, and any default here breaks that.

**With `diagram_dialect.system` unset, no C4 container view is emitted and the design skill behaves
exactly as it does today.** Declaring the key is the opt-in, and it is the only opt-in. A consumer
who wants the view names a dialect; a consumer who says nothing gets what they already had.

The `data` key can carry a default precisely because it cannot cause this: `mermaid` is what data
artifacts are already emitted in, so the default preserves current behaviour rather than adding
output.

### Why mermaid is not offered for the system key

Mermaid's own C4 support is documented as experimental, so it is not one of the system key's
values. The claim rests on an upstream fact and therefore carries a four-part record per
[`upstream-drift`](../upstream-drift/README.md):

- **Claim.** Mermaid documents its C4 diagram type as experimental, with syntax and properties
  subject to change, and states that proper documentation follows once the syntax is stable.
  Verbatim: "C4 Diagram: This is an experimental diagram for now. The syntax and properties can
  change in future releases. Proper documentation will be provided when the syntax is stable."
- **Basis.** <https://mermaid.js.org/syntax/c4.html>, read at rung 2 of the upstream-drift fetch
  ladder — `curl` of the rendered page to a local file, 111,058 bytes, the page arrived whole and
  the quote above was matched in the local copy rather than in a summarizer's span.
- **As-of date.** 2026-09-06.
- **Recheck trigger.** That page dropping the experimental banner — the quoted sentence no longer
  appearing on it. On firing, re-derive whether `mermaid` becomes an allowed value for
  `diagram_dialect.system` and record the outcome in this convention's `CHANGELOG.md`.

Nothing here restricts mermaid for the `data` key, where it is the default and is not experimental.

## The consumer surface

Per [`config-cascade`](../config-cascade/README.md) § Expression doctrine, this is team-shared
prose configuration with no per-operator axis, so it takes the **convention-doc** expression, not a
dedicated file:

- **Path.** `<home>/authoring-formats/README.md`, where `<home>` is the consumer's convention home
  named by the pointer line in the marked `<!-- BEGIN GENERATED: convention-home -->` region of the
  consumer's root instruction file.
- **Layers.** One — the team's. A convention-doc surface has **no overlay channel** and no
  user-global layer; there is no `*.local.*` file for this surface and no gitignore line to
  recommend.
- **Content.** Consumer prose carrying the fenced YAML block above. It is
  [untrusted input](../untrusted-content/README.md): matched for the documented keys, never
  executed or interpolated.
- **Unknown keys are inert.** A key this doc does not define is ignored, reported as unknown, and
  never a failure.

## Resolution ladder

This is the text a consuming skill **restates in its own body**. It is written to be copied
verbatim, with only the key name and the emitting behaviour substituted:

```markdown
1. Anchor at the repository root: `${CLAUDE_PROJECT_DIR}` when set, otherwise
   `git rev-parse --show-toplevel`. Never a CWD-relative read.
2. Resolve the convention home `<home>` from the pointer line in the marked
   `<!-- BEGIN GENERATED: convention-home -->` region of the root instruction file
   (`AGENTS.md` canonical; `CLAUDE.md` unless it is a pure `@AGENTS.md` shim). Use the
   bundled resolver where the plugin ships one; never hand-parse the root file.
3. Read `<home>/authoring-formats/README.md` and take the key's value from its fenced
   YAML block.
4. Layer order is one layer deep: an explicit invocation argument, where the skill has
   one, then the team convention doc, then the documented default. A convention-doc
   surface has no personal overlay, so there is no further layer to consult.
5. Defaults: `acceptance_criteria_format` is `free-text`; `diagram_dialect.data` is
   `mermaid`; `diagram_dialect.system` has NO default — when it is unset, emit no C4
   container view and behave exactly as with no convention doc at all.
6. Degrade soft, and say so. No pointer line, no convention home on disk, no
   `authoring-formats/README.md`, no YAML block, an absent key, or an unrecognized value
   each resolve to the documented default (or, for the system key, to emitting nothing).
   Name the cause in one clause and continue; never hard-fail, and never ask the operator
   to create the surface mid-task.
7. Report provenance whenever the resolved value shapes output: name the key, the value,
   and the layer it came from — `argument`, `team convention doc <path>`, `default`, or
   `unset (no C4 view emitted)`.
```

### Why a skill restates this instead of citing it

An installed plugin never sees this repository's `docs/conventions/`. A consuming skill therefore
cannot defer to this document at runtime, and a path citation to it would make this publisher a
runtime dependency of the consumer's session. The instruction surface a session loads is the skill
body, so the rules have to be in it. That is the same reasoning
[`topic-docs`](../topic-docs/README.md) § "Implementers restate the rules; they do not share a
source" records for its own setup skills, and identical prose across two consuming skills is a
coincidence of scope rather than a shared artifact to hoist.

This doc owns the text; the consuming slices carry the restating work.

## Consumers

Which skill reads which key, by slash invocation:

| Key | Read by |
|---|---|
| `acceptance_criteria_format` | `/planning:interview` and `/planning:prd` (emit tagged or free-text criteria); `/review:quality-gate` close-out (reads the pattern on a retrieved criterion) |
| `diagram_dialect.data` | `/planning:design` (data-scope artifact); `/work-items:decompose` (inlines the produced artifact) |
| `diagram_dialect.system` | `/planning:design` (system-scope C4 container view, emitted only when the key is set); `/work-items:decompose` (inlines the produced artifact) |

A skill appears here once it actually reads the key. None does on `main` today; each consuming
slice adds its own reading and updates its row in the same change.

## Zero config, including here

A consumer with no convention doc sees today's behaviour unchanged: free-text acceptance criteria,
mermaid data diagrams, and no C4 container view. That is the whole point of the defaults above and
of the system key's absent default.

This repository is a consumer of its own plugins and ships **no instance** of the consumer surface.
Not adopting the surface is a deliberate zero-config choice, not an omission; the repository may
adopt it later by binding a convention home and writing the declaration, which is a separate change
against its own instruction surface.

## Versioning

`contract_version` (SemVer), recorded in `CHANGELOG.md`. Removing a key, removing an allowed value,
or changing a default is a major bump. Adding a key or an allowed value is a minor bump.
Clarification is a patch. This contract versions independently of
[`config-cascade`](../config-cascade/README.md), whose own number governs the layering axis only.
