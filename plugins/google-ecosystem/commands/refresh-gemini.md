---
description: Refresh Gemini CLI docs index without scraping. Rebuilds index from existing files.
---

# Refresh Gemini CLI Documentation Index

Refresh the local index without re-scraping from the web. Use this when you've manually modified documentation files or need to rebuild the index.

## Steps

1. Rebuild the index from filesystem:

```bash
python "${CLAUDE_PLUGIN_ROOT}/skills/gemini-cli-docs/scripts/management/rebuild_index.py"
```

2. Verify the index integrity:

```bash
python "${CLAUDE_PLUGIN_ROOT}/skills/gemini-cli-docs/scripts/management/manage_index.py" verify
```

3. Report the document count:

```bash
python "${CLAUDE_PLUGIN_ROOT}/skills/gemini-cli-docs/scripts/management/manage_index.py" count
```

Report the results of each step.
