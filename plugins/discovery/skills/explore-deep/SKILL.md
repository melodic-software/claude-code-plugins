---
name: explore-deep
description: "Run the full explore workflow in an isolated forked subagent so verbose file reads and search output stay out of the main conversation; only a short summary returns, with findings persisted to an EXPLORE.md artifact. Use for thorough or large-scope investigation (10+ file reads or broad search sweeps)."
argument-hint: "[scope] (e.g., /discovery:explore-deep payments module dependencies, /discovery:explore-deep tests, /discovery:explore-deep git)"
user-invocable: true
disable-model-invocation: false
context: fork
agent: general-purpose
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`
Project root: !`git rev-parse --show-toplevel 2>/dev/null || echo "unknown"`

These values orient this fork only. The project root is an absolute machine path — use it to resolve files while working, but never echo it into `EXPLORE.md`; the `/explore` outcome gate you run in Step 3 requires relative, machine-agnostic paths.

## Purpose

You are a forked **general-purpose** subagent running the canonical explore workflow (the sibling `/explore` skill) on behalf of the main session. Your investigation runs in an isolated context — you do NOT see the parent conversation, and the main session does NOT see your file reads, Glob results, or Grep output; only your final summary returns.

On Claude Code ≥2.1.218 this fork runs in the background, so you get the narrower background-subagent built-in tool set plus every MCP tool — not the parent's full pool. The [sub-agents reference](https://code.claude.com/docs/en/sub-agents#available-tools) owns that list; read it there rather than trusting an enumeration here. Every tool this workflow needs is inside the set; a step needing one outside it sets `background: false` (also ≥2.1.218). Below that version a forked skill always ran in the foreground and did inherit the full pool. This is the **read-only exploration phase**: do NOT Edit source files and do NOT run mutating Bash (no writes/moves/deletes/installs, no git-state changes). The ONLY files you Write are the `EXPLORE.md` artifact in Step 3 and, when absent, the memory root's self-ignoring `.gitignore` guard. Read-only Bash (e.g. `git log`, `git diff`) for the git-history dimension is fine. This read-only boundary is by instruction, not tool-enforced — honor it deliberately.

This is a forked-execution variant of `/explore`: same investigation discipline, cleaner main-session context.

## Step 1 — Load the consuming project's conventions

As a fork you auto-load the project's memory (`CLAUDE.md`), but path-scoped project rules do NOT auto-load in subagent contexts. Before doing scope-relevant work, explicitly Read the consuming project's rule files relevant to `$ARGUMENTS` (its `.claude/rules/` or equivalent — architecture rules, the ecosystem conventions for the file types in scope, testing conventions when scope involves tests). Skip any that don't exist; never invent paths.

**Scope comes exclusively from `$ARGUMENTS`** — a forked skill does not see the parent conversation, so the caller must pass explicit scope in the invocation. If `$ARGUMENTS` is empty, run a general repository-orientation pass (project structure, build configuration, test layout) and state in both the artifact and your return summary that no scope was provided.

## Step 2 — Execute the explore workflow

Follow the sibling `/explore` skill exactly:

- Cover the relevant subset of its 6 exploration dimensions (codebase reading, git history, project structure, test discovery, configuration, environment)
- Use Glob/Grep/Read aggressively — that's the whole point of running in a fork (the verbose tool calls don't pollute main context)
- Produce its 7-section output report (summary, current state, existing patterns, test coverage, constraints, planned-direction alignment, open questions)

**Scope**: $ARGUMENTS

## Step 3 — Persist the artifact

**Before writing, run the Outcome gate** the `/explore` workflow defines — the binary artifact self-check, not a "did I explore enough?" recap; any FAIL → fix first.

Write findings to `<memory_dir>/<slug>/EXPLORE.md` — a memory-tier artifact, never committed. Destination, slug, and runtime guards resolve per the plugin's topic-docs binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)). As a fork you run under the contract's non-interactive/forked-mode rule — flag any assumed destination in your return summary.

**If EXPLORE.md already exists** there for an unrelated task, write a sidecar `EXPLORE-<scope>.md` in the same directory instead (scope slugged per the same spec) and surface the filename choice in your return summary — the sidecar avoids clobbering prior work.

## Step 4 — Return summary to main session

Your conversation history stays in the fork. Return:

1. A one-paragraph summary (3–5 sentences) of the highest-signal findings
2. The artifact path
3. Any blocking open questions the main session must answer before proceeding

Do NOT include the full 7-section report in your return — that's what the artifact is for.
