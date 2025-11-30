# CLAUDE.md

See @README for project overview and installation.

## Critical Rules

- **NEVER read `index.yaml` directly** - use `manage_index.py` scripts
- **NEVER chain `cd &&` in PowerShell** - causes path doubling
- **Use `MSYS_NO_PATHCONV=1`** in Git Bash
- **Use Python 3.12** for spaCy operations

## Documentation

For Claude Code topics, invoke the `docs-management` skill or use:

```bash
python plugins/claude-ecosystem/skills/docs-management/scripts/core/find_docs.py search <keywords>
```

For Gemini CLI topics, invoke the `gemini-cli-docs` skill or use:

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/core/find_docs.py search <keywords>
```

## Conventions

- Skills: noun-phrase names (`hook-management`)
- Commands: verb-phrase names (`scrape-docs`)
- Skills use `allowed-tools`, agents use `tools` in frontmatter
