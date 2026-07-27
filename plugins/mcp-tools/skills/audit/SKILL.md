---
name: audit
description: "Audit MCP server tool definitions against design quality criteria. Use when: 'audit MCP tools', 'check MCP tool descriptions', 'review MCP server quality', 'tool annotations', 'readOnlyHint missing', 'parameter descriptions missing', 'mcp audit', or before shipping MCP server changes. Optional path argument targets a single server directory; omit to audit the whole project. Produces per-tool PASS/WARN/FAIL scorecard covering description completeness, parameters, naming, and annotations. Language-agnostic — Python (FastMCP), TypeScript, .NET. Not for: MCP server configuration or connection issues."
argument-hint: "[path] — a directory to scope the audit to (e.g. a single server dir), or omit for the whole project"
user-invocable: true
disable-model-invocation: false
metadata:
  cheatsheet-stage: review
  cheatsheet-summary: Audit MCP tool definitions against design quality criteria
---

## Purpose

Evaluate MCP server tool definitions against design quality criteria drawn from two upstream
authorities, cited (not recapped) so the current text always governs:

- [MCP specification 2025-11-25 — Tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) — the normative protocol (MUST / SHOULD / OPTIONAL requirements for names, schemas, annotations).
- [Anthropic — Writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents) — engineering guidance for descriptions, parameters, namespacing, and workflow-shaped granularity.

Produces a per-tool scorecard with actionable findings. Catches description gaps, missing annotations,
and naming issues before they degrade LLM tool selection accuracy.

## Server discovery configuration

Phase 1 enumerates MCP servers and their tool source files by scanning the project for the per-language
tool markers. The `tool-marker`, `name-extraction`, and `description-extraction` rules are upstream
MCP-SDK conventions, stable across repos. See [reference/server-discovery.md](reference/server-discovery.md)
for the per-language discovery rules and how servers are grouped.

## Arguments

Parse `$ARGUMENTS`:

- **`<path>`** — audit a single scope. A directory to narrow the scan to (typically one server's directory).
- ***(empty)*** — audit every tool discovered under the project root.

## Track progress

For multi-server audit runs (Phases 1-3 across ≥2 servers), keep an in-response checklist of the three
phases and tick each as it completes. Phase 2 may run subagent fan-out for ≥5 tools.

## Workflow

### Phase 1: Discover servers and tools

1. `bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/discover.sh"` (or `--path <dir>` when `$ARGUMENTS` supplies a directory).
2. **Optional scope filter.** If a path was given as `$ARGUMENTS`, pass it to `discover.sh --path <dir>`.

### Phase 2: Evaluate against checklist

Read each `Tool file:` from Phase 1. Extract descriptions, parameters, and annotations per
[reference/server-discovery.md](reference/server-discovery.md) language rules. Load the detailed
checklist from [reference/checklist.md](reference/checklist.md).

For each tool, evaluate every criterion in the checklist. Record result as:

- **PASS** — criterion met
- **WARN** — criterion partially met or could be improved
- **FAIL** — criterion not met

### Phase 3: Report

Output a markdown report with this structure:

```markdown
# MCP Tool Audit Report

**Date:** YYYY-MM-DD
**Servers audited:** N
**Tools audited:** N
**Overall:** X pass, Y warn, Z fail

## Summary by server

| Server | Tools | Pass | Warn | Fail |
|--------|-------|------|------|------|
| <server-name> | N | ... | ... | ... |

## Findings by server

### Server: <server-name> (<language>)

#### Tool: <tool_name>

| Criterion | Authority | Result | Details |
|-----------|-----------|--------|---------|
| C1 Description has "what" | ANTHROPIC | WARN | Missing "when to use" context |
| C9 Name charset/length valid | SPEC-SHOULD | PASS | |
| C12 readOnlyHint set | SPEC-OPTIONAL | WARN | Read-only tool lacks the hint |
| ... | ... | ... | ... |

(repeat for each tool)
```

**Prioritize FAIL items** — highest-value improvements. WARN items are suggestions. A missing
annotation is always WARN, never FAIL — annotations are OPTIONAL in the spec.

## What this skill does NOT do

- Does not modify tool definitions — it reports. Use findings to guide manual improvements.
- Does not test tool functionality — use MCP Inspector for that.
- Does not evaluate MCP resources — only tools.
