---
schema_version: "1.1"
name: shape-and-depth-nested-radius
description: "Hard (the familiar shortcut is to copy the panel's radius, and the common formula forgets the border): a pane inside a bordered, padded panel takes the outer radius minus the border width minus the padding"
tags: [web, shape-and-depth, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The preview pane's border-radius is 16px (28px outer radius minus the 2px border minus the 10px padding), not the panel's 28px, not 18px and not 26px"
---

Design question about our settings screen. The settings panel has `border-radius: 28px`, a `2px solid` border and `padding: 10px`, and the preview pane inside it also has `border-radius: 28px`. Where the pane meets the panel, the corners look pinched and uneven. What radius should the preview pane get, and why? This run cannot write files, so put the CSS in your reply.
