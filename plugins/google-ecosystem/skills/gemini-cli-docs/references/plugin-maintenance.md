# Plugin Maintenance

## Table of Contents

- [Overview](#overview)
- [Routine Maintenance Tasks](#routine-maintenance-tasks)
- [Index Health Checks](#index-health-checks)
- [Cache Management](#cache-management)
- [Log Rotation](#log-rotation)
- [Drift Detection Schedule](#drift-detection-schedule)

---

## Overview

The gemini-cli-docs skill requires periodic maintenance to ensure documentation remains current, indexes are healthy, and caches don't grow unbounded.

**Maintenance frequency recommendations:**

| Task | Frequency | Command |
|------|-----------|---------|
| Index refresh | After each scrape | `/google-ecosystem:refresh-docs` |
| Drift detection | Weekly | `python scripts/maintenance/detect_changes.py` |
| Log cleanup | Monthly | `python scripts/maintenance/cleanup_logs.py` |
| Cache clearing | As needed | `python scripts/maintenance/clear_cache.py` |
| Stale doc cleanup | Quarterly | `python scripts/maintenance/cleanup_stale.py` |

---

## Routine Maintenance Tasks

### Weekly Tasks

1. **Check for upstream documentation changes**

   ```bash
   python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/detect_changes.py \
       --check-hashes
   ```

2. **Review any 404 URLs**

   ```bash
   python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/detect_changes.py \
       --check-404s
   ```

### Monthly Tasks

1. **Clean up old logs**

   ```bash
   python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_logs.py \
       --days 30
   ```

2. **Audit search quality**

   ```bash
   python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/validation/run_search_audit.py
   python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/validation/analyze_search_audit.py
   ```

### Quarterly Tasks

1. **Full documentation refresh**

   ```bash
   /google-ecosystem:scrape-docs
   /google-ecosystem:refresh-docs
   ```

2. **Remove stale documentation**

   ```bash
   python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_stale.py \
       --dry-run
   # Review output, then:
   python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_stale.py
   ```

---

## Index Health Checks

### Verify Index Integrity

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/validation/quick_validate.py
```

**Healthy index indicators:**

- All entries have valid file paths
- No orphaned files (files without index entries)
- No missing files (index entries without files)
- Keywords present for all documents
- Tags assigned appropriately

### Rebuild Index from Scratch

If the index becomes corrupted:

```bash
# Clear the index
rm plugins/google-ecosystem/skills/gemini-cli-docs/canonical/index.yaml
rm plugins/google-ecosystem/skills/gemini-cli-docs/canonical/index.json

# Rebuild from files
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/management/manage_index.py refresh
```

---

## Cache Management

### View Cache Status

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/clear_cache.py --info
```

### Clear Inverted Index Cache

When search results seem stale or incorrect:

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/clear_cache.py --inverted
```

### Clear All Caches

For a complete reset:

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/clear_cache.py
```

---

## Log Rotation

### Log File Locations

```
logs/
  core/           # Scraping, discovery logs
  management/     # Index management logs
  maintenance/    # Cleanup, drift detection logs
  validation/     # Audit, validation logs
  diagnostics/    # JSON diagnostic files
```

### Cleanup Commands

**Keep last 30 days (default):**

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_logs.py
```

**Keep last 7 days:**

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_logs.py --days 7
```

**Keep only 5 diagnostic files per script:**

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_logs.py --keep-diagnostics 5
```

---

## Drift Detection Schedule

### Automated Drift Detection

Set up a scheduled task or cron job:

**Linux/macOS (crontab):**

```bash
# Weekly drift check (Sundays at 2 AM)
0 2 * * 0 cd /path/to/claude-code-plugins && python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/detect_changes.py --check-404s --check-hashes >> /var/log/gemini-docs-drift.log 2>&1
```

**Windows (Task Scheduler):**

Create a scheduled task that runs:

```powershell
python D:\repos\gh\melodic\claude-code-plugins\plugins\google-ecosystem\skills\gemini-cli-docs\scripts\maintenance\detect_changes.py --check-404s --check-hashes
```

### Manual Drift Review

After drift detection, review and clean:

```bash
# Preview what would be cleaned
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_drift.py --dry-run

# Clean confirmed drift
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/maintenance/cleanup_drift.py --clean-404s --clean-missing
```

---

## Troubleshooting Maintenance Issues

### Index Won't Refresh

1. Check file permissions on canonical/ directory
2. Verify YAML syntax in existing index.yaml
3. Try deleting index files and rebuilding

### Cache Won't Clear

1. Check for file locks (another process using cache)
2. Manually delete cache/ directory contents
3. Restart any long-running processes

### Drift Detection Fails

1. Check network connectivity to geminicli.com
2. Verify SSL certificates are valid
3. Check for rate limiting (wait and retry)

### Logs Growing Too Large

1. Run cleanup more frequently
2. Reduce diagnostic retention
3. Check for runaway logging (infinite loops)
