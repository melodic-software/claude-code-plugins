---
topic: tool-definitions-prefix-pruning
section: deferral-controls
abstract: "Deferral is controlled by the ENABLE_TOOL_SEARCH env var (unset/true/auto/auto:N/false) and opted out per-server or per-tool via alwaysLoad; there is no settings.json key for either, and no experimental flag beyond CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS."
claims:
  - claim: "ENABLE_TOOL_SEARCH is a real, documented environment variable with five documented values: unset, true, auto, auto:N, false."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/env-vars"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://code.claude.com/docs/en/mcp#configure-tool-search"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://code.claude.com/docs/en/agent-sdk/tool-search#configure-tool-search"
        tier: 1
        pool: "Anthropic / code.claude.com"
  - claim: "alwaysLoad is a real, documented option that opts a tool INTO the prefix — at MCP server level in .mcp.json, and per-tool via the tool's _meta object as 'anthropic/alwaysLoad'."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/mcp#exempt-a-server-from-deferral"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://code.claude.com/docs/en/agent-sdk/typescript"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
        tier: 0
        pool: "anthropics/claude-code upstream repo"
  - claim: "There is NO settings.json key controlling tool-search deferral: settings.md contains zero occurrences of ENABLE_TOOL_SEARCH, alwaysLoad, toolSearch, or disallowedTools."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://code.claude.com/docs/en/settings.md (grep over full raw page, 334KB, 2026-08-17)"
        tier: 0
        pool: "Anthropic / code.claude.com (raw markdown, parsed locally)"
  - claim: "'disabledTools' is NOT a documented Claude Code settings key; it appears in user bug reports but in none of the 21 first-party doc pages fetched."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "grep for 'disabledTools' across 21 fetched first-party doc pages, 2026-08-17"
        tier: 0
        pool: "Anthropic docs corpus (parsed locally)"
      - url: "https://github.com/anthropics/claude-code/issues/30480"
        tier: 2
        pool: "GitHub / anthropics-claude-code issue tracker"
produced_by: phase-2-3
---

# Settings that control deferral

The topic asked to verify names like `alwaysLoad`, tool-search settings, and an experimental flag
**against current docs rather than assuming they exist**. Verdict: `alwaysLoad` and a tool-search
control both exist and are documented; the tool-search control is an **environment variable, not a
settings.json key**; and there is a separate experimental-beta flag that acts as an override-proof
kill switch.

## 1. `ENABLE_TOOL_SEARCH` — the deferral master control (env var)

Documented on three first-party pages, all fetched 2026-08-17. Canonical row from
`https://code.claude.com/docs/en/env-vars`:

> `ENABLE_TOOL_SEARCH` — Controls MCP tool search. Unset, Claude Code defers all MCP tools by
> default. It still loads them upfront on Google Cloud's Agent Platform models earlier than the
> Claude 4.5 generation, on a Microsoft Foundry deployment hosted on Azure, and when
> `ANTHROPIC_BASE_URL` points to a non-first-party host. `true` always defers and sends the beta
> header… `auto` loads upfront when tool definitions fit within 10% of context. `auto:N` sets a
> custom threshold, such as `auto:5` for 5%. `false` loads all tools upfront. A value you set
> yourself is ignored when `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` is set.

The five values, from `https://code.claude.com/docs/en/agent-sdk/tool-search#configure-tool-search`:

| Value | Behavior |
|---|---|
| (unset) | Tool search on. Definitions deferred and discovered on demand. Falls back to upfront on the exception platforms. |
| `true` | Always on, except the Foundry-on-Azure and older-Agent-Platform exceptions. Sends the beta header through proxies; **requests fail on proxies that don't support `tool_reference` blocks**. |
| `auto` | "Counts the tokens in the tool definitions that tool search can defer and compares the total against the model's context window. When the total reaches 10% of the window, tool search activates. Below that, the SDK loads every tool definition into context upfront." |
| `auto:N` | Same with a custom percentage; `auto:5` activates at 5%. Lower values activate sooner. |
| `false` | Off. "All tool definitions are loaded into context on every turn." |

**`auto` is the direction a trimming skill would want to move, not away from.** Note what counts
toward the threshold: "each MCP tool that isn't marked `alwaysLoad`, from any server, plus the
built-in tools that load on demand. The SDK always loads core built-in tools such as Bash, Read, and
Edit upfront and doesn't count them toward the threshold."

In the Agent SDK this is set through the `env` option on `query()`, not a dedicated option —
"In TypeScript, `env` replaces the subprocess environment, so spread `...process.env`."

## 2. `alwaysLoad` — the opt-INTO-prefix escape hatch (real, three forms)

`https://code.claude.com/docs/en/mcp#exempt-a-server-from-deferral` (fetched 2026-08-17):

> If a server's tools should always be visible to Claude without a search step, set `alwaysLoad` to
> `true` in that server's configuration. Every tool from that server then loads into context at
> session start regardless of the `ENABLE_TOOL_SEARCH` setting. **Use this for a small number of
> tools that Claude needs on every turn, since each upfront tool consumes context that would
> otherwise be available for your conversation.**

