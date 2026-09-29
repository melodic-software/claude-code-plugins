---
description: "Chart the modules inside one deployable as a C4 component view: group them by directory, namespace, or a declared layering, and draw a directed arrow for every internal build reference, each citing the declaration it came from. Use when: 'map components', 'component diagram', 'what is inside this service', 'module dependencies', 'which way do the arrows point', 'C4 component view', 'layering of this deployable'. Skip when: the question is which repositories exist (map-landscape), which deployables exist (map-containers), or module-design friction (improve)."
argument-hint: "[container] [--group-by directory|namespace|layer] [--layers <outside,to,inside>] [--out <dir>]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Chart the modules inside one deployable as a C4 component view
---

## Repository context

The current repository is the subject. Collect its root with an individual Bash
call, `git rev-parse --show-toplevel`. A failure (not a repository, git
unavailable) is an unknown value; `${CLAUDE_PROJECT_DIR}` is the root either way.

## Purpose

Answer "what are the modules inside this one deployable, and which way do the
arrows point" from build declarations, not from recall. The scope is one
container. Charting every deployable is `/architecture:map-containers`. The
landscape of repositories is `/architecture:map-landscape`.

## Resolve home and dialect

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` first. Run
`bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"`
and follow the exit code. Exit 0 means read `<home>/architecture/README.md` for
`architecture_dir` and the optional `component_layers`. Exit 1, 2, and 3 mean
there is no declared home.

`--out <dir>` wins for this run alone. Then a declared topic-doc value. Then
one question. `architecture_dir` has no default: an undeclared, unconfirmed
home, including every non-interactive run, stops and points at
`/architecture:setup`. `component_layers` has no default. Absent,
`--group-by layer` cannot run.

This skill does not read `landscape_dialect` and does not add a dialect key.
The diagram dialect is `diagram_dialect.system` from the authoring-formats
topic doc. Resolve it by restating this ladder, then running the resolver
rather than parsing the topic doc yourself. The ladder is a resolution order,
not a task list:

```markdown
1. Anchor at the repository root: `${CLAUDE_PROJECT_DIR}` when set, otherwise
   `git rev-parse --show-toplevel`. Never a CWD-relative read.
2. Resolve the convention home `<home>` with the bundled resolver above. Never hand-parse the root
   file.
3. The printed home is repo-relative: join it to the root, then pass
   `<root>/<home>/authoring-formats/README.md` to the resolver.
4. Layer order is one layer deep: an explicit `--dialect` argument, then the team convention doc.
   There is no personal overlay.
5. `diagram_dialect.system` has NO default. Allowed values are `likec4` and `c4-plantuml`. When it
   is unset, write `components.md` with the prose and tables and draw no diagram block.
6. Degrade soft, and say so. No pointer, no doc, no key, or an unrecognized value (mermaid
   included, which the convention refuses) each resolve to emitting no view. The resolver names
   the cause on stderr. Do not hard-fail and do not ask the operator to create the surface
   mid-task.
7. Report provenance: the key, the value, and the layer (`argument`, `team convention doc <path>`,
   or `unset (no C4 view emitted)`).
```

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-diagram-dialect.sh" --kind system \
  --formats "<root>/<home>/authoring-formats/README.md"
```

Omit `--formats` when no convention home resolved. Stdout is `likec4`,
`c4-plantuml`, or `none`. `c4-plantuml` writes `components.md` with one fenced
`plantuml` block (`C4_Component`); `likec4` writes it with one fenced `likec4`
block and a component view of the container. Both carry the tables. `none`
writes `components.md` with the prose and tables and no diagram block.

This skill never writes the consumer's root instruction file or its topic doc.

## Read the dependency graph

The view is a render of `dependency-graph.json`. The physical shape, the edge
kinds, and the unknown-ecosystem rule are in
[dependency-graph.md](reference/dependency-graph.md). Do not draw a box the
record does not contain, and do not add an edge the record does not cite.

1. When `<architecture_dir>/dependency-graph.json` already exists, confirm it
   is schema_version 1, then render that file. Do not recollect. Say so in the
   report.
2. Otherwise run the shared extractor,
   `${CLAUDE_PLUGIN_ROOT}/skills/map-dependencies/scripts/dependency-graph.sh`,
   and write its stdout to `<architecture_dir>/dependency-graph.json` unchanged.
   Do not pretty-print it.
3. If that script is not on disk, run
   [component-graph.sh](scripts/component-graph.sh). It emits schema_version 1
   that this renderer accepts, from .NET `ProjectReference` and
   `PackageReference` only. Any other ecosystem is `unknown` with empty node
   and edge arrays, not an empty architecture. Field differences between the
   two writers are in [dependency-graph.md](reference/dependency-graph.md).

Pass `--generated-on` to the fallback from `git -C <root> log -1 --format=%cs`,
or `unknown` when that fails, so a second run on the same HEAD does not churn.
`dependency-graph.sh` takes `--generated-on` and `--out` too and defaults to the
same HEAD commit date. Write a graph you collected. A graph that was
already there stays untouched.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/map-dependencies/scripts/dependency-graph.sh" "<root>"
```

```bash
"${CLAUDE_SKILL_DIR}/scripts/component-graph.sh" \
  --repo "<root>" --out "<architecture_dir>/dependency-graph.json" \
  --generated-on "<YYYY-MM-DD|unknown>"
```

## Choose one container

A container is one deployable: an indegree-zero project, plus the projects
reached by following internal edges. When exactly one deployable covers every
project, that is the subject. When the renderer exits 3, it lists the choices
and writes nothing. In an interactive run, ask which one and re-run with
`--container`. In a non-interactive run, stop and report the list. Do not chart
all of them.

