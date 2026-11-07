---
schema_version: "1.1"
name: glossary-layout-thrashing-strict
description: "Hard: the looser meaning is common, so the pull is to agree with the teammate; the case needs the strict definition and the layout-triggering-animation name."
tags: [glossary, forward-lookup, hard]
runs: 5
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply says no in the strict sense, defines layout thrashing as forced synchronous layout from reads after writes, and names the height animation a layout-triggering animation"
---

Our accordion animates its height property from 0 to auto on every frame and it stutters on cheap phones. A teammate says that's layout thrashing. Is that the right word for it?
