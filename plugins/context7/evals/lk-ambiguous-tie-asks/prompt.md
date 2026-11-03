---
description: "After probing two close candidates whose docs answer the question equally well, the lookup names both library IDs and asks the user which one they mean"
tags: [context7, lookup, outcome, cli]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Bash, Read]
expected_outcome: "Both probes answer the question, so the probe cannot settle the choice: the reply names /lumen-http/lumen and /lumenjs/lumen and asks the user which library they mean, instead of picking one. Showing both retry options alongside the question is fine. The prompt carries both probe results because in the eval sandbox the ctx7 CLI cannot load and no MCP server is configured."
---

/context7:lookup Lumen "retry a failed request with exponential backoff"

I already ran the resolve step and the docs query against both top candidates; don't rerun them. Finish the lookup from these results.

`ctx7 library Lumen "retry a failed request with exponential backoff"`:

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

`ctx7 docs "/lumen-http/lumen" "retry a failed request with exponential backoff"`:

````text
### Retry failed requests

Set `retry` on the client or on one request. `backoff: "exponential"` doubles the delay after each attempt, starting at `delayMs`.

```js
import { createClient } from "lumen";

const api = createClient({
  baseUrl: "https://api.example.com",
  retry: { limit: 3, backoff: "exponential", delayMs: 200, on: [502, 503, 504] },
});
```
````

`ctx7 docs "/lumenjs/lumen" "retry a failed request with exponential backoff"`:

````text
### Retry failed requests

Pass `retry` to `useLumen`. `retryDelay: "exponential"` doubles the wait after each failed attempt, starting at `retryBaseMs`.

```jsx
const { data, error } = useLumen("/api/orders", {
  retry: 3,
  retryDelay: "exponential",
  retryBaseMs: 200,
});
```
````
