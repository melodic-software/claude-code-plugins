---
name: test-e2e
description: "End-to-end live app verification — check prerequisites, start the app, drive UI/API flows, and capture evidence (screenshots, responses, logs); includes a non-UI smoke-test playbook for libraries, MCP servers, hooks, and scripts. Use for 'e2e', 'smoke test', 'test the app', or when UI/API changes need runtime verification; for comprehensive build+test+lint use /verify-changes."
argument-hint: "[scenario] (e.g., /implementation:test-e2e, /implementation:test-e2e the login flow, /implementation:test-e2e non-ui)"
user-invocable: true
disable-model-invocation: false
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

## Handoff

- All scenarios pass → `/verify-changes outcome` (composes intent + evidence; chains back here when needed)
- Visual bugs or API errors found → `/test-diagnose`
- Scenario planning needed first → `/test-plan`

## What this skill does NOT do

- **Does not own browser-automation mechanics** — `/playwright:playwright` (when the playwright plugin is installed) covers sessions, snapshots, tracing, Windows quirks; this skill owns the broader orchestrator + API + UI story
- **Does not replace `/verify-changes`** — that skill orchestrates the mechanical prerequisite (build+test+lint) + outcome verification

## Gotchas

- **Semantic locators ONLY** — accessibility-based element refs from snapshots, never CSS selectors or XPath that break on cosmetic changes
- Orchestrator version coupling + health-check waits — wait for the orchestrator's health signal before driving flows; don't poll blindly
- Playwright CLI vs MCP token budget (~27K vs ~114K per workflow) — CLI by default; detail in [context/e2e.md](context/e2e.md)
