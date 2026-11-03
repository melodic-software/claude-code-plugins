---
description: "After probing two close candidates, the lookup answers from the one whose docs cover the question, names the chosen and the rejected library ID, and asks no clarifying question"
tags: [context7, lookup, outcome, cli]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Bash, Read]
expected_outcome: "The reply answers from /lumen-http/lumen (the retry option with exponential backoff), names /lumen-http/lumen as the library it chose and /lumenjs/lumen as the runner-up it rejected because its docs do not cover retries, and does not ask the user which library they meant. The prompt carries both probe results because in the eval sandbox the ctx7 CLI cannot load and no MCP server is configured; lk-ambiguous-probes-candidates grades that the probes run."
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
### Cache a request

`useLumen` caches each response by key and refetches it after `staleTime` ms.

```jsx
const { data, error } = useLumen("/api/orders", { staleTime: 30000 });
```

### Handle errors

`error` holds the last failed response. Render a fallback when it is set.
````
