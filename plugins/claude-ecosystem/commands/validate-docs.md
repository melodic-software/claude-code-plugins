---
description: Validate Claude docs index integrity and detect drift without making changes.
allowed-tools: Bash, Skill
---

# Validate Command

Validate the Claude documentation index integrity and detect drift.

## Purpose

This is read-only validation - no changes made.

## Checks Performed

- Index integrity (file existence)
- Drift detection (404s, hash mismatches)
- Metadata coverage
- Missing files

## Instructions

Invoke the `docs-management` skill to validate the documentation index.

Request validation report including any detected issues or drift.
