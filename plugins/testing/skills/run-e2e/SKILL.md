---
description: "When the bundled run skill resolves in this session, prefer it to launch the app for a quick look; this skill for evidenced verification flows. End-to-end live app verification. Check prerequisites, start the app, drive UI/API flows, and capture evidence (screenshots, responses, logs); includes a non-UI smoke-test playbook for libraries, MCP servers, hooks, and scripts. Use when: the user wants the running app verified end to end (e2e, smoke test, 'does it actually work'), the UI clicked through, or UI/API changes need runtime verification; for comprehensive build+test+lint use /verification:confirm."
argument-hint: "[unattended] [scenario]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Start the app, drive real flows, capture evidence
---

## Native step: run (bundled skill)

When the bundled `run` skill resolves in this session, the Step 3 drive subagent invokes it through
the Skill tool as `run`, asking it only to launch the app and report how to reach it (URL, port,
process). The driving stays with this skill: screenshots, responses, and logs are layered on top of
`run`'s result under the evidence contract in [context/e2e.md](context/e2e.md). Prerequisites, run
config, evidence, and handoff stay with this skill too. The step runs only under the
one-launch-path rule in the Boundary section: it is skipped when the project's orchestrator governs
the start, when the app is already running, and on the non-UI route, where there is no app to
launch.

**Identity check.** The name is in the skill listing; the description is advisory. A listed `run`
that reads as a project skill is not a skip: the bundled skill itself defers to a project skill of
that name ([context/bundled-run.md](context/bundled-run.md)). A description that reads as an
unrelated surface is an identity mismatch: skip with a warning and use this skill's own launch
playbook. A name with no description (`name-only`, listing-budget overflow) is invoked with the
warning "identity confirmed by name alone".

**Mutation.** `run` starts processes rather than editing files. The drive subagent saves
`git diff HEAD` to a scratch file outside the tree immediately before and after the invocation, as
individual Bash calls, and compares the two files with `cmp`. Any difference is **mutation detected
after a scoped invocation**: the run exits degraded and the report names the paths whose
`diff --git` section differs between the files. A path that was already dirty and is unchanged is
not named.

**Already running.** [context/e2e.md](context/e2e.md) requires a running app. On this path the
launch meets that requirement, so Step 1 does not stop on a missing app. Before invoking `run`, the
drive subagent probes the URL or port the scenario or the project's documented start command
names. The scenario is free-form input, so the target is used only when it is a bare
`http://` or `https://` URL on `localhost` or `127.0.0.1`, or a bare port number, with no
whitespace or shell metacharacters; the subagent passes it as one quoted argument
(`curl -fsS --max-time 5 "<url>"`, or a connect to the port). Any other value is not probed. A
response skips the step, so `run` never starts a second instance. No usable target, or no
response, means not running and the step proceeds.

