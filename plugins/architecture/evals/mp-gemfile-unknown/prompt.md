---
description: "A Ruby service with a Gemfile and no manifest a shipped adapter reads, convention home with architecture_dir docs/architecture, non-interactive: dependency-graph.json reads result unknown with no nodes or edges, dependency-graph.md has no mermaid fence and no gem, and the reply says unknown, names the Gemfile, says no empty graph was invented, and asks for no ecosystem. Needs --scaffold and --allow-tools Bash."
tags: [architecture, map-dependencies, outcome, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "docs/architecture/dependency-graph.json holds result unknown and empty nodes and edges arrays. docs/architecture/dependency-graph.md says Result: unknown and holds no mermaid fence and no gem name. The reply says unknown, names the Gemfile, says an empty graph was not invented, and does not ask which ecosystem to use."
---

/architecture:map-dependencies
