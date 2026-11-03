---
description: "On an ambiguous library match, the lookup runs the docs query against both close candidates before asking the user anything"
tags: [context7, lookup, outcome, cli]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Bash, Read]
expected_outcome: "The run calls ctx7 docs (or the npx ctx7 form) once with /lumen-http/lumen and once with /lumenjs/lumen, so both close candidates are probed. The prompt carries the ctx7 library result because in the eval sandbox the ctx7 CLI cannot load and no MCP server is configured; a docs call counts even when it fails there. What the reply says after failed probes is not graded here: lk-ambiguous-names-choice grades the choice and the absence of a clarifying question."
---

/context7:lookup Lumen "retry a failed request with exponential backoff"

I already ran the resolve step for this. `ctx7 library Lumen "retry a failed request with exponential backoff"` returned:

```text
1. Title: Lumen
   Library ID: /lumen-http/lumen
   Description: HTTP client for Node.js and browsers
   Code Snippets: 412
   Source Reputation: High
   Benchmark Score: 81

2. Title: Lumen
   Library ID: /lumenjs/lumen
   Description: Fetch wrapper with request caching for React apps
   Code Snippets: 398
   Source Reputation: High
   Benchmark Score: 80
```
