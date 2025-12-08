---
description: Regenerate the capability index cache for SessionStart injection
allowed-tools: Bash, Read
---

# Refresh Capability Index

Regenerate the capability index that is injected at session start.

## Context

The capability index is a token-efficient summary of ALL available skills, agents, and commands from installed plugins. It helps Claude know what tools are at its disposal.

By default (static mode), the index is cached and must be manually refreshed when:

- New plugins are installed
- Skills, agents, or commands are added/modified
- You want to update the index after changes

## Action

Run the Python generator to refresh the cache:

```bash
# Find the plugins directory and generator script
PLUGINS_DIR="$(cd "${CLAUDE_PROJECT_ROOT:-$(pwd)}" && pwd)/plugins"
GENERATOR="${PLUGINS_DIR}/claude-ecosystem/hooks/inject-capability-index/python/generate_index.py"
CACHE_FILE="${PLUGINS_DIR}/claude-ecosystem/hooks/inject-capability-index/cache/capability-index.txt"

# Generate index (use configured detail level or default to standard)
DETAIL="${CLAUDE_HOOK_CAPABILITY_INDEX_DETAIL:-standard}"

# Run generator and extract index text
python3 "$GENERATOR" --detail "$DETAIL" --plugins-dir "$PLUGINS_DIR" --output text > "$CACHE_FILE"

# Report success
echo "Capability index refreshed at: $CACHE_FILE"
echo "Detail level: $DETAIL"
wc -l "$CACHE_FILE" | awk '{print "Lines:", $1}'
wc -c "$CACHE_FILE" | awk '{print "Characters:", $1}'
echo "Estimated tokens: $(( $(wc -c < "$CACHE_FILE") / 4 ))"
```

## Configuration

The detail level can be configured via environment variable:

- `CLAUDE_HOOK_CAPABILITY_INDEX_DETAIL=minimal` - Names + 1-line descriptions (~1,500 tokens)
- `CLAUDE_HOOK_CAPABILITY_INDEX_DETAIL=standard` - Names + descriptions + keywords (~2,200 tokens)
- `CLAUDE_HOOK_CAPABILITY_INDEX_DETAIL=comprehensive` - Full index with triggers (~3,500 tokens)

## Verification

After refreshing, you can view the cached index:

```bash
cat "${PLUGINS_DIR}/claude-ecosystem/hooks/inject-capability-index/cache/capability-index.txt" | head -50
```

The refreshed index will be used in the next session start (or immediately if using `dynamic` mode).
