---
description: "Convention home declares architecture_dir docs/architecture and diagram_dialect.system c4-plantuml, and docs/architecture/dependency-graph.json already holds Billing.Api -> Billing.Application -> Billing.Domain: the component view renders that graph without re-collecting it or touching it, through render-components.sh with --dialect c4-plantuml and directory grouping, draws the three components and the two declared edges with cited declarations in one plantuml block, never hand-writes components.md, closes with the fixed report quoting the summary counts, and offers the interactive view without building it. Needs --scaffold and --allow-tools Bash,Write,Edit."
tags: [architecture, map-components, outcome, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "No Bash call runs dependency-graph.sh. A render-components.sh call passes --dialect c4-plantuml and no namespace or layer grouping. docs/architecture/components.md says Grouping: directory, holds Component entries for Billing.Api, Billing.Application and Billing.Domain, Rel lines Api -> Application and Application -> Domain only, evidence rows citing each ProjectReference, and exactly one plantuml fence. No Write, Edit or shell write targets components.md or dependency-graph.json. The reply's report labels run Artifacts, Container, Grouping, Components, Thin result, Layer violations, Aggregated, External and unresolved, Graph source, Dialect in order, quotes components=3 edges=2 drawn_edges=2, offers the interactive view, and no build-view.mjs call runs."
---

/architecture:map-components
