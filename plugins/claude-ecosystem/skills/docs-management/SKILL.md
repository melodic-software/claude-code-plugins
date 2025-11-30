---
name: docs-management
description: Single source of truth and librarian for ALL Claude official documentation. Manages local documentation storage, scraping, discovery, and resolution. Use when finding, locating, searching, or resolving Claude documentation; discovering docs by keywords, category, tags, or natural language queries; scraping from sitemaps or docs maps; managing index metadata (keywords, tags, aliases); or rebuilding index from filesystem. Run scripts to scrape, find, and resolve documentation. Handles doc_id resolution, keyword search, natural language queries, category/tag filtering, alias resolution, sitemap.xml parsing, docs map processing, markdown subsection extraction for internal use, hash-based drift detection, and comprehensive index maintenance.
---

# Claude Docs Management

## 🚨 CRITICAL: Path Doubling Prevention - MANDATORY

**ABSOLUTE PROHIBITION: NEVER use `cd` with `&&` in PowerShell when running scripts from this skill.**

**The Problem:** If your current working directory is already inside the skill directory, using relative paths causes PowerShell to resolve paths relative to the current directory instead of the repository root, resulting in path doubling.

**REQUIRED Solutions (choose one):**

1. **✅ ALWAYS use helper scripts** (recommended - they handle path resolution automatically)
2. **✅ Use absolute path resolution** (if not using helper script)
3. **✅ Use separate commands** (never `cd` with `&&`)

**NEVER DO THIS:**

- ❌ Chain `cd` with `&&`: `cd <relative-path> && python <script>` causes path doubling
- ❌ Assume current directory
- ❌ Use relative paths when current dir is inside skill directory

**For all scripts:** Always run from repository root using relative paths, OR use helper scripts that handle path resolution automatically.

## 🚨 CRITICAL: Large File Handling - MANDATORY SCRIPT USAGE

### ⚠️ ABSOLUTE PROHIBITION: NEVER use read_file tool on the index.yaml file

The file exceeds 25,000 tokens and will ALWAYS fail. You MUST use scripts.

**✅ REQUIRED: ALWAYS use manage_index.py scripts for ANY index.yaml access:**

```bash
python scripts/management/manage_index.py count
python scripts/management/manage_index.py list
python scripts/management/manage_index.py get <doc_id>
python scripts/management/manage_index.py verify
```

All scripts automatically handle large files via `index_manager.py`.

## Available Slash Commands

This skill provides three slash commands for common workflows:

- **`/claude-ecosystem:scrape-docs`** - Scrape all configured Claude documentation sources, then refresh index and validate
- **`/claude-ecosystem:refresh-docs`** - Refresh the local index and metadata without scraping from remote sources
- **`/claude-ecosystem:validate-docs`** - Validate the index and references for consistency and drift without scraping

## Overview

This skill provides automation tooling for documentation management. It manages:

- **Canonical storage** (encapsulated in skill) - Single source of truth for official docs
- **Subsection extraction** - Token-optimized extracts for skills (60-90% savings)
- **Drift detection** - Hash-based validation against upstream sources
- **Sync workflows** - Quarterly maintenance automation
- **Documentation discovery** - Keyword-based search and doc_id resolution
- **Index management** - Metadata, keywords, tags, aliases for resilient references

**Core value:** Prevents link rot, enables offline access, optimizes token costs, automates maintenance, and provides resilient doc_id-based references.

## When to Use This Skill

This skill should be used when:

- **Scraping documentation** - Fetching docs from sitemaps or docs maps
- **Finding documentation** - Searching for docs by keywords, category, or natural language
- **Resolving doc references** - Converting doc_id to file paths
- **Managing index metadata** - Adding keywords, tags, aliases, updating metadata
- **Rebuilding index** - Regenerating index from filesystem (handles renames/moves)

## Workflow Execution Pattern

**CRITICAL: This section defines HOW to execute operations in this skill.**

### Delegation Strategy

#### Default approach: Delegate to Task agent

For ALL scraping, validation, and index operations, delegate execution to a general-purpose Task agent.

**How to invoke:**

Use the Task tool with:

- `subagent_type`: "general-purpose"
- `description`: Short 3-5 word description
- `prompt`: Full task description with execution instructions

### Execution Pattern

**Scripts run in FOREGROUND by default. Do NOT background them.**

When Task agents execute scripts:

- ✅ **Run directly**: `python .claude/skills/docs-management/scripts/core/scrape_all_sources.py --parallel --skip-existing`
- ✅ **Streaming logs**: Scripts emit progress naturally via stdout
- ✅ **Wait for completion**: Scripts exit when done with exit code
- ❌ **NEVER use `run_in_background=true`**: Scripts are designed for foreground execution
- ❌ **NEVER poll output**: Streaming logs appear automatically, no BashOutput polling needed
- ❌ **NEVER use background jobs**: No `&`, no `nohup`, no background process management

