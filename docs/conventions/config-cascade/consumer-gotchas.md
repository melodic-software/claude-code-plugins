# Consumer-contributed gotchas (config-cascade tier)

Ratified by #3547. Extends the [config-cascade contract](README.md) with a **concatenating prose**
surface for skill-specific gotchas that consumers add without forking shipped plugin files.

## Problem

Many skills ship a `## Gotchas` section (failure-driven guidance the model reads when the skill
loads). Consumers need repo-specific lines without editing the plugin cache (lost on update) and
without parking them in root `CLAUDE.md` (wrong scope: every session pays for every gotcha).

## Pattern

| Tier | Where | Merge | Promotion |
|---|---|---|---|
| **Bundled** | Shipped `SKILL.md` `## Gotchas` or `context/gotchas.md` | baseline | generalizable lines → issue this marketplace |
| **Local (cascade)** | Participating plugin's config surface | **concatenate** after bundled gotchas at invocation | repo-specific only |
| **Upstream** | Shipped skill after curation | replaces/extends bundled | file an issue here when not repo-specific |

### Local tier resolution

A participating plugin reads consumer gotchas from either:

1. A `## Gotchas` section in its existing cascade file (for example `.claude/bugs.md`), or
2. A dedicated file `.claude/<plugin>/gotchas.md` when the plugin declares that path.

Layers follow the normal three-layer cascade (user-global, team, local overlay). **Form 1
(concatenate)** applies: every layer that exists is loaded and appended in layer order after the
bundled gotchas. Unknown keys in the YAML block of a shared config file stay inert; only the
Gotchas prose section participates.

Loads **only when the skill loads** (instruction-placement doctrine).

The **failure-driven-only rule binds consumer layers too**: a consumer line records a failure the
model actually hit in that repository, never speculative advice.

### Rejected alternatives (why not)

- **Setup writes consumer `CLAUDE.md` / `CLAUDE.local.md`:** session-wide cost; wrong loading scope.
- **Editing files under `CLAUDE_PLUGIN_DATA`:** lost on plugin update.
- **One global gotchas file across plugins:** wrong scope plus merge semantics the cascade already
  solves per surface.

## Participating plugins

| Plugin | Consumer path | Status on `main` |
|---|---|---|
| `bugs` | `.claude/bugs.md` `## Gotchas` | wired: `/bugs:scan` and `/bugs:write` pre-compute `scripts/concat-gotchas.sh` |

Plugins with an existing config surface (`source-control`, `codebase-health`) adopt the same shape
in their owner docs when wired.

## Authoring

`playbooks:skill-authoring` documents the bundled gotchas discipline and points here for the
cascade tier and promotion path.