> The `alwaysLoad` field is available on all server types. An MCP server can also mark individual
> tools as always-loaded by including `"anthropic/alwaysLoad": true` in the tool's `_meta` object,
> which has the same effect for that tool only.

Three forms, all documented:

| Form | Where | Scope |
|---|---|---|
| `"alwaysLoad": true` in the server entry | `.mcp.json` | every tool from that server |
| `"anthropic/alwaysLoad": true` in a tool's `_meta` | MCP server's own tool declaration | that one tool |
| `extras.alwaysLoad: true` on `tool()`, or `options.alwaysLoad` on an SDK MCP server | Agent SDK (TypeScript) | per tool / per server |

The SDK reference (`https://code.claude.com/docs/en/agent-sdk/typescript`, fetched 2026-08-17) words
the per-tool form precisely: "`alwaysLoad: true` keeps this tool's full schema in the initial prompt
instead of deferring it."

**Startup cost, and it is a real trade:** "Setting `alwaysLoad: true` also makes startup wait for the
server's tools, capped at the standard 5-second connect timeout, since they must be present when the
first prompt is built."

Provenance: added in **v2.1.121** — "Added `alwaysLoad` option to MCP server config — when `true`,
all tools from that server skip tool-search deferral and are always available"
(`https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`, fetched 2026-08-17).

There is a companion field for the other direction of quality, not quantity: `extras.searchHint`, "a
one-line capability phrase shown in the deferred-tool list" — it makes a deferred tool findable
without loading its schema.

## 3. `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` — the override-proof kill switch

From `https://code.claude.com/docs/en/env-vars` (fetched 2026-08-17):

> Set to `1` to strip Anthropic-specific `anthropic-beta` request headers and **beta tool-schema
> fields (such as `defer_loading` and `eager_input_streaming`) from API requests**. … Standard fields
> (`name`, `description`, `input_schema`, `cache_control`) are preserved. **MCP tool search is
> disabled and all MCP tools load upfront, even when you set `ENABLE_TOOL_SEARCH`.** On Claude Code
> v2.1.227 or later, managed settings can keep tool search on.

For the skill this is a **regression trap**: an org or proxy setup that sets this variable silently
converts every deferred definition into an upfront one, and no `ENABLE_TOOL_SEARCH` value undoes it.
A trimming skill should detect it and report it rather than recommending deferral into a session that
cannot defer.

## 4. What does NOT exist — checked, and reported as absence

Absences below were established by grepping the **full raw markdown** of each page, not by search:

- **No `settings.json` key for tool search.** `https://code.claude.com/docs/en/settings.md` (334 KB,
  fetched 2026-08-17) contains **zero** occurrences of `ENABLE_TOOL_SEARCH`, `alwaysLoad`,
  `toolSearch`, or `disallowedTools`. Its *Available settings*, *Permission settings*, and *Tools
  available to Claude* sections were read; the last is four sentences long and merely points at the
  tools reference. Deferral is env-var-and-`.mcp.json`-only.
- **No `disabledTools` key.** Zero occurrences across all 21 first-party pages fetched. It appears
  only in user-filed issues (below). A skill must not emit it.
- **No CLI flag for tool search.** The full flag table at
  `https://code.claude.com/docs/en/cli-reference` (fetched 2026-08-17) has no tool-search flag;
  `--tools`, `--allowedTools`, `--disallowedTools` are permission/availability flags, covered in
  `RESEARCH-permission-pruning.md`.

**Sources checked for these absences:** `settings`, `cli-reference`, `env-vars`, `mcp`,
`agent-sdk/tool-search`, `agent-sdk/typescript`, `plugins-reference`, `plugin-relevance`,
`sub-agents`, `permissions`, `agent-sdk/permissions`, `tools-reference`, `costs`, `context-window`,
`monitoring-usage`, `headless`, `interactive-mode`, `commands`, plus the upstream `CHANGELOG.md`.
**Sources left unchecked:** the ~165 other `code.claude.com/docs/en/` pages in the sitemap (notably
the gateway, Bedrock, Vertex, Foundry, and self-hosted-environment families), `managed-mcp`,
`server-managed-settings`, and the Python SDK reference.

## The `disabledTools` confusion, and why it does not falsify anything

Two upstream issues surface when searching this topic, and a skill author will hit them:

- `https://github.com/anthropics/claude-code/issues/30480` — "[BUG] disabled system tools still
  consume the context", **closed as not planned**. Reports that
  `{"disabledTools": ["EnterWorktree","NotebookEdit","Skill"]}` in `~/.claude/settings.json` left
  `/context` unchanged at 11.7k for system tools.
- `https://github.com/anthropics/claude-code/issues/66073` — "Feature: Allow disabling specific
  built-in tools to reduce context overhead", **closed as not planned, stale**. Asks for a
  `disabledTools` setting; claims ~30 built-ins cost 16,000+ tokens.

Both fetched 2026-08-17. **Neither contradicts the documented behavior**, because both used
`disabledTools` — a key Claude Code does not document and, on the evidence of #30480's own
observation, does not implement as a context-level control. The documented mechanism that *does*
remove definitions is a bare-name deny rule (`RESEARCH-permission-pruning.md`), which this run
verified empirically. Treat these issues as evidence about an **invented key**, not about
`disallowedTools` or `permissions.deny`.
