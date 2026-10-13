---
description: "A claimed off-by-one in paginate, whose 1-based math is correct, gets the No bug confirmed summary instead of a five-field report"
tags: [bugs, write, outcome, no-bug]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "A 'No bug confirmed' summary with the claimed description, the verified state grounded in the (page - 1) * pageSize math (page 2 starts at index pageSize), and a recommendation. No steps-to-reproduce section and no severity line."
---

/bugs:write There's a bug in `paginate` in apps/reports/src/paginate.js: page 2 skips the last row that should have been on page 1, it's off by one. Here is the whole function; it is the only `paginate` in the repo and it has not changed in six weeks:

```javascript
// Returns the slice of `items` for a 1-based page number.
// page 1 => items[0 .. pageSize-1], page 2 => items[pageSize .. 2*pageSize-1], ...
export function paginate(items, page, pageSize) {
  const start = (page - 1) * pageSize;
  return items.slice(start, start + pageSize);
}
```

Report the bug.
