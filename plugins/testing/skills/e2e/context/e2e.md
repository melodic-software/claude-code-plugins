# End-to-End (E2E) App Testing

Autonomous application testing — start the app, navigate, interact, take screenshots, verify behavior. This mode activates when end-to-end live verification of a running application is needed (UI flows, API contracts, distributed traces, structured logs).

## Prerequisites Check (MANDATORY — hard-fail if missing)

Before ANY live testing, verify tool availability. The e2e orchestrator and any prerequisite MCP come from the consuming project's conventions (Aspire, docker-compose, tilt, a dev-server script). Universal browser-automation tooling stays prose.

| Requirement | How to check | Required? | Purpose |
|------------|-------------|-----------|---------|
| Orchestrator tooling/MCP | per the consuming project's orchestrator convention | YES (when orchestrator configured) | App orchestration, start/stop, health, logs |
| Playwright CLI | `playwright-cli --version` (expect 0.1.x+) | Recommended | Browser automation, screenshots, form filling — token-efficient |
| Chrome DevTools MCP | `mcp__chrome-devtools__list_pages` | Optional | Lighthouse audits, performance traces, network inspection |
| Claude in Chrome | `mcp__claude-in-chrome__tabs_context_mcp` | Optional | GIF recording, natural language element finding |
| App running | orchestrator's resource-list call shows healthy resources | YES | Something to test |

**If the project's orchestrator MCP is not connected:** STOP. Report what's missing and how to fix it. Do not attempt workarounds.

**If app not running:** suggest starting via the project's documented start command, then re-check via the orchestrator's health/resource-list call.

**If Playwright CLI missing:** install globally via `npm install -g @playwright/cli@latest`; when the `playwright` plugin is installed, invoke `/playwright:playwright` for usage — it owns defaults, sessions, and per-scenario references.

**If only orchestrator tooling available (no browser automation):** degrade to API + log verification and report that visual/UI testing is unavailable.

## Token Optimization: CLI by default

**Critical for context budget.** Playwright MCP consumes ~114K tokens for a multi-step workflow. Playwright CLI consumes ~27K tokens for the same work — 4.2x reduction. CLI writes snapshots and screenshots to disk so the agent reads only what it needs.

| Approach | When to use | Token cost |
|----------|------------|------------|
| **Playwright CLI** (via `/playwright:playwright` when installed) | Default — all navigation, interaction, snapshots, screenshots | ~27K tokens/workflow |
| **Playwright MCP** | Opt-in for stateful exploratory flows needing a continuous in-context browser (check how the consuming project enables/disables it in its MCP config) | ~114K tokens/workflow |
| **Orchestrator MCP + curl** | API-only verification, health checks, structured log inspection | Minimal |

**See `/playwright:playwright`** (when the playwright plugin is installed) for CLI mechanics — commands, sessions, snapshots, storage, tracing, network mocking, Windows quirks. This skill (`/testing:e2e`) owns the broader orchestrator + API + UI story.

## Browser-tool fit triage

Browser-adjacent surfaces with overlapping but distinct fit. Pick by what evidence the change needs, not by what's most familiar.

| Tool | When it fits | When it does NOT fit |
|---|---|---|
| Playwright CLI | **Default** — token-efficient capture, headless, deterministic Chromium; pre/post snapshots + screenshots + console + network | Real-Chrome-fingerprint flows; Lighthouse perf evidence |
| Claude in Chrome (built-in CC feature) | GIF recording for multi-step demos; natural-language find on flaky locators; auth carry-through to real personal Chrome | Token-efficient autonomous E2E (use Playwright CLI instead); CI |
| Chrome DevTools MCP (when configured) | Lighthouse audits; Core Web Vitals (LCP/FCP/TBT/CLS); performance traces; protocol-level network inspection | UI navigation/interaction flows (Playwright CLI is faster) |
| Orchestrator MCP + `curl` | API-only verification; structured-log inspection; distributed-trace introspection | Anything user-facing |

## UI evidence contract

