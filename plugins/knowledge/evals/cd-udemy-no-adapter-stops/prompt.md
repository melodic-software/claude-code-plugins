---
description: "A Udemy course URL hits the Platform detection table row that has no adapter: the reply reports that no adapter exists and points at the discovery checklist, and the run stops with no extraction script and no file written or edited (no improvised adapters/udemy.js)"
tags: [knowledge, course-digest, outcome, stop-gate]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply says Udemy has no adapter (unsupported), names the provider discovery checklist as where adding one starts, and stops. No Bash call runs a course extraction script or Playwright; no Write or Edit call."
---

/knowledge:course-digest https://www.udemy.com/course/clean-architecture-in-dotnet/
