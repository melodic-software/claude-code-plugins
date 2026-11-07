---
description: "Legacy be-ambitious 3. A software fix request (stop one crash). The reply raises it from fixing one crash toward the importer not crashing on malformed input, with concrete methods and an executable check named before any fresh-context reviewer (executable-check-first, llm), points at /discipline:scrutinize-dont-coast for that review (scrutinize-pointer, with-only; SKILL.md line 59), carries the two scope-fence lines verbatim (scope-fence-lines, with-only; SKILL.md line 99), and edits nothing. Needs --allow-tools Bash Write Edit so the no-* graders measure a reachable tool."
tags: [discipline, be-ambitious, outcome, no-network]
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
