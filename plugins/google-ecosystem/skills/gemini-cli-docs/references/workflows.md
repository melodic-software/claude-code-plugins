# Workflows

## Table of Contents

- [Scraping Gemini CLI Documentation](#scraping-gemini-cli-documentation)
- [Refreshing the Index](#refreshing-the-index)
- [Detecting and Cleaning Drift](#detecting-and-cleaning-drift)
- [Adding Documentation Categories](#adding-documentation-categories)

---

## Scraping Gemini CLI Documentation

**Scenario:** Scrape or update Gemini CLI documentation from geminicli.com.

### Using the Slash Command

```bash
/google-ecosystem:scrape-docs
```

### Using the Script Directly

**Linux/macOS:**

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/core/scrape_docs.py \
    --llms-txt https://geminicli.com/llms.txt
```

**Windows (PowerShell):**

```powershell
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/core/scrape_docs.py `
    --llms-txt https://geminicli.com/llms.txt
```

### Validation After Scraping

Always validate after scraping:

```bash
# Check file count
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/validation/quick_validate.py \
    --output geminicli-com

# Run comprehensive validation
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/validation/validate_scraped_docs.py
```

---

## Refreshing the Index

**Scenario:** Rebuild the index after scraping or when metadata needs updating.

### Using the Slash Command

```bash
/google-ecosystem:refresh-docs
```

### Using the Script Directly

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/management/manage_index.py refresh
```

### What Refresh Does

1. **Scans canonical/** - Finds all markdown files
2. **Extracts metadata** - Parses frontmatter
3. **Generates keywords** - Uses spaCy NLP (if available)
4. **Updates index.yaml** - Writes consolidated index
5. **Syncs index.json** - Creates JSON mirror

### Using the Public API

```python
from gemini_docs_api import refresh_index

result = refresh_index(check_drift=True)
if result['success']:
    print(f"Refreshed successfully: {result['steps_completed']}")
else:
    print(f"Errors: {result['errors']}")
```

---

## Detecting and Cleaning Drift

**Scenario:** Documentation may become stale when source URLs change or content is removed.

### Detecting Drift

**Using the Script:**

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/detect_changes.py \
    --check-404s \
    --check-hashes
```

**Using the Public API:**

```python
from gemini_docs_api import detect_drift

drift = detect_drift(check_404s=True, check_hashes=True)
print(f"404 URLs: {drift['url_404_count']}")
print(f"Missing files: {drift['missing_files_count']}")
print(f"Hash mismatches: {drift['hash_mismatch_count']}")
```

### Cleaning Drift

**Dry Run (Preview):**

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_drift.py \
    --dry-run
```

**Actual Cleanup:**

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_drift.py \
    --clean-404s \
    --clean-missing
```

**Using the Public API:**

```python
from gemini_docs_api import cleanup_drift

# Preview what would be cleaned
result = cleanup_drift(clean_404s=True, clean_missing_files=True, dry_run=True)
print(f"Would remove {result['index_entries_removed']} entries")

# Actually clean (with dry_run=False)
result = cleanup_drift(clean_404s=True, clean_missing_files=True, dry_run=False)
```

---

## Adding Documentation Categories

**Scenario:** Gemini CLI adds a new documentation section.

### Step 1: Discover New URLs

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/discover_categories.py \
    --llms-txt https://geminicli.com/llms.txt
```

### Step 2: Update Sources Configuration

Edit `references/sources.json` to add the new source:

```json
{
  "name": "Gemini CLI New Section",
  "url": "https://geminicli.com/llms.txt",
  "type": "llms-txt",
  "filter": "/new-section/",
  "output": "geminicli-com/new-section"
}
```

### Step 3: Scrape the New Section

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/core/scrape_docs.py \
    --llms-txt https://geminicli.com/llms.txt \
    --filter "/new-section/"
```

### Step 4: Refresh Index

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/management/manage_index.py refresh
```

### Step 5: Validate

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/validation/quick_validate.py \
    --output geminicli-com/new-section
```

---

## Development Mode Workflow

**Scenario:** Testing changes to the skill before committing.

### Enable Development Mode

Set the environment variable to use local plugin code:

```bash
# Linux/macOS
export GEMINI_DOCS_DEV_ROOT=/path/to/claude-code-plugins

# Windows PowerShell
$env:GEMINI_DOCS_DEV_ROOT = "D:\repos\gh\melodic\claude-code-plugins"
```

### Run Scripts in Dev Mode

```bash
# Scrape using local code
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/core/scrape_docs.py \
    --llms-txt https://geminicli.com/llms.txt
```

### Verify Dev Mode Active

Scripts will show dev mode indicator in output:

```
[DEV MODE] Using local plugin: D:\repos\gh\melodic\claude-code-plugins
```

---

## Cache Management Workflow

**Scenario:** Clear caches to force fresh data.

### View Cache Status

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/clear_cache.py --info
```

### Clear All Caches

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/clear_cache.py
```

### Clear Specific Cache

```bash
# Clear only inverted index cache
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/clear_cache.py --inverted

# Clear only LLMS/scraper cache
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/clear_cache.py --llms
```

---

## Log Maintenance Workflow

**Scenario:** Clean up old log files to prevent unbounded growth.

### Preview Cleanup

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_logs.py \
    --dry-run
```

### Execute Cleanup

```bash
# Delete logs older than 30 days (default)
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_logs.py

# Delete logs older than 7 days
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_logs.py --days 7

# Keep only 5 latest diagnostics per script
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_logs.py --keep-diagnostics 5
```
