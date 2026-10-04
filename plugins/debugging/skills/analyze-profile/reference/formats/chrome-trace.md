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
  arguments as JSON text with secret-shaped strings redacted.
- `frames` and `samples`: the CPU samples DevTools embeds in `ProfileChunk` events, one profile per
  `pid:id` pair. Same columns as the `.cpuprofile` page.

## Queries

Run each with `query_profile.py`, as shown on the `.cpuprofile` page.

Thread names, to find the main thread:

```sql
SELECT pid, tid, json_extract(args, '$.name') FROM events WHERE ph = 'M' AND name = 'thread_name';
```

Longest complete events on one thread (`--param pid=<pid> --param tid=<tid>`):

```sql
SELECT name, ts, dur FROM events
WHERE ph = 'X' AND pid = :pid AND tid = :tid ORDER BY dur DESC LIMIT 20;
```

Time per event name on that thread, to tell scripting from layout and paint:

```sql
SELECT name, COUNT(*), SUM(dur) AS total_us FROM events
WHERE ph = 'X' AND pid = :pid AND tid = :tid GROUP BY name ORDER BY total_us DESC LIMIT 20;
```

The frames that ran inside a long event come from `frames` and `samples` with the heaviest-frame
query on the `.cpuprofile` page; filter on the profile whose `pid` matches the thread.

## Reading it

A long `Layout` or `Recalculate Style` right after script that reads geometry points at forced
synchronous layout: find the script frame in the samples just before it. Long tasks with few
samples inside them usually mean time spent outside JavaScript; check the event names under the
same task.
