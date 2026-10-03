---
description: "Renamed to /review:explain-change. This stub stays for one release and only points there. Use when: '/review:pr-explainer' is typed by name."
argument-hint: "[pr-number|this branch]"
user-invocable: true
disable-model-invocation: true
metadata:
  workflow-stage: review
  summary: Renamed to /review:explain-change; one-release stub
---

# Renamed: use `/review:explain-change`

`/review:pr-explainer` is now `/review:explain-change`. Tell the reader the new name, then run `/review:explain-change` with the same arguments. This stub does nothing else and is removed in the next release.

## Next

/review:explain-change

## Gotchas

- This stub builds nothing. The old builder is gone, so any page comes from `/review:explain-change`.
