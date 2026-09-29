---
description: "Cite which project depends on which from build manifests, with the file and declaration on every edge. Use when: 'map dependencies', 'project reference graph', 'dependency graph', 'what references what', 'internal dependencies', 'package references', 'which projects depend on which'. Skip when: the question is which repositories exist, which is /architecture:map-landscape, shallow modules, which is /architecture:improve, or source imports and call graphs."
argument-hint: "[path] [--include-external] [--external-only] [--cycles-only]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Cite project and package edges from build manifests
---

## Repository context

The current repository is the default subject. Collect its root with one Bash call,
`git rev-parse --show-toplevel`. Treat a failure as an unknown root and ask for a path.
Do not walk the working directory for nested repositories.

## Purpose

Answer "which project depends on which, and in which direction" from build declarations
a script read. Every edge names the file and the declaration it came from. The canonical
artifact is `dependency-graph.json`. The human render is a mermaid `flowchart` of the
internal edges. This is the model, not a C4 diagram.

The dialect decision lives in `${CLAUDE_PLUGIN_ROOT}/reference/config.md`. Read it.
Do not restate it, and do not emit a C4 view from this skill. This flowchart does
not follow `landscape_dialect`. `diagram_dialect.system` stays the planning opt-in.

## Resolve home

Read `${CLAUDE_PLUGIN_ROOT}/reference/config.md` for `architecture_dir`. Run
`bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "${CLAUDE_PROJECT_DIR}"`
and follow the exit code. Never parse the root instruction file yourself.

`--out <dir>` wins for this run alone. Then a declared `architecture_dir`. With neither,
including every non-interactive run, stop and point at `/architecture:setup`. This skill
never writes the topic doc.

## Build the graph

```bash
"${CLAUDE_SKILL_DIR}/scripts/dependency-graph.sh" "<repo-path>"
```

Write stdout to `<architecture_dir>/dependency-graph.json` unchanged. The document is
one object per line. Do not pretty-print it. A reader given another layout exits 1.

`result` is `ok` or `unknown`. `unknown` means no shipped adapter could read the tree.
The message says which manifests were found. That is the answer. Do not draw a diagram,
and do not fill the arrays by hand. An empty graph is `result` `ok` with project nodes
and no edges, which is a real repository that declares no references.

The first adapter is .NET:

- `ProjectReference` is a directed internal edge. The target is the `Include` path
  relative to the project file. A target that is missing, or that resolves outside the
  repository root, is `status` `unresolved`. Never match it to a project of the same
  name somewhere else on disk.
- `PackageReference` is an external package edge. The node id is `pkg:` plus the Include.
- `*.sln` and `*.slnx` contribute membership. A project path that does not resolve inside
  the root is a finding, not an edge.
- Source files are not read. A `using` or an import is not an edge.

Other ecosystems stay unread. The message names them. Node, Go, Python, Rust, and JVM
adapters are not this skill yet.

`node_threshold` in the record (40) is the documented count of internal project nodes
above which the human diagram aggregates to directories. The JSON stays at project
resolution.

## Render

```bash
"${CLAUDE_SKILL_DIR}/scripts/render-dependencies.sh" \
  --record "<architecture_dir>/dependency-graph.json" \
  --out "<architecture_dir>"
```

This writes `dependency-graph.md`. The summary line on stdout is the report's counts.
Keep it. Do not redraw the flowchart yourself.

- Default: internal project edges only. External packages are counted and collapsed.
- `--include-external`: draw package edges as well.
- `--external-only`: draw package edges and not internal project edges.
- `--cycles-only`: draw only internal edges that sit on a reported cycle.
- `--include-external` and `--external-only` together are a usage error.

Cycles are a section at the top of `dependency-graph.md`. Above the threshold the diagram
says it aggregated to directory level.

## Close with the report

- **Artifacts**: `dependency-graph.json` and `dependency-graph.md`, or `none written` when
  there was no `architecture_dir` and no `--out`.
- **Result**: `ok` or `unknown`, and the message when it is non-empty.
- **Counts**: quote the summary line. Do not count nodes by hand.
- **Unresolved**: how many project references and solution memberships did not resolve,
  and that none of them were matched by file name.
- **Cycles**: the cycle lines, or none.
- **Aggregation**: `no`, or `yes` with the threshold the artifact states.
- **Diagram**: mermaid flowchart, or no diagram because the result is unknown or a filter
  left nothing to draw.

## What this skill does NOT do

- Import graphs, call graphs, or runtime discovery.
- A C4 component, container, context, or deployment view. The component view that reads
  this graph is the successor below.
- Resolve a `ProjectReference` by searching the disk for a matching file name.
- Invent an empty graph for an ecosystem this skill does not read.
- Fetch, or modify any file in the subject repository other than the two artifacts in
  the architecture directory.
- Choose a checkout identity. Project ids are repo-relative paths. They are not the
  directory name of the clone.

## Next

/architecture:map-components

The component view reads dependency-graph.json.

## Gotchas

- **The shared .NET reader is the one portfolio-facts uses.** An `Include` on the next
  line, a single-quoted `Include`, and an `Update` version override are not edges. A
  reference inside an XML comment is still cited, because the reader matches the tag
  text rather than the XML structure.
- **Evidence stops at the end of the tag.** A `Version` child element on the following
  lines is not part of the citation. A `Version` attribute on the same tag is.
- **`bin`, `obj`, `node_modules`, `vendor`, and dot-directories** other than the CI and
  devcontainer directories are not walked. A project that lives only there is absent.
- **A solution folder is not a project.** Only paths ending in `.csproj` or `.fsproj`
  are membership.
- **Aggregation is a view.** `dependency-graph.json` stays one node per project. The
  markdown says when the flowchart collapsed to directories.
- **The flowchart does not follow `landscape_dialect`.** That key is the system landscape.
  This diagram is a mermaid flowchart either way.
