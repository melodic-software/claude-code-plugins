# Hook Audit Framework

**Architecture:** This framework provides scoring criteria and query guides. **All validation rules are fetched from official documentation via docs-management skill** - this file contains NO duplicated official content.

## How Audits Work

1. **Auditor loads** `hook-management` skill
2. **Skill delegates** to `docs-management` for official rules
3. **Official docs provide** the actual validation criteria
4. **This framework provides** scoring weights and thresholds

## Documentation Query Guide

Before auditing, query `docs-management` skill for these topics:

| Category | Query Keywords | What to Fetch |
| -------- | -------------- | ------------- |
| Hook Events | "hook events", "PreToolUse", "PostToolUse", "SessionStart" | Valid event types |
| Configuration | "hooks configuration", "hooks.json schema" | Required fields, structure |
| Matchers | "hook matchers", "tool matchers", "path matchers" | Matcher syntax and patterns |
| Decision Control | "hook decision", "block", "allow", "deny" | Valid decision values |
| Exit Codes | "hook exit codes", "hook return values" | Exit code meanings |
| Environment | "hook environment variables", "$CLAUDE_PROJECT_DIR" | Available variables |

**CRITICAL:** The auditor MUST query docs-management and use the returned official documentation as the source of truth for validation rules.

## Audit Scoring Rubric

This scoring rubric is used by the `hook-auditor` agent for formal audits.

### Category Scores

| Category | Points | Description |
| -------- | ------ | ----------- |
| Configuration Structure | 25 | Valid hooks.json, required fields present, valid event types |
| Hook Scripts | 20 | Scripts exist, proper structure, correct exit codes |
| Matchers | 20 | Appropriate tool/path matchers, not over/under matching |
| Environment Variables | 15 | Follows naming convention, documented, properly used |
| Testing | 20 | Has tests, tests pass, adequate coverage |

The maximum possible score is **Total: 100 points**.

### Scoring Details

**Note:** Pass conditions are validated against official documentation fetched via docs-management. The criteria below describe WHAT to check, not the specific rules (which come from docs).

#### Configuration Structure (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid hooks.json syntax | 8 | Query: "hooks configuration", "hooks.json" |
| Required fields present | 7 | Query: "hooks.json schema", "required fields" |
| Valid event types | 5 | Query: "hook events", "PreToolUse PostToolUse" |
| Command paths valid | 5 | File system check: scripts exist |

#### Hook Scripts (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Script exists | 5 | File system check |
| Proper shebang/structure | 5 | Repository standard: bash/python/node |
| Correct exit codes | 5 | Query: "hook exit codes" |
| JSON output format | 5 | Query: "hook JSON output schema" |

#### Matchers (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid matcher syntax | 8 | Query: "hook matchers", "tool matchers" |
| Not over-matching | 6 | Analysis: matchers appropriate for purpose |
| Not under-matching | 6 | Analysis: catches intended cases |

#### Environment Variables (15 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Follows naming convention | 8 | Repository standard: `CLAUDE_HOOK_{NAME}_ENABLED` |
| Variables documented | 4 | Repository standard: README or hook.yaml |
| Proper defaults | 3 | Repository standard: sensible defaults |

#### Testing (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Tests exist | 8 | File system check: tests/ directory |
| Tests pass | 7 | Execution check: run tests |
| Adequate coverage | 5 | Analysis: key scenarios covered |

### Thresholds

| Score Range | Result |
| ----------- | ------ |
| 85-100 | **PASS** |
| 70-84 | **PASS WITH WARNINGS** |
| Below 70 | **FAIL** |

### Automatic Failures

Regardless of score, a hook **automatically fails** if:

- hooks.json is invalid JSON - Syntax error
- Referenced scripts don't exist - Broken configuration
- Uses invalid event types - Query docs-management to verify

## Repository-Specific Standards

These standards are specific to this repository and NOT from official Claude Code documentation:

| Standard | Value | Rationale |
| -------- | ----- | --------- |
| Environment variable naming | `CLAUDE_HOOK_{NAME}_ENABLED` | Consistency across hooks |
| Script languages | Bash, Python, Node.js | Supported in shared utilities |
| Test location | `tests/` subdirectory | Vertical slice organization |
| Config file | `config.yaml` per hook | Externalized configuration |

## Hook Discovery Patterns

### Plugin Hooks

- Location: `plugins/{plugin}/hooks/hooks.json`
- Scripts: `plugins/{plugin}/hooks/{hook-name}/`

### Local Hooks

- Location: `.claude/settings.json` (hooks section)
- Or: `.claude/hooks/` directory with hooks.json

## What This Framework Does NOT Contain

This file intentionally excludes:

- **Specific event type lists** - Fetch from docs-management
- **Exact matcher syntax** - Fetch from docs-management
- **Precise exit code meanings** - Fetch from docs-management
- **Any content that exists in official documentation**

The authoritative source for all validation rules is official Claude Code documentation accessed via the docs-management skill.

---

**Last Updated:** 2025-12-05
**Architecture:** Query-based audit framework (no duplicated official content)
