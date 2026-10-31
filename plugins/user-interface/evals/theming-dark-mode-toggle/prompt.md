---
schema_version: "1.1"
name: theming-dark-mode-toggle
description: "Happy path: a dark mode toggle flips one set of color variables at the theme root instead of per-component dark overrides, and suppresses transitions while the theme switches"
tags: [web, theming, happy-path]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Components read color variables whose values flip once at the theme root under a class or attribute the toggle sets (a dark theme selector, or light-dark() tokens switched through color-scheme), and the toggle turns transitions off for the switch and back on after paint"
---

Add a dark mode with a toggle button to this React app. Each component sets its own colors today.

```css
.header { background: #ffffff; color: #111111; transition: background-color 200ms, color 200ms; }
.card { background: #ffffff; color: #111111; transition: background-color 300ms; }
.button { background: #111111; color: #ffffff; transition: background-color 150ms; }
```

This run cannot write files, so put the CSS and the toggle component in your reply.
