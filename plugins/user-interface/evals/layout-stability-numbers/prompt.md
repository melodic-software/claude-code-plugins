---
schema_version: "1.1"
name: layout-stability-numbers
description: "Hard (the familiar shortcut for jumping digits is a monospace font, which changes the face; and the label swap that shoves its neighbors is easy to miss): a live timer takes equal-width digits in its own font, and a button whose label changes keeps a fixed or minimum width"
tags: [web, layout-stability, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The timer gets `font-variant-numeric: tabular-nums` (or the Tailwind class `tabular-nums`) and keeps the interface font, not a monospace face; the save button gets a fixed or minimum width set as a length, not a content keyword such as `fit-content`, or stacks both labels in one grid cell, so 'Saving…' does not change its width"
---

Our recording toolbar shows a live timer like `0:41.18` in Inter next to a "Recording" label, then a "Save" button and a "Discard" button in a row. The digits in the timer keep jumping around as it counts, and when you click Save its label changes to "Saving…" and shoves Discard to the right. Fix both. This run cannot write files, so put the CSS in your reply.
