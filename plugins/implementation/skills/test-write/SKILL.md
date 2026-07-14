---
name: test-write
description: "Write and place tests across all ecosystems — TDD cadence (Red→Green→Refactor in vertical slices), test naming, test-type selection, project placement, and fixture patterns. Use for 'write tests', 'test this', 'where should this test go', or when code was just written without tests; for diagnosing failures use /test-diagnose, for coverage-gap analysis /test-plan, for running tests /build."
argument-hint: "[task] (e.g., /implementation:test-write, /implementation:test-write the new handler, /implementation:test-write organize)"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`

## Purpose

Authoring discipline for tests: what to test, how to name it, which test type fits, and where the test lives. `/implement` calls this skill during its TDD cadence; `/build` owns test INVOCATION (the actual commands, SSOT). Test STRUCTURE configuration (frameworks, project locations, naming, fixture conventions) belongs to the consuming project — read its testing conventions (its `CLAUDE.md` / rules / test-structure docs) before writing tests, and infer from existing test projects when nothing is documented.

## Arguments

`$ARGUMENTS` — optional task description. `organize` (or a placement-shaped question) routes to the placement guidance; anything else is authoring.

## Step 0: Route

| Signal | Context file |
|--------|-------------|
| Writing new tests, TDD, "test this code" | [context/write.md](context/write.md) |
| "Where should this test go", new test project decision, fixture patterns | [context/organize.md](context/organize.md) |

Read the relevant context file before proceeding. Both draw on the consuming project's testing conventions for per-ecosystem naming, locations, and fixtures.

## Step 1: Prerequisites

- **Branch correct?** Don't write code on the default branch in a PR-based workflow
- **Test frameworks available?** Identify the frameworks the project already uses (existing test projects, package manifests)
- **Tests exist for the area?** Check for test projects covering the changed area. If none exist and code has testable behavior, flag it

## Cross-cutting principles

- **Test behavior, not implementation** — assert on what the user sees or what the API returns, not internal state (Kent C. Dodds: "The more your tests resemble the way your software is used, the more confidence they can give you")
- **Four Pillars** (Vladimir Khorikov): protection against regressions, resistance to refactoring, fast feedback, maintainability — every test scores well on all four
- **Naming** — follow the project's documented patterns; sensible defaults by test type: unit `{Method}_Should{Behavior}_When{Condition}`, integration `{Subject}_{Behavior}`, architecture `{Subject}_Should{Constraint}`
- When uncertain about a testing decision (mock or not, output vs state test), load `/tdd:tdd` (when the `tdd` plugin is installed) for authoritative Beck/Khorikov guidance

## Handoff

- Run the new tests via `/build`, then continue `/implement`
- **For HIGH/CRITICAL test suites** (new domain logic, security-critical behavior, regression-prone paths, mocks of non-trivial dependencies, non-deterministic dependencies like clock/random/network) call the `advisor` tool (when available in the session) — rubber-duck checkpoint before commit. Lightweight cross-model critique catches false-green or brittle tests before slow CI runs — the author writing tests for their own code is the producer verifying its own work, and this cross-model pass is that independence seam. Skip for trivial test additions
- After an `organize` decision: proceed to authoring for the new test project
- Coverage gaps still open → `/test-plan`; failures while running → `/test-diagnose`

## What this skill does NOT do

- **Does not run test commands** — `/build` is SSOT for CLI invocation
- **Does not diagnose failures** — `/test-diagnose`
- **Does not replace the project's testing conventions** — the consuming project's rules are the source of truth for frameworks, naming, organization; this skill defers to them

## Gotchas

- Framework traps — `.NET`: xUnit v3 rejects `--nologo`/`-v q` (zero tests ran, exit 5); .NET 10 requires `dotnet test --project`; `Microsoft.NET.Sdk.Web` recursively compiles child directories (never nest a test project inside a Web SDK app). Check the consuming project's own gotcha notes before writing tests
- Shared-state workarounds (collection fixtures, process-global singletons) are repo-specific — consult the consuming project's testing conventions before writing or moving tests in affected areas
