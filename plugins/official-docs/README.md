# official-docs Plugin

Claude Code official documentation skill with local search, caching, and offline access.

## Features

- **599 pre-scraped documentation files** from official sources
- **Keyword-based search** with inverted index for fast discovery
- **doc_id resolution** for stable, refactorable references
- **Token-optimized subsection extraction** (60-90% context savings)
- **Offline access** - works without internet after installation
- **Drift detection** - hash-based validation against upstream

## Coverage

| Source | Documents | Content |
|--------|-----------|---------|
| docs.claude.com | ~227 | Claude API docs, resources, release notes |
| code.claude.com | ~89 | Claude Code CLI documentation |
| platform.claude.com | ~150 | Platform API reference |
| anthropic.com | ~181 | Engineering blog, news, research |
| modelcontextprotocol.io | ~50 | MCP protocol documentation |

## Installation

1. Add the marketplace:
   ```bash
   /plugin marketplace add kyle-sexton/claude-code-plugins
   ```

2. Install this plugin:
   ```bash
   /plugin install official-docs@claude-code-plugins
   ```

## Usage

Once installed, invoke the skill by name:

```
Use the official-docs skill to find documentation about hooks
```

Or use the skill's search capabilities:

```
Search official-docs for "CLAUDE.md memory hierarchy"
```

### Available Operations

- **Resolve doc_id**: Find document by stable identifier
- **Keyword search**: Search by technical keywords
- **Natural language query**: Conversational search
- **Category/tag filtering**: Browse by topic area
- **Subsection extraction**: Get specific sections (token-efficient)

## Updating Documentation

The plugin ships with pre-scraped docs. To update to latest:

```bash
# Navigate to plugin skill directory
cd ~/.claude/plugins/official-docs@claude-code-plugins/skills/official-docs

# Run scrape (requires Python 3.10+)
python scripts/core/scrape_all_sources.py --parallel --skip-existing

# Refresh index (use Python 3.12 for spaCy compatibility)
py -3.12 scripts/management/refresh_index.py
```

## Dependencies

**Required (auto-installed):**
- pyyaml
- requests
- beautifulsoup4
- markdownify

**Optional (for enhanced keyword extraction):**
- spacy
- yake

## License

MIT

## Author

Kyle Sexton - https://github.com/kyle-sexton
