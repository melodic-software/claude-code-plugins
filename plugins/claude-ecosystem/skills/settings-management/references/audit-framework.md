# Settings Audit Framework

**Architecture:** This framework provides scoring criteria and query guides. **All validation rules are fetched from official documentation via docs-management skill** - this file contains NO duplicated official content.

## How Audits Work

1. **Auditor loads** `settings-management` skill
2. **Skill delegates** to `docs-management` for official rules
3. **Official docs provide** the actual validation criteria
4. **This framework provides** scoring weights and thresholds

## Documentation Query Guide

Before auditing, query `docs-management` skill for these topics:

| Category | Query Keywords | What to Fetch |
| -------- | -------------- | ------------- |
| Schema | "settings.json", "settings schema", "available settings" | Valid options list |
| Permission Rules | "permission rules", "allow deny ask", "permission patterns" | Rule syntax |
| Sandbox | "sandbox settings", "sandbox configuration" | Sandbox options |
| Environment | "env settings", "environment variables settings" | Env config |
| Precedence | "settings precedence", "enterprise project user" | Hierarchy rules |
| Model Config | "model settings", "default model", "model aliases" | Model options |

**CRITICAL:** The auditor MUST query docs-management and use the returned official documentation as the source of truth for validation rules.

## Audit Scoring Rubric

This scoring rubric is used by the `settings-auditor` agent for formal audits.

### Category Scores

| Category | Points | Description |
| -------- | ------ | ----------- |
| JSON Validity | 20 | Valid JSON syntax, well-formed |
| Schema Compliance | 25 | Only valid settings options used |
| Permission Rules | 25 | Valid permission patterns, appropriate restrictions |
| Environment Config | 15 | Valid env vars, no secrets exposed |
| Precedence Awareness | 15 | Correct scope usage |

The maximum possible score is **Total: 100 points**.

### Scoring Details

**Note:** Pass conditions are validated against official documentation fetched via docs-management. The criteria below describe WHAT to check, not the specific rules (which come from docs).

#### JSON Validity (20 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid JSON syntax | 10 | Syntax check |
| Well-formed structure | 5 | Query: "settings.json structure" |
| No trailing commas | 5 | Syntax check |

#### Schema Compliance (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid top-level keys | 10 | Query: "settings schema", "available settings" |
| Valid option values | 10 | Query: specific option documentation |
| No deprecated options | 5 | Query: "deprecated settings" |

#### Permission Rules (25 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid rule syntax | 10 | Query: "permission rules syntax" |
| Appropriate tool patterns | 8 | Query: "permission patterns" |
| No overly permissive rules | 7 | Analysis: security assessment |

#### Environment Config (15 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Valid env var names | 5 | Analysis: naming conventions |
| No exposed secrets | 7 | Security check: no API keys, passwords |
| Appropriate hook env vars | 3 | Repository standard |

#### Precedence Awareness (15 points)

| Criterion | Points | Validation Source |
| --------- | ------ | ----------------- |
| Correct file location | 8 | Query: "settings precedence" |
| Appropriate scope | 7 | Analysis: settings match intended scope |

### Thresholds

| Score Range | Result |
| ----------- | ------ |
| 85-100 | **PASS** |
| 70-84 | **PASS WITH WARNINGS** |
| Below 70 | **FAIL** |

### Automatic Failures

Regardless of score, a settings file **automatically fails** if:

- Invalid JSON syntax
- Contains exposed secrets in **project or enterprise scope** (API keys, passwords, tokens)
- Uses completely invalid/unrecognized options

**Note:** User-level settings with credentials receive WARNING (not auto-fail) since they are not version controlled. See "Scope-Aware Credential Detection" below.

### Scope-Aware Credential Detection

API keys and credentials in settings files are evaluated differently based on scope:

| Scope | Credentials Found | Severity | Score Impact | Rationale |
| ------- | ------------------- | ---------- | -------------- | ----------- |
| Project | Yes | CRITICAL | Auto-fail | Version controlled, shared with team |
| User | Yes | WARNING | -7 points (env config) | Not version controlled, personal use acceptable |
| Enterprise | Yes | CRITICAL | Auto-fail | Managed policy violation |

**Project-level (`.claude/settings.json`) messaging:**

- Impact: "Credentials exposed in version control history"
- Recommendations: Revoke keys, use environment variables, clean git history

**User-level (`~/.claude/settings.json`) messaging:**

- Impact: "Credentials stored in plaintext on local machine (not version controlled)"
- Recommendations: Consider using environment variables with `${VAR}` expansion
- Do NOT mention git history cleanup (not applicable)
- Acceptable: For personal development machines, hardcoded user-level keys are acceptable with warning

## Settings File Discovery

| Scope | Location |
| ----- | -------- |
| Enterprise | OS-specific managed settings location |
| Project | `.claude/settings.json` |
| User | `~/.claude/settings.json` |
| Plugin | Within plugin directories |

## Repository-Specific Standards

These standards are specific to this repository and NOT from official Claude Code documentation:

| Standard | Value | Rationale |
| -------- | ----- | --------- |
| Secrets in project settings | Never (CRITICAL) | Version controlled, shared |
| Secrets in user settings | Warning only | Not version controlled |
| Hook env var naming | `CLAUDE_HOOK_{NAME}_ENABLED` | Consistency |
| Descriptive comments | Via separate documentation | Settings is JSON (no comments) |

## What This Framework Does NOT Contain

This file intentionally excludes:

- **Specific valid settings options** - Fetch from docs-management
- **Exact permission rule syntax** - Fetch from docs-management
- **Complete schema specification** - Fetch from docs-management
- **Any content that exists in official documentation**

---

**Last Updated:** 2025-12-06
**Architecture:** Query-based audit framework (no duplicated official content)
