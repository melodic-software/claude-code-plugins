# V8 `.heapsnapshot`

Load this page when the artifact is a JSON object with `snapshot`, `nodes`, `edges` and
`strings`. Chrome DevTools' Memory panel, the Node.js heap snapshot signal and the inspector
protocol write it.

Format pointer: the HeapProfiler domain of the DevTools protocol,
<https://chromedevtools.github.io/devtools-protocol/tot/HeapProfiler/>, and the DevTools heap
snapshot guide, <https://developer.chrome.com/docs/devtools/memory-problems/heap-snapshots>. The
field layout is described inside each file under `snapshot.meta`, and the converter reads it from
there. As of 2026-10-04. Recheck when the converter exits 2 on a snapshot a current Chrome or
Node.js wrote.

## What the converter stores

- `nodes`: one row per heap object. `idx` is its position in the file, `node_id` the snapshot's
  stable id, `type` (`object`, `string`, `closure`, `array`, `native`, `synthetic` and others),
  `name` (the constructor name, or the string's value for a string), `self_size` in bytes.
- `edges`: one row per reference, `from_idx` to `to_idx`, with its `type` (`property`, `element`,
  `context`, `internal`, `hidden`, `shortcut`, `weak`) and `name` (the property name, or the index
  for elements).

Snapshot files can run to hundreds of megabytes and the converter reads the whole file into
memory; run it, and the queries, in a subagent.

## Queries

Run each with `query_profile.py`, as shown on the `.cpuprofile` page.

Largest objects by type and name:

```sql
SELECT type, name, COUNT(*) AS n, SUM(self_size) AS bytes FROM nodes
GROUP BY type, name ORDER BY bytes DESC LIMIT 20;
```

Who points at one object (`--param idx=<node idx>`), skipping weak references:

```sql
SELECT e.type, e.name, n.idx, n.type, n.name FROM edges e JOIN nodes n ON n.idx = e.from_idx
WHERE e.to_idx = :idx AND e.type != 'weak';
```

Path from one object up to the root, one holder per step (same `--param idx`); `via` on each row
is the reference that holder uses to reach the row above:

```sql
WITH RECURSIVE path(idx, via, depth) AS (
  SELECT :idx, NULL, 0
  UNION ALL
  SELECT (SELECT e.from_idx FROM edges e WHERE e.to_idx = path.idx AND e.type != 'weak' LIMIT 1),
         (SELECT e.type || ':' || e.name FROM edges e WHERE e.to_idx = path.idx AND e.type != 'weak' LIMIT 1),
         depth + 1
  FROM path WHERE path.idx IS NOT NULL AND depth < 30
)
SELECT p.depth, p.via, n.type, n.name FROM path p JOIN nodes n ON n.idx = p.idx ORDER BY p.depth;
```

Node `idx = 0` is the synthetic root. The first holder found is not always the shortest path;
when the path loops or runs past 30 steps, query the holders at each step by hand.

## Reading it

The cause is the first holder on the path that the application owns: a module-level cache, a
listener list, a closure kept by a timer. Find where that holder is created or added to in source,
and report that file and line. One snapshot shows what is held, not what grows; for a leak, load
two snapshots taken minutes apart and compare counts per `type, name`.
