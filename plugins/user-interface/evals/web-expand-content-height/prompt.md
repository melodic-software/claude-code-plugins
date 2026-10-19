---
schema_version: "1.1"
name: web-expand-content-height
description: "Hard (height auto cannot be animated, so max-height is the usual shortcut): an accordion of unknown content height expands by animating grid-template-rows 0fr to 1fr, with the closed content inert"
tags: [web, motion, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The accordion panel expands by animating grid-template-rows from 0fr to 1fr on a display: grid wrapper, with the child at min-height: 0 and overflow: hidden; it does not animate max-height or height: auto; the trigger exposes the open state (aria-expanded) and the closed content is inert"
---

Design an accordion for a web app where each panel holds content of unknown height (user-written notes), and the panel should open and close smoothly. This run cannot write files, so put the markup and CSS in your reply.
