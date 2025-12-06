# Output Style Audit Framework

**Architecture:** This framework provides scoring criteria and query guides. **All validation rules are fetched from official documentation via docs-management skill** - this file contains NO duplicated official content.

## How Audits Work

1. **Auditor loads** `output-customization` skill
2. **Skill delegates** to `docs-management` for official rules
3. **Official docs provide** the actual validation criteria
4. **This framework provides** scoring weights and thresholds

## Documentation Query Guide

Before auditing, query `docs-management` skill for these topics:

| Category | Query Keywords | What to Fetch |
| -------- | -------------- | ------------- |
| File Structure | "output styles", "output-styles directory" | Valid locations |
| Frontmatter | "output style frontmatter", "name description" | Required fields |
| Content | "output style content", "style instructions" | Content requirements |
| Switching | "/output-style", "style switching" | Compatibility rules |
| Built-in Styles | "built-in output styles", "Default Explanatory Learning" | What to avoid duplicating |

**CRITICAL:** The auditor MUST query docs-management and use the returned official documentation as the source of truth for validation rules.

## Audit Scoring Rubric

This scoring rubric is used by the `output-style-auditor` agent for formal audits.

### Category Scores

| Category | Points | Description |
| -------- | ------ | ----------- |
| File Structure | 20 | Correct location, .md extension |
| YAML Frontmatter | 30 | Required fields present and valid |
| Content Quality | 30 | Clear instructions, proper structure |
| Compatibility | 20 | Works with style switching, no conflicts |

The maximum possible score is **Total: 100 points**.

### Scoring Details

**Note:** Pass conditions are validated against official documentation fetched via docs-management. The criteria below describe WHAT to check, not the specific rules (which come from docs).

#### File Structure (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Correct directory | 10 | Query: "output-styles directory" |
| .md file extension | 5 | Convention check |
| Kebab-case filename | 5 | Convention check |

#### YAML Frontmatter (30 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid YAML syntax | 8 | Syntax check |
| `name` field present | 8 | Query: "output style frontmatter" |
| `description` field present | 8 | Query: "output style frontmatter" |
| `keep-coding-instructions` if needed | 6 | Query: "keep-coding-instructions" |

#### Content Quality (30 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Clear instructions | 12 | Analysis: readability |
| Actionable guidance | 10 | Analysis: Claude can follow |
| Appropriate length | 8 | Query: "output style content" guidelines |

#### Compatibility (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| No built-in style conflicts | 10 | Query: "built-in output styles" |
| Works with /output-style | 10 | Query: "style switching" |

### Thresholds

| Score Range | Result |
| ----------- | ------ |
| 85-100 | **PASS** |
| 70-84 | **PASS WITH WARNINGS** |
| Below 70 | **FAIL** |

### Automatic Failures

Regardless of score, an output style **automatically fails** if:

- Invalid YAML frontmatter syntax
- Missing `name` field
- Empty content (no instructions)
- Not a markdown file

## Output Style Discovery

| Scope | Location |
| ----- | -------- |
| Project | `.claude/output-styles/*.md` |
| User | `~/.claude/output-styles/*.md` |

## Repository-Specific Standards

These standards are specific to this repository and NOT from official Claude Code documentation:

| Standard | Value | Rationale |
| -------- | ----- | --------- |
| Filename convention | kebab-case | Consistency |
| Description length | 1-2 sentences | Clarity in style list |
| Content organization | Sections with headers | Readability |

## What This Framework Does NOT Contain

This file intentionally excludes:

- **Specific frontmatter field requirements** - Fetch from docs-management
- **Built-in style names** - Fetch from docs-management
- **Exact content guidelines** - Fetch from docs-management
- **Any content that exists in official documentation**

---

**Last Updated:** 2025-12-05
**Architecture:** Query-based audit framework (no duplicated official content)
