# RESEARCH — claude.ai connectors in Claude Code

## Task restatement

Establish, for the author of a new marketplace skill that inventories and trims a session's fixed
startup context payload, what a claude.ai connector actually is in Claude Code, how it loads, what it
costs in context, and every supported way to disable or scope it — each claim carrying its source URL
and fetch date, with unverified material marked rather than filled in from recall.

Six questions were asked and all six are answered below. **Research date: 2026-08-17.** Claude Code
latest published release at that date: **2.1.233** (2026-08-14); local build inspected: **2.1.232**.

## Headline answer

A connector is **not a distinct mechanism**. It is an MCP server whose configuration lives in the
user's claude.ai account instead of a local file, occupying the lowest rung of the same MCP scope
hierarchy. Its tools reach the model by the same path as any MCP server's — **deferred behind tool
search by default**, so only names and server instructions enter the prefix — and `/context`
therefore folds it into the **`MCP tools`** row, with no connectors row anywhere. There are **seven**
supported disable/scope mechanisms with sharply different scopes. Disabling is in-session only via
the `/mcp` toggle; the settings key's timing is undocumented. Prompt-cache behavior is officially
documented and is **conditional on deferral state** — cache-neutral by default, whole-cache
invalidating in exactly the configurations that also make connectors context-expensive.

## Sidecar abstracts

- **`RESEARCH-connector-identity.md`** — A connector is an MCP server whose config lives in the
  user's claude.ai account rather than in Claude Code — same mechanism, different configuration
  source and a distinct internal transport type.
- **`RESEARCH-tool-loading-path.md`** — Connector tools are deferred behind tool search by default;
  only names and server instructions enter the prefix; `ENABLE_TOOL_SEARCH`, `alwaysLoad`,
  gateway/provider support and `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` decide otherwise.
- **`RESEARCH-context-attribution.md`** — `/context` has no connectors row — connectors are folded
  into the `MCP tools` category (or `MCP tools (deferred)`), with a per-tool breakdown keyed by
  server under `### MCP Tools` in `/context all`.
- **`RESEARCH-disable-and-scope.md`** — Seven supported mechanisms —
  `disableClaudeAiConnectors`, `ENABLE_CLAUDEAI_MCP_SERVERS`, the `/mcp` per-project toggle writing
  `disabledMcpServers`, `deniedMcpServers`/`allowedMcpServers`, `managed-mcp.json` with
  `allowAllClaudeAiMcps`, and `--mcp-config`/`--strict-mcp-config` — each with a distinct scope and
  precedence.
- **`RESEARCH-reversibility.md`** — The `/mcp` toggle acts in-session and persists per project;
  whether `disableClaudeAiConnectors` applies mid-session is **not** documented and the two relevant
  pages point opposite ways — treat it as restart-required.
- **`RESEARCH-prompt-cache.md`** — Official and specific: deferred connector tools never enter the
  cached prefix so connect/disconnect is cache-safe, but any connector whose tools load upfront
  invalidates the entire cache on every change.
- **`RESEARCH-gaps-and-unverified.md`** — Eight things this run could NOT verify, each naming the
  sources checked and the sources left unchecked, plus one near-miss where a summarizer inverted a
  documented semantic.
- **`RESEARCH-fetch-log.md`** — The written per-claim fetch record with artifact-ladder rungs and
  outcomes, plus the recency-gate verdict against Claude Code 2.1.233.

## Section → file + anchor

| Question | Section | File | Anchor |
|---|---|---|---|
| Q1 connector vs `.mcp.json` server | connector-identity | `RESEARCH-connector-identity.md` | `#q1--what-is-a-connector-versus-an-mcp-server-in-mcpjson` |
| Q2 how tools reach the model | tool-loading-path | `RESEARCH-tool-loading-path.md` | `#q2--how-does-a-connectors-tool-surface-reach-the-model` |
| Q3 `/context` attribution | context-attribution | `RESEARCH-context-attribution.md` | `#q3--what-does-context-attribute-connectors-to` |
| Q4 disable / scope mechanisms | disable-and-scope | `RESEARCH-disable-and-scope.md` | `#q4--every-supported-disable--scope-mechanism` |
| Q5 in-session vs restart | reversibility | `RESEARCH-reversibility.md` | `#q5--is-disabling-a-connector-reversible-in-session-or-does-it-need-a-restart` |
| Q6 prompt-cache invalidation | prompt-cache | `RESEARCH-prompt-cache.md` | `#q6--anything-official-about-connectors-and-prompt-cache-invalidation` |
| What could not be verified | gaps-and-unverified | `RESEARCH-gaps-and-unverified.md` | `#what-this-run-could-not-verify` |
| Evidence provenance + recency | fetch-log | `RESEARCH-fetch-log.md` | `#fetch-log` |
| Coverage ledger | — | `research-checklist.md` | — |

