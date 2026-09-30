# Report views: which one to draw

The build report can render four views of one run: a task graph, a timeline, a cache map and a
log excerpt. This page says how to pick.

## Examples

```
widget report --view graph --focus compile
widget report --view timeline --since 10m
```

## Guidance

- Choose the narrowest view that still carries the main finding.
- Put each view beside the sentence it backs up.
- Include only the jobs, cache entries, workers and locks that bear on what the reader asked,
  or on the choices still open in the thread.
- Any one view can work, several can, and all four together almost never do. Use restraint and
  do not pad the page.

## Sharing a report

Attach the rendered HTML to the pull request. Reports older than a week are regenerated.
