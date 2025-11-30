# CLAUDE.md

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

## Discovery

- `/claude-ecosystem:list-skills` - list available skills
- `/claude-ecosystem:list-commands` - list available commands

## Conventions

- Skills: noun-phrase names (`hook-management`)
- Commands: verb-phrase names (`scrape-docs`)
- Skills use `allowed-tools`, agents use `tools` in frontmatter
