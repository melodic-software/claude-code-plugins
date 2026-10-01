# Surface discovery and per-class examples for CC changelog integration

Referenced by `/claude-ops:changelog` (Phase 1 explore). `scripts/discover-surfaces.sh [root]` is the source of the surface list. It prints `repo-shape: marketplace|plugin|consumer`, then one line per class present with its count and glob. Explore runs it first and greps only the classes it prints. The tables below are examples of what a changelog item typically changes in each class, not a checklist: a class the script does not print does not exist here.

## Consumer classes

Printed for any repo. A standalone plugin (`.claude-plugin/plugin.json`, no marketplace) also prints its root-level `skills/`, `agents/`, `commands/` and `hooks/` classes; treat them as the plugin classes below.

| Class | What to check |
|---|---|
| `README.md`, `docs/**/*.md` | Onboarding and feature documentation that names a CC feature, flag, or workflow |
| `CLAUDE.md` (+ `CLAUDE.local.md`), `AGENTS.md` | CLI references, workflow guidance, feature mentions, prerequisites |
| `.claude/rules/**/*.md` | Quirk and workaround docs keyed to CC behavior. Behavioral changes may obsolete entries; new features may need new ones |
| `.claude/settings.json` (+ `settings.local.json`) | New `env` vars, permission patterns, hook entries, plugin config |
| `.mcp.json` | MCP server config changes |
| `.claude/hooks/**` | New hook events to handle, changed event schemas, changed env vars |
| `.claude/skills/**/SKILL.md`, `.claude/agents/*.md` | Frontmatter field changes, new capabilities or isolation modes to adopt |

## Marketplace classes

Printed in addition when `repo-shape` is `marketplace`.

| Class | What a changelog item typically changes |
|---|---|
| plugin skills and spokes | A frontmatter field, tool name, or documented behavior a skill body restates; a new capability a skill should adopt |
| plugin agents | Agent frontmatter fields, model or isolation behavior |
| plugin hook dirs | Hook event names, input schema, exit-code or output semantics |
| plugin READMEs | Feature descriptions that went stale or a component list that gained an entry |
| conventions (`docs/conventions/*/README.md`) | A repo rule that restates CC behavior the item changed |
| upstream ledgers (`docs/upstream/*.md`) | The drift marker and rows for the release the item lands in |
| native-surfaces store (`docs/native-surfaces/`) | A built-in command, tool, or bundled skill the item adds, renames, or removes |
| official-docs index, repo scripts | A docs URL that moved; a script that shells out to a changed CLI flag |

The vendor exclusion the script reports is deliberate: vendored upstream docs are reference material, not something to edit.

## Grep patterns for common changelog item types

Scope each grep to the classes the script printed (never repo-root unbounded). Substitute the printed globs for the paths below:

```bash
# New setting/env var
grep -rn "<SETTING_NAME>" .claude/ CLAUDE.md AGENTS.md 2>/dev/null

# New hook event
grep -rn "<EVENT_NAME>" .claude/ docs/ plugins/*/hooks/ 2>/dev/null

# New frontmatter field
grep -rn "<FIELD_NAME>" .claude/skills/ .claude/agents/ plugins/*/skills/*/SKILL.md plugins/*/agents/ 2>/dev/null

# New CLI flag
grep -rn -- "<FLAG_NAME>" CLAUDE.md .claude/ docs/ 2>/dev/null
```