## Next-stage handoff

### Settled — the skill can say these

1. **Connectors are MCP servers.** Anthropic's glossary: "An MCP server added to your claude.ai
   account rather than configured in Claude Code." The skill should present them as a *source* of MCP
   servers, not a separate category.
2. **They are conditional on auth.** Connectors load only when a claude.ai subscription login is the
   active authentication method. On API-key, Bedrock, Vertex, `apiKeyHelper`, `ANTHROPIC_PROFILE` or
   `claude setup-token` sessions there are none. Check auth method first.
3. **Deferred by default.** Only tool names and server instructions load at startup; full schemas
   stay out of the system-prompt prefix. Adding connectors has minimal context impact in the default
   configuration.
4. **`/context` reports them under `MCP tools`** (`MCP tools (deferred)` when deferred), with `/mcp`
   as the row's action hint and `Loaded`/`Available` counts. Per-connector detail is only in
   `/context all` → `### MCP Tools` → `Server` column. There is no connectors row and no
   `connectorTokens` field.
5. **Seven disable mechanisms exist**, with exact spellings in `RESEARCH-disable-and-scope.md`. The
   two the skill will use most: `disableClaudeAiConnectors: true` (all connectors, any scope,
   any-source-true, honored even over a managed `false`) and the `/mcp` toggle (one connector, per
   project, writes `disabledMcpServers` in `~/.claude.json`).
6. **`enabledMcpjsonServers` / `disabledMcpjsonServers` / `enableAllProjectMcpServers` do NOT apply
   to connectors.** They govern `.mcp.json` approval only. Offering them as connector controls would
   be a factual error.
7. **Cache behavior is conditional and documented.** Deferred → connect/disconnect is cache-safe.
   Loaded-upfront → any change invalidates everything. The same switches control both context cost
   and cache cost.
8. **Measure, don't quote.** No first-party per-connector token figure exists. `/context all` is the
   measurement surface.

### Open decisions for the skill's author

1. **Does the skill promise in-session effect?** Only the `/mcp` toggle is documented to work live.
   Recommend defaulting to "restart required" for settings-key changes and saying so.
2. **Does the skill run in cloud/web sessions?** If so, `disableClaudeAiConnectors` and
   `deniedMcpServers` URL patterns are documented to be inert there. It needs a surface check.
3. **Will the skill use an `mcp__claude_ai_*` deny rule?** It is the cheapest primitive found —
   cache-neutral and live-reloading — but its behavior against the connector namespace specifically
   is inferred, not documented. Verify empirically before shipping.
4. **How does the skill resolve which binary is on `PATH`?** This machine had two installs four
   months apart with materially different key support. Version-gate every claim: `disableClaudeAiConnectors`
   needs v2.1.182+, `allowAllClaudeAiMcps` v2.1.149+, policy-entry expansion v2.1.219+.
5. **`CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` is the silent context multiplier.** It forces every MCP
   tool upfront and cannot be overridden by `ENABLE_TOOL_SEARCH`. Worth surfacing prominently.

### Verification request

Outcome-gate criteria 4 (≥2 independent corroborators per claim) and 7 (every accepted claim HIGH
confidence) are **not graded by this run** — they require a context that did not make these choices.
Per-claim `sources[]` with URL, tier and publishing pool are in every sidecar header so a verifier can
grade them off the artifact. **Read `RESEARCH-gaps-and-unverified.md` §8 first**: independence is
genuinely limited here, since documentation, API reference and the shipped binary all share the
Anthropic publishing pool, and only the GitHub-issue corroboration is independent.
