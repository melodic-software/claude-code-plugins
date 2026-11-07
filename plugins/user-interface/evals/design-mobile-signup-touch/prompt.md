---
schema_version: "1.1"
name: design-mobile-signup-touch
description: "A form used by touch on phones reads touch-web.md beside web.md and applies its rules; the case never locks zoom."
tags: [design, web, touch]
runs: 3
max_turns: 25
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The design reads touch-web.md and applies at least three of its rules (hover gating, target size, input keyboard, no zoom lock, viewport units), and locks no zoom"
---

Design the mobile web version of our signup form. Most people fill it in on their phones. This run cannot write files, so put the design in your reply.
