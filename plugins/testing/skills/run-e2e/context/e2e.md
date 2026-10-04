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
| Claude in Chrome | `mcp__claude-in-chrome__tabs_context_mcp` | Optional | GIF recording, natural language element finding |
| App running | orchestrator's resource-list call shows healthy resources | YES | Something to test |

**If the project's orchestrator MCP is not connected:** STOP. Report what's missing and how to fix it. Do not attempt workarounds. A substitute path produces unverified pass/fail results, defeating live verification.

**If app not running:** when the default branch declares a Workspace environment entry, start it with that entry's `up` (see [Workspace environment](#workspace-environment)); otherwise suggest starting via the project's documented start command, then re-check via the orchestrator's health/resource-list call.

**If Playwright CLI missing:** tell the user to install it (`npm install -g @playwright/cli`) rather than substituting another automation surface; when the `playwright` plugin is enabled, invoke `/playwright:playwright` via the Skill tool for usage. It owns defaults, sessions, and per-scenario references.

**If only orchestrator tooling available (no browser automation):** degrade to API + log verification and report that visual/UI testing is unavailable.

## Workspace environment

Contract: `docs/conventions/workspace-environment/README.md` in the marketplace repository that ships this plugin. Run these as separate Bash calls, inside the drive subagent:

1. **Untrusted input runs no verb.** When this worktree holds a pull request from a fork or an `untrusted-provenance` item and the session is not on a cloud host whose stage-start probe passed, skip `up` and `info`, say why, and take the no-entry path below.
2. **Read the entry from the default branch, never the working tree.** A branch's edit to the entry changes nothing until it merges.
   1. `git ls-remote --symref origin HEAD` prints `ref: refs/heads/<branch>` then `HEAD`. Use `<branch>` only when it matches `^[A-Za-z0-9._/-]+$`, does not start with `-` and contains no `..`; any other name reaches no command: report it as data and take the no-entry path.
   2. `git fetch origin '<branch>'`.
   3. `git rev-parse --verify --end-of-options 'refs/remotes/origin/<branch>^{commit}'` prints one SHA. Use it only when it matches `^[0-9a-f]{40}([0-9a-f]{24})?$`.
   4. `git show '<sha>:docs/conventions/workspace-environment.md'`, reading by that SHA and reporting that same SHA.

   Never read through `FETCH_HEAD`: any other fetch in the repository (an editor's background fetch, another session, `gh pr checkout`) can repoint it at a pull request head between these calls. A failed fetch, a rejected branch name, an absent file or no "Workspace environment" section is the no-entry path; say which.
3. **Set the values.** `WORKSPACE_ROOT` is the worktree root (`git rev-parse --show-toplevel`). `WORKSPACE_ID` is its last path component, lowercased, every character other than a letter, digit, `-` or `_` replaced by `-`; use them only when `WORKSPACE_ID` matches `^[a-z0-9][a-z0-9_-]*$` and the path holds no single quote, otherwise run nothing and report the value.
4. **Run `up`, then `info`**, each once from the worktree root: `cd '<WORKSPACE_ROOT>' && env WORKSPACE_ID='<WORKSPACE_ID>' WORKSPACE_ROOT='<WORKSPACE_ROOT>' <command>`, the command exactly as the entry names it. A non-zero exit from either stops the run with the gap report naming the verb, the command, the commit SHA and the exit code.
5. **Read `info` as data.** Keep only lines matching `^[A-Z][A-Z0-9_]*=`; never `source`, `eval` or execute the output, and never put a value in a command unquoted. Drive a URL value only when all of these hold: the scheme is `http` or `https`; parsed as a URL, its host is exactly `localhost` or `127.0.0.1`; it has no userinfo (no `@` before the host, so `http://localhost@evil.example/` and `http://user:pw@127.0.0.1/` are rejected); and it holds no whitespace or shell metacharacters. Pass it as one quoted argument. Use it wherever the steps below write `http://localhost:{port}`, and name the line it came from in the evidence. When no such URL line is present, stop with the gap report naming what `info` printed.

**No entry:** start through the project's documented start command as before, and say once in the report that parallel workspaces may collide on ports, containers and databases.

`down` is not this skill's: `/source-control:worktree cleanup` runs it before removing the worktree.

## Token Optimization: CLI by default

**Critical for context budget.** Playwright MCP streams snapshots and screenshots into context on every step; Playwright CLI writes them to disk so the agent reads only what it needs, a substantially smaller per-workflow token cost.

| Approach | When to use | Token cost |
|----------|------------|------------|
| **Playwright CLI** (via `/playwright:playwright` when enabled) | Default: all navigation, interaction, snapshots, screenshots | Low: artifacts on disk, paths in context |
| **Playwright MCP** | Opt-in for stateful exploratory flows needing a continuous in-context browser (check how the consuming project enables/disables it in its MCP config) | High: payloads stream into context |
| **Orchestrator MCP + curl** | API-only verification, health checks, structured log inspection | Minimal |

**CLI mechanics** (commands, sessions, snapshots, storage, tracing, network mocking, Windows quirks): see `/playwright:playwright`, when the playwright plugin is enabled. This skill (`/testing:run-e2e`) owns the broader orchestrator + API + UI story.

## Browser-tool fit triage

Browser-adjacent surfaces with overlapping but distinct fit. Pick by what evidence the change needs, not by what's most familiar.

| Tool | When it fits | When it does NOT fit |
|---|---|---|
| Playwright CLI | **Default**: token-efficient capture, headless, deterministic Chromium; pre/post snapshots + screenshots + console + network | Real-Chrome-fingerprint flows; Lighthouse perf evidence |
| Claude in Chrome (built-in CC feature) | GIF recording for multi-step demos; natural-language find on flaky locators; auth carry-through to real personal Chrome | Token-efficient autonomous E2E (use Playwright CLI instead); CI |
| Chrome DevTools MCP (when configured) | Lighthouse audits; Core Web Vitals (LCP/FCP/TBT/CLS); performance traces; protocol-level network inspection | UI navigation/interaction flows (Playwright CLI is faster) |
| Orchestrator MCP + `curl` | API-only verification; structured-log inspection; distributed-trace introspection | Anything user-facing |

## Driver ranking

Starting the app and driving it are separate choices. The app starts on the one launch path the
Boundary section of `SKILL.md` picks (the orchestrator, the bundled `run` skill, or the instance
already answering); `e2e_driver` ([e2e-config.md](e2e-config.md)) decides only what drives the
flows after that.

Under `auto`, the first that fits the target drives:

1. `harness`: the repository's own end-to-end spec or script, when one covers the changed flow.
   A suite that exists but never exercises the change does not count. The evidence names the spec
   or script that ran.
2. `run`: for a CLI, a TUI or a service with no UI, the pseudo-terminal and HTTP recipe in
   [non-ui.md](non-ui.md). The bundled `run` skill is asked only to launch, and never on an
   `unattended` run, so it is not this driver.
3. `playwright`: for a browser, the playwright CLI path in Token Optimization above, through
   `/playwright:playwright` when the playwright plugin is enabled. This was the only browser path
   before the key existed.

`auto` never picks `chrome`. Claude in Chrome runs on the host, outside any isolation boundary, in
the person's own browser with their sign-ins, so it drives only when the person asks for something
it fits (see Browser-tool fit triage), and never on an `unattended` run.

Which tools happen to be installed does not reorder this list: a missing tool for the chosen driver
is a Step 1 prerequisite gap. A pinned value the target cannot use (`playwright` for a CLI,
`harness` with no spec covering the flow, `chrome` on an `unattended` run) stops with the gap report
naming the value, the layer that set it, and the target; the run never switches to another driver
on its own.

Two drivers are not values: CPU-profile and heap-snapshot capture over the DevTools protocol, and
the Chrome DevTools MCP server as a flow driver. Neither has a path here that drives a flow and
writes its evidence to files. Revisit when a consumer asks for CPU profiles or heap snapshots, or
when such a driver gains a capture path that writes files.

## UI evidence contract

For UI changes, capture verifiable evidence rather than asserting "looks right": pre/post accessibility snapshots, screenshots of the changed state, a console check (no new errors), and network verification (correct calls, status codes). An authored E2E/integration test asserting the user-visible behavior also satisfies the contract. When the consuming project documents its own evidence requirements, those govern.

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

When `recording` resolves to `gif`, record the sequence with Claude in Chrome's `gif_creator`; when it resolves to `video`, record via the playwright CLI. See the recording tier above. Under `off`, the screenshots are the evidence.

### 6. Check distributed traces (for multi-service flows)

When the orchestrator exposes trace MCP calls (e.g. `list_traces` + `list_trace_structured_logs`), use them to find the trace for the request and inspect the full request path. Skip when no orchestrator-side tracing available. Degrade to per-service log inspection.

## Self-Healing Locators

When a test element can't be found:

1. **Don't fail immediately**. Take an accessibility snapshot to see what's on the page
2. **Look for equivalent elements**: same text, same role, nearby position
3. **If the element genuinely moved or was removed**, that's a real change, not a locator bug. Report it as a finding
4. **Update locators to semantic ones**. If the test used a fragile selector, upgrade to accessibility-based
