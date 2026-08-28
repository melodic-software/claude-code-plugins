# Parsing the build log

The runner's own documentation states the shape:

> Each log line is a JSON object carrying the task id, the event name, a monotonic timestamp in
> milliseconds since the run started, and nothing else at the top level. Payloads specific to an
> event live under a `data` key, so a consumer that does not recognize an event can still read
> its identity and its ordering.
>
> — Widget Runner docs, `https://example.invalid/widget-runner/docs/logs`, read 2026-08-26

Our parser leans on that last guarantee. We match on the event name and ignore anything under
`data` we were not written to expect, which is how the parser survived two runner upgrades
without a change.

The same page notes that "a line longer than 64 kilobytes is truncated and marked `truncated:
true`" (`https://example.invalid/widget-runner/docs/logs`, read 2026-08-26), which is why our
oversized-payload test asserts on the flag rather than on the payload.
