# Plan: google-ecosystem Plugin with Gemini CLI Documentation

## Overview

Create a new `google-ecosystem` plugin with **full search parity** documentation infrastructure for Google Gemini CLI. The plugin will be self-contained (per Claude Code plugin isolation requirements) with the complete inverted index + weighted scoring system for accurate search results.

## Architecture Decision

**Approach: Full Search Parity (Adapted)**

Rationale:
- Search accuracy is critical - MVP Grep approach lacks relevance ranking
- Copy core search infrastructure (~4,000 LOC) from official-docs
- Adapt all Claude-specific references to Gemini CLI
- Simplify where possible (single source vs multiple domains)
- Remove features not needed for 43-page corpus

## Directory Structure

```
plugins/google-ecosystem/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── gemini-cli-docs/
│       ├── SKILL.md                    # Main skill definition
│       ├── gemini_docs_api.py          # Public API (adapted from official_docs_api.py)
│       │
│       ├── canonical/                  # Scraped documentation storage
│       │   ├── index.yaml              # Main index (YAML for git-friendly diffs)
│       │   ├── index.json              # JSON mirror for fast loading
│       │   └── geminicli-com/          # Docs organized by domain
│       │       └── docs/
│       │           └── *.md            # ~43 scraped markdown files
│       │
│       ├── .cache/
│       │   ├── inverted_index.json     # O(1) keyword lookup cache
│       │   └── cache_version.json      # Cache validation metadata
│       │
│       ├── config/
│       │   ├── __init__.py
│       │   ├── config_registry.py      # Config loading with env overrides
│       │   ├── defaults.yaml           # HTTP, scraping, search settings
│       │   └── filtering.yaml          # Gemini-specific stop words, phrases
│       │
│       ├── references/
│       │   └── sources.json            # Source configuration (geminicli.com)
│       │
│       └── scripts/
│           ├── __init__.py
│           ├── bootstrap.py            # Path setup (adapted)
│           │
│           ├── core/
│           │   ├── __init__.py
│           │   ├── scrape_docs.py      # Main scraper (adapted)
│           │   ├── llms_parser.py      # Parse llms.txt
│           │   └── doc_resolver.py     # Search/resolution (adapted)
│           │
│           ├── utils/
│           │   ├── __init__.py
│           │   ├── http_utils.py       # HTTP with retry/backoff
│           │   ├── logging_utils.py    # Structured logging
│           │   ├── config_helpers.py   # Config access
│           │   ├── script_utils.py     # Common utilities
│           │   ├── path_config.py      # Path resolution
│           │   ├── cache_manager.py    # Cache validation
│           │   ├── metadata_utils.py   # Tag normalization
│           │   └── search_constants.py # Scoring weights
│           │
│           └── management/
│               ├── __init__.py
│               ├── index_manager.py    # YAML/JSON index I/O
│               └── rebuild_index.py    # Rebuild from filesystem
│
├── agents/
│   └── gemini-docs-researcher.md       # Research agent
│
└── commands/
    ├── scrape-gemini.md                # Scrape/refresh docs
    └── validate-gemini.md              # Validate index
```

## Implementation Steps

### Phase 1: Plugin Scaffolding

1. Create `plugins/google-ecosystem/.claude-plugin/plugin.json`
2. Create directory structure as shown above
3. Create `__init__.py` files for Python packages

### Phase 2: Copy & Adapt Core Scripts

**Files to copy from `claude-ecosystem/skills/docs-management/`:**

| Source File | Target File | Adaptation Required |
|-------------|-------------|---------------------|
| `scripts/bootstrap.py` | Same | Change env var prefix `OFFICIAL_DOCS_` → `GEMINI_DOCS_` |
| `scripts/core/doc_resolver.py` | Same | Remove subsection scoring (optional for 43 pages) |
| `scripts/core/llms_parser.py` | Same | Minimal changes |
| `scripts/core/scrape_docs.py` | Same | Simplify for single source |
| `scripts/utils/http_utils.py` | Same | Change user agent string |
| `scripts/utils/logging_utils.py` | Same | Change log category names |
| `scripts/utils/config_helpers.py` | Same | Update config paths |
| `scripts/utils/script_utils.py` | Same | Minimal changes |
| `scripts/utils/path_config.py` | Same | Update skill name reference |
| `scripts/utils/cache_manager.py` | Same | Minimal changes |
| `scripts/utils/metadata_utils.py` | Same | Minimal changes |
| `scripts/utils/search_constants.py` | Same | Keep scoring weights |
| `scripts/management/index_manager.py` | Same | Minimal changes |
| `config/config_registry.py` | Same | Update env var prefix |
| `official_docs_api.py` | `gemini_docs_api.py` | Rename, update paths |

