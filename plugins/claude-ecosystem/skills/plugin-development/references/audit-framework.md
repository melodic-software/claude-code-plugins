# Plugin Audit Framework

**Architecture:** This framework provides scoring criteria and query guides. **All validation rules are fetched from official documentation via docs-management skill** - this file contains NO duplicated official content.

## How Audits Work

1. **Auditor loads** `plugin-development` skill
2. **Skill delegates** to `docs-management` for official rules
3. **Official docs provide** the actual validation criteria
4. **This framework provides** scoring weights and thresholds

## Documentation Query Guide

Before auditing, query `docs-management` skill for these topics:

| Category | Query Keywords | What to Fetch |
| -------- | -------------- | ------------- |
| Manifest | "plugin.json", "plugin manifest", "plugin schema" | Required fields, structure |
| Structure | "plugin structure", "plugin organization" | Directory layout requirements |
| Commands | "plugin commands", "plugin slash commands" | Command integration |
| Skills | "plugin skills", "skills in plugins" | Skill packaging |
| Agents | "plugin agents", "plugin subagents" | Agent distribution |
| Hooks | "plugin hooks", "hooks.json" | Hook configuration |
| Marketplace | "plugin marketplace", "plugin distribution" | Publishing requirements |

**CRITICAL:** The auditor MUST query docs-management and use the returned official documentation as the source of truth for validation rules.

## Audit Scoring Rubric

This scoring rubric is used by the `plugin-auditor` agent for formal audits.

### Category Scores

| Category | Points | Description |
| -------- | ------ | ----------- |
| Manifest Structure | 25 | Valid plugin.json, required fields present |
| Component Organization | 25 | Proper directories for all components |
| Namespace Compliance | 20 | Consistent naming, no conflicts |
| Documentation | 15 | README, descriptions, usage examples |
| Distribution Readiness | 15 | Version, dependencies, marketplace requirements |

The maximum possible score is **Total: 100 points**.

### Scoring Details

**Note:** Pass conditions are validated against official documentation fetched via docs-management. The criteria below describe WHAT to check, not the specific rules (which come from docs).

#### Manifest Structure (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid JSON syntax | 5 | Syntax check |
| Name field | 8 | Query: "plugin.json", "plugin name" |
| Description field | 4 | Query: "plugin manifest" |
| Version field | 4 | Query: "plugin version", "semver" |
| Other required fields | 4 | Query: "plugin schema" |

#### Component Organization (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Commands directory | 7 | Query: "plugin commands structure" |
| Skills directory | 6 | Query: "plugin skills structure" |
| Agents directory | 6 | Query: "plugin agents structure" |
| Hooks directory | 6 | Query: "plugin hooks structure" |

#### Namespace Compliance (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Consistent prefix | 10 | Repository standard: plugin name prefix |
| No reserved words | 5 | Query: "plugin naming restrictions" |
| No conflicts | 5 | Analysis: unique names |

#### Documentation (15 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| README exists | 5 | File system check |
| Component descriptions | 5 | Analysis: all components have descriptions |
| Usage examples | 5 | Repository standard: practical examples |

#### Distribution Readiness (15 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid semver version | 5 | Query: "plugin version" |
| Dependencies documented | 5 | Repository standard |
| Marketplace metadata | 5 | Query: "plugin marketplace" |

### Thresholds

| Score Range | Result |
| ----------- | ------ |
| 85-100 | **PASS** |
| 70-84 | **PASS WITH WARNINGS** |
| Below 70 | **FAIL** |

### Automatic Failures

Regardless of score, a plugin **automatically fails** if:

- plugin.json is invalid JSON
- Missing name field
- Missing description field

## Repository-Specific Standards

These standards are specific to this repository and NOT from official Claude Code documentation:

| Standard | Value | Rationale |
| -------- | ----- | --------- |
| Namespace prefix | Plugin name | Consistency |
| README required | Yes | Discoverability |
| Descriptions required | All components | User guidance |

## What This Framework Does NOT Contain

This file intentionally excludes:

- **Specific manifest field requirements** - Fetch from docs-management
- **Exact structure requirements** - Fetch from docs-management
- **Any content that exists in official documentation**

---

**Last Updated:** 2025-12-05
**Architecture:** Query-based audit framework (no duplicated official content)
