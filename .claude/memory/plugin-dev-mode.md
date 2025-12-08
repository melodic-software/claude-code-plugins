# Plugin Development Mode

**Token Budget:** ~1,200 tokens | **Load Type:** Context-dependent (load when developing plugins)

## Problem: Installed Plugin vs Development Repository

When plugins are installed via `/plugin install`, Claude Code uses scripts from the **installed plugin location** (typically `~/.claude/plugins/marketplaces/...`), not from your development repository.

This means:

- Script changes in your dev repo are **not used** by default
- Scraping/validation runs against the installed plugin's code
- Your local changes appear to have no effect

## Solution: Dev Mode Environment Variables

Each plugin with scripts that write to disk supports a dev mode environment variable that redirects all operations to your development repository.

**IMPORTANT:** Claude's Bash tool uses **Git Bash (MINGW64)** on Windows, not PowerShell. Always use Bash inline prefix syntax when running commands through Claude Code.

### Claude Ecosystem Plugin (docs-management skill)

**Environment Variable:** `OFFICIAL_DOCS_DEV_ROOT`

**CRITICAL:** Environment variables do NOT persist across Claude's Bash tool calls. Each command runs in a fresh shell. You must set the env var in the SAME command that runs the script.

**Bash syntax (use this in Claude Code):**

```bash
# Inline prefix - env var active only for this command
OFFICIAL_DOCS_DEV_ROOT="<repo-root>/plugins/claude-ecosystem/skills/docs-management" python <script-path>
```

**PowerShell syntax (for native PowerShell terminal only):**

```powershell
# Set env var AND run script in same command - ONLY works in native PowerShell, NOT in Claude Code
$env:OFFICIAL_DOCS_DEV_ROOT = "<repo-root>/plugins/claude-ecosystem/skills/docs-management"; python <script-path>
```

**Why this matters:** Claude's Bash tool spawns a fresh shell for each command, and on Windows it uses Git Bash (MINGW64), not PowerShell. PowerShell syntax like `$env:VAR` will not work in Claude Code.

**Verification:** Scripts will display `[DEV MODE]` banner when dev mode is active:

```text
[DEV MODE] Using development skill directory:
  <repo-root>/plugins/claude-ecosystem/skills/docs-management
  Set via: OFFICIAL_DOCS_DEV_ROOT
```

### Google Ecosystem Plugin (gemini-cli-docs skill)

**Environment Variable:** `GEMINI_DOCS_DEV_ROOT`

```bash
# Bash syntax (use this in Claude Code)
GEMINI_DOCS_DEV_ROOT="<repo-root>/plugins/google-ecosystem/skills/gemini-cli-docs" python <script-path>
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

| Plugin           | Skill           | Env Var                  | Scripts Affected                                                                  |
| ---------------- | --------------- | ------------------------ | --------------------------------------------------------------------------------- |
| claude-ecosystem | docs-management | `OFFICIAL_DOCS_DEV_ROOT` | `scrape_docs.py`, `scrape_all_sources.py`, `refresh_index.py`, `rebuild_index.py` |
| google-ecosystem | gemini-cli-docs | `GEMINI_DOCS_DEV_ROOT`   | `scrape_docs.py`, `scrape_all_sources.py`, `refresh_index.py`, `rebuild_index.py` |

## Claude Code Session Behavior

**Important:** When running scripts from within Claude Code:

1. **Claude's Bash tool uses Git Bash (MINGW64) on Windows** - not PowerShell
2. **Env vars do NOT persist** between Bash tool calls
3. **Always use Bash inline prefix syntax** - `VAR="value" command`
4. **Do NOT use PowerShell syntax** - `$env:VAR` will not work in Claude Code
5. **Verify mode banner** - if you see `[PROD MODE]`, the env var was not applied
6. **Alternative:** Set env var in terminal BEFORE starting Claude Code session

### Example: Correct Usage in Claude Code

```bash
# CORRECT - Bash inline prefix syntax
OFFICIAL_DOCS_DEV_ROOT="<repo-root>/plugins/claude-ecosystem/skills/docs-management" python <repo-root>/plugins/claude-ecosystem/skills/docs-management/scripts/core/scrape_all_sources.py --parallel
```

```bash
# WRONG - PowerShell syntax does not work in Claude Code's Bash tool
$env:OFFICIAL_DOCS_DEV_ROOT = "..."; python script.py  # <-- Will fail!
```

```bash
# WRONG - env var lost between commands
export OFFICIAL_DOCS_DEV_ROOT="..."
# ... later, in separate Bash call ...
python scripts/core/scrape_all_sources.py  # <-- env var NOT set here!
```

## Debugging Tips

1. **Check mode banner:** Look for `[DEV MODE]` or `[PROD MODE]` in script output
2. **Verify paths:** Scripts log the canonical directory they're using
3. **Check git status:** After running, `git status` should show changes in your repo
4. **Wrong env var name?** Each skill uses a different env var - check the table above
5. **PROD MODE when expecting DEV?** The env var was not set - use inline syntax

**Last Updated:** 2025-12-06
