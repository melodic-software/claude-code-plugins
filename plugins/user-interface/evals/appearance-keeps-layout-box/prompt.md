---
schema_version: "1.1"
name: appearance-keeps-layout-box
description: "Hard (a live number and its loading state usually shift the layout): a number that updates in place uses tabular digits in a fixed-width slot, and the skeleton has the final size"
tags: [web, motion, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The countdown uses tabular digits (font-variant-numeric: tabular-nums or the equivalent) in a fixed-width slot, and its loading skeleton is sized to the final layout, so no appearance change moves the layout box"
---

Design a countdown timer for a web page that shows the minutes and seconds left in a sale, ticking once a second, with a loading state while the end time is fetched. Describe the design and give the CSS in your reply in under 200 words. This run cannot write files.
