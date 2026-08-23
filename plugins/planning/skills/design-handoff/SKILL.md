---
description: "Gate and package a finished design for /planning:plan: binary check that every thread in design-threads.md is RESOLVED, directional, or TAGGED-DEFERRED, then emit the plan-ready summary and resume prompt. Use when: 'design handoff', 'hand off the design', 'is the design ready', 'plan-ready summary', 'design gate', /planning:design discussion rounds stop surfacing gaps, or entering /planning:plan from a completed design session. FAILs on any thread that is unresolved AND untagged. Names it and routes back to /planning:design. Skip when: still exploring the design space. Use /planning:design; mid-session save-point to clear and resume later. Use a session-handoff capability."
argument-hint: "(no args; reads the design-threads artifact in the topic's contract slice)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: plan
  summary: Gate a finished design and package it for planning
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`

## Purpose

The seam between design and planning. `/planning:plan`'s prerequisite check blocks on design-gate evidence; this skill produces that evidence honestly. A binary check read off the artifact, then a handoff summary sourced from the artifacts rather than recalled from conversation memory.

Design artifacts live in `<contract_dir>/<topic-slug>/design/` (default `docs/topics/`). The topic's contract slice on the task branch, joining the memory slice under `contract_tier: local`; roots, tier, and precedence resolve per the topic-docs binding [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md). Derive `<topic-slug>` from the task or branch name (kebab-case, ≤40 chars; shared with `/planning:design` and `/planning:plan`).

## Binary gate. Check the artifact, not your memory

Read `design-threads.md` in the topic's resolved design slice (`<contract_dir>/<topic-slug>/design/`, default `docs/topics/`; the memory slice under `contract_tier: local`) and confirm, thread by thread, that **every** design thread is one of:

- **RESOLVED**. The deciding rationale is recorded in the artifact (not merely "decided"), or
- **directional**. Direction agreed AND the remaining detail carries a research tag, or
- **TAGGED-DEFERRED**. An explicit research tag naming the external investigation needed.

A thread that is unresolved AND untagged is a silent gap → **FAIL**: list the offending thread(s), route back by invoking `/planning:design` via the Skill tool (its design-threads and discussion rounds) to resolve or tag, and do NOT hand off. This is a binary check read off `design-threads.md`, not a "did we cover enough?" recap. A producing model rubber-stamps its own recap, so the gate must be read off the file rather than judged from memory.

If `design-threads.md` does not exist, check for `design-resolution.md` at the same path (the `/planning:design` early-exit artifact). Early-exit slices hand off on that artifact alone. Neither present → FAIL: no design evidence; route back by invoking `/planning:design` via the Skill tool.

## Handoff summary (gate passed)

Hand off by invoking `/planning:plan` via the Skill tool. Sourced from the artifacts, not recalled from memory:

- Resolved decisions with their recorded rationale (from `design-threads.md`)
- Deferred research items with tags
- Design artifacts produced
- Dependency order for implementation (which decisions block others)
- Extension / config / observability threads **RESOLVED** or **TAGGED-DEFERRED**. `/planning:plan` next walks its design-default checklist against the plan
- **Review-routing notes**. When the consuming project declares review checklists (architecture, code-design, security, multi-tenancy, messaging, and the like), list which apply to this slice so `/planning:plan` and the implementation stage inherit proactive review targets
- **Mechanization notes** (optional). When the project distinguishes deterministic mechanization from human judgment, mark per capability whether a sub-step is script-, hook-, agent-, or human-owned; a trivial early-exit records "no deterministic sub-steps"

Emit a resume prompt so a fresh cleared session can pick up at `/planning:plan` reading only the persisted artifacts.

## What this skill does NOT do

- **Design exploration or thread resolution**. That's `/planning:design` (a FAILed gate routes there; this skill never resolves threads itself)
- **Implementation planning**. That's `/planning:plan` (this skill packages its input)
- **Mid-session save-point**. That's a session-handoff capability (a journal entry plus status for a later clear-and-resume). This skill is the design→plan stage seam, not a pause-point

## Gotchas

- A thread marked "decided" without recorded rationale is NOT RESOLVED. The rationale must be in the artifact, or `/planning:plan` inherits an unexplainable decision. FAIL it back by invoking `/planning:design` via the Skill tool to record the why
- Do not soften a FAIL into a warning because the offending thread "feels minor". Silent gaps are exactly what the binary gate exists to catch
- `/planning:design`'s `handoff` action is an in-session shortcut that delegates here. This skill is the single canonical gate implementation, so criteria changes land here only
