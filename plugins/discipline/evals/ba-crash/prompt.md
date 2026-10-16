---
description: "A software fix request (stop one crash). The reply raises it from fixing one crash toward the importer not crashing on malformed input, with concrete methods and an executable check, fences scope, and edits nothing."
tags: [discipline, be-ambitious, outcome]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, Bash]
expected_outcome: "Raised version aims past the single crash (for example property-based or fuzz tests over malformed rows) with an executable check; a scope fence; no Write, Edit or Bash call."
---

/discipline:be-ambitious Fix the crash in this CSV importer when a row is empty:

```python
def load_rows(path):
    rows = []
    with open(path) as f:
        for line in f:
            name, qty, price = line.strip().split(",")
            rows.append({"name": name, "qty": int(qty), "price": float(price)})
    return rows
```
