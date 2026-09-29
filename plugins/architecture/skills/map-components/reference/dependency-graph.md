# dependency-graph.json

The record `map-components` renders. `dependency-graph.sh` in `map-dependencies`
is the shared writer. [component-graph.sh](../scripts/component-graph.sh) is the
fallback when that file is absent and that writer is not on disk. Both are
schema_version 1, one object per line, with a node line's first key `id` and an
edge line's first key `from`.

`dependency-graph.sh` also writes `result`, `message`, `cycles`, and `findings`.
A package id is `pkg:` plus the Include. An unresolved project reference is
`kind` `project` with `status` `unresolved`, and its `to` is not a charted
project. `node_threshold` is 40. The fallback writes `subject`,
`unknown_reason`, and `unshipped`, uses package ids `nuget:<Include>`, uses edge
`kind` `unresolved`, and sets `node_threshold` to 24. The example below is the
fallback shape. The renderer accepts both: a project edge whose `to` is not a
charted project is unresolved, and `ecosystem` `unknown` draws no diagram. The
reason is `unknown_reason` when that field is set, otherwise `message`.

## Physical shape

One object per line. A reader exits 1 on any other layout, including a
compacted record and a record with one key per line. Empty arrays may sit on
the key's line (`"nodes": []`).

A node line's first key is `id`. An edge line's first key is `from`.

```json
{
  "schema_version": 1,
  "generated_on": "YYYY-MM-DD",
  "subject": "<directory basename, or the origin repository name>",
  "ecosystem": "dotnet",
  "unknown_reason": "",
  "unshipped": "",
  "node_threshold": 24,
  "nodes": [
    {"id":"src/Api/Api.csproj","name":"Api","path":"src/Api/Api.csproj","ecosystem":"dotnet","kind":"project"}
  ],
  "edges": [
    {"from":"src/Api/Api.csproj","to":"src/Domain/Domain.csproj","kind":"project","evidence":"src/Api/Api.csproj: <ProjectReference Include=\"..\\Domain\\Domain.csproj\""}
  ]
}
```

## Fields

| Field | Meaning |
|---|---|
| `ecosystem` | `dotnet` when the .NET adapter ran. `unknown` otherwise, with both arrays empty. The reason is `unknown_reason` or, from `dependency-graph.sh`, `message`. |
| `node_threshold` | Component count above which the view aggregates. Default 24 when the field is absent. |
| node `kind` | `project` or `package`. |
| node `namespace` | Optional. Namespace grouping uses it when present, else the node `name`. |
| edge `kind` | `project` (internal), `package` (external, collapsed), or `unresolved`. A `project` edge whose `to` is not a charted project, including `dependency-graph.sh`'s `status` `unresolved`, is unresolved. |
| edge `evidence` | `<repo-relative file>: <matched declaration>`. |

`ProjectReference` and `PackageReference` are accepted as edge kinds and treated
as `project` and `package`. A breaking change to this shape bumps
`schema_version`.

## What an edge is

A `project` edge's `to` is the repo-relative path of a project file this scan
charted, after resolving the Include relative to the declaring project and
collapsing `.` and `..`. A missing target, a path that escapes the root, an
absolute path, or a glob is `unresolved`. The `to` of an unresolved edge is the
Include text. It is never matched by project name to some other file on disk.

A package edge's `to` is `pkg:<Include>` from `dependency-graph.sh` and
`nuget:<Include>` from the fallback. Package nodes are collapsed on the
diagram. Their declarations stay in the evidence table.

`ecosystem: unknown` is the result for an unrecognized ecosystem. The renderer
writes `unknown_reason` when set, otherwise `message`, and does not draw a
diagram.
