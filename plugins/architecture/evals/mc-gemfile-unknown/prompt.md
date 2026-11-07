---
description: "A Ruby service with a Gemfile, no .NET project and no dependency-graph.json, convention home with diagram_dialect.system c4-plantuml: the component view runs dependency-graph.sh with --out docs/architecture/dependency-graph.json, that record reads result unknown with no nodes or edges, and components.md says unknown and draws no diagram block or gem. Needs --scaffold and --allow-tools Bash."
tags: [architecture, map-components, outcome, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "A Bash call runs dependency-graph.sh with --out docs/architecture/dependency-graph.json. That file holds result unknown and empty nodes and edges arrays. docs/architecture/components.md says the ecosystem is unknown, holds no fenced block, and names no gem from the Gemfile."
---

/architecture:map-components
