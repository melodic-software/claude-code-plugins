---
description: "Convention home declares architecture_dir docs/architecture; src/App/App.csproj references src/Lib/Lib.csproj and the Newtonsoft.Json package, and no graph exists yet: the dependency map runs dependency-graph.sh into docs/architecture/dependency-graph.json, which keeps one object per line with the resolved App -> Lib project edge citing its ProjectReference and a package edge to pkg:Newtonsoft.Json, renders through render-dependencies.sh with Newtonsoft.Json absent from the mermaid flowchart, never hand-writes either file, quotes the summary line, and offers the interactive view without building it. Needs --scaffold and --allow-tools Bash,Write,Edit."
tags: [architecture, map-dependencies, outcome, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "A Bash call runs dependency-graph.sh writing docs/architecture/dependency-graph.json, whose App -> Lib edge line reads kind project, status resolved and cites src/App/App.csproj's ProjectReference, with a package edge line to pkg:Newtonsoft.Json. A render-dependencies.sh call runs with --record, and dependency-graph.md's mermaid flowchart draws App --> Lib and never Newtonsoft. No Write or Edit targets either file and no shell write targets dependency-graph.md. The reply quotes result=ok, nodes=3, internal_edges=1 and external_edges=1 from the summary line and offers the interactive view; no build-view.mjs call runs."
---

/architecture:map-dependencies
