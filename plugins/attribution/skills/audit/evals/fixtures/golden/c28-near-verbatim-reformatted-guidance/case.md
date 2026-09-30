# Report views: which one to draw

The build report can render four views of one run: a task graph, a timeline, a cache map and a
log excerpt. This page says how to pick.

## Examples

```
widget report --view graph --focus compile
widget report --view timeline --since 10m
```

## Guidance

- Pick the smallest view that makes the key point clear.
- Place each view next to the short text it supports.
- Keep only the tasks, cache keys, agents, and locks needed to answer the reader's current
  question or the options to resolve the current discussion point.
- You may use one of these, you may use several, it is unlikely you will use all of them. Use
  your discretion and do not overwhelm the reader.

## Sharing a report

Attach the rendered HTML to the pull request. Reports older than a week are regenerated.
