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
5. Unanswered: `landscape_dialect` falls back to its documented default, `mermaid`, for every
   skill that reads it. `architecture_dir` has no fallback. Undeclared and unconfirmed, including
   every non-interactive run, every `map-*` skill stops and points at `/architecture:setup`.

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
| `architecture_dir` | repo-relative directory path | **none** | Where every `map-*` skill writes its record and its rendered view. `map-landscape` writes `landscape.json`, `landscape.dsl` / `landscape.md`, and `portfolio.md`, and reads `landscape-notes.md`. The other skills write their own records in this same directory (`dependency-graph.json`, `components.md` / `components.dsl`, `context.json`, `containers.json`, `flow.json`, `events.json`, `data-model.json`, `deployment.json`, `states.json`, and the matching rendered files). No default: an undeclared, unconfirmed value stops the skill rather than picking a directory. `--out <dir>` overrides it for one run. |
| `landscape_dialect` | `structurizr` \| `mermaid` | `mermaid` | Which picture `map-landscape`, `map-components`, `map-context`, `map-containers`, `map-flow`, `map-events`, and `map-deployment` emit. `map-dependencies`, `map-data`, and `map-states` do not read it. The per-skill files are in the dialect decision below. |
| `component_layers` | comma-separated layer names | **none** | Optional. Ordered from outside to inside. `/architecture:map-components --group-by layer` reads it. Absent, that grouping cannot run. A name is letters, digits, `.`, `_`, or `-`. |

An unknown key, a `landscape_dialect` value outside the two above, or a `component_layers` value
that is not a comma-separated list of layer names, is reported by `/architecture:setup check` as
a FAIL with a remediation line. It is never silently ignored and never coerced to the default.
`component_layers` absent is a PASS: the key is optional.

## C4 dialect surfaces

This plugin owns the C4-shaped views that share `landscape_dialect`. The authoring-formats
convention owns `diagram_dialect.system` and `diagram_dialect.data`. The keys stay separate,
with separate allowed values and separate defaults, because they are different artifacts, not
because they disagree about mermaid.

| Artifact | Key | Owner | Allowed values | Default | Emitter |
|---|---|---|---|---|---|
| C4 system landscape | `landscape_dialect` | this document | `structurizr`, `mermaid` | `mermaid` | `/architecture:map-landscape` |
| C4 component view | `landscape_dialect` | this document | `structurizr`, `mermaid` | `mermaid` | `/architecture:map-components` |
| C4 system context | `landscape_dialect` | this document | `structurizr`, `mermaid` | `mermaid` | `/architecture:map-context` |
| C4 container view of the code | `landscape_dialect` | this document | `structurizr`, `mermaid` | `mermaid` | `/architecture:map-containers` |
| C4 dynamic view | `landscape_dialect` | this document | `structurizr`, `mermaid` | `mermaid` | `/architecture:map-flow` |
| Async message topology | `landscape_dialect` | this document | `structurizr`, `mermaid` | `mermaid` | `/architecture:map-events` |
| C4 deployment view | `landscape_dialect` | this document | `structurizr`, `mermaid` | `mermaid` | `/architecture:map-deployment` |
| C4 container view of a design | `diagram_dialect.system` | authoring-formats convention | `likec4`, `c4-plantuml` | none (opt-in) | `/planning:design` |
| Data diagram | `diagram_dialect.data` | authoring-formats convention | `mermaid`, `dbml` | `mermaid` | `/planning:design`, `/architecture:map-data` |

## Map family dialect decision

Recorded 2026-09-28 for [#4639](https://github.com/melodic-software/claude-code-plugins/issues/4639),
from the child skill implementations. No per-skill dialect key is added.

| Skill | Dialect |
| --- | --- |
| map-components, map-context, map-containers, map-flow, map-events, map-deployment | `landscape_dialect` (`structurizr` or `mermaid`, default `mermaid`) |
| map-data | `diagram_dialect.data` (`mermaid` or `dbml`, default `mermaid`) |
| map-dependencies | no dialect key; a mermaid `flowchart` of the build graph |
| map-states | no dialect key; a mermaid `stateDiagram-v2` |

`map-containers` reads `landscape_dialect`. Mermaid writes `containers.md` (`C4Container`).
Structurizr writes `containers.dsl` (a container view). It does not read `diagram_dialect.system`.
That key stays the opt-in design view `/planning:design` emits, mermaid refused, no default. An
unset `diagram_dialect.system` still emits no design container view. It does not suppress the
as-built container view.

`map-flow` reuses `landscape_dialect`. Mermaid writes `flow.md` (a `sequenceDiagram`). Structurizr
writes `flow.dsl` (a dynamic view). `map-events` reuses the same key: mermaid writes `events.md`
(a flowchart of publish and send) and structurizr writes `events.dsl`. `map-context` writes
`context.md` or `context.dsl`. `map-components` writes `components.md` (`C4Component`) or
`components.dsl`. `map-deployment` writes `deployment.md` (`C4Deployment`) or `deployment.dsl`.

`landscape_dialect` is a format choice for artifacts these skills emit when invoked. It does not
add a deliverable on its own, and it does not add `component_dialect` or any other per-skill key.

`diagram_dialect.system` is the opt-in C4 container view `/planning:design` emits. A default on that
key would add an artifact a consumer never asked for, which is why the key is unset unless the team
names a dialect.

Mermaid C4 being experimental is why the authoring-formats system key refuses mermaid as a value. It
is not a claim that mermaid is unfit for this landscape surface, whose allowed set is
`structurizr | mermaid`.

The mermaid-C4 experimental fact and its recheck trigger live in the authoring-formats convention
([Why mermaid is not offered for the system key](../../../docs/conventions/authoring-formats/README.md#why-mermaid-is-not-offered-for-the-system-key)).
This document does not carry a second stamp. That trigger fires when the experimental banner
drops or when mermaid documents a dedicated landscape type. On firing, re-derive whether this
key's mermaid default should change, whether `/architecture:map-landscape`'s mermaid output
should use a dedicated landscape type instead of a `C4Context` diagram without a focal system,
and whether the other mermaid pictures that reuse this key should stay as they are:
`C4Component`, a focal `C4Context`, `C4Container`, a `sequenceDiagram`, the events flowchart,
and `C4Deployment`. Record the outcomes in this plugin's `CHANGELOG.md`. Recheck also when a
view needs an allowed set `landscape_dialect` does not have.

## What writes this surface

Only `/architecture:setup apply`, and only two artifacts: the marked `convention-home` pointer
region in the root instruction file, and `<home>/architecture/README.md`. Every `map-*` skill
reads this surface and never writes it. `map-data` also reads `<home>/authoring-formats/README.md`
for `diagram_dialect.data` and never writes that file. None of these skills writes any other file
in the consumer's root.
