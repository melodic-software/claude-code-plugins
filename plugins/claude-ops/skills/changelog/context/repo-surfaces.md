# Repo surfaces for CC changelog integration

Surface categories to check when a CC changelog item lands. Referenced by `/changelog` (Phase 1 explore). The concrete file set varies per consumer repo — enumerate what exists (`ls`, `Glob`) before grepping; skip categories the repo doesn't have.

## Surface categories

### Project instructions and rules

| Surface | What to check |
|---|---|
| `CLAUDE.md` (+ `CLAUDE.local.md`) | CLI references, workflow guidance, feature mentions |
| `AGENTS.md` | Prerequisites, tool references |
| `.claude/rules/**/*.md` (when present) | Quirks/workaround docs keyed to CC behavior — behavioral changes may obsolete entries; new features may need new ones |

### Configuration

| Surface | What to check |
|---|---|
| `.claude/settings.json` (+ `settings.local.json`) | New `env` vars, permission patterns, hook entries, plugin config |
| `.mcp.json` | MCP server config changes |

### Hooks

| Surface | What to check |
|---|---|
| `.claude/hooks/**` and hook entries in settings | New hook events to handle, changed event schemas, changed env vars |

### Skills + Agents

| Surface | What to check |
|---|---|
| `.claude/skills/**/SKILL.md` | Frontmatter field changes, new capabilities to adopt |
| `.claude/agents/*.md` | Agent frontmatter changes, new isolation modes |

### Documentation

| Surface | What to check |
|---|---|
| Any repo docs that describe CC features (hook-event references, CLI cheat-sheets, onboarding docs) | Stale behavior descriptions, new capabilities worth documenting |

## Grep patterns for common changelog item types

Scope greps to the surfaces above (never repo-root unbounded):

```bash
# New setting/env var
grep -rn "<SETTING_NAME>" .claude/ CLAUDE.md AGENTS.md 2>/dev/null

# New hook event
grep -rn "<EVENT_NAME>" .claude/ docs/ 2>/dev/null

# New frontmatter field
grep -rn "<FIELD_NAME>" .claude/skills/ .claude/agents/ 2>/dev/null

# New CLI flag
grep -rn -- "<FLAG_NAME>" CLAUDE.md .claude/ docs/ 2>/dev/null
```
