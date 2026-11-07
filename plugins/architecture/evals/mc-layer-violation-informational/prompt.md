---
description: "Convention home declares component_layers host, application, domain and diagram_dialect.system c4-plantuml; Billing.Domain references Billing.Application back, and Billing.Shared sits in no declared layer. Grouping by layer passes --group-by layer and exactly --layers host,application,domain to render-components.sh, tags only the Domain -> Application edge as a layer violation in the diagram and the violations table, leaves Billing.Shared in the undeclared group instead of a declared layer, quotes violations=1, and says enforcement belongs to architecture tests. Needs --scaffold and --allow-tools Bash."
tags: [architecture, map-components, outcome, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "A render-components.sh call passes --group-by layer and --layers host,application,domain with no other layer. docs/architecture/components.md declares the layer-violation tag, puts $tags=\"layer-violation\" on the Billing.Domain -> Billing.Application Rel and on no other Rel, lists that edge under Layer violations, and draws Billing.Shared outside the host, application and domain boundaries. The reply quotes violations=1 and says enforcement belongs to the consumer's architecture tests."
---

/architecture:map-components Billing.Api --group-by layer
