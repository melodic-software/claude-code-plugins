---
description: "Triggering case for engineering-concepts:load. The request asks to bring a catalog topic into the session as working context before design work, the description's main use. The plugin ships no curated records yet, so the answer is not graded; the grader reads only the Skill call."
tags: [engineering-concepts, load, triggering]
max_turns: 8
timeout_seconds: 240
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "A Skill call loads engineering-concepts:load."
---

Before we design the new export service, load the engineering-concepts topic on modularity into this session so we keep those concepts in view while we work.
