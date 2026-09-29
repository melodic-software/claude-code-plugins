# dependency-graph.json as the renderer reads it

`dependency-graph.sh` in `map-dependencies` writes the record, and its header is
the schema (`--help` prints it). This page is what `render-components.sh` takes
from it. A record with no `result` key did not come from that script, and the
renderer exits 1 on it.

## Physical shape

One object per line. The renderer exits 1 on any other layout, including a
compacted record and a record with one key per line. Empty arrays may sit on
the key's line (`"nodes": []`).

A node line's first key is `id`. An edge line's first key is `from`.

```json
{
  "schema_version": 1,
  "generated_on": "YYYY-MM-DD",
  "result": "ok",
  "message": "",
  "ecosystem": "dotnet",
  "node_threshold": 40,
  "cycles_truncated": false,
  "nodes": [
    {"id":"src/Api/Api.csproj","name":"Api","path":"src/Api/Api.csproj","ecosystem":"dotnet","kind":"project"},
    {"id":"src/Domain/Domain.csproj","name":"Domain","path":"src/Domain/Domain.csproj","ecosystem":"dotnet","kind":"project"}
  ],
  "edges": [
    {"from":"src/Api/Api.csproj","to":"src/Domain/Domain.csproj","kind":"project","status":"resolved","evidence":"src/Api/Api.csproj: <ProjectReference Include=\"..\\Domain\\Domain.csproj\" />"}
  ],
  "cycles": [],
  "findings": []
}
```

## Fields

| Field | What the renderer does with it |
|---|---|
| `ecosystem` | `dotnet` renders a view. `unknown` writes the record's `message` and draws no diagram. |
| `message` | The reason shown for an `unknown` record. |
| `node_threshold` | Component count above which the view aggregates. 40 when absent. |
| node `kind` | `project` is a component. `package` is not one. |
| node `namespace` | Optional. Namespace grouping uses it when present, else the node `name`. |
| edge `kind` and `status` | A `project` edge with `status` `resolved` whose two ends are charted projects is an arrow. A `project` edge with `status` `unresolved` is listed and never drawn. A `package` edge is collapsed. |
| edge `evidence` | `<repo-relative file>: <matched declaration>`, cited in the edge table. |

## What an edge is

A resolved `project` edge's `to` is the repo-relative path of a project file the
scan charted. An unresolved edge's `to` is the Include text. It is never matched
by project name to some other file on disk, even when that text equals a charted
project's id.

A package edge's `to` is `pkg:<Include>`. Package nodes are collapsed on the
diagram. Their declarations stay in the edge table.

`ecosystem: unknown` is the result for an unrecognized ecosystem. It is not an
empty architecture.
