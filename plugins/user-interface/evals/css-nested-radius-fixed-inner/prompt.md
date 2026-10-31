---
schema_version: "1.1"
name: css-nested-radius-fixed-inner
description: "Hard (the padding is larger than the inner radius): Written from MB:plugins/user-interface/skills/write-css/reference/spacing-and-shape.md:139-164. With the inner radius fixed by the design system, the outer radius is the inner radius plus the padding; deriving the inner from the outer would reach zero. Head derives the inner from the outer by default, but where the project fixes the inner token it adds the gap to it, so both versions share the outcome."
tags: [web, shape, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The container's radius is the button token plus the 16px padding (calc(var(--radius-control) + 16px), 22px), and the button and input keep var(--radius-control)"
---

Our search field is a rounded container with 16px of padding holding a text input and a Search
button. The input's and button's corners come from our design-system token
`--radius-control: 6px`, which every button and input must use. Give the container corners that
sit concentric with the button. The container has no border. Plain CSS. This run cannot write
files, so put the CSS in your reply.
