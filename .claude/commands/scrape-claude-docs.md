---
description: Run docs scraping in dev mode using local plugin code (not globally installed plugin)
allowed-tools: Read, Bash, Skill
---

# Scrape Docs (Dev Mode)

Run the full documentation scraping workflow using **local plugin code** instead of the globally installed plugin.

## Purpose

This command ensures:

1. **Dev mode environment variables** are set before any scripts run
2. **Local plugin code** at `plugins/claude-ecosystem/skills/docs-management/` is used
3. **All scraped docs go to local repo** (ready for plugin update push)
4. **Index refresh and validation** use local code and local data

## Dev Mode Environment Variable

```powershell
# PowerShell - resolve dynamically from repo root
$env:OFFICIAL_DOCS_DEV_ROOT = "$(git rev-parse --show-toplevel)/plugins/claude-ecosystem/skills/docs-management"
```

```bash
# Bash/Git Bash - resolve dynamically from repo root
export OFFICIAL_DOCS_DEV_ROOT="$(git rev-parse --show-toplevel)/plugins/claude-ecosystem/skills/docs-management"
```

This overrides the installed plugin path, redirecting all operations to the local development copy.

## Workflow

### Step 1: Set Dev Mode Environment Variable

Set the environment variable shown above before any script execution.

### Step 2: Scrape, Refresh, and Validate

Invoke the `docs-management` skill with this request:

```text
IMPORTANT: Dev mode is active. Verify [DEV MODE] appears in script output.

Please scrape all configured Claude documentation sources. Skip unchanged documents, then refresh the local index and metadata and validate.

Run ALL scripts in FOREGROUND so we can see progress and verify dev mode banners.

IMPORTANT: Use Python 3.13 for validation (py -3.13) due to spaCy compatibility. Python 3.14 works for scraping.
```

### Step 3: Verify Dev Mode

Check that `[DEV MODE]` appears in script output (not `[PROD MODE]`).

### Step 4: Git Status Check

Run `git status` to see what files changed in the local repo.

### Step 5: Content Diff Analysis

Analyze scraped content changes to detect potential issues from external source changes:

```bash
# Check for significant content changes in scraped docs
git diff --stat plugins/claude-ecosystem/skills/docs-management/canonical/

# Review specific changes for potential issues:
# - Broken formatting from upstream changes
# - Missing sections or content
# - New content that may need metadata updates
# - Encoding issues or unexpected characters
git diff plugins/claude-ecosystem/skills/docs-management/canonical/ | head -200
```

**What to look for:**

- **Large deletions**: May indicate upstream page restructuring or removal
- **Formatting changes**: Broken markdown, missing headers, malformed links
- **Encoding issues**: Unexpected characters, mojibake, or encoding artifacts
- **Metadata drift**: Changes that may require index.yaml updates
- **Script adjustments needed**: Patterns that suggest scraping logic needs updates

If issues are found, investigate the source URLs and determine if adjustments are needed to sources.json or scraping scripts.

### Step 6: Final Report

Summarize:

1. Scraping results (documents scraped, skipped, errors)
2. Validation results (index integrity, metadata coverage)
3. Content diff analysis findings (any issues detected)
4. Files ready for commit

## What NOT to Do

- Do NOT run scripts without setting `OFFICIAL_DOCS_DEV_ROOT` first
- Do NOT use the global `/claude-ecosystem:scrape-docs` command (uses installed plugin)
- Do NOT run validation with Python 3.14 (spaCy compatibility issues)
- Do NOT run scripts in background with polling loops

---

**Last Updated:** 2025-12-03
