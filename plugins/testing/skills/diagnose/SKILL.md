---
name: diagnose
description: "Diagnose and fix failing tests — failure classification, root-cause analysis (never retry blindly), then the reproduce → isolate → fix → retest → regression loop. Use for 'why does this fail', visible test failures, stack traces, or flaky tests; for authoring new tests use /testing:write, for running the suite /toolchain:check."
argument-hint: "[failure] (e.g., /testing:diagnose, /testing:diagnose the frozen-logger error, /testing:diagnose loop)"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`

## Purpose

The failure half of testing: understand WHY a test fails, then prove the fix. Never dismiss a failure, never retry blindly — "probably a timing issue" is not a diagnosis; even intermittent failures have deterministic root causes. Repo-specific shared-state workarounds and framework traps live in the consuming project's testing conventions — consult them before diagnosing.

## Arguments

`$ARGUMENTS` — optional failure description or `loop` to enter the fix cycle directly for an already-diagnosed bug.

## Step 0: Route

| Signal | Phase | Context file |
|--------|-------|-------------|
| Failure needs diagnosis — stack trace, assertion mismatch, flaky test | **investigate** | [context/investigate.md](context/investigate.md) |
| Root cause known, fix needed — reproduce → isolate → fix → retest → regression | **loop** | [context/loop.md](context/loop.md) |

Default entry is **investigate**; it chains into **loop** once the root cause is found. Read the relevant context file before proceeding.

## Handoff

| After phase | Suggest |
|-------------|---------|
| `investigate` | Enter the `loop` phase if a fix is needed, or report root cause. Root cause in test infrastructure → fix the test, not production code. Genuine bug → document, then fix via `/implementation:implement fix` |
| `loop` | `/verification:confirm fix` (when the `verification` plugin is installed) when all green after the regression pass (routes fix-confirmation to the `fix` criterion — symptom resolved + no regression) |

## Integration with /implementation:implement

When `/implementation:implement` hits a test failure during its TDD cadence it chains here for the reproduce→fix→retest cycle, then resumes after the loop exits green. Invoked standalone, the loop drives the full cycle including code edits and suggests `/verification:confirm` afterwards.

## What this skill does NOT do

- **Does not run the suite wholesale** — `/toolchain:check` is SSOT for CLI invocation; this skill runs targeted reproductions
- **Does not author new feature tests** — `/testing:write` (the loop's reproduce step writes only the failing test capturing the bug)

## Gotchas

- Framework traps — .NET examples: xUnit v3 rejects `--nologo` ("zero tests ran", exit 5); .NET 10 requires `dotnet test --project`; parallel-execution races. Check the consuming project's own gotcha notes before diagnosing
- Process-global singleton symptoms ("frozen", "already initialized") — usually a shared-state fixture problem; check the consuming project's fixture conventions for the named pattern before inventing a workaround
