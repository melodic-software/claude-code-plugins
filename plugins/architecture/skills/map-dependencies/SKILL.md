---
description: "Cite which project depends on which from build manifests, with the file and declaration on every edge. Use when: 'map dependencies', 'project reference graph', 'dependency graph', 'what references what', 'internal dependencies', 'package references', 'which projects depend on which'. Skip when: the question is which repositories exist, which is /architecture:map-landscape, shallow modules, which is /architecture:improve, or source imports and call graphs."
argument-hint: "[path] [--include-external] [--external-only] [--cycles-only] [--out <dir>]"
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
"${CLAUDE_SKILL_DIR}/scripts/dependency-graph.sh" \
  --out "<architecture_dir>/dependency-graph.json" "<repo-path>"
```

The script writes the record itself and exits 1 when it cannot. `generated_on` is the
HEAD commit date (`unknown` with no commit), so a second run on the same commit is
byte-identical; `--generated-on <date>` overrides it. The document is one object per
line. Do not pretty-print it. A reader given another layout exits 1.

`result` is `ok` or `unknown`. `unknown` means no shipped adapter could read the tree.
The message says which manifests were found. That is the answer. Do not draw a diagram,
and do not fill the arrays by hand. An empty graph is `result` `ok` with project nodes
and no edges. Read it as a repository that declares no references only when no
`unread-reference-tags` or `unread-manifest` finding exists. The first means the collector
skipped reference tags in a file, and the edge list is short by that count. The second
means a manifest holds a declaration whose shape no reader handles; its evidence is the
file, a colon, and the declaration skipped, one finding per declaration.

Every shipped adapter whose manifests are present runs, and their nodes, edges and
findings are one record. `ecosystem` is the adapter's name when one ran, `mixed` when
more than one ran, and `unknown` when none did. Each node carries its own `ecosystem`.

The .NET adapter:

- `ProjectReference` is a directed internal edge. The target is the `Include` path
  relative to the project file. A target that is missing, or that resolves outside the
  repository root, is `status` `unresolved`. Never match it to a project of the same
  name somewhere else on disk.
- `PackageReference` is an external package edge. The node id is `pkg:` plus the Include.
- A `ProjectReference` or `PackageReference` in a `Directory.Build.props` or
  `Directory.Build.targets` is an edge from every project under that file's folder whose
  nearest such file it is, and the evidence cites the props file. A project never gets an
  edge to itself that way. Any other `.props` or `.targets` file, and
  `Directory.Packages.props`, has no known importer, so its references are counted in an
  `unread-reference-tags` finding and not drawn.
- `*.sln` and `*.slnx` contribute membership. A project path that does not resolve inside
  the root is a finding, not an edge.
- Source files are not read. A `using` or an import is not an edge.

The Node adapter:

- Every `package.json` outside `node_modules` is a project node, id its repo-relative path.
  Workspace members are the package folders that the `workspaces` globs (array or
  `{"packages": [...]}` form) and a `pnpm-workspace.yaml` `packages` list expand to.
- A dependency, dev, peer or optional dependency that names a member of the declaring
  package's workspace, or whose spec is `workspace:`, `file:` or `link:` pointing at a
  package folder inside the root, is an internal project edge. Every other entry is an
  external package edge to `pkg:node:<name>`.
- A spec that names no member, leaves the root, or points at a folder with no `package.json`
  is `unresolved`. Never match it to a package of the same name elsewhere on disk.
- A negated glob, a flow-list `packages:`, a `catalog:` spec and a non-string dependency
  value are `unread-manifest` findings, not edges. The script header carries the sources
  for the workspace rules.

The Go adapter:

- Every `go.mod` is a project node, id its repo-relative path, name its module path.
- A `replace` whose target is a local path (`./` or `../`) holding a `go.mod` inside the
  root is an internal project edge, and the evidence cites the `replace` line. A missing
  or out-of-root target is `unresolved`.
- A `require` of a module that is another `go.mod` in the repo is internal only when a
  `replace` or a `go.work` `use` line points it there; otherwise it is an external edge
  to `pkg:go:<module>`. `go.work` `use` lines are membership.
- Any other directive the reader cannot parse, a `go.work` `replace`, and a `use` line
  naming no `go.mod` in the root are `unread-manifest` findings.

The Python adapter:

- Every `pyproject.toml` is a project node, id its repo-relative path. A `setup.py` or
  `requirements*.txt` with no manifest beside it is a node too; one beside a manifest is
  read as that project.
- A path reference is an internal project edge when it names a folder inside the root
  holding a `pyproject.toml` (else a `setup.py`), and the evidence cites the declaration.
  Path references are a `name @ file:` dependency string, a poetry or uv `path =` entry,
  and a `-e`, `./` or `../` requirements line. A missing or out-of-root path is
  `unresolved`.
- A `[tool.uv.workspace]` `members` glob, minus `exclude`, is an internal project edge from
  the workspace root to each `pyproject.toml` it matches; a literal member holding none is
  `unresolved`.
- Every other named requirement is an external edge to `pkg:python:<normalized name>`.
  `-r` includes are followed only inside the root.
- `setup.py` is never executed or parsed; each one is an `unread-manifest` finding. So
  are dynamic dependencies, a uv `workspace = true` source, a multi-line inline table, and
  an include that is missing or outside the root.

The Rust adapter:

- Every `Cargo.toml` is a project node, id its repo-relative path.
- A `path =` dependency in `[dependencies]`, `[dev-dependencies]` or `[build-dependencies]`
  is an internal project edge when it names a folder inside the root holding a
  `Cargo.toml`, and the evidence cites the declaration. A missing or out-of-root path is
  `unresolved`.
- A `[workspace]` `members` glob, minus `exclude`, is an internal project edge from the
  workspace root to each `Cargo.toml` it matches; a literal member holding none is
  `unresolved`.
- A dependency written `workspace = true` takes its source from the nearest ancestor
  `[workspace.dependencies]`: a `path =` entry is an internal edge, any other entry an
  external one, and the evidence cites both declarations. A workspace entry no member
  inherits draws no edge.
- Every other dependency is an external edge to `pkg:rust:<name>`.
- Any `[target.*]` dependency table, a `path =` under `[patch]` or `[replace]`, a
  `workspace = true` with no workspace entry to resolve it, a multi-line inline table, and
  a members glob the reader cannot resolve are `unread-manifest` findings.

The JVM adapter (Gradle and Maven):

- Every `pom.xml`, `build.gradle` and `build.gradle.kts` is a project node, id its
  repo-relative path. A folder with a `settings.gradle(.kts)` and no build file is a node
  under the settings file.
- A `settings.gradle(.kts)` `include` argument is an internal project edge from the settings
  folder's project to the folder its project path names, when that folder holds a build
  file. A `project(':x')` or `project(path = ':x')` dependency in a build file resolves from
  the nearest settings file above it. A `pom.xml` `<modules><module>` entry is an internal
  project edge to the `pom.xml` in the folder it names. Each edge cites the declaration.
  A project path or module naming no build file, or leaving the root, is `unresolved`.
- No external package edge is drawn for JVM.
- `includeFlat`, `includeBuild`, an include holding a variable, an interpolated string or a
  spread, anything inside a loop, a `projectDir`, `buildFileName` or `name` assignment,
  `apply from`, a `projects.x` type-safe accessor, a `project(...)` with a non-literal
  argument, a module holding a `${property}`, and a module naming a pom file not called
  `pom.xml` are `unread-manifest` findings.

Read: .NET, Node, Go, Python, Rust, and JVM (Gradle and Maven). Declined: Ruby (`Gemfile`) and
PHP (`composer.json`) are detected and named in the record's `message`, never parsed. The
unread rule: a manifest or declaration no reader handles is reported, never guessed at and
never dropped. A tree holding only declined manifests is `unknown`; in a tree a reader ran on,
the message still names the declined ecosystems and each skipped declaration is an
`unread-manifest` finding.

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
- **Unread**: the `unread_files` count, each file and tag count from the
  `unread-reference-tags` findings, and each skipped declaration from the
  `unread-manifest` findings.
- **Cycles**: the cycle lines, or none. Each line is one witness cycle for a group of
  projects that depend on each other, not every cycle in the group.
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

- **The shared .NET reader is the one portfolio-facts uses.** It reads each reference tag
  as a whole, so an `Include` on a later line and a single-quoted `Include` are edges. A
  reference inside an XML comment is not, and an `Update` or `Remove` override is not a
  reference. A reference-like tag it cannot turn into an edge (`FrameworkReference`,
  `GlobalPackageReference`, an empty or missing `Include`) is counted in the
  `unread-reference-tags` finding.
- **Directory.Build.props edges follow MSBuild's lookup.** MSBuild imports the nearest
  `Directory.Build.props` above a project and stops there, and a relative `Include` in an
  imported file is relative to the importing project's folder. This collector does not
  evaluate `Condition` or `$(...)` properties, so a props reference that a condition
  would exclude is still drawn, and one built from a property is `unresolved`.
  - Claim: MSBuild walks up from the project to the first `Directory.Build.props` and
    imports that one; an imported file's relative `Include` resolves from the project's
    folder.
  - Basis: https://learn.microsoft.com/en-us/visualstudio/msbuild/customize-by-directory
    and https://learn.microsoft.com/en-us/visualstudio/msbuild/msbuild-items
  - As of: 2026-09-29.
  - Recheck: when either page changes the lookup rule or the base of a relative `Include`.
- **Evidence stops at the end of the tag.** A `Version` child element on the following
  lines is not part of the citation. A `Version` attribute on the same tag is.
- **`bin`, `obj`, `node_modules`, `vendor`, and dot-directories** other than the CI and
  devcontainer directories are not walked. A project that lives only there is absent.
- **A solution folder is not a project.** Only paths ending in `.csproj` or `.fsproj`
  are membership. A member with another project extension (`.vbproj`, `.sqlproj`) is an
  `unread-manifest` finding.
- **Aggregation is a view.** `dependency-graph.json` stays one node per project. The
  markdown says when the flowchart collapsed to directories.
- **The flowchart does not follow `landscape_dialect`.** That key is the system landscape.
  This diagram is a mermaid flowchart either way.
