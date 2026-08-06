---
name: audit
description: "Audit MCP server tool definitions against design quality criteria. Use when: 'audit MCP tools', 'check MCP tool descriptions', 'review MCP server quality', 'tool annotations', 'readOnlyHint missing', 'parameter descriptions missing', 'check the _meta annotations', 'maxResultSizeChars', 'requiresUserInteraction', 'alwaysLoad', 'are my server instructions too long', 'mcp audit', or before shipping MCP server changes. Optional path argument targets a single server directory; omit to audit the whole project. Produces per-tool PASS/WARN/FAIL scorecard covering description completeness, parameters, naming, annotations, and the Claude Code `_meta` annotations, plus a server-level result for the server `instructions` size budget. Language-agnostic — Python (`mcp`), TypeScript, .NET. Not for: MCP server configuration or connection issues."
argument-hint: "[path] — a directory to scope the audit to (e.g. a single server dir), or omit for the whole project"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: review
  summary: Audit MCP tool definitions against design quality criteria
---

## Purpose

Evaluate MCP server tool definitions against design quality criteria drawn from three upstream
authorities, cited (not recapped) so the current text always governs:

- [MCP specification 2025-11-25 — Tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) — the normative protocol (MUST / SHOULD / OPTIONAL requirements for names, schemas, annotations).
- [Anthropic — Writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents) — engineering guidance for descriptions, parameters, namespacing, and workflow-shaped granularity.
- [Claude Code — Connect Claude Code to tools via MCP](https://code.claude.com/docs/en/mcp) — Claude-Code-specific client behavior: `_meta` annotations and truncation limits.

Produces a per-tool scorecard with actionable findings. Catches description gaps, missing annotations,
and naming issues before they degrade LLM tool selection accuracy.

## Server discovery configuration

Phase 1 enumerates MCP servers and their tool source files by scanning the project for the per-language
tool markers. The `tool-marker`, `name-extraction`, `description-extraction`, and `meta-extraction`
rules are upstream MCP-SDK conventions, stable across repos. See
[reference/server-discovery.md](reference/server-discovery.md) for the per-language discovery rules and
how servers are grouped.

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

Read each `Tool file:` from Phase 1. Per the language rules in
[reference/server-discovery.md](reference/server-discovery.md), extract descriptions, parameters,
wire-level annotations (C12-C14), and the tool's `_meta` object (C17-C19) — the last via
**meta-extraction**, recording each key's JSON type and not merely its presence, because C18 turns on
it. Load the detailed checklist from [reference/checklist.md](reference/checklist.md).

Once per server, also resolve its `instructions` field — see **Server instructions** in
[reference/server-discovery.md](reference/server-discovery.md) — and evaluate C4's per-server clause
against it. Phase 1's records are per-tool, so this is the only step that reaches it; its result lands
in the server-level row of the Phase 3 report, not in any tool's table.

Evaluate every criterion in the checklist against each tool, and C4's per-server clause once per
server. Record each result as:

- **PASS** — criterion met
- **WARN** — criterion partially met or could be improved
- **FAIL** — criterion not met
- **info** — an optimization opportunity rather than a defect; the severity `reference/checklist.md`
  assigns to C8, C11, C14, and by default to C17-C19
- **n/a** — the criterion has no subject here, so it cannot pass: a server whose construction site
  declares no `instructions` gives C4's per-server clause nothing to size
- **undetermined** — the subject was not reachable in the scanned scope (no server construction site
  found), which is not the same as its being absent

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

Server-level criteria — the outcomes that belong to the server, not to any one tool:

| Criterion | Authority | Result | Details |
|-----------|-----------|--------|---------|
| C4 Server `instructions` within size budget | OPINION | n/a | Construction site declares no `instructions` |

#### Tool: <tool_name>

| Criterion | Authority | Result | Details |
|-----------|-----------|--------|---------|
| C1 Description has "what" | ANTHROPIC | WARN | Missing "when to use" context |
| C9 Name charset/length valid | SPEC-SHOULD | PASS | |
| C12 readOnlyHint set | SPEC-OPTIONAL | WARN | Read-only tool lacks the hint |
| C18 requiresUserInteraction is JSON `true` | OPINION | FAIL | Declared as the string `"true"` — silently ignored |
| ... | ... | ... | ... |

(repeat for each tool)
```

**Prioritize FAIL items** — highest-value improvements. WARN items are suggestions and info items are
optimizations; `n/a` and `undetermined` record that a criterion had no subject, or none reachable, and
neither counts as a pass in the summary table. A missing annotation is never FAIL — annotations are
OPTIONAL in the spec (C12-C14) or Claude-Code-specific advisories (C17-C19); only a declared value
Claude Code silently ignores can FAIL (C18).

## What this skill does NOT do

- Does not modify tool definitions — it reports. Use findings to guide manual improvements.
- Does not test tool functionality — use MCP Inspector for that.
- Does not evaluate MCP resources — only tools.