**Skip report.** When the step does not run, or runs and cannot be trusted, the state names why:
`did not resolve in this session`; `invocation refused (<reason>)`, never retried (not in the
session's skills allowlist, `disableBundledSkills`, `skillOverrides`, or a permission deny);
`identity mismatch`; `mutation detected after a scoped invocation`; or `resolved but degraded`
when `run` says it ran a weaker procedure, in which case the report relays its disclosure instead
of calling the launch complete. Each state names the axis line:
settings or environment, plan, platform or provider, host surface; and the enable path
(`disableBundledSkills`, `skillOverrides`). Every skip falls back to this skill's own launch playbook, the project's
documented start command per [context/e2e.md](context/e2e.md); mutation detected exits degraded
instead of launching a second time.

The `run` body enters context once and stays there.

**Result block.** The Step 3 evidence output opens with this block, whichever state the step ended
in:

```text
Native step: run
State: ran | resolved but degraded (<disclosure>) | did not resolve in this session (<axis>) | invocation refused (<reason>) | identity mismatch | skipped (unattended | orchestrator governs the start | non-UI route | app already running) | mutation detected after a scoped invocation
Outside-scope changes: none | <paths>
```

**`unattended`:** never invoke `run`; this skill's own launch playbook runs, and the result block
records `State: skipped (unattended)` without asking.

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -20`

The pipe is the bound and belongs in the command. A read-time cap ("read only the first 20 entries")
bounds nothing: the Bash tool returns the command's complete output into context before there is
anything to decide about.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git. The dated record for that composition claim is the worktree skill's
[reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md),
"The pre-compute block runs as one shell invocation".

## Purpose

Autonomous live verification of a running application: start it, navigate, interact, screenshot, assert. UI changes follow the mandatory evidence contract in [context/e2e.md](context/e2e.md); non-UI runtime surfaces route to the smoke-test playbook. The e2e-orchestrator configuration (start command, prerequisite tooling, degraded fallback) comes from the consuming project's conventions. Its orchestrator (Aspire, docker-compose, tilt, a dev-server script) and any documented evidence requirements govern.

## Arguments

`$ARGUMENTS`: `[unattended] [scenario]`, e.g., `/testing:run-e2e`, `/testing:run-e2e the login flow`,
`/testing:run-e2e non-ui`, `/testing:run-e2e unattended the login flow`.

- `unattended`, optional, the first token: the caller declares no one is present. Its effect is the
  `unattended` rule in the Native step.
- `scenario`, optional description of what to verify. `non-ui` routes directly to the non-UI
  playbook.

## Step 0: Route

| Signal | Context file |
|--------|-------------|
| UI flows, browser evidence, API + UI orchestration | [context/e2e.md](context/e2e.md) |
| Non-UI runtime surface (library, MCP server, hooks, scripts, infrastructure) | [context/non-ui.md](context/non-ui.md) |

UI changes (Blazor / Razor / HTML / CSS / JS shipped to browser) take the e2e route because the UI evidence contract applies there.

## Step 1: Prerequisites

Check tool availability per the prerequisite matrix in [context/e2e.md](context/e2e.md). When the consuming project names a prerequisite orchestrator tool/MCP, its absence hard-fails. STOP and report what's missing and how to fix it; do not attempt workarounds, because a substitute path produces unverified pass/fail results, defeating live verification.

On a hard-fail, STOP **and** write a structured verification-environment gap report to the run's evidence output before stopping. The report lists what is missing, each key, CLI, MCP, or environment the run needs, and what the operator must provide to make the run possible. The STOP still holds; the gap report is its actionable half, so the operator receives a precise list of what to supply rather than a bare failure.

## Step 2: Resolve run config

Two keys govern this run: `recording` (`video | gif | off`) and `browser_mode` (`headed | headless`). They live in the consumer-tracked surface `.claude/testing/e2e.md`; [context/e2e-config.md](context/e2e-config.md) owns their definitions, defaults, and precedence. Resolve them before driving:

- Anchor at the repo root, then read every layer of the surface that exists, user-global, team, and local overlay, and merge `recording` and `browser_mode` per key. Report which layer supplied each effective value. The generic layer mechanics (anchoring, reading every layer, provenance, soft-degrade) are the layering contract's. See the [config-cascade contract](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/config-cascade/README.md); this step only names the surface path, the keys, and the per-key merge.
- An explicit instruction in the session prompt overrides the file layers for that run, the keys are defaults only. The precedence ladder is in [context/e2e-config.md](context/e2e-config.md).

## Step 3: Drive the run (subagent-isolated)

Delegate the drive loop to a subagent: it starts the app, navigates, interacts, and captures evidence, returning only the evidence paths. The orchestrator consumes those paths. It never carries the browser session in its own context.

The launch, on whichever path the one-launch-path rule in the Boundary section selects, happens
inside this subagent, and the evidence output it returns opens with the Native step result block.

Pass the resolved config through to the executor:

- `browser_mode` → the `/playwright:playwright` session invocation. The executor owns the headed/headless flag spelling; `run-e2e` supplies the resolved value.
- `recording` → the capture path: `video` records via the playwright CLI, `gif` via `gif_creator`, `off` keeps the evidence-contract screenshots as the floor.

The workflow steps themselves live in [context/e2e.md](context/e2e.md).

## Handoff

- Surface verification available → the bundled `/verify` skill (Claude Code ≥2.1.145) covers the same surface. Suggest the user run it and consume its findings rather than delegating to it: whether Claude may invoke it itself is [governed by a runtime gate](https://code.claude.com/docs/en/skills#bundled-skills) that can differ between two clients on one version, and the suggestion holds in either state where delegation does not. The orchestrator path in this skill runs unchanged either way. Verified 2026-08-10 against the linked reference and the shipped 2.1.223–2.1.226 clients; recheck trigger: a Claude Code release whose changelog names `/verify` or bundled-skill invocability
- All scenarios pass → invoke `/verification:confirm outcome` via the Skill tool when the `verification` plugin is installed (composes intent + evidence; chains back here when needed); otherwise report the captured evidence for outcome sign-off directly
- Visual bugs or API errors found → for API errors, read the orchestrator's structured logs for the root cause first; then invoke `/testing:diagnose` via the Skill tool
- Scenario planning needed first → invoke `/testing:plan` via the Skill tool

## Boundary, the bundled `run` skill

One native Claude Code surface launches the application this skill verifies, and the two get
conflated whenever the request is "run it and see":

- **`run` (bundled skill).** Ships with Claude Code rather than as a marketplace plugin, beside
  `/verify` and `/run-skill-generator`. It infers the launch from the project type (CLI, server,
  TUI, browser-driven), starts the app, and drives it so a change can be looked at. It captures no
  evidence to a contract and has no non-UI mode.
- **This skill (marketplace plugin).** Starts the app through the consuming project's
  orchestrator configuration (or through `run` where none governs the start), drives UI and API
  flows, and captures evidence under the contract in
  [context/e2e.md](context/e2e.md); its non-UI smoke lane has no native counterpart.

**Routing.** When the bundled `run` skill resolves in this session, prefer it directly for a quick
look at a change with no record needed. Prefer this skill when the outcome must be evidenced
(screenshots, responses, logs) or when the target is a library, MCP server, hook, or script; for an
app whose start the project's orchestrator does not govern, this skill then launches through `run`
(the Native step above). The `/verify` handoff in the Handoff section stands beside this one.

**Mutation gate.** Neither surface edits code, but both start processes. This skill drives the run
in an isolated subagent and fingerprints the tracked tree around the `run` invocation (Native step,
Mutation).

**One launch path per verification.** When the project's orchestrator configuration governs the
start (Aspire, docker-compose, tilt, a dev-server script), the Native step is skipped with
`skipped (orchestrator governs the start)` and the orchestrator path runs unchanged. Otherwise,
when `run` resolves, `run` launches the app. Never both. When the app is already running, nothing
launches: the step records `skipped (app already running)`. The launch, on either path, happens
inside the Step 3 drive subagent.

**Availability is never assumed.** Bundled surfaces are gated by settings, environment, plan, and
host; this section states what to do when one resolves, never that it is present. The four-part
records live in [context/bundled-run.md](context/bundled-run.md).

## What this skill does NOT do

- **Does not own browser-automation mechanics**. `/playwright:playwright` (when the playwright plugin is installed) covers sessions, snapshots, tracing, Windows quirks; this skill owns the broader orchestrator + API + UI story
- **Does not replace `/verification:confirm`**. That skill orchestrates the mechanical prerequisite (build+test+lint) + outcome verification

## Gotchas

- **Semantic locators**. Use the snapshot's accessibility-based element refs; CSS selectors and XPath break on cosmetic changes
- Orchestrator version coupling + health-check waits. Wait for the orchestrator's health signal before driving flows; don't poll blindly
- Playwright CLI vs MCP token budget: CLI is substantially cheaper (artifacts go to disk, only paths enter context). CLI by default; detail in [context/e2e.md](context/e2e.md)
