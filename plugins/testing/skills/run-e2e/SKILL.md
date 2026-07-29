---
name: run-e2e
description: "End-to-end live app verification — check prerequisites, start the app, drive UI/API flows, and capture evidence (screenshots, responses, logs); includes a non-UI smoke-test playbook for libraries, MCP servers, hooks, and scripts. Use for 'e2e', 'smoke test', 'test the app', or when UI/API changes need runtime verification; for comprehensive build+test+lint use /verification:confirm."
argument-hint: "[scenario] (e.g., /testing:run-e2e, /testing:run-e2e the login flow, /testing:run-e2e non-ui)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: test
  summary: Start the app, drive real flows, capture evidence
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`

## Purpose

Autonomous live verification of a running application: start it, navigate, interact, screenshot, assert. UI changes follow the mandatory evidence contract in [context/e2e.md](context/e2e.md); non-UI runtime surfaces route to the smoke-test playbook. The e2e-orchestrator configuration (start command, prerequisite tooling, degraded fallback) comes from the consuming project's conventions — its orchestrator (Aspire, docker-compose, tilt, a dev-server script) and any documented evidence requirements govern.

## Arguments

`$ARGUMENTS` — optional scenario description. `non-ui` routes directly to the non-UI playbook.

## Step 0: Route

| Signal | Context file |
|--------|-------------|
| UI flows, browser evidence, API + UI orchestration | [context/e2e.md](context/e2e.md) |
| Non-UI runtime surface (library, MCP server, hooks, scripts, infrastructure) | [context/non-ui.md](context/non-ui.md) |

UI changes (Blazor / Razor / HTML / CSS / JS shipped to browser) MUST use the e2e route — the UI evidence contract is mandatory there.

## Step 1: Prerequisites (MANDATORY — hard-fail if missing)

Check tool availability per the prerequisite matrix in [context/e2e.md](context/e2e.md). When the consuming project names a prerequisite orchestrator tool/MCP, its absence hard-fails — STOP and report what's missing and how to fix it; do not attempt workarounds.

On a hard-fail, STOP **and** write a structured verification-environment gap report to the run's evidence output before stopping. The report lists what is missing — each key, CLI, MCP, or environment the run needs — and what the operator must provide to make the run possible. The STOP still holds; the gap report is its actionable half, so the operator receives a precise list of what to supply rather than a bare failure.

## Step 2: Resolve run config

Two keys govern this run: `recording` (`video | gif | off`) and `browser_mode` (`headed | headless`). They live in the consumer-tracked surface `.claude/testing/e2e.md`; [context/e2e-config.md](context/e2e-config.md) owns their definitions, defaults, and precedence. Resolve them before driving:

- Anchor at the repo root, then read every layer of the surface that exists — user-global, team, and local overlay — and merge `recording` and `browser_mode` per key. Report which layer supplied each effective value. The generic layer mechanics (anchoring, reading every layer, provenance, soft-degrade) are the layering contract's — see the [config-cascade contract](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/config-cascade/README.md); this step only names the surface path, the keys, and the per-key merge.
- An explicit instruction in the session prompt overrides the file layers for that run — the keys are defaults only. The precedence ladder is in [context/e2e-config.md](context/e2e-config.md).

## Step 3: Drive the run (subagent-isolated)

Delegate the drive loop to a subagent: it starts the app, navigates, interacts, and captures evidence, returning only the evidence paths. The orchestrator consumes those paths — it never carries the browser session in its own context.

Pass the resolved config through to the executor:

- `browser_mode` → the `/playwright:playwright` session invocation. The executor owns the headed/headless flag spelling; `run-e2e` supplies the resolved value.
- `recording` → the capture path: `video` records via the playwright CLI, `gif` via `gif_creator`, `off` keeps the evidence-contract screenshots as the floor.

The workflow steps themselves live in [context/e2e.md](context/e2e.md).

## Handoff

- Surface verification available → when the bundled `/verify` command is present (Claude Code ≥2.1.145), delegate surface verification to it first and consume its findings; when absent, the orchestrator path in this skill runs unchanged as the fallback
- All scenarios pass → `/verification:confirm outcome` when the `verification` plugin is installed (composes intent + evidence; chains back here when needed); otherwise report the captured evidence for outcome sign-off directly
- Visual bugs or API errors found → `/testing:diagnose`
- Scenario planning needed first → `/testing:plan`

## What this skill does NOT do

- **Does not own browser-automation mechanics** — `/playwright:playwright` (when the playwright plugin is installed) covers sessions, snapshots, tracing, Windows quirks; this skill owns the broader orchestrator + API + UI story
- **Does not replace `/verification:confirm`** — that skill orchestrates the mechanical prerequisite (build+test+lint) + outcome verification

## Gotchas

- **Semantic locators ONLY** — accessibility-based element refs from snapshots, never CSS selectors or XPath that break on cosmetic changes
- Orchestrator version coupling + health-check waits — wait for the orchestrator's health signal before driving flows; don't poll blindly
- Playwright CLI vs MCP token budget (~27K vs ~114K per workflow) — CLI by default; detail in [context/e2e.md](context/e2e.md)
