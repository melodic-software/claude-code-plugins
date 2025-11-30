# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Claude Code plugins repository containing the `claude-ecosystem` plugin - a comprehensive ecosystem plugin with official documentation management, meta-skills for all Claude Code features, and development guidance.

## Architecture

### Plugin Structure

```text
plugins/claude-ecosystem/
├── .claude-plugin/plugin.json  # Plugin manifest (v2.0.0)
├── agents/                     # Custom agents (docs-researcher)
├── commands/                   # Slash commands (scrape-docs, refresh-docs, validate-docs)
├── hooks/                      # Plugin hooks (hooks.json)
├── skills/                     # 15+ meta-skills for Claude Code features
│   ├── docs-management/        # Core skill - documentation scraping, indexing, resolution
│   └── [topic]-management/     # Topic-specific meta-skills
└── scripts/                    # Build/maintenance scripts
```

### Skills Architecture

All skills follow a **pure delegation architecture**:

1. Each `SKILL.md` provides keyword registries and navigation
2. `docs-management` skill is the single source of truth for official documentation
3. Meta-skills do NOT duplicate official documentation - they delegate to `docs-management`

Skills use noun-phrase naming convention (e.g., `hook-management`, `memory-management`, `skill-development`).

### docs-management Core Components

The central skill at `plugins/claude-ecosystem/skills/docs-management/`:

- `canonical/` - Local storage of scraped official documentation (by domain)
- `config/` - Configuration system (`defaults.yaml`, `config_registry.py`)
- `references/sources.json` - Documentation sources configuration
- `scripts/` - Python scripts organized by function:
  - `core/` - Scraping, finding, resolving docs
  - `management/` - Index management, metadata extraction
  - `validation/` - Index verification, search audits
  - `maintenance/` - Cleanup, drift detection
- `tests/` - Pytest test suite

## Development Commands

### Documentation Management

```bash
# Scrape all documentation sources (use Python 3.14+)
python plugins/claude-ecosystem/skills/docs-management/scripts/core/scrape_all_sources.py --parallel --skip-existing

# Refresh index without scraping (use Python 3.12 for spaCy compatibility)
py -3.12 plugins/claude-ecosystem/skills/docs-management/scripts/management/refresh_index.py

# Find documentation
python plugins/claude-ecosystem/skills/docs-management/scripts/core/find_docs.py search <keywords>
python plugins/claude-ecosystem/skills/docs-management/scripts/core/find_docs.py resolve <doc_id>
python plugins/claude-ecosystem/skills/docs-management/scripts/core/find_docs.py query "natural language query"

# Index management
python plugins/claude-ecosystem/skills/docs-management/scripts/management/manage_index.py count
python plugins/claude-ecosystem/skills/docs-management/scripts/management/manage_index.py list
python plugins/claude-ecosystem/skills/docs-management/scripts/management/manage_index.py verify

# Validation
py -3.12 plugins/claude-ecosystem/skills/docs-management/scripts/validation/validate_index_vs_docs.py --summary-only
```

### Testing

```bash
# Run tests from the docs-management skill directory
cd plugins/claude-ecosystem/skills/docs-management
pytest tests/ -v

# Run specific test categories
pytest tests/ -m unit
pytest tests/ -m integration
pytest tests/ -m "not slow"
```

### Dependencies

```bash
# Install required dependencies
pip install pyyaml requests beautifulsoup4 markdownify

# Install optional NLP dependencies (recommended)
pip install spacy yake
python -m spacy download en_core_web_sm

# Or use the setup script
python plugins/claude-ecosystem/skills/docs-management/scripts/setup/setup_dependencies.py --install-required
```

## Important Conventions

### Python Version Requirements

- **Python 3.12**: Required for spaCy/validation operations (keyword extraction, metadata)
- **Python 3.14+**: Works for scraping operations
- Use `py -3.12` on Windows to specify Python version

### Path Handling

**CRITICAL: Never chain `cd` with `&&` in PowerShell** - causes path doubling issues.

Use one of:

- Helper scripts that handle path resolution
- Absolute paths
- Separate commands (not chained with `&&`)

### Index File Handling

**NEVER use read_file tool on `index.yaml`** - file exceeds token limits. Always use `manage_index.py` scripts.

### Platform Notes

- **Windows**: Use PowerShell (recommended) or prefix Git Bash commands with `MSYS_NO_PATHCONV=1`
- Git Bash path conversion can break filter patterns

## Slash Commands

Available plugin commands:

- `/claude-ecosystem:scrape-docs` - Scrape documentation sources, then refresh and validate
- `/claude-ecosystem:refresh-docs` - Refresh local index without scraping
- `/claude-ecosystem:validate-docs` - Validate index integrity and detect drift

## Configuration

- `config/defaults.yaml` - Central configuration with all default values
- Environment variables: `CLAUDE_DOCS_<SECTION>_<KEY>` for overrides
- `DOCS_MANAGEMENT_DEV_ROOT` - Set for development mode (writes to dev repo instead of installed plugin)
