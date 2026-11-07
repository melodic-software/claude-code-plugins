---
schema_version: "1.1"
name: glossary-manual-not-optical-kerning
description: "Hard: 'optical' suggests judging by eye, pulling toward agreeing with the wrong premise."
tags: [glossary, forward-lookup, hard]
runs: 5
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply says it is manual kerning, defines optical kerning as automatic from glyph shapes, and names metrics kerning"
---

Our designer nudged the A and the V in the logo by eye until the gap looked right. Is that what optical kerning means?
