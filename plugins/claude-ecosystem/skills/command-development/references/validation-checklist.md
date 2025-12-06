# Slash Command Audit Framework

**Architecture:** This framework provides scoring criteria and query guides. **All validation rules are fetched from official documentation via docs-management skill** - this file contains NO duplicated official content.

## How Audits Work

1. **Auditor loads** `command-development` skill
2. **Skill delegates** to `docs-management` for official rules
3. **Official docs provide** the actual validation criteria
4. **This framework provides** scoring weights and thresholds

## Documentation Query Guide

Before auditing, query `docs-management` skill for these topics:

| Category | Query Keywords | What to Fetch |
| -------- | -------------- | ------------- |
| File Structure | "slash commands", "command locations", ".claude/commands" | Valid directories, file extension requirements |
| YAML Frontmatter | "command frontmatter", "allowed-tools", "description" | Required/optional fields, valid values |
| Description | "command description", "slash command discovery" | Description requirements and best practices |
| Tool Configuration | "allowed-tools commands", "command permissions" | How to restrict tools, valid tool names |
| Arguments | "$ARGUMENTS", "command arguments", "$1 $2" | Argument syntax and patterns |
| File References | "file references commands", "@ prefix" | File inclusion syntax |

**CRITICAL:** The auditor MUST query docs-management and use the returned official documentation as the source of truth for validation rules.

## Audit Scoring Rubric

This scoring rubric is used by the `command-auditor` agent for formal audits.

### Category Scores

| Category | Points | Description |
| -------- | ------ | ----------- |
| File Structure | 20 | Correct location, naming convention, .md extension |
| YAML Frontmatter | 25 | Description present, allowed-tools valid, argument-hint if applicable |
| Description Quality | 20 | Clear, concise, third-person, explains purpose and when to use |
| Tool Configuration | 15 | Appropriate restrictions (not over/under restricted) |
| Content Quality | 20 | Well-structured body, proper argument handling, file references correct |

The maximum possible score is **Total: 100 points**.

### Scoring Details

**Note:** Pass conditions are validated against official documentation fetched via docs-management. The criteria below describe WHAT to check, not the specific rules (which come from docs).

#### File Structure (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Correct directory location | 8 | Query: "command locations", ".claude/commands" |
| File extension | 4 | Query: "slash commands", "command file format" |
| File naming convention | 4 | Query: "command naming", "slash command files" |
| Meaningful name | 4 | Subjective: name reflects command purpose |

#### YAML Frontmatter (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Frontmatter present | 5 | Query: "command frontmatter" |
| `description` field | 10 | Query: "command description field" |
| `allowed-tools` valid | 5 | Query: "allowed-tools commands" |
| `argument-hint` | 5 | Query: "argument-hint frontmatter" |

#### Description Quality (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Clear purpose | 8 | Query: "command description best practices" |
| Concise | 4 | Repository standard: under 100 words |
| Action-oriented | 4 | Repository standard: uses active verbs |
| When to use | 4 | Repository standard: implies usage context |

#### Tool Configuration (15 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Not over-restricted | 8 | Analysis: tools match stated purpose |
| Not under-restricted | 7 | Analysis: excludes unnecessary tools |

#### Content Quality (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Well-structured | 8 | Repository standard: clear sections |
| Argument handling | 6 | Query: "$ARGUMENTS", "command arguments" |
| File references | 6 | Query: "file references commands", "@ prefix" |

### Thresholds

| Score Range | Result |
| ----------- | ------ |
| 85-100 | **PASS** |
| 70-84 | **PASS WITH WARNINGS** |
| Below 70 | **FAIL** |

### Automatic Failures

Regardless of score, a command **automatically fails** if:

- No frontmatter AND no description (undiscoverable) - Repository policy
- File extension violates official requirements - Query docs-management to verify
- File is empty or only contains frontmatter - Repository policy

## Repository-Specific Standards

These standards are specific to this repository and NOT from official Claude Code documentation:

| Standard | Value | Rationale |
| -------- | ----- | --------- |
| Description length | Under 100 words | Conciseness for discoverability |
| Naming convention | Verb-noun kebab-case | Consistency with built-in commands |
| Structure | Clear sections | Maintainability |

## What This Framework Does NOT Contain

This file intentionally excludes:

- **Specific YAML field requirements** - Fetch from docs-management
- **Exact naming rules** - Fetch from docs-management
- **Precise syntax requirements** - Fetch from docs-management
- **Any content that exists in official documentation**

The authoritative source for all validation rules is official Claude Code documentation accessed via the docs-management skill.

---

**Last Updated:** 2025-12-05
**Architecture:** Query-based audit framework (no duplicated official content)
