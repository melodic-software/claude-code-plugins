# Category Playbook

## Why fix order matters

Config issues affect build tooling — fix first. Enforcement prevents regression — add before
refactoring. Docs reflect all changes — update last.

## Categories

### Config Drift

Config files that don't match their documentation or each other.
**Fix:** Update config or docs (config is the behavioral source of truth).

### Missing Enforcement

Rules in docs that could be caught automatically.
**Fix:** Implement the check (analyzer, test, formatter/linter rule, git hook, CI gate).

### Code Quality

SOLID/DRY violations, missing abstractions, domain-model issues.
**Fix:** Refactor with TDD.

### Doc Drift

Documentation that doesn't match code reality.
**Fix:** Update docs to match code. Mark aspirational content as "planned".

## Priority: Config Drift → Missing Enforcement → Code Quality → Doc Drift

## Severity (use these consistently — never HIGH/MEDIUM/LOW)

| Severity | Definition |
|----------|-----------|
| `error` | Incorrect claim, broken reference, contradicts reality, will mislead |
| `warning` | Undocumented setting, inconsistency, stale content |
| `info` | Minor, cosmetic, or improvement opportunity |
