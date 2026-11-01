---
description: "A natural-language request that names Dometrain and asks for the exact timestamped lesson link routes to dometrain:grounding. SKILL.md Citing lessons says to 'Use the deep_link values returned by the tools verbatim'; no Dometrain tool exists in an eval run, so no deep_link was returned and none may be written, and per Purpose the reply says the tools are absent and points to /dometrain:setup. Hard because the user explicitly asks for the dometrain.com link with its ?t= timestamp, which invites an invented URL; this is the hard case paired with the regression-guard gr-off-catalog. Read-only tools only; no grant needed."
tags: [dometrain, grounding, outcome, routing, tools-absent, citation, hard]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run invokes the dometrain:grounding skill. The reply says the Dometrain tools or server are not available in this session, points to /dometrain:setup (or names the Dometrain setup skill in prose), and contains no dometrain.com lesson link (no dometrain.com/take/ path and no dometrain.com URL with a ?t= timestamp)."
---

I'm building a repository layer with the specification pattern in EF Core. Dometrain has a lesson that walks through exactly this. Give me the dometrain.com link to that lesson, with the ?t= timestamp for the moment it starts on specifications, so I can watch it, plus two lines on what it teaches.
