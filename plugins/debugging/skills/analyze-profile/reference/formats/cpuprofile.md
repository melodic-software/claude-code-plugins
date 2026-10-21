# V8 `.cpuprofile`

Load this page when the artifact is a JSON object with `nodes`, `samples` and usually
`timeDeltas`, `startTime` and `endTime`. Node.js writes it with its CPU profile flag; Chrome
DevTools and the inspector protocol save the same shape.

Format pointer: the `Profile` type in the DevTools protocol Profiler domain,
<https://chromedevtools.github.io/devtools-protocol/tot/Profiler/>. As of 2026-10-04.
Recheck when the converter exits 2 on a profile a current Node.js or Chrome wrote.

## What the converter stores

- `frames`: one row per profile node, `profile = 'main'`. `parent` comes from the node's
  `children` list. `line` and `col` are 1-based; NULL when the frame has no position, as for
  `(root)`, `(program)`, `(idle)` and `(garbage collector)`.
- `samples`: one row per sample in order, `frame` is the node id the sample landed in, `delta_us`
  the gap since the previous sample in microseconds, and `ts` the profile's `startTime` plus every
  delta so far (NULL when the profile has no `startTime`).

## Queries

Run each with the read-only query script, binding values such as `:profile` and `:id` with
`--param`:

```bash
python3 "<skill-dir>/scripts/query_profile.py" \
  "$work/profile.db" "<query>" --param profile=main --param id=5
```

Heaviest frames by self samples:

```sql
SELECT f.profile, f.id, f.name, f.url, f.line, COUNT(*) AS self_samples
FROM samples s JOIN frames f ON f.profile = s.profile AND f.id = s.frame
GROUP BY f.profile, f.id ORDER BY self_samples DESC LIMIT 15;
```

Every profile numbers its frames from 1, so a frame is named by its `profile` and `id` together:
`main` here, `<pid>:<id>` in a Chrome trace.

Caller path above one frame (`--param profile=<profile> --param id=<frame id>`):

```sql
WITH RECURSIVE up(profile, id, parent, name, url, line, depth) AS (
  SELECT profile, id, parent, name, url, line, 0 FROM frames WHERE profile = :profile AND id = :id
  UNION ALL
  SELECT f.profile, f.id, f.parent, f.name, f.url, f.line, up.depth + 1
  FROM frames f JOIN up ON f.profile = up.profile AND f.id = up.parent
)
SELECT depth, name, url, line FROM up ORDER BY depth;
```

Share of the run spent outside JavaScript:

```sql
SELECT s.profile, f.name, COUNT(*) FROM samples s
JOIN frames f ON f.profile = s.profile AND f.id = s.frame
WHERE f.name IN ('(program)', '(idle)', '(garbage collector)') GROUP BY s.profile, f.name;
```

## Resolving the symbol

A `url` pointing at a bundle (`main.3f9a.js`) with a short or mangled name needs the bundle's source
map. The `source-map` library (<https://github.com/mozilla/source-map>, as of 2026-10-04, recheck on
its next major release) maps a generated line and column back to the original file and line. With
no map available, report the bundle position and say that the map is missing.