### Phase 3: Create Gemini-Specific Configuration

**`config/defaults.yaml`** - Key changes from Claude version:
```yaml
http:
  user_agent: "Gemini-Docs-Scraper/1.0 (Educational purposes)"  # Changed

scraping:
  rate_limit: 0.5
  max_workers: 4  # Reduced (only 43 pages)

search:
  domain_weights:
    geminicli.com: 10.0  # Single domain, highest priority
```

**`config/filtering.yaml`** - Gemini-specific stop words:
```yaml
# REMOVE Claude-specific terms
domain_stop_words:
  - 'gemini'      # Equivalent to 'claude'
  - 'google'      # Equivalent to 'anthropic'
  - 'geminicli-com'  # Domain prefix
  # REMOVE: claude, anthropic, code-claude-com, etc.

# UPDATE technical phrases for Gemini CLI
technical_phrases:
  - 'memport'             # Gemini memory import
  - 'policy engine'       # Gemini security
  - 'trusted folders'     # Gemini security
  - 'checkpointing'       # Gemini feature
  - 'model routing'       # Gemini feature
  - 'codebase investigator'  # Gemini subagent
  - 'token caching'       # Gemini feature
  - 'prompt compression'  # Gemini feature
  # REMOVE: CLAUDE.md, progressive disclosure, agent skills, etc.
```

**`references/sources.json`**:
```json
[
  {
    "name": "geminicli.com (llms-txt)",
    "type": "llms-txt",
    "url": "https://geminicli.com/llms.txt",
    "skip_existing": true,
    "expected_count": 43,
    "timeout": 300
  }
]
```

### Phase 4: Claude-Specific Items to Remove/Change

**In `doc_resolver.py`:**
- Remove/simplify subsection matching (~100 lines) - optional for small docs
- Update domain weight references
- Remove anthropic.com-specific category handling

**In `defaults.yaml`:**
- Remove all `code.claude.com`, `docs.claude.com`, `anthropic.com` domain weights
- Remove Claude-specific keyword extraction settings (or simplify)
- Change environment variable prefix: `CLAUDE_DOCS_` → `GEMINI_DOCS_`

**In `filtering.yaml`:**
- Replace all Claude/Anthropic technical phrases with Gemini equivalents
- Update domain stop words
- Keep generic stop words (query_stop_words, generic_verbs, etc.)

**In all scripts:**
- Change `official-docs` references → `gemini-cli-docs`
- Change `Claude-Docs-Scraper` user agent → `Gemini-Docs-Scraper`
- Update import paths

### Phase 5: SKILL.md Definition

```markdown
---
name: gemini-cli-docs
description: Google Gemini CLI documentation and guidance. Use for Gemini CLI installation, commands, tools, extensions, MCP, and troubleshooting.
allowed-tools: Read, Glob, Grep, Bash
---

# Gemini CLI Documentation Skill

## Quick Start

Use the `gemini_docs_api.py` for programmatic access:
- `search_by_keyword(['checkpointing'])` - Keyword search
- `search_by_natural_language('how to configure extensions')` - NL search
- `resolve_doc_id('geminicli-com-docs-cli-commands')` - Get doc path

## Manual Search

1. **Keyword search**: Use doc_resolver.py
2. **Browse index**: Read `canonical/index.yaml`
3. **Read specific doc**: `canonical/geminicli-com/docs/<path>.md`

## Documentation Categories

| Category | Topics |
|----------|--------|
| Get Started | installation, authentication, configuration, examples |
| CLI | commands, settings, themes, checkpointing, security |
| Core | tools API, policy engine, memory, memport |
| Tools | file system, shell, web fetch, MCP servers |
| Extensions | creating, releasing, managing extensions |
| IDE | VS Code, JetBrains, companion spec |

## Maintenance

- **Refresh docs**: `/scrape-gemini` slash command
- **Validate index**: `/validate-gemini` slash command
```

### Phase 6: Initial Scrape & Commit

1. Run scraping script to fetch all ~43 pages
2. Verify inverted index builds correctly
3. Test keyword and NL searches
4. Commit pre-scraped docs (following official-docs pattern)

## Critical Files to Copy & Adapt

