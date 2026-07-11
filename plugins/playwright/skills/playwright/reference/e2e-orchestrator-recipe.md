# E2E against a locally-orchestrated app stack

Original content — not from upstream. The orchestration story for running Playwright CLI against apps started by a local orchestrator: .NET Aspire, docker-compose, tilt, or a plain dev server.

## Prerequisite: stack up and healthy

Start the stack with its own orchestrator, for example:

```bash
dotnet run --project <path-to-aspire-apphost>   # .NET Aspire
docker compose up -d                             # docker-compose
tilt up                                          # tilt
```

Wait for every service to report healthy — the orchestrator's dashboard usually shows this, or verify programmatically:

```bash
curl -s http://localhost:<port>/health | jq .
```

Endpoint URLs are often dynamic (Aspire in particular assigns ports at startup) — grab them from the orchestrator dashboard or its CLI/MCP surface rather than assuming.

## Recommended flow

```bash
# 1. Fresh start
playwright-cli kill-all

# 2. Open a named session against the app under test
playwright-cli -s=smoke open http://localhost:<port>/<entry-path>

# 3. Snapshot to locate interactive elements
playwright-cli -s=smoke snapshot
# → Read .playwright-cli/page-*.yml to find refs

# 4. Execute the scenario
playwright-cli -s=smoke click e42          # interact by ref
playwright-cli -s=smoke fill e37 '{"foo":"bar"}' --submit

# 5. Capture evidence
playwright-cli -s=smoke screenshot --filename=smoke-<date>.png
playwright-cli -s=smoke console            # check for JS errors
playwright-cli -s=smoke network            # verify the API call shape

# 6. Tear down
playwright-cli -s=smoke close
```

## When to use Playwright CLI vs other tools

| Need | Tool |
|---|---|
| Pure API endpoint verification | `curl` + `jq` — fastest, no browser overhead |
| Health / readiness checks | The orchestrator's dashboard or MCP surface + `curl /health` |
| Structured log inspection | The orchestrator's log/trace surface |
| **UI flow through Swagger/Scalar or the app itself** | Playwright CLI |
| **Interactive component behavior (Blazor, SPA hydration)** | Playwright CLI |
| **Visual regression** | Playwright CLI screenshot + image diff |
| Performance (Core Web Vitals, Lighthouse) | Chrome DevTools tooling |

Playwright CLI complements the orchestrator's own observability and `curl` — it does NOT replace them. Reach for it when the test needs actual DOM/UI interaction, not HTTP.

## Framework gotcha: Blazor Interactive Auto

Blazor Interactive Auto (Server + WASM) renders elements progressively. Two common gotchas:

### Wait for interactive after navigation

Before clicking a Blazor component, wait for it to be interactive — `@onclick` handlers attach after the WASM runtime loads:

```bash
playwright-cli -s=blazor open http://localhost:<port>/counter
playwright-cli -s=blazor run-code "async page => {
  await page.waitForFunction(() =>
    window.Blazor && window.Blazor._internal && window.Blazor._internal.navigationManager
  );
}"
playwright-cli -s=blazor click e5     # now safe — runtime is ready
```

### Enhanced navigation breaks expected URL flow

Blazor's enhanced-nav intercepts link clicks. If a test expects page navigation but `waitForURL` never fires, the click probably hit an enhanced-nav link that rewrote the DOM without full navigation. Use `waitForLoadState('networkidle')` or a DOM-based predicate instead.

## Cleanup discipline

Never commit `.playwright-cli/` content — add it to the project's `.gitignore`. Run `rm -rf .playwright-cli/` after large traces/videos to reclaim disk. `playwright-cli close-all && playwright-cli kill-all` between test batches prevents zombie daemons holding file locks.

## Cross-worktree notes

Each git worktree has its own `.playwright-cli/` (gitignored, relative to CWD). Session state (`-s=<name>`) is keyed by daemon process, per-user, NOT per-worktree — two worktrees running `-s=smoke` concurrently share the same browser. For concurrent isolation, use distinct session names per worktree:

```bash
# In worktree A
playwright-cli -s=smoke-feature-x open http://localhost:5001

# In worktree B concurrently
playwright-cli -s=smoke-feature-y open http://localhost:5002
```