### Anti-Pattern Detection

**Red flags indicating incorrect execution:**

🚩 Using `run_in_background=true` in Bash tool
🚩 Repeated BashOutput calls in a loop
🚩 Checking process status with `ps` or `pgrep`
🚩 Manual polling of script output
🚩 Background job management (`&`, `nohup`, `jobs`)
🚩 **Using BashOutput AFTER Task agent completes** ← CRITICAL RED FLAG

**If you recognize these patterns, STOP and correct immediately.**

### After Task Agent Completes

**CRITICAL: When the Task agent reports "Done", READ its report and summarize to the user. DO NOT use BashOutput.**

**Correct workflow:**

1. Task agent reports "Done (X tool uses · Y tokens · Z time)"
2. ✅ READ the agent's message containing its final report
3. ✅ SUMMARIZE the agent's findings to the user
4. ❌ NEVER use BashOutput to "check the real results"
5. ❌ NEVER poll or verify what the agent already reported

### Error and Warning Reporting

**CRITICAL: Report ALL errors, warnings, and issues - never suppress or ignore them.**

When executing scripts via Task agents:

- ✅ **Report script errors**: Exit codes, exceptions, error messages
- ✅ **Report warnings**: Deprecation warnings, import issues, configuration problems
- ✅ **Report unexpected output**: 404s, timeouts, validation failures
- ✅ **Include context**: What was being executed when the error occurred

**Red flags that indicate issues:**

🚩 Non-zero exit code
🚩 Lines containing "ERROR", "FAILED", "Exception", "Traceback"
🚩 "WARNING" or "WARN" messages
🚩 "404 Not Found", "500 Internal Server Error"

### Domain-Specific Reporting for Scraping

**CRITICAL**: When reporting scraping results, distinguish behavior by domain.

**Domain-Specific .md URL Behavior:**

1. **docs.claude.com** and **code.claude.com**: These domains serve .md URLs successfully
2. **anthropic.com**: These domains do NOT serve .md URLs (404 expected, configured with `try_markdown: false`)

**Accurate Reporting:**

✅ **Good (Domain-Specific)**: "docs.claude.com: 97 URLs using direct .md (97 skipped/unchanged). anthropic.com: 164 URLs using HTML conversion (158 skipped/unchanged)."

❌ **Bad (Misleading)**: "All .md URL attempts returned 404 (expected - these are HTML pages)" ← This is misleading because Claude domains successfully use .md URLs

## Quick Start

### Refresh Index End-to-End (No Scraping)

Use this when you want to rebuild and validate the local index/metadata **without scraping**:

**⚠️ IMPORTANT: Use Python 3.12 for validation** - spaCy/Pydantic have compatibility issues with Python 3.14+

```bash
# Use Python 3.12 for full compatibility with spaCy
py -3.12 .claude/skills/docs-management/scripts/management/refresh_index.py
```

Optional flags:

```bash
# Check for missing files before rebuilding
py -3.12 .claude/skills/docs-management/scripts/management/refresh_index.py --check-missing-files

# Detect drift (404s, missing files) after rebuilding
py -3.12 .claude/skills/docs-management/scripts/management/refresh_index.py --check-drift

# Detect and automatically cleanup drift
py -3.12 .claude/skills/docs-management/scripts/management/refresh_index.py --check-drift --cleanup-drift
```

This script runs the full pipeline:

- ✅ Checks dependencies
- ✅ (Optional) Checks for missing files
- ✅ Rebuilds the index from the filesystem
- ✅ Extracts keywords & metadata for all documents
- ✅ Validates metadata coverage
- ✅ Generates a summary report
- ✅ (Optional) Detects and cleans up drift

Expected runtime: ~20-30 seconds for ~500 documents

### Scrape All Sources (Used by `/scrape-official-docs`)

Use this when the user explicitly wants to **hit the network and scrape docs**:

#### Python Version Requirement

- **Python 3.14 works by default** for scraping
- **Python 3.12 required for spaCy operations** (keyword extraction, metadata extraction)

```bash
# Step 1: Scrape documentation (Python 3.14+ works)
python .claude/skills/docs-management/scripts/core/scrape_all_sources.py \
  --parallel \
  --skip-existing

# Step 2: IMMEDIATELY run validation after scraping completes
# ⚠️ Use Python 3.12 for validation (spaCy compatibility)
py -3.12 .claude/skills/docs-management/scripts/management/refresh_index.py
```

#### Validation is Required After Scraping

Since `--auto-validate` is now default: False (for speed), you **MUST run validation separately** immediately after scraping.

Optional: Detect and cleanup drift after scraping:

```bash
# Auto-cleanup workflow (detect and cleanup in one flag)
python .claude/skills/docs-management/scripts/core/scrape_all_sources.py \
  --parallel \
  --skip-existing \
  --auto-cleanup

# Then validate (use Python 3.12)
py -3.12 .claude/skills/docs-management/scripts/management/refresh_index.py
```

### Find Documentation

```bash
# Resolve doc_id to file path
python .claude/skills/docs-management/scripts/core/find_docs.py resolve <doc_id>

# Search by keywords
python .claude/skills/docs-management/scripts/core/find_docs.py search skills progressive-disclosure

# Natural language search
python .claude/skills/docs-management/scripts/core/find_docs.py query "how to create skills"

# List by category
python .claude/skills/docs-management/scripts/core/find_docs.py category api

# List by tag
python .claude/skills/docs-management/scripts/core/find_docs.py tag skills
```

## Configuration System

The docs-management skill uses a unified configuration system with a single source of truth.

**Configuration Files:**

- **`config/defaults.yaml`** - Central configuration file with all default values
- **`config/config_registry.py`** - Canonical configuration system with environment variable support
- **`references/sources.json`** - Documentation sources configuration (required for scraping)

**Path Configuration:**

All paths configured in `config/defaults.yaml` under the `paths` section.

**Environment Variable Overrides:**

All configuration values can be overridden using environment variables: `CLAUDE_DOCS_<SECTION>_<KEY>`

