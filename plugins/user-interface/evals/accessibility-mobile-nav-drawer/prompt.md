---
schema_version: "1.1"
name: accessibility-mobile-nav-drawer
description: "Happy path: a slide-in mobile nav drawer takes its links out of the tab order while closed, and its icon-only close button gets a name that says the action"
tags: [web, accessibility, happy-path]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The closed drawer's links cannot be reached by Tab (inert, visibility hidden or display none on the closed panel, not opacity or a transform alone), and the icon-only close button has an accessible name that names the action, such as aria-label=\"Close menu\""
---

Build a mobile navigation drawer for our React app: a menu button opens a panel that slides in from
the left with five links, and an X icon button in the panel closes it. Today we hide the closed
panel like this:

```css
.drawer { transform: translateX(-100%); opacity: 0; transition: transform 200ms, opacity 200ms; }
.drawer[data-open] { transform: none; opacity: 1; }
```

This run cannot write files, so put the component and its CSS in your reply.
