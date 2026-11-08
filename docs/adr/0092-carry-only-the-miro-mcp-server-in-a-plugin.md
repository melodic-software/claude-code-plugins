# Carry only the Miro MCP server in a plugin

- Status: accepted
- Date: 2026-07-12
- Related: the carry discriminator in
  [MCP servers as a plugin component](../migration-playbook.md#mcp-servers-as-a-plugin-component-carry-decision);
  the miro trust accept in
  [ADR 0093](0093-record-plugin-acceptance-security-reviews.md#review-record-miro-first-party-mcp-server-accept-2026-07-12)

## Context

medley's `.mcp.json` declared 14 MCP servers when the plugin migration began. A plugin-shipped server
auto-connects whenever the plugin is enabled, and a stdio one spawns a local process in every such
session, so each server needed a verdict on whether a plugin carries it. The verdict is
*plugin-carry*, not "is the server useful", and comes from the playbook's uniform discriminator
(CLI-first, SHIP, STAY degraded-but-functional, STAY medley-bound).

## Decision

**Decision table for medley `.mcp.json` (14 servers, audited 2026-07-12).** `enabled`/`disabled` =
medley `.claude/settings.json` `enabledMcpjsonServers`/`disabledMcpjsonServers` at audit time.

| Server | Transport | Secret | Verdict | Basis |
|---|---|---|---|---|
| miro | stdio (bundled) | `miro_api_token` (`sensitive`) | **SHIP (cutover+bundle)** | Owner-confirmed 2026-07-12: ships as a **dedicated** `miro` plugin whose whole capability *is* the Miro board server, so it is *useless without the server* (rule 2), not event-storming's optional dependency (event-storming stays degraded-but-functional and ships no server, consuming miro only when connected). The server's TypeScript **relocates** out of `mcp-servers/miro/node` into `plugins/miro/server` (single source of truth, no copy left behind; one level below the plugin root since 2026-09-11 so no plugin-root lockfile triggers the automatic `npm ci` in a consumer's plugin cache), bundled to one `server/dist/index.min.js` invoked as `node ${CLAUDE_PLUGIN_ROOT}/server/dist/index.min.js` (sidesteps #58510); `MIRO_API_TOKEN` → `userConfig` `miro_api_token` (`sensitive`, Claude secure credential storage); `defaultEnabled: false` so it never auto-starts unasked. First instance of the SHIP convention |
| aspire | stdio (`aspire` native) | none | STAY | medley .NET Aspire orchestration; no general-purpose plugin; infra-bound |
| azure | stdio | `AZURE_CLIENT_SECRET`… | STAY (disabled) | Infra opt-in; disabled (auth-isolation issues); not a plugin concern |
| azure-devops | stdio | `AZURE_DEVOPS_PAT` | STAY (disabled) | Infra opt-in PAT workflow; disabled; work-item tooling uses `gh`, not ADO |
| ccusage | stdio | none | STAY | Live consumer `/harness-ops:observability`; CLI covers the need (rule 1) and harness-ops is multi-skill, so shipping would spawn it for changelog/troubleshooting sessions. CLI-first is the preferred future direction |
| chrome-devtools | stdio | none | STAY | Ad-hoc browser/debug; stateful; no migrating plugin structurally requires it (degraded-but-functional) |
| context7 | http | `CONTEXT7_API_KEY` | STAY (CLI-first) | context7 plugin ships `ctx7`; HTTP MCP kept repo-level as fallback |
| github-events | stdio (repo-built) | `GITHUB_EVENTS_SECRET` | STAY | Repo-local broker; stateful `activeFilter`; repo identity via `CLAUDE_PROJECT_DIR`, so not repo-agnostic |
| microsoft-learn | http | none | STAY | `/discovery:research` + .NET docs; no plugin structurally requires it; degrades to WebSearch/WebFetch |
| nuget | stdio (`dotnet dnx`) | none | STAY | `/packages` + .NET; no dotnet/packages plugin in the locked slugs; .NET-scoped |
| openai-developer-docs | http | none | STAY | codex/OpenAI research; degraded-but-functional |
| perplexity | stdio | `PERPLEXITY_API_KEY` | STAY | `/discovery:research` + ai-briefing; multi-consumer, degrades gracefully, and shipping would auto-spawn for all discovery sessions |
| playwright | stdio | none | STAY (CLI-first, disabled) | playwright plugin ships `@playwright/cli`; MCP disabled in medley in its favor |
| ref | http | `REF_API_KEY` | STAY | `/discovery:research` doc search; degraded-but-functional |

**SHIP: 1. STAY: 13. DROP: 0.** Only `miro` clears the SHIP bar, and only once reframed as its own
dedicated plugin (rule 2). The other 13 are CLI-first, degraded-but-functional (their consumer plugin
already runs without them), or infra-bound. Every STAY server has a live consumer; the three disabled
entries are deliberate documented opt-ins, not dead servers. firecrawl already migrated to
`firecrawl-cli` (absent from `.mcp.json`), so it confirms rule 1 rather than being a 15th row.

**Secret mapping for the credentialed servers.** `MIRO_API_TOKEN` → `miro_api_token` (stdio, `env`),
`PERPLEXITY_API_KEY` → `perplexity_api_key` (stdio, `env`), `REF_API_KEY` → `ref_api_key` (HTTP,
`headers`), `CONTEXT7_API_KEY` → `context7_api_key` (HTTP, `headers`). Infra/medley-bound secrets
(`AZURE_*`, `AZURE_DEVOPS_PAT`, `GITHUB_EVENTS_SECRET`) do not map, so those servers stay
repo-level.

**miro: the closest call.** miro initially landed STAY when weighed as event-storming's optional
dependency. The owner's 2026-07-12 direction reframed it: the Miro board capability becomes a
**dedicated** `miro` plugin, and a dedicated server-wrapper plugin is useless without its server
(rule 2 → SHIP). The original STAY objection, that bundling would auto-start a credentialed MCP for
every event-storming session, is dissolved by `defaultEnabled: false` (the plugin installs disabled;
event-storming keeps its structured-markdown default and consumes miro only when a consumer opts in).
The mechanism is **cutover + bundle**: relocate the server's source into the plugin (the playbook's
reintegration end-state, where the repo drops its in-repo copy), single-file esbuild bundle,
`node <server>` over stdio, with no npm/registry publish, no consumer token wall, and no `npx`
(#58510).

## Consequences

- `miro` is the only marketplace plugin that ships an MCP server. Its first-party trust accept is
  the miro record in [ADR 0093](0093-record-plugin-acceptance-security-reviews.md).
- The miro SHIP ratified the two bundling mechanisms the discriminator's rule 2 names.