For UI changes, capture verifiable evidence rather than asserting "looks right": pre/post accessibility snapshots, screenshots of the changed state, a console check (no new errors), and network verification (correct calls, status codes). An authored E2E/integration test asserting the user-visible behavior also satisfies the contract. When the consuming project documents its own evidence requirements, those govern.

## E2E Testing Workflow

### 1. Plan what to verify

Use the test plan from `/testing:plan` or generate scenarios from changes:

- Which endpoints changed?
- Which UI flows are affected?
- What does "working correctly" look like?

### 2. Verify health

Call the orchestrator's resource-list/health MCP or CLI → check all resources are running and healthy.

If any resource is unhealthy, read its logs before proceeding (orchestrator's console + structured-log MCP calls per resource).

### 3. Test API endpoints

For backend changes, verify endpoints directly via `curl` or Playwright CLI:

```bash
curl -s http://localhost:{port}/health | jq .
playwright-cli -s=test open http://localhost:{port}/health
```

### 4. Test UI flows (if applicable)

Navigate to the app and interact using Playwright CLI in a named session (keeps browser alive across commands):

```bash
playwright-cli -s=uitest open http://localhost:{port}      # opens browser, emits snapshot file path
playwright-cli -s=uitest snapshot                          # refresh accessibility tree (YAML with element refs: e37, e48, ...)
playwright-cli -s=uitest click e48                         # interact by element ref from snapshot
playwright-cli -s=uitest fill e37 "test input"             # fill text into an input
playwright-cli -s=uitest press Enter                       # keyboard
playwright-cli -s=uitest screenshot                        # writes PNG to .playwright-cli/ (not context)
playwright-cli -s=uitest console                           # summarize console messages
playwright-cli -s=uitest network                           # list network requests
playwright-cli -s=uitest close                             # close session
```

Artifacts land in `.playwright-cli/` **relative to CWD when each command runs** (gitignored). Read the YAML snapshot file directly to locate element refs — do not dump it into context blindly; keep the token savings.

**Use semantic locators ONLY** (the snapshot's element refs `e2`, `e37` etc. are stable accessibility-based handles — NOT CSS selectors):

- `click e48` where the snapshot shows `- button "Submit" [ref=e48]` (good)
- CSS selectors like `#submit-btn` (bad — breaks on cosmetic changes)

### 5. Capture evidence

For each verified scenario:

- Screenshot of the expected state
- Console log check (no errors)
- Network request verification (correct API calls, status codes)

For multi-step flows, use Claude in Chrome GIF recording:

```
mcp__claude-in-chrome__gif_creator → record the interaction sequence
```

### 6. Check distributed traces (for multi-service flows)

When the orchestrator exposes trace MCP calls (e.g. `list_traces` + `list_trace_structured_logs`), use them to find the trace for the request and inspect the full request path. Skip when no orchestrator-side tracing available — degrade to per-service log inspection.

## Self-Healing Locators

When a test element can't be found:

1. **Don't fail immediately** — take an accessibility snapshot to see what's on the page
2. **Look for equivalent elements** — same text, same role, nearby position
3. **If the element genuinely moved or was removed** — that's a real change, not a locator bug. Report it as a finding
4. **Update locators to semantic ones** — if the test used a fragile selector, upgrade to accessibility-based

## After E2E testing

- If all scenarios pass: proceed to `/verification:confirm outcome` (composes /verification:confirm default + intent + evidence; chains back to /testing:e2e if needed)
- If visual bugs found: `/testing:diagnose` for diagnosis and the fix cycle
- If API errors found: check the orchestrator's structured logs for root cause
- Document findings — E2E results are ephemeral. Screenshot evidence persists

## Marketplace plugin skills (invoke only when installed)

- **`cloudflare:web-perf`** — measure Core Web Vitals (FCP, LCP, TBT, CLS, Speed Index) via Chrome DevTools MCP. Use for performance verification baselines during E2E testing
- **`document-skills:webapp-testing`** — Playwright-based test automation patterns including semantic locators, accessibility-first selectors, and multi-step workflow scripting
