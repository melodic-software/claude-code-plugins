# End-to-End (E2E) App Testing

Autonomous application testing: start the app, navigate, interact, take screenshots, verify behavior. This mode activates when end-to-end live verification of a running application is needed (UI flows, API contracts, distributed traces, structured logs).

## Prerequisites check

Before live testing, verify tool availability. The e2e orchestrator and any prerequisite MCP come from the consuming project's conventions (Aspire, docker-compose, tilt, a dev-server script). Universal browser-automation tooling stays prose.

The Playwright CLI row's version floor was verified 2026-09-06 against the package registry entry
for `@playwright/cli`, whose latest published version that day is 0.1.19. Two names exist and only
one is live: the unscoped `playwright-cli` package is deprecated and sits at a different, much
higher version, so a floor read against that name means nothing. Recheck the floor when the scoped
package publishes a 0.2 or 1.0 release, or when the binary the row invokes stops resolving to it.

| Requirement | How to check | Required? | Purpose |
|------------|-------------|-----------|---------|
| Orchestrator tooling/MCP | per the consuming project's orchestrator convention | YES (when orchestrator configured) | App orchestration, start/stop, health, logs |
| Playwright CLI | `playwright-cli --version` (the package is `@playwright/cli`, published at 0.1.19 on 2026-09-06; expect 0.1.x or later) | Recommended | Token-efficient browser automation, screenshots, form filling |
| Chrome DevTools MCP | `mcp__chrome-devtools__list_pages` | Optional | Lighthouse audits, performance traces, network inspection |
| Claude in Chrome | `mcp__claude-in-chrome__tabs_context_mcp` | Optional | The user's logged-in browser and GIF demos, on a native host (see the rubric for WSL) |
| App running | orchestrator's resource-list call shows healthy resources | YES | Something to test |

**If the project's orchestrator MCP is not connected:** STOP. Report what's missing and how to fix it. Do not attempt workarounds. A substitute path produces unverified pass/fail results, defeating live verification.

**If app not running:** suggest starting via the project's documented start command, then re-check via the orchestrator's health/resource-list call.

**If Playwright CLI missing:** tell the user to install it (`npm install -g @playwright/cli`) rather than substituting another automation surface; when the `playwright` plugin is enabled, invoke `/playwright:playwright` via the Skill tool for usage. It owns defaults, sessions, and per-scenario references.

**If only orchestrator tooling available (no browser automation):** degrade to API + log verification and report that visual/UI testing is unavailable.

## Browser-tool rubric

This table is the one place that says which browser tool fits which job; other skills point here
through `/testing:run-e2e`. Pick by the job, not by habit.

| Job | Tool | Not for |
|---|---|---|
| Verify a change from a terminal coding agent (default) | Playwright CLI through `/playwright:playwright`, headless. It writes snapshots and screenshots to disk, so only paths enter context. On WSL2, Linux-side Chromium; headed through WSLg only when the user asks | A browser the user is logged into |
| Long-running exploration that holds browser state across many steps | Playwright MCP, opt-in (check how the consuming project enables it in its MCP config) | Routine verification: it streams page payloads into context |
| Deep performance or network debugging: traces, Core Web Vitals, Lighthouse, protocol-level requests | Chrome DevTools MCP, when configured; the CLI's `console` and `network` cover the basics | UI navigation flows |
| A regression the suite must keep catching | A committed spec in the project's existing browser-test framework, run in CI; `@playwright/test` when the project has none | One-off checks during development: drive the app once and keep the evidence |
| The user's logged-in real browser, or a GIF demo | Claude in Chrome on a native host. From WSL, fetch the WSL note (pointer below) before routing here; while it does not list WSL as supported, and until the live test reports, use the CLI's saved auth state or a persistent profile after one login | Autonomous runs; CI |
| API-only checks, health, structured logs, traces | Orchestrator MCP + `curl` | Anything user-facing |

Claude in Chrome from WSL. Pointer: the WSL note at the top of
<https://code.claude.com/docs/en/chrome>; user reports of `claude --chrome` working from WSL are in
the comments on <https://github.com/anthropics/claude-code/issues/79655>. As of: 2026-10-04. Recheck
trigger: the page drops its WSL line, or the live test of `claude --chrome` from WSL reports.

**CLI mechanics** (commands, sessions, snapshots, storage, tracing, network mocking, Windows quirks):
see `/playwright:playwright`, when the playwright plugin is enabled.

## UI evidence contract

For UI changes, capture verifiable evidence rather than asserting "looks right": pre/post accessibility snapshots, screenshots of the changed state, a console check (no new errors), and network verification (correct calls, status codes). An authored E2E/integration test asserting the user-visible behavior also satisfies the contract. When the consuming project documents its own evidence requirements, those govern.

### Inspect the render

A screenshot on disk is not an inspection. Agents verifying UI changes have reported "looks good"
over misaligned or ugly buttons, clipped text, overlap and low contrast (user report, 2026-10-04).
For every changed screen, run these checks in order and report each one's result, or why it did not
run:

