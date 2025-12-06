# Memory (CLAUDE.md) Audit Framework

**Architecture:** This framework provides scoring criteria and query guides. **All validation rules are fetched from official documentation via docs-management skill** - this file contains NO duplicated official content.

## How Audits Work

1. **Auditor loads** `memory-management` skill
2. **Skill delegates** to `docs-management` for official rules
3. **Official docs provide** the actual validation criteria
4. **This framework provides** scoring weights and thresholds

## Documentation Query Guide

Before auditing, query `docs-management` skill for these topics:

| Category | Query Keywords | What to Fetch |
| -------- | -------------- | ------------- |
| Structure | "CLAUDE.md", "memory file structure" | File format requirements |
| Import Syntax | "import syntax", "@path import", "memory imports" | Valid import patterns |
| Hierarchy | "memory hierarchy", "enterprise project user" | Precedence rules |
| Content | "CLAUDE.md content", "memory organization" | Content guidelines |
| Progressive Disclosure | "progressive disclosure", "memory size" | Size recommendations |

**CRITICAL:** The auditor MUST query docs-management and use the returned official documentation as the source of truth for validation rules.

## Audit Scoring Rubric

This scoring rubric is used by the `memory-auditor` agent for formal audits.

### Category Scores

| Category | Points | Description |
| -------- | ------ | ----------- |
| Structure | 25 | Valid markdown, proper sections |
| Import Syntax | 25 | Correct @path syntax, files exist |
| Hierarchy Compliance | 20 | Correct level (enterprise/project/user) |
| Content Organization | 20 | Progressive disclosure, appropriate size |
| No Anti-Patterns | 10 | No circular imports, excessive nesting |

The maximum possible score is **Total: 100 points**.

### Scoring Details

**Note:** Pass conditions are validated against official documentation fetched via docs-management. The criteria below describe WHAT to check, not the specific rules (which come from docs).

#### Structure (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid markdown syntax | 10 | Markdown parsing |
| Proper section organization | 10 | Query: "CLAUDE.md structure" |
| Clear headings | 5 | Analysis: readability |

#### Import Syntax (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid @path syntax | 10 | Query: "import syntax", "@path import" |
| Referenced files exist | 10 | File system check |
| Relative paths resolve | 5 | Path resolution check |

#### Hierarchy Compliance (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Correct file location | 10 | Query: "memory hierarchy" |
| Appropriate scope content | 10 | Analysis: content matches level |

#### Content Organization (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Progressive disclosure used | 8 | Query: "progressive disclosure" |
| Appropriate file size | 7 | Query: "memory size" guidelines |
| Focused content | 5 | Analysis: not too broad |

#### No Anti-Patterns (10 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| No circular imports | 5 | Dependency graph analysis |
| No excessive nesting | 3 | Import depth check |
| No duplicate content | 2 | Content analysis |

### Thresholds

| Score Range | Result |
| ----------- | ------ |
| 85-100 | **PASS** |
| 70-84 | **PASS WITH WARNINGS** |
| Below 70 | **FAIL** |

### Automatic Failures

Regardless of score, a memory file **automatically fails** if:

- Circular import chain detected
- References non-existent files
- Invalid markdown syntax that prevents parsing
- Excessive size without progressive disclosure (>500 lines with no imports)

## Memory File Discovery

| Location | Type |
| -------- | ---- |
| `CLAUDE.md` (root) | Project root memory |
| `.claude/CLAUDE.md` | Project memory |
| `.claude/memory/*.md` | Project memory imports |
| `~/.claude/CLAUDE.md` | User memory |

## Memory Hierarchy

Precedence (highest to lowest):

1. **Enterprise** (managed policies)
2. **Project root** (`CLAUDE.md`)
3. **Project dot-claude** (`.claude/CLAUDE.md`)
4. **User** (`~/.claude/CLAUDE.md`)

## Repository-Specific Standards

These standards are specific to this repository and NOT from official Claude Code documentation:

| Standard | Value | Rationale |
| -------- | ----- | --------- |
| Root CLAUDE.md size | < 100 lines with imports | Progressive disclosure |
| Import depth | Max 3 levels | Maintainability |
| Memory file size | < 500 lines each | Context efficiency |
| Token estimates | Document in imports | Budget awareness |

## Anti-Pattern Detection

### Circular Import Detection

Build import graph and check for cycles:

```text
CLAUDE.md -> memory/a.md -> memory/b.md -> CLAUDE.md  [CYCLE!]
```

### Excessive Nesting

```text
CLAUDE.md
  -> memory/level1.md
    -> memory/level2.md
      -> memory/level3.md
        -> memory/level4.md  [TOO DEEP!]
```

## What This Framework Does NOT Contain

This file intentionally excludes:

- **Specific import syntax rules** - Fetch from docs-management
- **Exact size limits** - Fetch from docs-management
- **Memory hierarchy details** - Fetch from docs-management
- **Any content that exists in official documentation**

---

**Last Updated:** 2025-12-05
**Architecture:** Query-based audit framework (no duplicated official content)
