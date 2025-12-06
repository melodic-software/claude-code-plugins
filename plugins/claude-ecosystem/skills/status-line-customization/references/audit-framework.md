# Status Line Audit Framework

**Architecture:** This framework provides scoring criteria and query guides. **All validation rules are fetched from official documentation via docs-management skill** - this file contains NO duplicated official content.

## How Audits Work

1. **Auditor loads** `status-line-customization` skill
2. **Skill delegates** to `docs-management` for official rules
3. **Official docs provide** the actual validation criteria
4. **This framework provides** scoring weights and thresholds

## Documentation Query Guide

Before auditing, query `docs-management` skill for these topics:

| Category | Query Keywords | What to Fetch |
| -------- | -------------- | ------------- |
| Script Requirements | "status line script", "statusLine setting" | Script requirements |
| JSON Input | "status line JSON", "status line input structure" | Input format |
| Output Format | "status line output", "terminal output" | Output requirements |
| Color Codes | "terminal color", "ANSI escape codes" | Color handling |
| Cross-Platform | "cross-platform script", "bash python node" | Platform support |

**CRITICAL:** The auditor MUST query docs-management and use the returned official documentation as the source of truth for validation rules.

## Audit Scoring Rubric

This scoring rubric is used by the `statusline-auditor` agent for formal audits.

### Category Scores

| Category | Points | Description |
| -------- | ------ | ----------- |
| Script Structure | 25 | Valid script, proper shebang, executable |
| JSON Handling | 25 | Correctly parses JSON input structure |
| Output Format | 25 | Proper terminal formatting, colors |
| Cross-Platform | 25 | Works on Windows, macOS, Linux |

The maximum possible score is **Total: 100 points**.

### Scoring Details

**Note:** Pass conditions are validated against official documentation fetched via docs-management. The criteria below describe WHAT to check, not the specific rules (which come from docs).

#### Script Structure (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid shebang line | 8 | Script analysis |
| Executable permissions | 7 | File permissions check |
| No syntax errors | 10 | Script validation |

#### JSON Handling (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Reads stdin correctly | 10 | Script analysis |
| Parses JSON structure | 10 | Query: "status line input structure" |
| Handles missing fields | 5 | Robustness check |

#### Output Format (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Outputs to stdout | 8 | Script analysis |
| Valid terminal formatting | 10 | Query: "status line output" |
| Color codes if used | 7 | Query: "terminal color codes" |

#### Cross-Platform (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Bash compatibility | 8 | Script portability |
| No OS-specific features | 8 | Platform analysis |
| Fallback handling | 9 | Robustness check |

### Thresholds

| Score Range | Result |
| ----------- | ------ |
| 85-100 | **PASS** |
| 70-84 | **PASS WITH WARNINGS** |
| Below 70 | **FAIL** |

### Automatic Failures

Regardless of score, a status line script **automatically fails** if:

- Script cannot be parsed/validated
- Does not read from stdin
- No output to stdout
- Critical syntax errors

## Status Line Discovery

Status lines are configured in settings.json:

| Setting Location | Configuration Key |
| ---------------- | ----------------- |
| Project | `.claude/settings.json` -> `statusLine` |
| User | `~/.claude/settings.json` -> `statusLine` |

## Script Language Support

Common languages for status line scripts:

| Language | Shebang | JSON Parser |
| -------- | ------- | ----------- |
| Bash | `#!/bin/bash` | `jq` |
| Python | `#!/usr/bin/env python3` | `json` module |
| Node.js | `#!/usr/bin/env node` | Built-in |

## Repository-Specific Standards

These standards are specific to this repository and NOT from official Claude Code documentation:

| Standard | Value | Rationale |
| -------- | ----- | --------- |
| Preferred language | Bash or Python | Cross-platform |
| Color support | Optional with fallback | Terminal compatibility |
| Error handling | Silent fallback | Don't break Claude |

## What This Framework Does NOT Contain

This file intentionally excludes:

- **Specific JSON input structure** - Fetch from docs-management
- **Required output format details** - Fetch from docs-management
- **Terminal color code specifications** - Fetch from docs-management
- **Any content that exists in official documentation**

---

**Last Updated:** 2025-12-05
**Architecture:** Query-based audit framework (no duplicated official content)