1. **Accessibility scan.** Run axe (`@axe-core/playwright` with WCAG tags) when the project has
   it; otherwise report the scan as not run and name the package. A clean scan is necessary, not
   sufficient: no tool finds every failure, and in GDS's 2017 test, 29% of barriers were missed by
   all ten tools combined. Report manual accessibility review as not performed unless a person did it.
2. **Geometry.** Assert layout from the DOM at two or more viewport widths (a phone and a desktop
   width): sibling controls' bounding boxes do not overlap; text does not clip (under hidden overflow,
   `scrollWidth` or `scrollHeight` larger than the client size is a failure); elements meant to align share
   an edge or center; changed elements are in the viewport. An aria snapshot is not a layout check:
   it records roles, names and text, and gave identical output for a broken and a correct layout in a
   local probe (2026-10-04), where geometry checks caught both defects.
3. **Pixel baseline**, when the project keeps one: `toHaveScreenshot`, with baselines generated and
   compared in the same container, since rendering differs across hosts. A diff shows change, not
   whether the change is a defect.
4. **Look at it.** Read cropped, element-level screenshots at each width and check each against a
   list: misaligned or inconsistent buttons, clipped or overlapping text, spacing, contrast,
   anything unlike the design or the neighboring screens. Findings are leads: confirm a spatial
   lead (alignment, clipping, overlap, viewport) with a step-2 check, and any other lead (contrast,
   color, typography, divergence from the design) with a measurable check such as a contrast ratio,
   the pixel baseline, or the design source; report a lead no check can confirm as unconfirmed, never
   drop it. "No issues found" is never a pass: vision models miss many real visual changes (DiffSpot,
   pointer below).

Evidence pointers, as of 2026-10-04:
[Playwright accessibility testing](https://playwright.dev/docs/accessibility-testing) (automated
scans cannot find every WCAG failure);
[GDS tool audit](https://accessibility.blog.gov.uk/2017/02/24/what-we-found-when-we-tested-tools-on-the-worlds-least-accessible-webpage/);
[DiffSpot, arXiv 2605.29615](https://arxiv.org/abs/2605.29615);
[Playwright visual comparisons](https://playwright.dev/docs/test-snapshots) (same-environment
baselines). Recheck trigger: a benchmark measures current vision models on UI defects, an
injected-defect eval in this repository reports catch rates per check, or either cited Playwright
page changes what it says about automated accessibility coverage or same-environment baselines.

### Recording tier (optional)

Recording is off by default. The screenshot evidence above is the floor. When the `recording` key ([e2e-config.md](e2e-config.md)) is set, a run also captures a moving record; it supplements the screenshots, never replaces them.

| `recording` | Capture path | Fits |
|---|---|---|
| `video` | playwright CLI video | long or multi-page flows where a screenshot set loses the sequence |
| `gif` | `gif_creator` | short demos, a few steps worth showing inline |
| `off` | none (screenshots only) | default |

### Session artifacts

When a run produces a recording or drives a named session, record its artifacts in the evidence output so a reviewer can retrace it:

| Artifact | Points to |
|---|---|
| Recording path | the video/GIF file on disk (gitignored, alongside the other capture artifacts) |
| Session ID | the playwright CLI / browser session name the run drove |
| Transcript pointer | the run's evidence output: console/network capture and snapshot files |

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

Artifacts land in `.playwright-cli/` **relative to CWD when each command runs** (gitignored). Read the YAML snapshot file directly to locate element refs. Do not dump it into context blindly; keep the token savings.

**Use semantic locators** (the snapshot's element refs `e2`, `e37` etc. are stable accessibility-based handles; CSS selectors break on cosmetic changes):

- `click e48` where the snapshot shows `- button "Submit" [ref=e48]` (good)
- CSS selectors like `#submit-btn` (bad: breaks on cosmetic changes)

### 5. Capture evidence

For each verified scenario:

- Screenshot of the expected state
- Console log check (no errors)
- Network request verification (correct API calls, status codes)
- The render checks in [Inspect the render](#inspect-the-render), each with its result

When `recording` resolves to `gif`, record the sequence with Claude in Chrome's `gif_creator`; when it resolves to `video`, record via the playwright CLI. See the recording tier above. Under `off`, the screenshots are the evidence.

### 6. Check distributed traces (for multi-service flows)

When the orchestrator exposes trace MCP calls (e.g. `list_traces` + `list_trace_structured_logs`), use them to find the trace for the request and inspect the full request path. Skip when no orchestrator-side tracing available. Degrade to per-service log inspection.

## Self-Healing Locators

When a test element can't be found:

1. **Don't fail immediately**. Take an accessibility snapshot to see what's on the page
2. **Look for equivalent elements**: same text, same role, nearby position
3. **If the element genuinely moved or was removed**, that's a real change, not a locator bug. Report it as a finding
4. **Update locators to semantic ones**. If the test used a fragile selector, upgrade to accessibility-based
