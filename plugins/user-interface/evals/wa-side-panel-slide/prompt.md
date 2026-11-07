---
schema_version: "1.1"
name: wa-side-panel-slide
description: "Routine: the slide ships with its reduced-motion variant, on the drawer curve within the large role, and exits the edge it entered."
tags: [write-animation, reduced-motion, routine]
runs: 3
max_turns: 20
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer slides the panel in from the right and back out the right edge within 300ms, with a reduced-motion variant in the same answer that removes the slide"
---

Make the side panel slide in from the right when it opens and slide back out when it closes. This run cannot write files, so put the code in your reply.
