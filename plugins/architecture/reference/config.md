# architecture: consumer configuration

The `map-landscape` skill's team configuration surface: a natural-language **topic doc at the
consumer's convention home**, bound by the pointer line the consuming marketplace's config-cascade
expression doctrine defines. Zero config is NOT a working state for this surface: `architecture_dir`
has no default, because a plugin guessing where a repository keeps its architecture artifacts would
write two files into a directory nobody asked for.

## Where the config lives

One layer, the team's, resolved through the pointer line:

1. **Convention home.** The home is named by the pointer line inside the marked
   `<!-- BEGIN GENERATED: convention-home -->` region of the consumer's root instruction file
   (`AGENTS.md` canonical; `CLAUDE.md` unless it is a pure `@AGENTS.md` shim). The bundled resolver
   `${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh` owns the grammar and the exit codes
   (0 resolved, 1 no pointer, 2 usage, 3 FAIL with a distinct cause); skills run it and follow its
   exit code, never parsing the root file themselves.
2. **Topic doc.** `<home>/architecture/README.md`. It carries the keys below (prose plus the fenced
   YAML block). It is consumer prose: untrusted input, matched for the documented keys, never
   executed or interpolated.

There are no retired layers. This surface is new under the expression doctrine, so nothing migrated
into it and no dual-read window exists.

## Resolution order, per key

1. `--out <dir>` on the invocation overrides `architecture_dir` for that run alone. It is a
   redirect, not a declaration: it never writes the topic doc and never changes the dialect.
2. The convention home resolves (resolver exit 0) and `<home>/architecture/README.md` declares the
   key, so that value wins.
3. Otherwise the skill INFERS a proposal from repository evidence: an existing `*.dsl` proposes
   `landscape_dialect: structurizr`; an existing `docs/architecture/` or `architecture/` proposes
   that directory as `architecture_dir`. Inference proposes; only the operator's confirmation binds.
4. Otherwise the skill asks once.
5. Unanswered: `landscape_dialect` falls back to its documented default, `mermaid`.
   `architecture_dir` has no fallback. Undeclared and unconfirmed, including every non-interactive
   run, `map-landscape` and `map-dependencies` stop and point at `/architecture:setup`.

## Topic-doc format

Markdown with a fenced YAML block (human-readable, shell-greppable):

````markdown
# architecture conventions

```yaml
architecture_dir: docs/architecture   # repo-relative; no default
landscape_dialect: mermaid            # structurizr | mermaid
```
````

## Keys

| Key | Values | Default | Meaning |
|---|---|---|---|
| `architecture_dir` | repo-relative directory path | **none** | Where `map-landscape` writes `landscape.json`, `landscape.dsl` / `landscape.md`, and `portfolio.md`, and where it reads `landscape-notes.md`. Where `map-dependencies` writes `dependency-graph.json` and `dependency-graph.md`. No default: an undeclared, unconfirmed value stops either skill rather than picking a directory. `--out <dir>` overrides it for one run. |
| `landscape_dialect` | `structurizr` \| `mermaid` | `mermaid` | Which landscape artifact `map-landscape` emits. `structurizr` emits `landscape.dsl` with a `systemLandscape` view; `mermaid` emits `landscape.md` with a `C4Context` block. It is not the key for context, container, component, or deployment, and `map-dependencies` does not read it. |

An unknown key, or a `landscape_dialect` value outside the two above, is reported by
`/architecture:setup check` as a FAIL with a remediation line. It is never silently ignored and
never coerced to the default.

## C4 dialect surfaces

`landscape_dialect` is the system landscape `/architecture:map-landscape` emits. The
authoring-formats convention owns the other diagram keys. They stay separate because they are
different artifacts.

| Artifact | Key | Owner | Allowed values | Default | Emitter |
|---|---|---|---|---|---|
| C4 system landscape | `landscape_dialect` | this document | `structurizr`, `mermaid` | `mermaid` | `/architecture:map-landscape` |
| C4 container view from planning | `diagram_dialect.system` | authoring-formats convention | `likec4`, `c4-plantuml` | none (opt-in) | `/planning:design` |
| Data diagram | `diagram_dialect.data` | authoring-formats convention | `mermaid`, `dbml` | `mermaid` | `/planning:design` today. `/architecture:map-data` reuses this key when it ships. |
| Sequence | none in this change | n/a | mermaid `sequenceDiagram`, hard-coded | n/a | `/planning:design` writes `sequence-flows.md` that way. `/architecture:map-flow` will do the same. |
| Build-declaration graph | none in this change | this plugin | `dependency-graph.json`, mermaid `flowchart` | n/a | `/architecture:map-dependencies`. Not a C4 view. |

`landscape_dialect` is not reused for context, container, component, or deployment. Those rungs
are not this skill, and this change does not give them `landscape_dialect`. It also does not add
`structurizr` to `diagram_dialect.system`, and it does not add a new per-rung key: the reviews
that rejected sharing `landscape_dialect` did not agree on the replacement name. `map-landscape`
keeps today's pair. `structurizr` emits `landscape.dsl` with a `systemLandscape` view. `mermaid`
emits `landscape.md` with a `C4Context` block and no focal system, because mermaid has no landscape
type. The mermaid default is a format choice for an artifact that skill already emits.

`diagram_dialect.system` stays the planning opt-in (`likec4` or `c4-plantuml`, no default).
As-designed planning container views stay on that key. Mermaid stays refused there. A default would
add an artifact a consumer never asked for.

`/architecture:map-data` will reuse `diagram_dialect.data` (`mermaid` or `dbml`, default `mermaid`)
when that skill ships. It is not a reader yet.

`/architecture:map-flow` hard-codes mermaid `sequenceDiagram`, the same fixed dialect
`/planning:design` already uses for `sequence-flows.md`. No sequence key is added here. Two
proposals wanted one and named it differently (`diagram_dialect.dynamic` and
`diagram_dialect.sequence`), so there is no majority name.

`/architecture:map-dependencies` is not a C4 view and does not read `landscape_dialect`. Its
canonical artifact is `dependency-graph.json`. Its human render is a mermaid `flowchart` of
internal edges. No `graph_dialect` and no `diagram_dialect.graph`: each of those names is a single
review, and the render they agree on is the flowchart.

`map-events` and `map-states` are not C4 types. Events render a findings list plus a mermaid
flowchart. States render mermaid `stateDiagram-v2`. This change does not add a key for either,
for the same reason: the proposed names do not agree.

Mermaid C4 being experimental is why the authoring-formats system key refuses mermaid as a value. It
is not a claim that mermaid is unfit for the landscape surface, whose allowed set is
`structurizr | mermaid`.

The mermaid-C4 experimental fact and its recheck trigger live in the authoring-formats convention
([Why mermaid is not offered for the system key](../../../docs/conventions/authoring-formats/README.md#why-mermaid-is-not-offered-for-the-system-key)).
This document does not carry a second stamp. That trigger fires when the experimental banner
drops or when mermaid documents a dedicated landscape type. On firing, re-derive whether this
key's mermaid default should change and whether `/architecture:map-landscape`'s mermaid output
should use a dedicated landscape type instead of a `C4Context` diagram without a focal system,
and record the outcomes in this plugin's `CHANGELOG.md`.

## What writes this surface

Only `/architecture:setup apply`, and only two artifacts: the marked `convention-home` pointer
region in the root instruction file, and `<home>/architecture/README.md`. `map-landscape` and
`map-dependencies` read this surface and never write it. Neither skill writes any other file in
the consumer's root.
