# Troubleshooting

## Scraping fails for specific URL

**Symptom:** `scrape_docs.py` errors on specific URL

**Solutions:**

1. Check if URL is accessible (try in browser)
2. Check if content format changed (HTML structure)
3. Check rate limiting (wait and retry)
4. Manual fallback (copy content, add frontmatter manually)

## Section not found during extraction

**Symptom:** `get_document_section()` can't find section

**Solutions:**

1. List available headings (use `get_document_content()` to see structure)
2. Check for typos in section title
3. Check if upstream renamed the section
4. Update index.yaml with new section title

## Windows-Specific Issues

### Unicode Encoding Errors (FIXED)

**Symptom:** `UnicodeEncodeError: 'charmap' codec can't encode character` when running scripts

**Status:** FIXED - Scripts now auto-detect Windows and configure UTF-8 encoding

**Current behavior:** Scripts work without environment variables on Windows.

### Git Bash Path Conversion

**Symptom:** Filter patterns converted to Windows paths (e.g., `/docs/` becomes `C:/Program Files/Git/docs/`)

**Status:** AUTO-FIXED - Scripts now automatically detect and correct Git Bash path conversion

**Current behavior:**

- `scrape_docs.py` automatically detects Git Bash path conversion and restores the original pattern
- Scripts work correctly from Git Bash without manual workarounds

**Manual workaround (if needed):** Use `MSYS_NO_PATHCONV=1` environment variable with Git Bash:

```bash
MSYS_NO_PATHCONV=1 python scripts/core/scrape_docs.py \
    --llms-txt https://geminicli.com/llms.txt \
    --filter "/docs/"
```

**Alternative:** Use PowerShell or CMD instead of Git Bash (no path conversion issues).

### Expected 404 Errors

**Symptom:** Some URLs return 404 during scraping

**Status:** EXPECTED - Scripts handle gracefully

**Explanation:**

- llms.txt may reference docs that don't exist yet
- Upstream docs may be moved/removed
- Scripts log error and continue processing remaining URLs

**Action:** None required - this is normal behavior.

## Index Issues

### Index Not Found

**Symptom:** Scripts report "index.yaml not found"

**Solutions:**

1. Run refresh to rebuild: `/google-ecosystem:refresh-docs`
2. Check base directory path is correct
3. Verify canonical/ directory exists

### Stale Index After Scraping

**Symptom:** New documents not appearing in search results

**Solutions:**

1. Always refresh index after scraping
2. Run: `python scripts/management/manage_index.py refresh`
3. Clear inverted index cache: `python scripts/maintenance/clear_cache.py --inverted`

### Keywords Not Extracted

**Symptom:** Documents missing keywords

**Solutions:**

1. Check spaCy is installed: `python -c "import spacy"`
2. Install English model: `python -m spacy download en_core_web_sm`
3. Run keyword extraction: `python scripts/management/manage_index.py extract-keywords`

## Search Issues

### No Results for Valid Query

**Symptom:** Search returns empty results for terms that should match

**Solutions:**

1. Check index contains documents: `python scripts/management/manage_index.py list --limit 5`
2. Check keywords in index: Look at `canonical/index.yaml`
3. Rebuild inverted index: Clear cache and refresh

### Poor Relevance

**Symptom:** Top results not relevant to query

**Solutions:**

1. Run search audit: `python scripts/validation/run_search_audit.py`
2. Check tag configuration: `python scripts/validation/audit_tag_config.py`
3. Update keywords for relevant documents

## Performance Issues

### Slow Scraping

**Symptom:** Scraping takes too long

**Solutions:**

1. Rate limiting is intentional (1.5s between requests)
2. Use `--skip-existing` to only fetch new/changed docs
3. Check network connectivity

### Slow Search

**Symptom:** Search queries take too long

**Solutions:**

1. Check inverted index cache exists
2. Clear and rebuild cache
3. Reduce index size by removing stale docs

## Development Mode Issues

### Dev Mode Not Active

**Symptom:** Scripts use installed plugin instead of local code

**Solutions:**

1. Check environment variable: `echo $GEMINI_DOCS_DEV_ROOT`
2. Set correctly: `export GEMINI_DOCS_DEV_ROOT=/path/to/plugins`
3. Verify path exists and contains the plugin

### Import Errors in Dev Mode

**Symptom:** `ImportError` or `ModuleNotFoundError` when running scripts

**Solutions:**

1. Check PYTHONPATH includes scripts directory
2. Run from skill root directory
3. Use bootstrap import pattern

## Cache Issues

### Stale Cache Data

**Symptom:** Results don't reflect recent changes

**Solutions:**

1. View cache status: `python scripts/maintenance/clear_cache.py --info`
2. Clear all caches: `python scripts/maintenance/clear_cache.py`
3. Refresh index after clearing

### Cache Files Corrupted

**Symptom:** Errors when loading cache

**Solutions:**

1. Delete cache files manually: `rm -rf cache/*`
2. Clear via script: `python scripts/maintenance/clear_cache.py`
3. Rebuild inverted index on next search

## Logging Issues

### Log Directory Full

**Symptom:** Disk space warnings, many log files

**Solutions:**

1. Run log cleanup: `python scripts/maintenance/cleanup_logs.py`
2. Reduce retention: `--days 7` (keep only 7 days)
3. Reduce diagnostics: `--keep-diagnostics 5` (keep 5 per script)

### Missing Logs for Debugging

**Symptom:** Need logs but they were cleaned up

**Solutions:**

1. Increase retention before running scripts
2. Check diagnostics folder for JSON files
3. Enable verbose mode on scripts: `--verbose`
