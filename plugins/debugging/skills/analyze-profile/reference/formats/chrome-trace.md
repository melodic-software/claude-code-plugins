# Chrome trace events

Load this page when the artifact is a JSON array of event objects, or an object with a
`traceEvents` array; a `.json.gz` file is the same thing gzipped, and the converter reads it as is.
Chrome DevTools Performance recordings, `chrome://tracing`, Perfetto's JSON export and many
non-browser tools write this shape.

Format pointer: the Trace Event Format document,
<https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU>, and Perfetto's
documentation, <https://perfetto.dev/docs/>. As of 2026-10-04. Recheck when the converter exits 2
on a trace a current Chrome saved, or when DevTools changes its save format.

## What the converter stores

- `events`: one row per event in file order. `ph` is the phase (`X` complete, `B`/`E` begin and
  end, `M` metadata, `P` sample data), `ts` and `dur` are microseconds, `args` is the event's
  arguments as JSON text with GitHub tokens, AWS access key ids and `Bearer` values redacted (only
  those shapes; review the rest by hand).
- `frames` and `samples`: the CPU samples DevTools embeds in `ProfileChunk` events, one profile per
  `pid:id` pair. Same columns as the `.cpuprofile` page; `samples.ts` starts from the `startTime`
  of the `Profile` event with the same `pid:id`, so it is on the events' clock.

## Queries

Run each with `query_profile.py`, as shown on the `.cpuprofile` page.

Thread names, to find the main thread:

```sql
SELECT pid, tid, json_extract(args, '$.name') FROM events WHERE ph = 'M' AND name = 'thread_name';
```

Longest complete events on one thread (`--param pid=<pid> --param tid=<tid>`):

```sql
SELECT seq, name, ts, dur FROM events
WHERE ph = 'X' AND pid = :pid AND tid = :tid ORDER BY dur DESC LIMIT 20;
```

Time per event name on that thread, to tell scripting from layout and paint:

```sql
SELECT name, COUNT(*), SUM(dur) AS total_us FROM events
WHERE ph = 'X' AND pid = :pid AND tid = :tid GROUP BY name ORDER BY total_us DESC LIMIT 20;
```

Frames sampled inside one event (`--param seq=<event seq>` from the queries above), from the
profiles of the event's process: a sample counts when its `ts` falls in `[ts, ts + dur)`.

```sql
SELECT s.profile, f.id, f.name, f.url, f.line, COUNT(*) AS self_samples
FROM events e
JOIN samples s ON s.profile LIKE e.pid || ':%' AND s.ts >= e.ts AND s.ts < e.ts + e.dur
JOIN frames f ON f.profile = s.profile AND f.id = s.frame
WHERE e.seq = :seq GROUP BY s.profile, f.id ORDER BY self_samples DESC LIMIT 15;
```

`samples.ts` is NULL when the trace has no `Profile` event with a `startTime` for that profile;
then the samples cannot be placed against events.

## Reading it

A long `Layout` or `Recalculate Style` right after script that reads geometry points at forced
synchronous layout: find the script frame in the samples just before it. Long tasks with few
samples inside them usually mean time spent outside JavaScript; check the event names under the
same task.
