# inject-capability-index Hook

SessionStart hook that injects a complete index of available capabilities (skills, agents, commands) into Claude's context at the beginning of each session.

## Purpose

Claude Code's system prompt truncates available skills and commands lists due to token limits (e.g., "21 of 91 skills"). This means Claude may not know about specialized capabilities that could help with specific tasks.

This hook provides Claude with a complete, categorized index of ALL available capabilities from installed plugins, improving task routing and capability discovery.

## Configuration

Configure via environment variables:

| Variable | Values | Default | Description |
| ---------- | -------- | --------- | ------------- |
| `CLAUDE_HOOK_CAPABILITY_INDEX_ENABLED` | `0`, `1` | `1` | Enable/disable hook |
| `CLAUDE_HOOK_CAPABILITY_INDEX_MODE` | `static`, `cached`, `dynamic` | `static` | Generation strategy |
| `CLAUDE_HOOK_CAPABILITY_INDEX_DETAIL` | `minimal`, `standard`, `comprehensive` | `standard` | Token budget level |

### Generation Modes

- **`static`** (default): Use pre-generated cache only. Fastest. Refresh manually via `/refresh-capability-index` when plugins change.
- **`cached`**: Check if source files changed since last generation. Regenerate if stale. Good balance of freshness and speed.
- **`dynamic`**: Always regenerate fresh index at session start. Slowest (~500ms) but always current.

### Detail Levels

| Level | Estimated Tokens | Contents |
| ------- | ------------------ | ---------- |
| `minimal` | ~1,500 | Names + 1-line descriptions |
| `standard` | ~2,200 | Names + descriptions + keywords |
| `comprehensive` | ~3,500 | Full index with usage triggers and examples |

## Manual Refresh

When using `static` mode (default), refresh the cache after installing or modifying plugins:

```bash
/refresh-capability-index
```

Or run the generator directly:

```bash
python3 plugins/claude-ecosystem/hooks/inject-capability-index/python/generate_index.py \
  --detail standard \
  --plugins-dir ./plugins \
  --output text > plugins/claude-ecosystem/hooks/inject-capability-index/cache/capability-index.txt
```

## Output Format

The hook injects content wrapped in `<capability-index>` tags:

```xml
<capability-index>
INSTALLED CAPABILITIES (97 skills, 64 agents, 157 commands across 11 plugins)

## claude-ecosystem (18 skills, 14 agents)
Skills:
- docs-management: Claude docs search/resolution | KW: documentation, official, canonical
- hook-management: Hooks config/enforcement | KW: hooks, PreToolUse, PostToolUse
...

Agents:
- docs-researcher (haiku): Search official Claude docs
- claude-code-issue-researcher (haiku): Search GitHub issues
...

Commands: /scrape-docs, /refresh-docs, /list-skills, ...

## code-quality (3 skills, 3 agents)
...
</capability-index>
```

## File Structure

```text
inject-capability-index/
├── README.md                 # This file
├── bash/
│   └── inject-capability-index.sh  # Entry point
├── python/
│   ├── __init__.py
│   ├── generate_index.py     # Index generator
│   └── frontmatter_parser.py # YAML extraction
├── cache/
│   └── capability-index.txt  # Cached index (gitignored)
└── tests/
    └── test-inject-capability-index.sh
```

## Dependencies

- Bash (Git Bash on Windows)
- Python 3.x (for index generation)
- No external Python packages required

## Disabling

To disable the hook temporarily:

```bash
export CLAUDE_HOOK_CAPABILITY_INDEX_ENABLED=0
```

Or permanently in your shell profile.

## Troubleshooting

### Cache not found in static mode

Run `/refresh-capability-index` to generate the initial cache.

### Slow session start

Switch to `static` mode (default) and use manual refresh:

```bash
export CLAUDE_HOOK_CAPABILITY_INDEX_MODE=static
```

### Python not found

Install Python 3.x or ensure it's in your PATH. The hook will skip injection gracefully if Python is unavailable.

## Related

- `/refresh-capability-index` - Manual cache refresh command
- `inject-best-practices` hook - Injects behavioral reminders
- `inject-current-date` hook - Injects UTC timestamp
