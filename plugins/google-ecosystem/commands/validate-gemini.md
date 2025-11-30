---
description: Validate Gemini CLI docs index integrity and detect drift without making changes.
---

# Validate Gemini CLI Documentation Index

Run validation checks on the documentation index without making any modifications.

## Steps

1. Run index verification:

```bash
python "${CLAUDE_PLUGIN_ROOT}/skills/gemini-cli-docs/scripts/management/manage_index.py" verify
```

1. Run full validation with summary:

```bash
python "${CLAUDE_PLUGIN_ROOT}/skills/gemini-cli-docs/scripts/validation/validate_index_vs_docs.py" --summary-only
```

1. Report document count:

```bash
python "${CLAUDE_PLUGIN_ROOT}/skills/gemini-cli-docs/scripts/management/manage_index.py" count
```

Report the results of each validation step, highlighting any issues found.
