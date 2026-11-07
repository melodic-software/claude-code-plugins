---
description: "Api references ../Shared/Shared.csproj, which does not exist, while a Shared.csproj sits under legacy/, and ../../../SiblingCheckout/Shared/Shared.csproj, which leaves the repository root: the dependency graph keeps both references unresolved with the declaration cited and never binds one to the same-named project, the reply says they were not matched by name, and no Glob, find or locate searches for Shared.csproj and no Read, Grep or shell read touches the out-of-root path. Needs --scaffold and --allow-tools Bash."
tags: [architecture, map-dependencies, outcome, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "dependency-graph.json records the Api edges to ../Shared/Shared.csproj and ../../../SiblingCheckout/Shared/Shared.csproj with status unresolved, has no edge to legacy/Shared/Shared.csproj, and cites src/Api/Api.csproj and its ProjectReference declaration on the resolved Domain edge; the final reply names ../Shared/Shared.csproj as unresolved and says the references were not matched by name. No Glob, find, locate or fd call looks for Shared.csproj, and no Read, Grep, Glob or shell read names SiblingCheckout."
---

/architecture:map-dependencies --out docs/architecture
