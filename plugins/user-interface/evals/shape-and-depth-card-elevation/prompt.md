---
schema_version: "1.1"
name: shape-and-depth-card-elevation
description: "Happy path: cards that draw depth with a solid border get a layered shadow token instead, and the harsh dark-mode border is changed"
tags: [web, shape-and-depth]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The card's depth comes from a stacked box-shadow of two or more layers in place of the solid border, and the dark theme no longer draws the harsh #444 border"
---

Give these cards elevation and fix the harsh border in dark mode.

```css
.card {
  border: 1px solid #e0e0e0;
  border-radius: 12px;
  padding: 16px;
}

.dark .card {
  border-color: #444;
}
```

This run cannot write files, so put the CSS in your reply.
