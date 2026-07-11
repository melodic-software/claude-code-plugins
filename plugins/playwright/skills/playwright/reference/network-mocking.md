# Network mocking

Intercept, mock, modify, or block network requests from the CLI or via `run-code`.

## CLI `route` commands

```bash
# Return 404 for all JPGs
playwright-cli route "**/*.jpg" --status=404

# Return a fixed JSON body
playwright-cli route "**/api/users" --body='[{"id":1,"name":"Alice"}]' --content-type=application/json

# Add/modify headers
playwright-cli route "**/api/data" --body='{"ok":true}' --header="X-Custom: value"

# Strip headers (e.g., anonymize requests)
playwright-cli route "**/*" --remove-header=cookie,authorization

# Inspect/manage routes
playwright-cli route-list
playwright-cli unroute "**/*.jpg"    # remove one
playwright-cli unroute               # remove all
```

## URL patterns

Playwright uses minimatch-style globs:

| Pattern | Matches |
|---|---|
| `**/api/users` | Path segment match |
| `**/api/*/details` | Single-segment wildcard |
| `**/*.{png,jpg,jpeg}` | Extension set |
| `**/search?q=*` | Query-string wildcard |

## Advanced — via `run-code`

CLI route commands cover static mocking. For conditional responses, request inspection, response modification, or timing control, use `run-code`:

### Conditional response based on request body

```bash
playwright-cli run-code "async page => {
  await page.route('**/api/login', route => {
    const body = route.request().postDataJSON();
    if (body.username === 'admin') {
      route.fulfill({ body: JSON.stringify({ token: 'mock-token' }) });
    } else {
      route.fulfill({ status: 401, body: JSON.stringify({ error: 'Invalid' }) });
    }
  });
}"
```

### Modify real upstream response

```bash
playwright-cli run-code "async page => {
  await page.route('**/api/user', async route => {
    const response = await route.fetch();
    const json = await response.json();
    json.isPremium = true;
    await route.fulfill({ response, json });
  });
}"
```

### Simulate network failures

```bash
playwright-cli run-code "async page => {
  await page.route('**/api/offline', route => route.abort('internetdisconnected'));
}"
```

Options: `connectionrefused`, `timedout`, `connectionreset`, `internetdisconnected`, `addressunreachable`, `blockedbyclient`, `blockedbyresponse`, `namenotresolved`.

### Delayed response (simulate slow backend)

```bash
playwright-cli run-code "async page => {
  await page.route('**/api/slow', async route => {
    await new Promise(r => setTimeout(r, 3000));
    route.fulfill({ body: JSON.stringify({ data: 'loaded' }) });
  });
}"
```

## When to mock in E2E tests

- **Deterministic assertions** on data-driven UI — fix the response shape for reproducibility
- **Error-path coverage** — 500/401/timeout flows that are hard to trigger against real backends
- **Offline-state UI** — test reconnect logic

**When NOT to mock:** full end-to-end flows against a running locally-orchestrated stack. If already orchestrating the real backend, mocking network calls defeats the purpose — see [e2e-orchestrator-recipe.md](e2e-orchestrator-recipe.md).
