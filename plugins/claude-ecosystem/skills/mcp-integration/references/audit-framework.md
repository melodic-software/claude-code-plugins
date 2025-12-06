# MCP Configuration Audit Framework

**Architecture:** This framework provides scoring criteria and query guides. **All validation rules are fetched from official documentation via docs-management skill** - this file contains NO duplicated official content.

## How Audits Work

1. **Auditor loads** `mcp-integration` skill
2. **Skill delegates** to `docs-management` for official rules
3. **Official docs provide** the actual validation criteria
4. **This framework provides** scoring weights and thresholds

## Documentation Query Guide

Before auditing, query `docs-management` skill for these topics:

| Category | Query Keywords | What to Fetch |
| -------- | -------------- | ------------- |
| Configuration Structure | ".mcp.json", "MCP configuration", "mcp config schema" | Valid file structure |
| Server Entries | "MCP server configuration", "mcpServers" | Server entry format |
| Transport Types | "MCP transport", "stdio", "http", "sse" | Valid transport options |
| Authentication | "MCP authentication", "OAuth", "MCP auth headers" | Auth configuration |
| Scopes | "MCP scopes", "project MCP", "user MCP" | Scope locations |
| Environment Variables | "MCP environment", "env expansion" | Env var patterns |

**CRITICAL:** The auditor MUST query docs-management and use the returned official documentation as the source of truth for validation rules.

## Audit Scoring Rubric

This scoring rubric is used by the `mcp-auditor` agent for formal audits.

### Category Scores

| Category | Points | Description |
| -------- | ------ | ----------- |
| Configuration Structure | 25 | Valid JSON, required fields present |
| Server Entries | 25 | Valid server configurations, proper format |
| Transport Config | 20 | Valid transport types, correct settings |
| Authentication | 15 | Proper auth setup, no exposed secrets |
| Scope Compliance | 15 | Appropriate scope (project/user/plugin) |

The maximum possible score is **Total: 100 points**.

### Scoring Details

**Note:** Pass conditions are validated against official documentation fetched via docs-management. The criteria below describe WHAT to check, not the specific rules (which come from docs).

#### Configuration Structure (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid JSON syntax | 10 | Syntax check |
| Required top-level structure | 10 | Query: ".mcp.json schema" |
| No unknown fields | 5 | Query: "MCP configuration options" |

#### Server Entries (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid server names | 8 | Query: "MCP server naming" |
| Required server fields | 10 | Query: "mcpServers configuration" |
| Valid command/args | 7 | Query: "MCP server command" |

#### Transport Config (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid transport type | 10 | Query: "MCP transport types" |
| Correct transport settings | 10 | Query: specific transport documentation |

#### Authentication (15 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| No hardcoded secrets | 8 | Security check |
| Proper auth configuration | 4 | Query: "MCP authentication" |
| Env var usage for secrets | 3 | Best practice check |

#### Scope Compliance (15 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Correct file location | 8 | Query: "MCP scopes", "mcp installation scopes" |
| Appropriate server scope | 7 | Analysis: servers match intended scope |

### Thresholds

| Score Range | Result |
| ----------- | ------ |
| 85-100 | **PASS** |
| 70-84 | **PASS WITH WARNINGS** |
| Below 70 | **FAIL** |

### Automatic Failures

Regardless of score, an MCP configuration **automatically fails** if:

- Invalid JSON syntax
- Contains exposed secrets (API keys, tokens, passwords)
- References non-existent commands/scripts
- Uses completely invalid transport types

## MCP Configuration Discovery

| Scope | Location |
| ----- | -------- |
| Project | `.mcp.json` (project root) |
| User | `~/.claude/.mcp.json` |
| Plugin | Within plugin directories |

## Repository-Specific Standards

These standards are specific to this repository and NOT from official Claude Code documentation:

| Standard | Value | Rationale |
| -------- | ----- | --------- |
| Env var for secrets | Always use `${ENV_VAR}` | Security |
| Server naming | Descriptive, lowercase | Consistency |
| Local servers | Prefer stdio transport | Simplicity |

## What This Framework Does NOT Contain

This file intentionally excludes:

- **Specific configuration schema** - Fetch from docs-management
- **Valid transport type list** - Fetch from docs-management
- **Authentication options** - Fetch from docs-management
- **Any content that exists in official documentation**

---

**Last Updated:** 2025-12-05
**Architecture:** Query-based audit framework (no duplicated official content)