## Group, then render

`--group-by` is `directory` (the default), `namespace`, or `layer`.

- `directory` groups by the project file's directory.
- `namespace` uses a `namespace` field on the node when the graph has one, and
  the project name otherwise.
- `layer` requires a declared layering convention: `component_layers` in the
  topic doc, or `--layers host,application,domain` ordered from outside to
  inside. A node matches a layer by a whole path segment or a dotted name
  segment. An edge from a later layer to an earlier one is drawn as a layer
  violation. The mark is informational. The exit code stays 0. Enforcement
  belongs to the consumer's architecture tests.

Above the node threshold (the record's `node_threshold`, else 24, or
`--node-threshold`), the view collapses to coarser groups and says so on the
artifact. It does not drop a component or an evidence row.

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-components.sh" \
  --graph "<architecture_dir>/dependency-graph.json" \
  --out "<architecture_dir>" \
  --dialect "<likec4|c4-plantuml|none>" \
  --group-by directory \
  --layers "<component_layers>" \
  --container "<name>" \
  --source "<dependency-graph.json|dependency-graph.sh|component-graph.sh>" \
  --notes "<architecture_dir>/components-notes.md"
```

Omit `--layers` when no convention is declared. Omit `--container` when the
graph has a single deployable. Omit `--notes` when `components-notes.md` does
not exist yet.

`components-notes.md` is the only file in the architecture directory you author,
and the only one you never overwrite: read it, extend it, and mark an
annotation as an annotation. Annotations say what a component is for.

The renderer prints one summary line. Keep it for the report:

`components: container="<name>" components=<n> edges=<n> drawn_edges=<n> violations=<n> aggregated=<yes|no> thin=<yes|no> external_collapsed=<n> unresolved=<n> dialect=<likec4|c4-plantuml|none>`

A thin result (`thin=yes`) is a single module with no internal edges. The
artifact says so and names the neighboring rungs. It does not present a one-box
diagram as the answer.

## Close with the report

End every run with this block, in this order:

- **Artifacts**: each path written, or `none written` when the run stopped to
  ask for a container.
- **Container**: the name, or the choice list when none was selected.
- **Grouping**: directory, namespace, or layer, and whether a layering
  convention was declared.
- **Components**: `components=`, `edges=`, `drawn_edges=`, quoted from the
  summary line.
- **Thin result**: `no`, or `yes` with the neighboring rungs named in the
  artifact (`/architecture:map-landscape`, `/architecture:map-containers`,
  `/architecture:improve`).
- **Layer violations**: the count, and that they are informational.
- **Aggregated**: `no`, or `yes` with the threshold and the statement that
  nothing was dropped.
- **External and unresolved**: the two counts. Unresolved targets were not
  matched by name.
- **Graph source**: existing `dependency-graph.json`, `dependency-graph.sh`,
  or `component-graph.sh`.
- **Dialect**: `diagram_dialect.system`, its value, and the layer: `argument`,
  `team convention doc <path>`, or `unset (no C4 view emitted)`.

## What this skill does NOT do

- Class-level or code-rung diagrams, behavior, or deployment. Those are other
  rungs.
- Chart every deployable in the repository. That is `/architecture:map-containers`.
- Modify the charted repository, fetch, or write outside `<architecture_dir>`
  (or `--out`).
- Fail the run because an edge violates a declared layering.
- Invent a home, a layering convention, or an edge.
- Re-collect when `<architecture_dir>/dependency-graph.json` is already present.
- Parse source imports. Evidence is a build declaration.

## Next

- The container is one module and the question is module design: `/architecture:improve`.
- The question is which systems the repository sits among: `/architecture:map-landscape`.
- The view settles a decision worth keeping: `/architecture:record-decision`.

## Gotchas

- **The dialect key is `diagram_dialect.system`, and it has no default.** The
  operator's decision on #4639 puts every C4 view of the code on the key the
  authoring-formats convention assigns to C4 system views, which refuses
  mermaid because mermaid C4 is experimental. That decision lives in
  `${CLAUDE_PLUGIN_ROOT}/reference/config.md`. Unset, `components.md` carries the
  tables and no diagram, and the report says no view was emitted.
- **A component diagram is one container.** Claim: the C4 component diagram
  scopes to a single container, and its primary elements are the components
  inside that container. The model is notation-independent. Basis:
  <https://c4model.com/diagrams/component> and <https://c4model.com/>, fetched
  2026-09-28. As of: 2026-09-28. Recheck when that component-diagram page states
  a scope other than a single container, or primary elements other than the
  components inside it.
- **The record is one object per line.** A node line starts with `{"id":`. An
  edge line starts with `{"from":`. Any other layout exits 1 and writes
  nothing. Regenerate the graph; do not pretty-print it.
- **An unresolved reference is not a nearby project with the same name.** The
  artifact lists it. It is not drawn as a component.
- **A backslash in a cited declaration is shown as a slash.** Diagram strings
  and table cells have no portable escape for their own delimiters, so the
  delimiter is swapped. The evidence table still names the file and the
  declaration.
- **`component-graph.sh` reads one adapter.** The Include attribute has to sit
  on the opening tag, double-quoted. A multiline tag, a single-quoted Include,
  and an Update attribute are not read. Another ecosystem stays `unknown`.
- **Aggregation is announced.** Past the threshold the view draws coarser
  groups and says how many components that replaced. The evidence table keeps
  every original declaration.
