---
description: "Regression guard: a request already the right size (one rename). The reply says it is the right size and stops instead of inflating it. Both arms are expected to keep scope bounded; paired with the hard-goal case, which a person judged hard."
tags: [discipline, be-ambitious, outcome, regression-guard]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, Bash]
expected_outcome: "Says the request is already the right size, raises nothing, and makes no Write, Edit or Bash call."
---

/discipline:be-ambitious Rename the variable `tmp` to `retry_count` in this function:

```python
def fetch(url):
    tmp = 0
    while tmp < 3:
        tmp += 1
```
