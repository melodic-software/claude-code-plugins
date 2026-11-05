---
description: "Legacy lookup bounded-lookups-then-fallback. For a package Context7 does not cover, the lookup tries at least once, runs at most 3 ctx7 lookup commands for the one topic, then tells the user Context7 did not cover it and invents no documented signature. tool_used counts Bash calls, so several ctx7 commands chained in one call count once against the cap. In the eval sandbox the ctx7 CLI cannot load and no MCP server is configured, so every lookup returns nothing. Needs --allow-tools Bash and --disallow-tools Grep Glob."
tags: [context7, lookup, outcome, cli, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Bash, Read]
expected_outcome: "The run attempts ctx7 library or ctx7 docs (or the npx ctx7 form) for obscure-internal-lib at least once and in no more than 3 Bash calls. The reply says Context7 did not return or cover the docs, and does not present a parameter list for frobnicate as documented or retrieved from Context7."
---

/context7:lookup obscure-internal-lib "exact parameter list of the frobnicate method"
