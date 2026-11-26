# dependency-graph.sh record and adapter rules

Behavior notes for `dependency-graph.sh`.

```text
Cite a repository's build-declaration dependency graph, as JSON.

WHY. A diagram of which project depends on which is model recall unless every
edge is a declaration a script read. This collector reads declarations only.
It does not read source imports, and it does not guess a missing project by
file name.

ProjectReference is a reference to another project. Basis:
https://learn.microsoft.com/en-us/visualstudio/msbuild/common-msbuild-project-items
PackageReference Include is the package id. Basis:
https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files
Verified 2026-09-28. Recheck when either page renames the item or stops using
Include as that string.

The human render is not a C4 diagram. C4's diagrams are system context,
containers, components, and code, plus system landscape, dynamic, and
deployment. Basis: https://c4model.com/ Verified 2026-09-28. Recheck when
that page adds a diagram type for a build-declaration graph.

Usage:
  dependency-graph.sh [--out <file>] [--generated-on <date>] <repo-path>
  dependency-graph.sh --help

Output: one JSON document on stdout, or in --out <file> with nothing on
stdout; a failed write exits 1 with a message. generated_on defaults to the
date of the repository's HEAD commit (git log -1 --format=%cs), so a second
run on the same commit is byte-identical, and to "unknown" when there is no
commit. --generated-on overrides it. The document is in the
one-object-per-line layout. Readers match objects by line, the same way landscape.json does. A reader
given any other layout must fail rather than report an empty graph.
render-dependencies.sh is that reader.

  {
    "schema_version": 1,
    "generated_on": "YYYY-MM-DD" | "unknown",
    "result": "ok" | "unknown",
    "message": "...",
    "ecosystem": "<name>" | "mixed" | "unknown",
    "node_threshold": 40,
    "cycles_truncated": false,
    "nodes": [ <one node object per line> ],
    "edges": [ <one edge object per line> ],
    "cycles": [ <one cycle object per line> ],
    "findings": [ <one finding object per line> ]
  }

  node     {"id","name","path","ecosystem","kind"} plus, on a project, the
           optional "namespace" and "test" fields.
           ecosystem is the name of the reader that produced the node.
           kind is "project" or "package". id of a project is its
           repo-relative path. id of a package is "pkg:" plus the Include.
           Nodes with the same id are one node, so a reader other than .NET
           puts its ecosystem name after the colon ("pkg:<ecosystem>:<name>").
           namespace is the project file's RootNamespace, else its
           AssemblyName, and is omitted when neither is a literal value.
           test is "yes" on a test project (IsTestProject true, or a
           reference to Microsoft.NET.Test.Sdk, xunit*, NUnit*, MSTest*, or
           Microsoft.Testing.Platform*) and is omitted otherwise. A record
           without either field is still schema_version 1.
  edge     {"from","to","kind","status","evidence"}
           kind is "project" or "package". status is "resolved" or
           "unresolved". evidence is the repo-relative file, a colon, and
           the matched declaration text.
  cycle    {"id"}  project ids joined by " -> ", rotated to start at the
           smallest id, first id repeated at the end. One witness cycle per
           strongly connected group of projects, and one per self-reference.
           The search is linear in projects plus edges, so it always
           finishes; cycles_truncated stays in the record for readers of
           schema_version 1 and is always false.
  finding  {"kind","path","evidence"}
           kind "unresolved-membership" is a solution project whose declared
           path is missing or outside the repository root.
           kind "unread-reference-tags" is a project or MSBuild file with
           reference tags this run did not turn into an edge. evidence is the
           file, a colon, and the count. A graph with this finding is not a
           complete list of that file's references.
           kind "unread-manifest" is a declaration in a manifest whose shape
           a reader does not handle. path is the manifest. evidence is that
           file, a colon, and the declaration it skipped, one finding per
           declaration. A graph with this finding is not a complete list of
           that manifest's dependencies.

Every shipped reader whose manifests are present runs, and their nodes, edges
and findings are merged into one record. The top-level ecosystem is the name
of the one reader that ran, "mixed" when more than one ran, and "unknown"
when none did. A reader of schema_version 1 that does not know a new
ecosystem name or finding kind still finds every field it reads.

result "unknown" means this run did not read a shipped adapter. The arrays
are empty and message says why. That is not an empty graph: an empty graph
is result "ok" with project nodes and no edges.

The .NET adapter: ProjectReference is a directed internal
edge whose target is the Include path relative to the project file.
PackageReference is an external package edge. A ProjectReference that is
missing or escapes the repository root is status "unresolved" and is never
matched to a similarly named project elsewhere. Solution files
(*.sln, *.slnx) contribute membership, not dependency edges. A member whose
path ends in another project extension (.vbproj, .sqlproj, ...) is an
unread-manifest finding.

A Directory.Build.props or Directory.Build.targets reference is an edge from
every project whose nearest such file, walking up from the project, is that
one; a relative Include resolves from the project's folder and the edge cites
the props file. A project never gets an edge to itself from those files. Any
other *.props or *.targets file, and Directory.Packages.props, is imported by
a path this collector does not evaluate: its references are counted in an
unread-reference-tags finding, not drawn. Basis:
https://learn.microsoft.com/en-us/visualstudio/msbuild/customize-by-directory
and https://learn.microsoft.com/en-us/visualstudio/msbuild/msbuild-items
Verified 2026-09-29. Recheck when either page changes the lookup rule or the
base of a relative Include in an imported file.

The Node adapter (lib/node-references.sh): every package.json outside
node_modules is a project node whose id is its repo-relative path. Workspace
members are the package folders that the "workspaces" globs of a package.json
(an array, or an object with a "packages" array) and the "packages" list of a
pnpm-workspace.yaml expand to, matched only against the package.json files
found under the root. A dependencies, devDependencies, peerDependencies or
optionalDependencies entry is an internal project edge when its name is a
member of a workspace that holds the declaring package, or its spec is
workspace: (a range, an alias pkg@range, or a relative path), file: or link:
and names a package folder inside the root. Every other entry is an external
package edge to "pkg:node:<name>". A spec that names no member, resolves
outside the root or to a folder with no package.json is status "unresolved"
and is never matched to a package of the same name elsewhere. A negated or
otherwise unexpanded glob, a flow-list "packages:", a catalog: spec, and a
dependency value that is not a string are unread-manifest findings.
Basis: https://docs.npmjs.com/cli/v11/using-npm/workspaces and
https://pnpm.io/workspaces Verified 2026-09-29. Recheck when either page
changes what "workspaces" or "packages" may hold or what workspace: accepts.

The Go adapter (lib/go-references.sh): every go.mod is a project node whose id
is its repo-relative path and whose name is its module path. A replace whose
target is a local path (./, ../) holding a go.mod inside the root is an
internal project edge to that module, and the evidence cites the replace
line; a target that is missing or outside the root is status "unresolved".
A require whose module path is that of another go.mod in the repo is internal
only when a replace or a go.work use line points it there (both modules named
by one go.work); otherwise it is an external edge to "pkg:go:<module>". A
directive the reader cannot parse, a go.work replace, and a use line naming no
go.mod in the root are unread-manifest findings.
Basis: https://go.dev/ref/mod#go-mod-file-replace and
https://go.dev/ref/mod#workspaces Verified 2026-09-29. Recheck when either
page changes what a replace target or a use directive may hold.

The Python adapter (lib/python-references.sh): every pyproject.toml, every
setup.py with no pyproject.toml beside it, and every requirements*.txt with
neither beside it is a project node whose id is its repo-relative path. A
requirements file beside a pyproject.toml or setup.py is read as that
project. An edge is read from [project] dependencies (and
optional-dependencies and dependency-groups), [tool.poetry.dependencies]
entries that carry path =, [tool.uv.sources] entries that carry path =, and
requirements lines. A [tool.uv.workspace] members glob (minus exclude) is an
internal project edge to each pyproject.toml it matches under the workspace
root folder; a literal member holding none is "unresolved". A path (a
"name @ file:" URL, a path =, a -e line, or a plain ./ or ../ line) naming a
folder inside the root that holds a pyproject.toml, else a setup.py, is an
internal project edge citing the declaration; a missing or out-of-root path
is status "unresolved". A named requirement is an external edge to
"pkg:python:<normalized name>" unless the
same file gives that name a path. -r includes are followed only inside the
root. setup.py is never executed or parsed: each is an unread-manifest
finding, and so are dynamic dependencies, a uv workspace = true source, a
multi-line inline table, and an include that is missing or leaves the root.
Basis: https://packaging.python.org/en/latest/specifications/dependency-specifiers/
https://packaging.python.org/en/latest/specifications/pyproject-toml/
https://pip.pypa.io/en/stable/reference/requirements-file-format/ and
https://docs.astral.sh/uv/concepts/projects/dependencies/#path and
https://docs.astral.sh/uv/concepts/projects/workspaces/ Verified
2026-09-29. Recheck when any page changes what a dependency string, a
requirements line, or a path source may hold.

The Rust adapter (lib/rust-references.sh): every Cargo.toml is a project node
whose id is its repo-relative path, named by [package] name else its folder.
A path = dependency in [dependencies], [dev-dependencies] or
[build-dependencies] naming a folder inside the root that holds a Cargo.toml
is an internal project edge citing the declaration; a missing or out-of-root
path is status "unresolved". Every other dependency is an external edge to
"pkg:rust:<lower-case name, _ as ->". A [workspace] members glob (minus
exclude) is an internal project edge from the workspace root to each
Cargo.toml it matches under the root's folder; a literal member holding none
is "unresolved". A dependency written workspace = true takes its source from
the nearest ancestor Cargo.toml with a [workspace] table: a
[workspace.dependencies] path = entry gives an internal edge, any other entry
an external one, and the evidence cites both declarations. A
[workspace.dependencies] entry no member inherits draws no edge. Unread: any
[target.*] dependency table, a path = under [patch] or [replace], workspace =
true with no [workspace.dependencies] entry to resolve it, a dependency value
that is neither a string nor an inline table, an inline table split across
lines, and a members glob node_glob_regex refuses.
Basis: https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html
https://doc.rust-lang.org/cargo/reference/workspaces.html Verified
2026-09-29. Recheck when either page changes what a dependency entry or a
members entry may hold.

The JVM adapter (lib/jvm-references.sh): every pom.xml, build.gradle and
build.gradle.kts is a project node whose id is its repo-relative path; a
folder with a settings.gradle(.kts) and no build file is one too, under the
settings file. A Gradle project is its folder. An include argument in
settings.gradle(.kts) is an internal project edge from the settings folder's
project to the folder that project path names, when that folder holds a
build file. A project(':x') dependency in a build file resolves from the
nearest settings file at or above it (a path with no colon resolves from the
build file's folder), and project(path = ':x') is the same reference. A
pom.xml <modules><module> entry, including one inside a profile, is an
internal project edge to the pom.xml in the folder it names, or to the
pom.xml it names when it ends in .xml. A project path or module that names no
build file, or leaves the root, is status "unresolved". Every edge cites the
declaration. No external package edge is drawn for JVM. Unread: includeFlat,
includeBuild, an include with a variable, an interpolated string or a spread,
an include or project reference inside a loop, a project(...).projectDir,
.buildFileName or .name assignment, apply from, projects.x type-safe
accessors, project(...) with a non-literal argument, a module holding a
property reference, and a module naming a pom file not called pom.xml.
Basis: https://docs.gradle.org/current/userguide/multi_project_builds.html
https://docs.gradle.org/current/userguide/declaring_dependencies_basics.html
and https://maven.apache.org/pom.html Verified 2026-09-29. Recheck when
any page changes how a project path maps to a folder or what a module entry
may hold.

node_threshold is the documented count of internal project nodes above which
the human diagram aggregates to directories. This file stays at project
resolution either way. The diagram is render-dependencies.sh.

Build output directories named bin and obj are not walked. Dot-directories
other than .github, .gitlab, .circleci, and .devcontainer are not walked.
node_modules and vendor are not walked.

Nothing here fetches. The only write is --out.

Portability: bash plus POSIX awk. No jq, no `grep -P`, no python.

Exit: 0 = a document was emitted (result ok or unknown); 1 = the path is
not a readable directory or --out cannot be written; 2 = usage.
```
