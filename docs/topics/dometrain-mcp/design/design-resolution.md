# Design resolution — dometrain-mcp

outcome: early-exit
tier: B (light design)

## Reason

No new types, data model, or module topology to design. The plugin's entire shape is Claude Code's
own plugin-manifest schema (`plugin.json`, `.mcp.json`, `SKILL.md` frontmatter) — a configuration
surface, not a software architecture. Every structural choice was already resolved by direct
precedent read during `/discovery:explore` (`plugins/miro` for `userConfig` + `defaultEnabled` +
setup-only skill shape; `plugins/context7` for the `update`-verb vendor/sync-baseline pattern) and
confirmed live against `code.claude.com/docs/en/plugins-reference` during `/discovery:research`.

The one genuinely new element — vendoring + sync-tracking Dometrain's own `dometrain-grounding` skill
content — is not a type-design question either; it's a direct application of `context7`'s already-
built `update.sh` script pattern (`plugins/context7/skills/lookup/scripts/update.sh` +
`context/update.md`), substituting Dometrain's single upstream URL for Upstash's two.

Type sketch (for completeness, not because modeling was needed):

| Artifact | Shape | Source |
|---|---|---|
| `plugin.json` | Claude Code plugin manifest schema, `userConfig.dometrain_api_key` (string, sensitive, required), `defaultEnabled: false` | `miro`'s `plugin.json`, adapted |
| `.mcp.json` | One `http`-type MCP server entry, `headers.Authorization` substituting `${user_config.dometrain_api_key}` | `plugins-reference` `headers`-substitution confirmation (RESEARCH.md) |
| `skills/setup/SKILL.md` | `check`-only setup skill, uniform contract frontmatter | `miro`'s `skills/setup/SKILL.md`, adapted (`/mcp` status check replaces live-tool-call check) |
| `skills/grounding/SKILL.md` + `vendor/SKILL.md` + `scripts/update.sh` | Usage-guidance skill seeded from and diff-tracked against Dometrain's upstream skill | `context7`'s `skills/lookup/{SKILL.md,vendor/,scripts/update.sh}`, adapted (one upstream URL, no CLI-version check) |

No `design-threads.md` produced — nothing to resolve beyond confirming this table maps 1:1 onto
existing precedent, which `/planning:plan` verifies during Step 2.
