---
description: "Api references ../Shared/Shared.csproj, which does not exist, while a Shared.csproj sits under legacy/: the dependency graph keeps the reference unresolved with its declaration cited and never binds it to the same-named project"
tags: [architecture, map-dependencies, outcome, scaffold]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "dependency-graph.json records the Api edge to ../Shared/Shared.csproj with status unresolved, has no edge to legacy/Shared/Shared.csproj, and cites src/Api/Api.csproj and its ProjectReference declaration on the resolved Domain edge; the final reply names ../Shared/Shared.csproj as unresolved."
---

/architecture:map-dependencies --out docs/architecture
