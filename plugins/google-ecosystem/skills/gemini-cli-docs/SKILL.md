---
name: gemini-cli-docs
description: Google Gemini CLI documentation and guidance. Use for Gemini CLI installation, commands, tools, extensions, MCP, and troubleshooting.
allowed-tools: Read, Glob, Grep, Bash
---

# Gemini CLI Documentation Skill

Single source of truth for Google Gemini CLI documentation. Use the `gemini_docs_api.py` for programmatic access.

## Quick Start

### Search Documentation

```python
# Natural language search
python scripts/core/find_docs.py query "how to use checkpointing"

# Keyword search
python scripts/core/find_docs.py search checkpointing session rewind

# Resolve doc_id to file path
python scripts/core/find_docs.py resolve geminicli-com-docs-cli-checkpointing
```

### Browse Index

```python
# List all indexed documents
python scripts/management/manage_index.py list

# Get entry count
python scripts/management/manage_index.py count

# Verify index integrity
python scripts/management/manage_index.py verify
```

## API Access

Use `gemini_docs_api.py` for programmatic access:

```python
from gemini_docs_api import find_document, resolve_doc_id, get_docs_by_tag

# Find by natural language query
docs = find_document("model routing configuration")

# Resolve doc_id to metadata
doc = resolve_doc_id("geminicli-com-docs-cli-checkpointing")

# Get docs by tag
cli_docs = get_docs_by_tag("cli")
```

## Documentation Categories

| Category | Topics |
|----------|--------|
| Get Started | installation, authentication, configuration, quickstart |
| CLI | commands, settings, themes, checkpointing, telemetry, trusted folders |
| Core | architecture, tools API, policy engine, memport |
| Tools | file system, shell, web fetch, web search, memory tool, MCP servers |
| Extensions | creating, managing, releasing extensions |
| IDE | VS Code, JetBrains, IDE companion |

## Gemini CLI Features

Key features documented:

- **Checkpointing**: File state snapshots, session management, rewind
- **Model Routing**: Flash vs Pro selection, automatic routing
- **Token Caching**: Prompt compression, cost optimization
- **Policy Engine**: Security controls, trusted folders
- **Memport**: Memory import/export
- **MCP Servers**: Model Context Protocol integration
- **Extensions**: Plugin system for CLI

## Maintenance Commands

### Scrape Documentation

```bash
# Scrape from llms.txt source
python scripts/core/scrape_all_sources.py --parallel --skip-existing
```

### Refresh Index

```bash
# Rebuild index from filesystem
python scripts/management/rebuild_index.py
```

### Validate Index

```bash
# Validate index integrity
python validation/validate_index_vs_docs.py --summary-only
```

## Directory Structure

```
gemini-cli-docs/
├── SKILL.md              # This file
├── gemini_docs_api.py    # Public API
├── canonical/            # Scraped documentation
│   ├── index.yaml        # Main index
│   ├── index.json        # JSON mirror (fast loading)
│   └── geminicli-com/    # Docs by domain
│       └── docs/
│           └── *.md      # ~43 documentation files
├── config/               # Configuration
│   ├── defaults.yaml     # Default settings
│   ├── filtering.yaml    # Keyword filtering
│   └── config_registry.py
├── scripts/              # Python scripts
│   ├── core/             # Scraping, search
│   ├── utils/            # Utilities
│   └── management/       # Index management
└── references/
    └── sources.json      # Documentation sources
```

## Configuration

Environment variable prefix: `GEMINI_DOCS_`

Example overrides:
```bash
# Set custom timeout
export GEMINI_DOCS_HTTP_DEFAULT_TIMEOUT=60

# Set max workers
export GEMINI_DOCS_SCRAPING_MAX_WORKERS=8
```

## Source

Documentation is scraped from: https://geminicli.com/llms.txt

## Test Scenarios

### Scenario 1: Keyword Search

**Query**: "Search for checkpointing documentation"
**Expected Behavior**:

- Skill activates on keyword "documentation"
- Returns relevant docs from index
**Success Criteria**: User receives matching documentation entries

### Scenario 2: Natural Language Query

**Query**: "How do I configure model routing in Gemini CLI?"
**Expected Behavior**:

- Skill activates on "Gemini CLI"
- Uses find_docs.py query command
**Success Criteria**: Returns relevant documentation with configuration steps

### Scenario 3: Doc ID Resolution

**Query**: "Resolve geminicli-com-docs-cli-checkpointing"
**Expected Behavior**:

- Resolves doc_id to file path
- Returns document metadata
**Success Criteria**: User receives full path and document content

## Version History

- v1.1.0 (2025-12-01): Added Test Scenarios section
- v1.0.0 (2025-11-25): Initial release