| Source Path (from `claude-ecosystem/skills/docs-management/`) | Notes |
|--------------------------------------------------------------|-------|
| `scripts/bootstrap.py` | Path setup - change env var prefix |
| `scripts/core/doc_resolver.py` | Core search - can simplify subsection logic |
| `scripts/core/llms_parser.py` | Parse llms.txt - minimal changes |
| `scripts/core/scrape_docs.py` | Scraper - simplify for single source |
| `scripts/utils/*.py` | All utility scripts |
| `scripts/management/index_manager.py` | Index I/O |
| `config/config_registry.py` | Config loading |
| `config/defaults.yaml` | Template for Gemini config |
| `config/filtering.yaml` | Template - replace Claude terms |
| `official_docs_api.py` | Rename to `gemini_docs_api.py` |

## Scripts NOT Needed (Simplifications)

These can be omitted - complexity not needed for 43 pages:

| Script | Reason to Omit |
|--------|----------------|
| `scrape_all_sources.py` | Only one source (llms.txt) |
| `delta_scraper.py` | Full re-scrape is fast enough |
| `dedup_manager.py` | No duplicates with single source |
| `detect_changes.py` | Manual validation sufficient |
| `cleanup_drift.py` | Minimal drift with small corpus |
| `validate_*.py` | Can add later if needed |
| `extract_subsection.py` | Docs are small enough to read fully |

## Estimated LOC

| Component | Lines | Notes |
|-----------|-------|-------|
| Core scripts (adapted) | ~2,500 | doc_resolver, scrape_docs, llms_parser |
| Utility scripts | ~1,500 | http, logging, config, paths, cache |
| Index management | ~800 | index_manager |
| Configuration | ~400 | defaults.yaml, filtering.yaml, sources.json |
| SKILL.md + API | ~200 | Skill definition + public API |
| **Total** | **~5,400** | Down from ~30,500 (full duplication) |

## Future Extensions (Not in Scope)

- [ ] Gemini CLI execution skill (non-interactive mode)
- [ ] Integration with Gemini 3.0 Pro model
- [ ] Delta scraping for efficiency
- [ ] Subsection extraction (if docs grow significantly)

## Success Criteria

1. All ~43 Gemini CLI docs scraped and indexed
2. Inverted index builds and caches correctly
3. Keyword search returns relevant results with proper ranking
4. Natural language search works (e.g., "how to configure extensions")
5. Skill activates correctly when discussing Gemini CLI
6. Plugin is fully self-contained
7. **No Claude/Anthropic-specific terms remain in code or config**

---

## Background Research

### Plugin Isolation Constraint

Claude Code plugins are designed as **self-contained, isolated units** with no supported mechanism for cross-plugin dependencies:
- All paths must be relative to plugin root (`./`)
- No `dependencies` field in plugin.json schema
- No mechanism for plugins to reference files outside their folder
- This is by design for portability and marketplace distribution

### Why Full Search Infrastructure is Needed

The official-docs search system provides accurate results through:

1. **Inverted Index with Weighted Scoring** (~1,124 lines in doc_resolver.py)
   - Title matches: 6 points (exact), 4 points (word boundary)
   - Description matches: 2 points (exact), 1 point (word boundary)
   - Keyword matches: 5 points (variant), 3 points (token), 2 points (substring)
   - Tag matches: 4 points (exact), 3 points (variant)
   - Identifier matches: 6 points (doc_id tokens)

2. **Keyword Variant Generation**
   - Normalizes keywords (lowercase, alphanumeric only)
   - Generates singular forms (strips trailing 's')
   - Tokenizes compound terms

3. **Stop Word Filtering**
   - Query stop words: "when", "how", "to", "best", "practices"
   - Natural language stop words for NL queries

4. **Generic Term Penalties**
   - Terms like "configuration", "setup", "installation" get penalized
   - Prevents ranking collapse when mixing generic + specific terms

5. **Coverage Multipliers**
   - All terms match in title: 2.0x
   - All terms match anywhere: 1.5x
   - Most terms match (67%+): 1.2x

A simple Grep-based MVP would lack all of these, resulting in poor search accuracy.

### Gemini CLI Documentation

- **Source**: https://geminicli.com/
- **llms.txt**: https://geminicli.com/llms.txt (lists all doc URLs)
- **Direct .md support**: URLs support `.md` extension (e.g., `/docs/architecture.md`)
- **~43 pages** across 9 categories: Get Started, CLI, Core, Tools, Extensions, IDE, About

Key features documented:
- REPL environment with terminal-based interaction
- Checkpointing (file state snapshots)
- Model routing (Flash vs Pro selection)
- Token caching and prompt compression
- Extensions system
- MCP server support
- Policy engine for security
