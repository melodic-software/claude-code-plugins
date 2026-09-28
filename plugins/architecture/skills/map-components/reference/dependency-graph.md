# dependency-graph.json

The record `map-components` renders. `map-dependencies` is the shared extractor.
Until that skill is present, [component-graph.sh](../scripts/component-graph.sh)
writes the same schema_version 1 shape from .NET `ProjectReference` and
`PackageReference` declarations.

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
| `ecosystem` | `dotnet` when the .NET adapter ran. `unknown` otherwise, with `unknown_reason` set and both arrays empty. |
| `node_threshold` | Component count above which the view aggregates. Default 24 when the field is absent. |
| node `kind` | `project` or `package`. |
| node `namespace` | Optional. Namespace grouping uses it when present, else the node `name`. |
| edge `kind` | `project` (internal), `package` (external, collapsed), or `unresolved`. |
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

A package edge's `to` is `nuget:<Include>`. Package nodes are collapsed on the
diagram. Their declarations stay in the evidence table.

`ecosystem: unknown` is the result for an unrecognized ecosystem. The renderer
writes that reason and does not draw a diagram.
