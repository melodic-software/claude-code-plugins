# architecture: consumer configuration

The architecture `map-*` skills' team configuration surface: a natural-language **topic doc at the
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
   run, every `map-*` skill stops and points at `/architecture:setup`.

## Topic-doc format

Markdown with a fenced YAML block (human-readable, shell-greppable):

````markdown
# architecture conventions

```yaml
architecture_dir: docs/architecture   # repo-relative; no default
landscape_dialect: mermaid            # structurizr | mermaid
component_layers: host, application, domain  # optional; outside to inside; no default
```
````

## Keys

| Key | Values | Default | Meaning |
|---|---|---|---|
| `architecture_dir` | repo-relative directory path | **none** | Where every `map-*` skill writes its record and its rendered view. `map-landscape` writes `landscape.json`, `landscape.dsl` / `landscape.md`, and `portfolio.md`, and reads `landscape-notes.md`. The other skills write their own records in this same directory (`dependency-graph.json`, `context.json`, `containers.json`, `flow.json`, `events.json`, `data-model.json`, `deployment.json`, `states.json`) and the matching rendered `.md` files. No default: an undeclared, unconfirmed value stops the skill rather than picking a directory. `--out <dir>` overrides it for one run. |
| `landscape_dialect` | `structurizr` \| `mermaid` | `mermaid` | Which landscape artifact `map-landscape` emits. `structurizr` emits `landscape.dsl` with a `systemLandscape` view; `mermaid` emits `landscape.md` with a `C4Context` block. No other `map-*` skill reads it; see the dialect decision below. |
| `component_layers` | comma-separated layer names | **none** | Optional. Ordered from outside to inside. `/architecture:map-components --group-by layer` reads it. Absent, that grouping cannot run. A name is letters, digits, `.`, `_`, or `-`. |

An unknown key, a `landscape_dialect` value outside the two above, or a `component_layers` value
that is not a comma-separated list of layer names, is reported by `/architecture:setup check` as
a FAIL with a remediation line. It is never silently ignored and never coerced to the default.
`component_layers` absent is a PASS: the key is optional.

## C4 dialect surfaces

This plugin owns one dialect key, `landscape_dialect`, for one artifact. Every other `map-*`
picture takes its dialect from the authoring-formats convention, which owns
`diagram_dialect.system` and `diagram_dialect.data`.

| Artifact | Key | Owner | Allowed values | Default | Emitter |
|---|---|---|---|---|---|
| C4 system landscape | `landscape_dialect` | this document | `structurizr`, `mermaid` | `mermaid` | `/architecture:map-landscape` |
| C4 container view of a design | `diagram_dialect.system` | authoring-formats convention | `likec4`, `c4-plantuml` | none (opt-in) | `/planning:design` |
| C4 component, system context, container, and deployment views of the code | `diagram_dialect.system` | authoring-formats convention | `likec4`, `c4-plantuml` | none (opt-in) | `/architecture:map-components`, `/architecture:map-context`, `/architecture:map-containers`, `/architecture:map-deployment` |
| Data diagram | `diagram_dialect.data` | authoring-formats convention | `mermaid`, `dbml` | `mermaid` | `/planning:design`, `/architecture:map-data` |

## Map family dialect decision

Recorded by the operator on
[#4639](https://github.com/melodic-software/claude-code-plugins/issues/4639) (2026-09-28): the
C4-shaped `map-*` views do not default to mermaid C4. Each child reads the dialect key the
authoring-formats convention assigns to its diagram kind, the same rule every other diagram in
this repository follows. Where the convention refuses mermaid (`diagram_dialect.system`), the map
views refuse it too. No per-skill dialect key is added.

| Skill | Dialect |
| --- | --- |
| map-components, map-context, map-containers, map-deployment | `diagram_dialect.system` (`likec4` or `c4-plantuml`, no default) |
| map-data | `diagram_dialect.data` (`mermaid` or `dbml`, default `mermaid`) |
| map-flow | no dialect key; a mermaid `sequenceDiagram` |
| map-events | no dialect key; a mermaid `flowchart` of publish, send, and consume |
| map-dependencies | no dialect key; a mermaid `flowchart` of the build graph |
| map-states | no dialect key; a mermaid `stateDiagram-v2` |
| map-landscape | `landscape_dialect`, unchanged |

The four C4 views resolve `diagram_dialect.system` through
`${CLAUDE_PLUGIN_ROOT}/lib/resolve-diagram-dialect.sh --kind system`. `likec4` writes the view's
`.md` file with one fenced `likec4` block; `c4-plantuml` writes it with one fenced `plantuml`
block, the fence tags `/planning:design` uses. With the key unset, absent, or set to a value
outside the allowed set (mermaid included), the skill still writes its JSON record and its `.md`
file with the prose and tables, draws no diagram block, and reports `unset (no C4 view emitted)`,
as `/planning:design` still writes `component-map.md` as prose when the key is unset.

The convention keys two diagram kinds: data diagrams and C4 system views. A traced call sequence
and a message topology are neither, so `map-flow` and `map-events` follow the repository's
unkeyed rule for those shapes, the one `/planning:design` applies to its `sequenceDiagram`
flows. Neither emits mermaid C4.

`landscape_dialect` keeps its mermaid default: it predates this decision, and the convention gives
a landscape no key. The mermaid-C4 experimental fact and its recheck trigger live in the
authoring-formats convention
([Why mermaid is not offered for the system key](../../../docs/conventions/authoring-formats/README.md#why-mermaid-is-not-offered-for-the-system-key)).
This document does not carry a second stamp. That trigger fires when the experimental banner
drops or when mermaid documents a dedicated landscape type. On firing, re-derive whether this
key's mermaid default should change and whether `/architecture:map-landscape`'s mermaid output
should use a dedicated landscape type instead of a `C4Context` diagram without a focal system,
and record the outcomes in this plugin's `CHANGELOG.md`.

## What writes this surface

Only `/architecture:setup apply`, and only two artifacts: the marked `convention-home` pointer
region in the root instruction file, and `<home>/architecture/README.md`. Every `map-*` skill
reads this surface and never writes it. `map-data` also reads `<home>/authoring-formats/README.md`
for `diagram_dialect.data`, and `map-components`, `map-context`, `map-containers`, and
`map-deployment` read it for `diagram_dialect.system`; none of them writes that file. None of
these skills writes any other file in the consumer's root.
