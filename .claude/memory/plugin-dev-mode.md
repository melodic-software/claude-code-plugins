# Plugin Development Mode

## Problem: Installed Plugin vs Development Repository

When plugins are installed via `/plugin install`, Claude Code uses scripts from the **installed plugin location** (typically `~/.claude/plugins/marketplaces/...`), not from your development repository.

This means:
- Script changes in your dev repo are **not used** by default
- Scraping/validation runs against the installed plugin's code
- Your local changes appear to have no effect

## Solution: Dev Mode Environment Variables

Each plugin with scripts that write to disk supports a dev mode environment variable that redirects all operations to your development repository.

### Claude Ecosystem Plugin (docs-management skill)

**Environment Variable:** `OFFICIAL_DOCS_DEV_ROOT`

```bash
# Set to your local skill directory
export OFFICIAL_DOCS_DEV_ROOT="D:/repos/gh/melodic/claude-code-plugins/plugins/claude-ecosystem/skills/docs-management"

# Then run scripts - they'll use your local code and write to your repo
python plugins/claude-ecosystem/skills/docs-management/scripts/core/scrape_all_sources.py --parallel --skip-existing
```

**PowerShell:**
```powershell
$env:OFFICIAL_DOCS_DEV_ROOT = "D:\repos\gh\melodic\claude-code-plugins\plugins\claude-ecosystem\skills\docs-management"
```

**Verification:** Scripts will display `[DEV MODE]` banner when dev mode is active:
```
[DEV MODE] Using development skill directory:
  D:\repos\gh\melodic\claude-code-plugins\plugins\claude-ecosystem\skills\docs-management
  Set via: OFFICIAL_DOCS_DEV_ROOT
```

### Google Ecosystem Plugin (gemini-cli-docs skill)

**Environment Variable:** `GEMINI_DOCS_DEV_ROOT`

```bash
export GEMINI_DOCS_DEV_ROOT="D:/repos/gh/melodic/claude-code-plugins/plugins/google-ecosystem/skills/gemini-cli-docs"
```

## When Dev Mode Is Required

Use dev mode when:
- Making changes to scraper scripts and testing them
- Running scrapes that should write to your dev repo (not installed plugin)
- Testing new features or fixes before publishing
- Any time you need script changes to take effect immediately

## When Dev Mode Is NOT Required

Skip dev mode when:
- Using the installed plugin as an end user
- Running validation/search that only reads (doesn't write)
- Testing that the published plugin works correctly

## Affected Skills/Scripts

| Plugin | Skill | Env Var | Scripts Affected |
|--------|-------|---------|------------------|
| claude-ecosystem | docs-management | `OFFICIAL_DOCS_DEV_ROOT` | `scrape_docs.py`, `scrape_all_sources.py`, `refresh_index.py`, `rebuild_index.py` |
| google-ecosystem | gemini-cli-docs | `GEMINI_DOCS_DEV_ROOT` | `scrape_docs.py`, `scrape_all_sources.py`, `refresh_index.py`, `rebuild_index.py` |

## Task Agent Considerations

When using Task agents to run scripts:
- Task agents inherit the parent environment
- Set the env var in your terminal BEFORE starting Claude Code
- Or pass it inline: `OFFICIAL_DOCS_DEV_ROOT="..." python script.py`

**Note:** Task agents spawned by skills/commands may not inherit env vars set mid-session. When in doubt, run scripts directly rather than through Task agents during development.

## Debugging Tips

1. **Check mode banner:** Look for `[DEV MODE]` or `[PROD MODE]` in script output
2. **Verify paths:** Scripts log the canonical directory they're using
3. **Check git status:** After running, `git status` should show changes in your repo
4. **Wrong env var name?** Each skill uses a different env var - check the table above

**Last Updated:** 2025-12-01
