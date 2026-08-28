# Widget Runner: the log format

Synthetic source page for the provenance golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/docs/logs`.

## One line per event

Each log line is a JSON object carrying the task id, the event name, a monotonic timestamp in
milliseconds since the run started, and nothing else at the top level. Payloads specific to an
event live under a `data` key, so a consumer that does not recognize an event can still read its
identity and its ordering.

## Truncation

A line longer than 64 kilobytes is truncated and marked `truncated: true`. The runner never
splits one event across two lines, because a consumer reading the stream incrementally cannot
tell a split from a new event.
