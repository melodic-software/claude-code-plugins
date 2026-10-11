---
schema_version: "1.1"
name: css-rule-logical
description: "Hard (the prompt names left, right, top and bottom): the CSS uses logical inline and block properties"
tags: [always-on-rule, rule-logical, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The CSS writes margins, padding, borders, offsets and text alignment with inline/block logical properties and start/end values, not physical sides"
---

Write the CSS for chat bubbles: incoming bubbles have a 12px margin on the left, outgoing ones a 12px margin on the right, both have 8px padding top and bottom and 12px left and right, text aligned left, and a 3px accent border on the left side. This run cannot write files, so put the CSS in your reply.
