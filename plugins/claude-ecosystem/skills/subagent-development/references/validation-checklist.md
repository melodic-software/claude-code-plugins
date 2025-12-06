# Subagent/Agent Audit Framework

**Architecture:** This framework provides scoring criteria and query guides. **All validation rules are fetched from official documentation via docs-management skill** - this file contains NO duplicated official content.

## How Audits Work

1. **Auditor loads** `subagent-development` skill
2. **Skill delegates** to `docs-management` for official rules
3. **Official docs provide** the actual validation criteria
4. **This framework provides** scoring weights and thresholds
5. **Undocumented features** checked via `references/undocumented-features.md`

## Documentation Query Guide

Before auditing, query `docs-management` skill for these topics:

| Category | Query Keywords | What to Fetch |
| -------- | -------------- | ------------- |
| Name Field | "agent name", "subagent name requirements" | Character restrictions, length limits, reserved words |
| Description Field | "agent description", "automatic delegation" | Description requirements, delegation triggers |
| Tools Configuration | "agent tools", "allowed-tools agents" | Tool specification format, inheritance |
| Model Selection | "agent model selection", "inherit sonnet haiku opus" | Valid model values, when to use each |
| File Locations | "agent file locations", ".claude/agents" | Valid directories, priority resolution |
| Optional Fields | "agent YAML frontmatter", "agent configuration" | All valid frontmatter fields |

**CRITICAL:** The auditor MUST query docs-management and use the returned official documentation as the source of truth for validation rules.

## Undocumented Features

For features NOT in official docs (color, permissionMode details, skills field), see:

- `references/undocumented-features.md`

These are validated separately from official documentation.

## Audit Scoring Rubric

This scoring rubric is used by the `agent-auditor` agent for formal audits.

### Category Scores

| Category | Points | Description |
| -------- | ------ | ----------- |
| Name Field | 20 | Lowercase, hyphens, max 64 chars, no reserved words |
| Description Field | 25 | Third person, delegation triggers, when-to-use guidance |
| Tools Configuration | 20 | Appropriate restrictions, not over/under restricted |
| Model Selection | 15 | Appropriate for task complexity (haiku/sonnet/opus/inherit) |
| Additional Fields | 20 | Color, skills, permissionMode correctly configured |

The maximum possible score is **Total: 100 points**.

### Scoring Details

**Note:** Pass conditions are validated against official documentation fetched via docs-management. The criteria below describe WHAT to check, not the specific rules (which come from docs).

#### Name Field (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Character restrictions | 6 | Query: "agent name", "subagent name requirements" |
| Valid characters | 4 | Query: "agent name", "subagent name requirements" |
| Length limit | 4 | Query: "agent name", "subagent name requirements" |
| No reserved words | 6 | Query: "agent name", "reserved words" |

#### Description Field (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Present and non-empty | 5 | Query: "agent description", "required fields" |
| Third person voice | 5 | Repository standard: no "I" or "You" |
| Delegation triggers | 8 | Query: "automatic delegation", "agent description" |
| When-to-use guidance | 7 | Repository standard: clear usage scenarios |

#### Tools Configuration (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Tools specified | 5 | Query: "agent tools", "tools field" |
| Not over-restricted | 8 | Analysis: tools match stated purpose |
| Not under-restricted | 7 | Analysis: excludes unnecessary tools |

#### Model Selection (15 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Model specified | 5 | Query: "agent model selection" |
| Appropriate selection | 10 | Repository standard (see below) |

**Model Selection Guidance (Repository Standard):**

- `haiku`: Simple tasks, parallel audits, search/lookup, low-latency needs
- `sonnet`: Complex reasoning, code analysis, multi-step workflows
- `opus`: Critical decisions, comprehensive analysis, highest capability needs
- `inherit`: Use parent conversation's model (default if unspecified)

#### Additional Fields (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Color (if used) | 8 | Undocumented: see `references/undocumented-features.md` |
| Skills (if used) | 6 | Undocumented: see `references/undocumented-features.md` |
| PermissionMode (if used) | 6 | Undocumented: see `references/undocumented-features.md` |

### Thresholds

| Score Range | Result |
| ----------- | ------ |
| 85-100 | **PASS** |
| 70-84 | **PASS WITH WARNINGS** |
| Below 70 | **FAIL** |

### Automatic Failures

Regardless of score, an agent **automatically fails** if:

- Missing required fields - Query docs-management to verify which are required
- Name violates official requirements - Query docs-management for name rules
- File is empty or malformed YAML - Repository policy

## Repository-Specific Standards

These standards are specific to this repository and NOT from official Claude Code documentation:

| Standard | Value | Rationale |
| -------- | ----- | --------- |
| Third person descriptions | No "I" or "You" | Consistency, delegation clarity |
| Model selection guidance | haiku/sonnet/opus mapping | Performance/cost optimization |
| Color assignments | Semantic categories | Visual consistency |
| When-to-use in description | Clear usage scenarios | Effective auto-delegation |

## What This Framework Does NOT Contain

This file intentionally excludes:

- **Specific name character rules** - Fetch from docs-management
- **Exact field requirements** - Fetch from docs-management
- **Precise syntax specifications** - Fetch from docs-management
- **Any content that exists in official documentation**

The authoritative source for all validation rules is official Claude Code documentation accessed via the docs-management skill.

For undocumented features (color, permissionMode, skills), see `references/undocumented-features.md`.

---

**Last Updated:** 2025-12-05
**Architecture:** Query-based audit framework (no duplicated official content)
