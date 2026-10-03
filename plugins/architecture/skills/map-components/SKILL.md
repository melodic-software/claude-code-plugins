---
description: "Chart the modules inside one deployable as a C4 component view, one directed arrow per internal build reference, each citing its declaration. Use when: 'map components', 'component diagram', 'what is inside this service', 'module dependencies', 'which way do the arrows point', 'C4 component view', 'layering of this deployable'. Skip when: which repositories exist (map-landscape), which deployables exist (map-containers), or module-design friction (improve)."
argument-hint: "[container] [--group-by directory|namespace|layer] [--layers <list>] [--dialect likec4|c4-plantuml]"
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

The view is a render of `dependency-graph.json`, the record
`/architecture:map-dependencies` writes. The writer's layout is in the header
of its `dependency-graph.sh` (`--help` prints it), and what this renderer reads
from it is in [dependency-graph.md](reference/dependency-graph.md). Do not draw
a box the record does not contain, and do not add an edge the record does not
cite.

1. When `<architecture_dir>/dependency-graph.json` already exists, confirm it
   is schema_version 1, then render that file. Do not recollect, and leave the
   file untouched. Say so in the report.
2. Otherwise run the shared extractor. It writes the record itself, and a
   second run on the same HEAD is byte-identical. Do not pretty-print it.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/map-dependencies/scripts/dependency-graph.sh" \
  --out "<architecture_dir>/dependency-graph.json" "<root>"
```

A tree holding no manifest that a reader handles is `result` `unknown` with empty
node and edge arrays, not an empty architecture. The render says so and draws
nothing. The ecosystems the extractor reads, and the ones it declines, are listed
in `/architecture:map-dependencies`.

## Choose one container

A container is one deployable: an indegree-zero project, plus the projects
reached by following internal edges. A test project (the node's `test` field) is
not a deployable: its references are not counted toward a project's indegree, so
`Api.Tests` referencing `Api` leaves `Api` a root, and it is never listed as a
choice. A stray manifest is not a deployable either: a project no internal edge
touches, in an ecosystem that no linked project and no .NET project shares (a
tooling `package.json`, a requirements file beside a .NET tree). It is not a
choice, it is not counted as outside the container, and the report says how many
were set aside. `--container` charts one anyway. A Node workspace root draws no
edge to its members and shares their ecosystem, so it is not set aside: a plain Node
workspace lists the root beside its top member, and `--container` picks the member. When exactly one deployable
covers every project, that is the subject.
When the renderer exits 3, it lists the choices and writes nothing. It also
exits 3 when every project is a test project, and says so; `--container` still
charts one on request. In an interactive run, ask which one and re-run with
`--container`. In a non-interactive run, stop and report the list. Do not chart
all of them.

## Group, then render

`--group-by` is `directory` (the default), `namespace`, or `layer`.

- `directory` groups by the parent of the project's own directory, one level up:
  `src/Api/Api.csproj` and `src/Domain/Domain.csproj` both group under `src`.
  A project directly under the root, or one folder down, groups under `.`.
- `namespace` groups by the containing namespace: the node's `namespace` field
  (`RootNamespace`, else `AssemblyName`, from the project file), else the project
  name, with the last dotted segment dropped. `Billing.Api` and
  `Billing.Domain` both group under `Billing`. A name with no dot is its own
  group.
- `layer` requires a declared layering convention: `component_layers` in the
  topic doc, or `--layers host,application,domain` ordered from outside to
  inside. A node matches a layer by a whole path segment or a dotted name
  segment. An edge from a later layer to an earlier one is drawn as a layer
  violation. The mark is informational. The exit code stays 0. Enforcement
  belongs to the consumer's architecture tests.

Above the node threshold (the record's `node_threshold`, else 40, or
`--node-threshold`), the view collapses to coarser groups and says so on the
artifact. It does not drop a component or an evidence row.

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-components.sh" \
  --graph "<architecture_dir>/dependency-graph.json" \
  --out "<architecture_dir>" \
  --dialect "<likec4|c4-plantuml|none>" \
  --group-by directory \
  --root "<root>" \
  --layers "<component_layers>" \
  --container "<name>" \
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

`--root` lets the renderer compare the record's `generated_on` with the HEAD
commit date of `<root>`. When they differ it writes one line, `dependency-graph.json
was generated on <d>; HEAD commit date is <d2>`, into `components.md` and to
stderr, and renders anyway.

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
- **Graph source**: the existing `dependency-graph.json`, or the one
  `dependency-graph.sh` wrote this run. Quote the staleness warning when the
  renderer printed one.
- **Dialect**: `diagram_dialect.system`, its value, and the layer: `argument`,
  `team convention doc <path>`, or `unset (no C4 view emitted)`.

## Interactive view

After the report, offer an interactive view of the chosen deployable's closure in one sentence. The markdown
and `dependency-graph.json` stay authoritative. Build it only with
`${CLAUDE_PLUGIN_ROOT}/scripts/build-view.mjs components --record <dependency-graph.json> --from <the chosen
deployable's node id>`, never hand-written; the publish destination comes from the `medium` cascade key.
Procedure: [`${CLAUDE_PLUGIN_ROOT}/reference/rendered-view.md`](${CLAUDE_PLUGIN_ROOT}/reference/rendered-view.md).

