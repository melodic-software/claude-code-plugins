# Change Detection Guide

## Table of Contents

- [Overview](#overview)
- [Detection Methods](#detection-methods)
- [Running Detection](#running-detection)
- [Interpreting Results](#interpreting-results)
- [Cleanup Workflows](#cleanup-workflows)
- [Automation](#automation)
- [Best Practices](#best-practices)

---

## Overview

Change detection (drift detection) identifies documentation that has become stale:

- **404 URLs** - Source pages that no longer exist
- **Missing files** - Index entries without corresponding files
- **Content changes** - Documents modified at source (hash mismatch)
- **Orphaned files** - Files without index entries

Regular drift detection ensures the documentation cache remains accurate and current.

---

## Detection Methods

### 404 URL Detection

Checks if source URLs still resolve:

```python
from gemini_docs_api import detect_drift

result = detect_drift(check_404s=True)
print(f"404 URLs found: {result['url_404_count']}")
for url in result['url_404s']:
    print(f"  - {url}")
```

**How it works:**

1. Read all URLs from index.yaml
2. Send HEAD request to each URL
3. Record URLs returning 404/410 status codes
4. Report results

### Missing File Detection

Checks if files referenced in index exist:

```python
result = detect_drift()
print(f"Missing files: {result['missing_files_count']}")
for path in result['missing_files']:
    print(f"  - {path}")
```

**How it works:**

1. Read all file paths from index.yaml
2. Check if each path exists on disk
3. Report missing files

### Hash-Based Change Detection

Detects content changes by comparing hashes:

```python
result = detect_drift(check_hashes=True)
print(f"Hash mismatches: {result['hash_mismatch_count']}")
for doc in result['hash_mismatches']:
    print(f"  - {doc['doc_id']}: stored={doc['stored_hash'][:8]}... current={doc['current_hash'][:8]}...")
```

**How it works:**

1. Re-fetch content from source URL
2. Compute SHA-256 hash of content
3. Compare with stored `content_hash` in index
4. Report mismatches

### Orphaned File Detection

Finds files without index entries:

```python
result = detect_drift()
print(f"Orphaned files: {result['orphaned_files_count']}")
for path in result['orphaned_files']:
    print(f"  - {path}")
```

---

## Running Detection

### Using the Script

**Full detection (all checks):**

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/detect_changes.py \
    --check-404s \
    --check-hashes
```

**Quick detection (no network):**

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/detect_changes.py
```

**Parallel detection (faster):**

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/detect_changes.py \
    --check-404s \
    --max-workers 20
```

### Using the API

```python
from gemini_docs_api import detect_drift

# Full detection
result = detect_drift(
    check_404s=True,
    check_hashes=True,
    max_workers=10
)

print(f"Detection completed:")
print(f"  - 404 URLs: {result['url_404_count']}")
print(f"  - Missing files: {result['missing_files_count']}")
print(f"  - Hash mismatches: {result['hash_mismatch_count']}")
print(f"  - Orphaned files: {result['orphaned_files_count']}")
```

---

## Interpreting Results

### Result Structure

```python
{
    "url_404_count": 3,
    "url_404s": [
        "https://geminicli.com/docs/removed-page",
        "https://geminicli.com/docs/old-feature"
    ],
    "missing_files_count": 1,
    "missing_files": [
        "canonical/geminicli-com/docs/missing.md"
    ],
    "hash_mismatch_count": 5,
    "hash_mismatches": [
        {
            "doc_id": "geminicli-com-docs-commands",
            "url": "https://geminicli.com/docs/commands",
            "stored_hash": "sha256:abc123...",
            "current_hash": "sha256:def456..."
        }
    ],
    "orphaned_files_count": 2,
    "orphaned_files": [
        "canonical/geminicli-com/docs/orphan1.md",
        "canonical/geminicli-com/docs/orphan2.md"
    ]
}
```

### Severity Levels

| Finding | Severity | Action |
|---------|----------|--------|
| 404 URLs | High | Remove from index, delete local file |
| Missing files | Medium | Remove from index or re-scrape |
| Hash mismatches | Low | Re-scrape to update content |
| Orphaned files | Low | Delete files or add to index |

---

## Cleanup Workflows

### Preview Cleanup

Always preview before actual cleanup:

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_drift.py \
    --dry-run
```

### Clean 404 URLs

Remove index entries for URLs that no longer exist:

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_drift.py \
    --clean-404s
```

### Clean Missing Files

Remove index entries for files that don't exist:

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_drift.py \
    --clean-missing
```

### Full Cleanup

Clean all drift issues:

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_drift.py \
    --clean-404s \
    --clean-missing
```

### Using the API

```python
from gemini_docs_api import cleanup_drift

# Preview cleanup
result = cleanup_drift(
    clean_404s=True,
    clean_missing_files=True,
    dry_run=True
)
print(f"Would remove {result['index_entries_removed']} entries")
print(f"Would delete {result['files_deleted']} files")

# Actual cleanup
result = cleanup_drift(
    clean_404s=True,
    clean_missing_files=True,
    dry_run=False
)
print(f"Removed {result['index_entries_removed']} entries")
print(f"Deleted {result['files_deleted']} files")
```

---

## Automation

### Scheduled Detection

**Linux/macOS (crontab):**

```bash
# Weekly drift check (Sundays at 2 AM)
0 2 * * 0 cd /path/to/repo && python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/detect_changes.py --check-404s --check-hashes >> /var/log/gemini-drift.log 2>&1
```

**Windows (Task Scheduler):**

Create scheduled task running:

```powershell
python D:\repos\plugins\google-ecosystem\skills\gemini-cli-docs\scripts\maintenance\detect_changes.py --check-404s --check-hashes
```

### CI/CD Integration

**GitHub Actions example:**

```yaml
name: Documentation Drift Check

on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly

jobs:
  drift-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.13'

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Run drift detection
        run: |
          python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/detect_changes.py \
            --check-404s \
            --check-hashes

      - name: Create issue if drift found
        if: failure()
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: 'Documentation drift detected',
              body: 'Weekly drift check found issues. Please review.'
            })
```

---

## Best Practices

### Detection Frequency

| Environment | 404 Check | Hash Check |
|-------------|-----------|------------|
| Development | On-demand | On-demand |
| Production | Weekly | Monthly |
| After scrape | Always | N/A |

### Handling Temporary 404s

Some 404s may be temporary (server issues). Before cleanup:

1. Wait 24-48 hours
2. Re-run detection
3. Only clean persistent 404s

### Hash Change Decisions

When content hash changes:

1. **Minor changes** - Re-scrape to update
2. **Major restructure** - May need index update
3. **Page removed** - Treat as 404

### Post-Cleanup Actions

After cleanup, always:

1. Refresh index: `python scripts/management/manage_index.py refresh`
2. Validate: `python scripts/validation/quick_validate.py`
3. Commit changes if in version control
