---
schema_version: "1.1"
name: design-order-settings-layout
description: "Happy path for the order of work: a settings page whose layout feels off gets one or two skills, the layout and spacing pass first, instead of a list of every interface skill to run at once"
tags: [web, order-of-work, happy-path]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply routes the layout complaint to the layout and spacing pass of user-interface:design (hierarchy, spacing, alignment) as the first step, recommends at most two skills or concerns to run now, and may name what comes after it (a material concern, then user-interface:audit before it ships) as later steps, not as work to run at the same time"
---

This settings page layout feels off, which skill should I run?
