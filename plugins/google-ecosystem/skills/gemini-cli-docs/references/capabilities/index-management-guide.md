# Index Management Guide

## Table of Contents

- [Overview](#overview)
- [Index Structure](#index-structure)
- [Index Operations](#index-operations)
- [Refresh Workflow](#refresh-workflow)
- [Keyword Extraction](#keyword-extraction)
- [Index Validation](#index-validation)
- [Troubleshooting](#troubleshooting)

---

## Overview

The index is the central metadata store for all documentation. It enables:

- **Fast lookups** - O(1) access by doc_id
- **Search** - Keyword and tag-based discovery
- **Drift detection** - Track content changes via hashes
- **Metadata storage** - Titles, URLs, timestamps

---

## Index Structure

### Primary Index (index.yaml)

Human-readable YAML format:

```yaml
geminicli-com-docs-installation:
  url: https://geminicli.com/docs/installation
  title: "Installation"
  description: "Getting started with Gemini CLI installation"
  path: geminicli-com/docs/installation.md
  domain: geminicli.com
  category: docs
  keywords:
    - installation
    - setup
    - getting started
    - requirements
  tags:
    - getting-started
    - cli
  content_hash: sha256:abc123def456...
  last_fetched: 2025-01-15T10:30:00Z

geminicli-com-docs-commands:
  url: https://geminicli.com/docs/commands
  title: "Commands"
  # ... more entries
```

### JSON Mirror (index.json)

Machine-readable JSON for programmatic access:

```json
{
  "geminicli-com-docs-installation": {
    "url": "https://geminicli.com/docs/installation",
    "title": "Installation",
    "path": "geminicli-com/docs/installation.md",
    "keywords": ["installation", "setup"],
    "tags": ["getting-started"],
    "content_hash": "sha256:abc123...",
    "last_fetched": "2025-01-15T10:30:00Z"
  }
}
```

### doc_id Generation

doc_id is derived from URL:

```
https://geminicli.com/docs/installation
            ↓
geminicli-com-docs-installation
```

**Rules:**

1. Remove protocol (`https://`)
2. Replace `.` with `-`
3. Replace `/` with `-`
4. Lowercase all characters
5. Remove trailing `-`

---

## Index Operations

### List Entries

```bash
# List all entries
python scripts/management/manage_index.py list

# Limit results
python scripts/management/manage_index.py list --limit 10

# Filter by domain
python scripts/management/manage_index.py list --domain geminicli.com
```

### Add Entry

Entries are typically added via scraping, but manual addition:

```bash
python scripts/management/manage_index.py add \
    --doc-id "geminicli-com-docs-new-feature" \
    --url "https://geminicli.com/docs/new-feature" \
    --title "New Feature" \
    --path "geminicli-com/docs/new-feature.md"
```

### Remove Entry

```bash
python scripts/management/manage_index.py remove \
    --doc-id "geminicli-com-docs-removed-page"
```

### Update Entry

```bash
python scripts/management/manage_index.py update \
    --doc-id "geminicli-com-docs-commands" \
    --title "CLI Commands Reference"
```

---

## Refresh Workflow

### Using the Slash Command

```bash
/google-ecosystem:refresh-docs
```

### Using the Script

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/management/manage_index.py refresh
```

### Using the API

```python
from gemini_docs_api import refresh_index

result = refresh_index(
    check_drift=True,     # Run drift detection after refresh
    cleanup_drift=False,  # Don't auto-cleanup
    max_workers=5         # Parallel workers
)

print(f"Refreshed: {result['docs_processed']} documents")
print(f"Keywords extracted: {result['keywords_extracted']}")
```

### What Refresh Does

1. **Scan canonical/** - Find all markdown files
2. **Parse frontmatter** - Extract existing metadata
3. **Extract keywords** - Use spaCy NLP (if available)
4. **Detect tags** - Apply tag detection rules
5. **Compute hashes** - SHA-256 of content
6. **Update index.yaml** - Write consolidated index
7. **Sync index.json** - Update JSON mirror
8. **Build inverted index** - Keyword to doc_id mapping

---

## Keyword Extraction

### Automatic Extraction

Keywords are extracted using spaCy NLP:

```python
# Noun chunks (multi-word phrases)
"session management" -> keyword
"model routing"      -> keyword

# Named entities
"Gemini CLI"         -> keyword
"Google Cloud"       -> keyword
```

### Manual Override

Add keywords in document frontmatter:

```yaml
---
title: "Checkpointing"
keywords:
  - checkpointing
  - session save
  - restore state
  - persistence
---
```

Manual keywords are merged with auto-extracted keywords.

### Keyword Configuration

In `config/defaults.yaml`:

```yaml
index:
  extract_keywords: true
  max_keywords: 20
```

### Keyword Quality

Good keywords are:

- **Specific** - "checkpointing" not "feature"
- **Searchable** - Terms users would search for
- **Accurate** - Actually relevant to content
- **Concise** - 1-3 words typically

---

## Index Validation

### Quick Validation

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/validation/quick_validate.py
```

**Checks:**

- All index entries have valid file paths
- No orphaned files (files without entries)
- Required fields present (url, title, path)

### Full Validation

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/validation/validate_scraped_docs.py
```

**Additional checks:**

- Frontmatter parsing valid
- Content hash matches
- URLs are well-formed
- Timestamps are valid ISO 8601

### Validate Tag Configuration

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/validation/audit_tag_config.py
```

---

## Troubleshooting

### Index Not Found

**Symptom:** "index.yaml not found" errors

**Solutions:**

1. Check path: `ls plugins/google-ecosystem/skills/gemini-cli-docs/canonical/`
2. Run refresh: `/google-ecosystem:refresh-docs`
3. Check working directory

### Duplicate doc_ids

**Symptom:** Warning about duplicate entries

**Solutions:**

1. Check for duplicate files in canonical/
2. Remove duplicates manually
3. Re-run refresh

### Missing Keywords

**Symptom:** Documents have no keywords

**Solutions:**

1. Check spaCy installed: `python -c "import spacy"`
2. Install model: `python -m spacy download en_core_web_sm`
3. Re-run refresh with `--extract-keywords`

### Index Corruption

**Symptom:** YAML parse errors, malformed entries

**Solutions:**

1. Delete corrupted index:

   ```bash
   rm canonical/index.yaml
   rm canonical/index.json
   ```

2. Rebuild from files:

   ```bash
   python scripts/management/manage_index.py refresh
   ```

### JSON/YAML Mismatch

**Symptom:** index.json doesn't match index.yaml

**Solutions:**

1. Refresh regenerates both from source files
2. Delete both and re-run refresh
3. Check for file locking issues

### Slow Index Operations

**Symptom:** Refresh/list operations slow

**Solutions:**

1. Check for very large index (>10k entries)
2. Use pagination for list operations
3. Consider index splitting by domain

---

## Best Practices

### Regular Maintenance

```bash
# Weekly refresh
python scripts/management/manage_index.py refresh

# Monthly validation
python scripts/validation/validate_scraped_docs.py
```

### Before Commits

```bash
# Validate index health
python scripts/validation/quick_validate.py

# Check for drift
python scripts/maintenance/detect_changes.py
```

### After Scraping

```bash
# Always refresh after scraping
python scripts/core/scrape_docs.py --llms-txt https://geminicli.com/llms.txt
python scripts/management/manage_index.py refresh
```
