---
description: Scrape Gemini CLI documentation from geminicli.com, then refresh and validate the index.
---

# Scrape Gemini CLI Documentation

Scrape all documentation from the configured sources (geminicli.com llms.txt).

## Steps

1. Run the scraping script with parallel processing:

```bash
python "${CLAUDE_PLUGIN_ROOT}/skills/gemini-cli-docs/scripts/core/scrape_all_sources.py" --parallel --skip-existing
```

1. After scraping completes, rebuild the index:

```bash
python "${CLAUDE_PLUGIN_ROOT}/skills/gemini-cli-docs/scripts/management/rebuild_index.py"
```

1. Verify the index:

```bash
python "${CLAUDE_PLUGIN_ROOT}/skills/gemini-cli-docs/scripts/management/manage_index.py" verify
```

Report the results of each step.
