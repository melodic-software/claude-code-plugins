---
schema_version: "1.1"
name: web-performance-long-list
description: "Happy path: a list of 5,000 rows that scrolls badly is virtualized with the virtualizer the project already depends on, rendering only the visible rows, each placed at its offset inside an inner element as tall as the whole list"
tags: [web, web-performance, happy-path]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The list renders through `useVirtualizer` from `@tanstack/react-virtual` (already a dependency), so only the visible rows exist in the DOM; the scroller keeps its fixed height and overflow, an inner element comes to the virtualizer's total size, and the rows are placed from their virtual items' start: each row absolutely positioned inside a positioned inner element, one wrapper translated by the first item's start, or spacer padding before and after the rows"
---

This list of 5,000 rows scrolls janky, make it smooth.

```jsx
import { useEffect, useState } from 'react';

export function LogList() {
  const [rows, setRows] = useState([]);

  useEffect(() => {
    fetch('/api/logs?limit=5000').then((r) => r.json()).then(setRows);
  }, []);

  return (
    <div className="log-list" style={{ height: 480, overflow: 'auto' }}>
      {rows.map((row) => (
        <div key={row.id} className="log-row" style={{ height: 32 }}>
          {row.message}
        </div>
      ))}
    </div>
  );
}
```

`@tanstack/react-virtual` is already in our `package.json`; nothing uses it yet. This run cannot
write files, so put the component in your reply.
