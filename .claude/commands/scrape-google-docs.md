---
description: Run Gemini CLI docs scraping in dev mode using local plugin code (not globally installed plugin)
allowed-tools: Read, Bash, Skill
---

# Scrape Google Docs (Dev Mode)

Run the full Gemini CLI documentation scraping workflow using **local plugin code** instead of the globally installed plugin.

## Purpose

This command ensures:

1. **Dev mode environment variables** are set before any scripts run
2. **Local plugin code** at `plugins/google-ecosystem/skills/gemini-cli-docs/` is used
3. **All scraped docs go to local repo** (ready for plugin update push)
4. **Index refresh and validation** use local code and local data

## Dev Mode Environment Variable

**CRITICAL:** Environment variables set mid-session do NOT persist across Claude's Bash tool calls. Each Bash command runs in a fresh shell. You must set the env var in the SAME command that runs the script.

**IMPORTANT:** Claude's Bash tool uses **Git Bash (MINGW64)** on Windows, not PowerShell. Use Bash inline prefix syntax for all commands executed by Claude Code.

**Bash syntax (use this in Claude Code):**

```bash
GEMINI_DOCS_DEV_ROOT="<repo-root>/plugins/google-ecosystem/skills/gemini-cli-docs" python <script-path>
```

**PowerShell syntax (for native PowerShell terminal only):**

```powershell
$env:GEMINI_DOCS_DEV_ROOT = "<repo-root>/plugins/google-ecosystem/skills/gemini-cli-docs"; python <script-path>
```

This overrides the installed plugin path, redirecting all operations to the local development copy.

## Workflow

### Step 1: Run Scraping with Dev Mode Env Var

Run the scraping script with the environment variable set inline:

```bash
GEMINI_DOCS_DEV_ROOT="<repo-root>/plugins/google-ecosystem/skills/gemini-cli-docs" python <repo-root>/plugins/google-ecosystem/skills/gemini-cli-docs/scripts/core/scrape_all_sources.py --parallel --skip-existing
```

**STOP AND VERIFY:** Check the first lines of output for `[DEV MODE]`. If you see `[PROD MODE]`, the environment variable was not set correctly. Do NOT proceed - troubleshoot the env var first.

### Step 2: Run Index Refresh with Python 3.13

Run the refresh script (use Python 3.13 for spaCy compatibility):

```bash
GEMINI_DOCS_DEV_ROOT="<repo-root>/plugins/google-ecosystem/skills/gemini-cli-docs" py -3.13 <repo-root>/plugins/google-ecosystem/skills/gemini-cli-docs/scripts/management/refresh_index.py
```

**STOP AND VERIFY:** Check for `[DEV MODE]` in output. If `[PROD MODE]` appears, stop and troubleshoot.

### Step 3: Git Status Check

Run `git status` to see what files changed in the local repo.

### Step 4: Content Diff Analysis

Analyze scraped content changes to detect potential issues from external source changes:

```bash
# Check for significant content changes in scraped docs
git diff --stat plugins/google-ecosystem/skills/gemini-cli-docs/canonical/

# Review specific changes for potential issues:
# - Broken formatting from upstream changes
# - Missing sections or content
# - New content that may need metadata updates
# - Encoding issues or unexpected characters
git diff plugins/google-ecosystem/skills/gemini-cli-docs/canonical/ | head -200
```

**What to look for:**

- **Large deletions**: May indicate upstream page restructuring or removal
- **Formatting changes**: Broken markdown, missing headers, malformed links
- **Encoding issues**: Unexpected characters, mojibake, or encoding artifacts
- **Metadata drift**: Changes that may require index.yaml updates
- **Script adjustments needed**: Patterns that suggest scraping logic needs updates

If issues are found, investigate the source URLs and determine if adjustments are needed to sources.json or scraping scripts.

### Step 5: Filter Effectiveness Analysis

After reviewing the git diff, perform a **structural analysis** to detect potential filtering gaps.

**Analysis Steps:**

1. **Source Analysis**: Since gemini-cli-docs uses a single source (geminicli.com llms.txt), check if:
   - All expected pages are being scraped (~73 expected)
   - Any pages are consistently causing issues
   - Content structure has changed requiring filter updates

2. **Change Location Analysis**: For each modified file:
   - Check if changes are only in the last 20% of the file (likely footer/related sections)
   - Check if the diff shows only frontmatter (`content_hash`) changes with <10 content lines changed

   **Red flag:** Multiple files with changes concentrated at the end = likely footer sections not being filtered.

3. **Cross-Reference with Scraper Logs**: During scraping, check for logged messages about:
   - Skipped URLs
   - Parse errors
   - Filter operations

**Potential Improvements Output:**

If issues are detected, include a "Potential Improvements" section with actionable suggestions:

- "Consider adding filtering rules for section X in `filtering.yaml`"
- "Source structure may have changed - review llms.txt parsing"
- "N files have footer-only changes - review filtering rules"

**Reference:** Filter configuration is in `plugins/google-ecosystem/skills/gemini-cli-docs/config/filtering.yaml`

### Step 6: Final Report

Summarize:

1. Scraping results (documents scraped, skipped, errors)
2. Validation results (index integrity, metadata coverage)
3. Content diff analysis findings (any issues detected)
4. Filter effectiveness analysis (any potential improvements identified)
5. Files ready for commit

## What NOT to Do

- Do NOT run scripts without the inline `GEMINI_DOCS_DEV_ROOT="..."` prefix
- Do NOT use PowerShell syntax (`$env:...`) in Claude Code - use Bash inline prefix instead
- Do NOT assume env vars persist between Bash tool calls (they do not)
- Do NOT use the global `/google-ecosystem:scrape-docs` command (uses installed plugin)
- Do NOT run refresh with Python 3.14 (spaCy compatibility issues)
- Do NOT run scripts in background with polling loops
- Do NOT proceed if `[PROD MODE]` appears - stop and fix the env var

---

**Last Updated:** 2025-12-05
