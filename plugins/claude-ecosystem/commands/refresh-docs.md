---
description: Refresh Claude docs index and validate metadata without network scraping.
allowed-tools: Bash, Skill
---

# Refresh Command

Refresh the local Claude documentation index without network scraping.

## Purpose

Use this command when you want to:

- Rebuild index from filesystem
- Extract keywords and metadata
- Validate metadata coverage
- Generate summary report

For full scraping + refresh, use `/claude-ecosystem:scrape-docs` instead.

## Instructions

Invoke the `docs-management` skill to refresh the local documentation index.

Request index rebuild and metadata validation from the skill.

**Note:** Use Python 3.12 for this command due to spaCy compatibility:

```text
Please refresh the local documentation index and validate metadata. Use Python 3.12 (py -3.12) for spaCy compatibility.
```