## What this skill does NOT do

- Class-level or code-rung diagrams, behavior, or deployment. Those are other
  rungs.
- Chart every deployable in the repository. That is `/architecture:map-containers`.
- Modify the charted repository, fetch, or write outside `<architecture_dir>`
  (or `--out`).
- Fail the run because an edge violates a declared layering.
- Invent a home, a layering convention, or an edge.
- Re-collect when `<architecture_dir>/dependency-graph.json` is already present.
  Whether a stale graph should be regenerated is the caller's call; the
  renderer's warning is how the staleness is surfaced, and it never blocks.
- Parse source imports. Evidence is a build declaration.

## Next

- The container is one module and the question is module design: `/architecture:improve`.
- The question is which systems the repository sits among: `/architecture:map-landscape`.
- The view settles a decision worth keeping: `/architecture:record-decision`.

## Gotchas

- **The dialect key is `diagram_dialect.system`, and it has no default.** The
  Every C4 view of the code reads the key the
  authoring-formats convention assigns to C4 system views, which refuses
  mermaid because mermaid C4 is experimental. The key is documented in
  `${CLAUDE_PLUGIN_ROOT}/reference/config.md`. Unset, `components.md` carries the
  tables and no diagram, and the report says no view was emitted.
- **A component diagram is one container.** Claim: the C4 component diagram
  scopes to a single container, and its primary elements are the components
  inside that container. The model is notation-independent. Basis:
  <https://c4model.com/diagrams/component> and <https://c4model.com/>. As of:
  2026-09-29. Recheck when that component-diagram page states
  a scope other than a single container, or primary elements other than the
  components inside it.
- **C4-PlantUML component syntax: read against the README, never run.** Claim: the `plantuml`
  block uses `!include <C4/C4_Component>`, `Container_Boundary(alias, label, ?tags, ?link, ?descr)`
  for the container, `Boundary(alias, label, ?type, ...)` per group, `Component(alias, label,
  ?techn, ?descr, ...)`, and `Rel(from, to, label, ?techn, ?descr, ?sprite, ?tags, ?link)`. A layer
  violation is `AddRelTag("layer-violation", $textColor, $lineColor)` plus `$tags` on that `Rel`,
  because `UpdateRelStyle(textColor, lineColor)` restyles every relationship. Basis:
  <https://github.com/plantuml-stdlib/C4-PlantUML/blob/master/README.md>, which shows the stdlib
  include only for `C4_Container` and says the released `C4_...` files ship in the stdlib, so the
  `C4_Component` stdlib name is inferred. As of: 2026-09-29. Recheck when that README changes
  those signatures or the include path, or when a host with Java can run PlantUML over a rendered
  block. No PlantUML run has parsed this output.
- **LikeC4 component syntax: parsed by the CLI.** Claim: the `likec4` block is a `specification`
  with `softwareSystem`, `container`, `boundary`, and `component` element kinds, a `model` nesting
  boundaries and components in the container, relationships by dotted full name with a
  `style { color red }` body, and a `views` block holding `view components of <container>` with
  `title` and `include *`; an aggregated view puts one component per group directly in the
  container. Basis: <https://likec4.dev/dsl/specification/>, <https://likec4.dev/dsl/model/>,
  <https://likec4.dev/dsl/views/>, and <https://likec4.dev/dsl/styling/>, plus `likec4@1.59.4
  validate` exiting 0 on the golden blocks in `${CLAUDE_PLUGIN_ROOT}/lib/likec4-golden/`
  (`components.c4`, `components-aggregated.c4`), which `render-components.test.sh` diffs
  against. As of: 2026-09-29. Recheck
  when any of those pages changes that syntax or a newer `likec4` release ships: set
  `LIKEC4_VALIDATE=1` when running the test to re-run the CLI.
- **The record is one object per line.** A node line starts with `{"id":`. An
  edge line starts with `{"from":`. Any other layout exits 1 and writes
  nothing. Regenerate the graph; do not pretty-print it.
- **An unresolved reference is not a nearby project with the same name.** The
  artifact lists it. It is not drawn as a component.
- **A backslash in a cited declaration is shown as a slash.** Diagram strings
  and table cells have no portable escape for their own delimiters, so the
  delimiter is swapped. The evidence table still names the file and the
  declaration.
- **An older graph is refused, not rendered.** A record with no `result` key
  did not come from `dependency-graph.sh`. The renderer exits 1 and writes
  nothing. Stop and point at `/architecture:map-dependencies`, which owns
  rewriting that file.
- **Aggregation is announced.** Past the threshold the view draws coarser
  groups and says how many components that replaced. The evidence table keeps
  every original declaration.
