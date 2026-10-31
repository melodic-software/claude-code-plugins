---
schema_version: "1.1"
name: icons-sidebar-stroke
description: "Happy path: 16px sidebar icons drawn with a 24px icon's 2px stroke get a stroke thinner for their size, and a filled icon from another set is replaced by an outline drawing that matches the rest"
tags: [web, icons, happy-path]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Every outline icon's stroke is a smaller share of its size than the original 2 in 16 (about 1.5 in 16, 1.5px at 16px), and the Reports icon becomes an outline drawing with no fill and the same stroke for its size as the others"
---

The 16px icons in this sidebar look heavy beside the labels, and the Reports icon doesn't look like
it belongs. Fix the icons. This run cannot write files, so put the corrected markup in your reply.

```html
<nav class="sidebar">
  <a href="/">
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M2 7 8 2l6 5v7H10v-4H6v4H2z" />
    </svg>
    Home
  </a>
  <a href="/inbox">
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M2 9h3l1 2h4l1-2h3" />
      <path d="M4 3h8l2 6v4H2V9z" />
    </svg>
    Inbox
  </a>
  <a href="/reports">
    <svg width="16" height="16" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
      <path d="M2 11h3v7H2zm6-5h3v12H8zm6-4h3v16h-3z" />
    </svg>
    Reports
  </a>
</nav>
```