**Full details:** [references/technical-details.md#configuration](references/technical-details.md)

## Dependencies & Environment

**Required:** `pyyaml`, `requests`, `beautifulsoup4`, `markdownify`
**Optional (recommended):** `spacy`, `yake` (for enhanced keyword extraction)

**Quick setup:**

```bash
python .claude/skills/docs-management/scripts/setup/setup_dependencies.py --install-required
```

**Auto-installation:** The `extract-keywords` command automatically installs optional dependencies if missing.

**Full details:** [references/technical-details.md#dependencies](references/technical-details.md)

## Core Capabilities

### 1. Scraping Documentation

Fetch documentation from official sources and store in canonical storage. Features: sitemap/docs map parsing, HTML→Markdown conversion, direct .md URL fetching (30-40% token savings), automatic metadata tracking, domain-based folder organization.

**Guide:** [references/capabilities/scraping-guide.md](references/capabilities/scraping-guide.md)

### 2. Extracting Subsections (Internal Use)

Extract specific markdown sections for internal skill operations. Features: ATX-style heading structure parsing, section boundaries detection, provenance frontmatter, token economics (60-90% savings typical).

**Guide:** [references/capabilities/extraction-guide.md](references/capabilities/extraction-guide.md)

### 3. Change Detection

Detect new and removed documentation pages from sitemaps, and detect content changes via hash comparison. Features: new/removed page detection, content hash comparison, automatic stale marking, change reporting and audit logs.

**Guide:** [references/capabilities/change-detection-guide.md](references/capabilities/change-detection-guide.md)

### 4. Finding and Resolving Documentation

Discover and resolve documentation references using doc_id, keywords, or natural language queries. Features: doc_id resolution, keyword-based search, natural language query processing, subsection discovery and extraction, category and tag filtering, alias resolution.

### 5. Index Management and Maintenance

Maintain index metadata, keywords, tags, and rebuild index from filesystem. Scripts: `manage_index.py`, `rebuild_index.py`, `generate_report.py`, `verify_index.py`.

## Workflows

Common maintenance and operational workflows for documentation management:

- **Adding New Documentation Source** - Onboarding new docs from sitemaps or docs maps
- **Scraping Multiple Sources** - Validation checkpoints to prevent wasted time/tokens
- **Token-Optimized Subsection Retrieval** - Workflow for extracting subsections instead of full documents

**Detailed Workflows:** [references/workflows.md](references/workflows.md)

## Metadata & Keyword Audit Workflows

**Lightweight audit:**

```bash
py -3.12 .claude/skills/docs-management/scripts/validation/validate_index_vs_docs.py --summary-only
```

**Tag configuration audit:**

```bash
py -3.12 .claude/skills/docs-management/scripts/validation/audit_tag_config.py --summary-only
```

**Full details:** [references/workflows.md#metadata--keyword-audit](references/workflows.md)

## Platform-Specific Requirements

### Windows Users

**MUST use PowerShell (recommended) or prefix Git Bash commands with `MSYS_NO_PATHCONV=1`**

Git Bash on Windows converts Unix paths to Windows paths, breaking filter patterns.

**See:** [Troubleshooting Guide](references/troubleshooting.md#git-bash-path-conversion)

## Troubleshooting

### spaCy Installation Issues

**Problem:** spaCy installation fails with Python 3.14+.

**Solution:** The script automatically detects and uses Python 3.12 if available. No manual intervention needed!

**If Python 3.12 not available:** Install Python 3.12:

- Windows: `winget install --id Python.Python.3.12 -e --source winget`
- macOS: `brew install python@3.12`
- Linux: `sudo apt install python3.12`

**Full troubleshooting:** [references/troubleshooting.md](references/troubleshooting.md)

## Public API

The docs-management skill provides a clean public API for external tools:

```python
from official_docs_api import (
    find_document,
    resolve_doc_id,
    get_docs_by_tag,
    get_docs_by_category,
    search_by_keywords,
    detect_drift,
    cleanup_drift,
    refresh_index
)
```

**Full API documentation:** See Public API section in original SKILL.md

## Plugin Maintenance

For plugin-specific maintenance workflows (versioning, publishing updates, changelog):

**See:** [references/plugin-maintenance.md](references/plugin-maintenance.md)

Quick reference:

- **Update workflow**: Scrape → Validate → Review → Commit → Version bump → Push
- **Version bumps**: Patch for doc refresh, Minor for new sources/features, Major for breaking changes
- **Testing**: Run `manage_index.py verify` and test search before pushing

## Development Mode

When developing this plugin locally, you may want changes to go to your dev repo instead of the installed plugin location. This skill supports explicit dev/prod mode separation via environment variable.

### How It Works

By default, scripts write to wherever the plugin is installed (typically `~/.claude/plugins/marketplaces/...`). When `DOCS_MANAGEMENT_DEV_ROOT` is set to a valid skill directory, all paths resolve to that location instead.

### Enabling Dev Mode

**One-time setup:**

```bash
# Navigate to your dev repo skill directory
cd /path/to/your/claude-code-plugins/plugins/claude-ecosystem/skills/docs-management

# Generate shell commands for your shell
python scripts/setup/enable_dev_mode.py
```

**PowerShell:**

```powershell
$env:DOCS_MANAGEMENT_DEV_ROOT = "D:\repos\gh\claude-code-plugins\plugins\claude-ecosystem\skills\docs-management"
```

**Bash/Zsh:**

```bash
export DOCS_MANAGEMENT_DEV_ROOT="/path/to/claude-code-plugins/plugins/claude-ecosystem/skills/docs-management"
```

### Verifying Mode

When you run any major script (scrape, refresh, rebuild), a mode banner will display:

**Dev mode:**

```
[DEV MODE] Using development skill directory:
  D:\repos\gh\claude-code-plugins\plugins\claude-ecosystem\skills\docs-management
  Set via: DOCS_MANAGEMENT_DEV_ROOT
Canonical dir: D:\...\canonical
```

**Prod mode:**

```
[PROD MODE] Using installed skill directory
  (Set DOCS_MANAGEMENT_DEV_ROOT to enable dev mode)
```

### Development Workflow

1. Set `DOCS_MANAGEMENT_DEV_ROOT` in your terminal
2. Run scripts - output goes to dev repo
3. Track changes: `git diff canonical/`
4. Commit and push when ready

### Disabling Dev Mode

**PowerShell:**

```powershell
Remove-Item Env:DOCS_MANAGEMENT_DEV_ROOT
```

**Bash/Zsh:**

```bash
unset DOCS_MANAGEMENT_DEV_ROOT
```

## Related Documentation

- **index.yaml** (in canonical storage) - Complete registry of docs and extracts
- **[references/parallelization-strategy.md](references/parallelization-strategy.md)** - Parallelization decision trees
- **[references/plugin-maintenance.md](references/plugin-maintenance.md)** - Plugin update and publishing workflows
- **[DEPENDENCIES.md](DEPENDENCIES.md)** - Script dependency graph and execution order

## Version History

- v1.19.0 (2025-11-25): Determinism fixes and observability enhancements
- v1.18.0 (2025-11-18): CRITICAL FIX: Enforce foreground execution pattern
- v1.17.1 (2025-11-18): Fix Task tool invocation syntax
- v1.17.0 (2025-11-18): Critical workflow execution guidance + error reporting
- v1.16.0 (2025-11-17): Comprehensive search quality audit & fixes (100% pass rate)
- v1.15.0 (2025-11-17): Critical bug fix + domain prioritization
- v1.14.0 (2025-11-17): Comprehensive skill audit & validation (A+ grade)

Full history: See original SKILL.md

## Last Updated

**Date:** 2025-11-28
**Model:** claude-opus-4-5-20251101

**Audit Result:** ✅ **EXCEPTIONAL PASS (A+)** - Score: 50/50 (100%)

**Audit Type:** Type B (Meta-Skill - Delegation Pattern Compliance)

**Status:** Production-ready. Serves as the canonical reference implementation for Type B meta-skills.
