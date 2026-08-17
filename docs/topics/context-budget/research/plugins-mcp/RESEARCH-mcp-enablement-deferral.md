---
topic: plugins-mcp-context-budget
section: mcp-enablement-deferral
abstract: MCP has two unrelated enable/disable key pairs — `enabledMcpjsonServers`/`disabledMcpjsonServers` (settings, .mcp.json approval) and `enabledMcpServers`/`disabledMcpServers` (~/.claude.json, per-project connection toggle) — and tools are deferred by default so a disabled server usually saves no context.
claims:
  - claim: "`enabledMcpjsonServers`, `disabledMcpjsonServers` and `enableAllProjectMcpServers` are current spellings in the settings reference and govern APPROVAL of servers defined in a project's .mcp.json, not connection state generally."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/settings#available-settings"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/mcp#disable-a-server-without-removing-it"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "binary-extracted /doctor bundled-skill prompt, 'Disable mechanics' block"
        tier: 0
        pool: "installed Claude Code v2.1.232 binary"
  - claim: "A separate, disjoint pair `disabledMcpServers`/`enabledMcpServers` lives per-project in ~/.claude.json and is what the /mcp toggle writes; the docs state explicitly that the two pairs are unrelated."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/mcp#disable-a-server-without-removing-it"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "binary-extracted /doctor bundled-skill prompt, 'Disable mechanics' block"
        tier: 0
        pool: "installed Claude Code v2.1.232 binary"
      - url: "claude -p '/mcp' output: 'Usage: /mcp [reconnect|enable|disable [<server>|all]]'"
        tier: 0
        pool: "installed Claude Code v2.1.232 on this machine"
  - claim: "MCP tool schemas are deferred by default via tool search; only tool names and server instructions load at session start."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/costs#reduce-mcp-server-overhead"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "claude -p '/context' showing a distinct 'System tools (deferred)' row (v2.1.232)"
        tier: 0
        pool: "installed Claude Code v2.1.232 on this machine"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (auto mode default, alwaysLoad entries)"
        tier: 1
        pool: "anthropics/claude-code GitHub repository"
produced_by: phase-1-phase-2-phase-3
---

# Q3 — MCP servers: enable/disable keys, scopes, and deferral

Docs fetched **2026-08-17**; CLI output from **Claude Code v2.1.232**, run 2026-08-17.

## The critical gotcha: there are TWO disjoint key pairs

This is the single easiest thing to get wrong, and the docs say so in as many words:

> "`disabledMcpServers` and `enabledMcpServers` are unrelated to `enabledMcpjsonServers` and
> `disabledMcpjsonServers`, which control approval of servers defined in a project's `.mcp.json`
> file."
> — <https://code.claude.com/docs/en/mcp#disable-a-server-without-removing-it> (fetched 2026-08-17)

| Key | Exact spelling | Lives in | Scope | What it does |
|---|---|---|---|---|
| approve `.mcp.json` servers | `enabledMcpjsonServers` | settings files (user/project/local/managed) | settings scopes | "List of specific MCP servers from `.mcp.json` files to approve" |
| reject `.mcp.json` servers | `disabledMcpjsonServers` | settings files | settings scopes | "List of specific MCP servers from `.mcp.json` files to reject" |
| approve all | `enableAllProjectMcpServers` | settings files | settings scopes | "Automatically approve all MCP servers defined in project `.mcp.json` files" |
| per-project opt-out | `disabledMcpServers` | `~/.claude.json`, project entry | **per project**, not a settings scope | Opt-out for user-configured servers, plugin servers, claude.ai connectors, and default-on built-ins |
| per-project opt-in | `enabledMcpServers` | `~/.claude.json`, project entry | **per project** | Opt-in for built-in servers that default to off, e.g. `computer-use` |

Note the casing: **`Mcpjson`** (lowercase `json`), not `McpJson`. All three settings keys verified
against the settings reference table at <https://code.claude.com/docs/en/settings#available-settings>
(fetched 2026-08-17). The `~/.claude.json` pair verified against the mcp page and independently
against the `/doctor` skill's own disable mechanics.

**The two `~/.claude.json` lists are disjoint, not layered:**

> "Claude Code consults exactly one of the two lists for each server, so neither list overrides the
> other. If you add a regular server to `enabledMcpServers`, or a default-off built-in server to
> `disabledMcpServers`, Claude Code ignores the entry."

**A rejection wins over an approval:** "A `disabledMcpjsonServers` entry in any settings file still
rejects the server."

## What `/doctor` does (Tier 0 — the delegation-relevant mechanics)

From the binary-extracted `/doctor` prompt, 2026-08-17:

> "MCP server: user/local scope → `/mcp disable <server>` (persists to `"disabledMcpServers"` in the
> project entry of `~/.claude.json` — reversible with `/mcp enable`); project `.mcp.json` server →
> add its name to `"disabledMcpjsonServers"` in `.claude/settings.local.json`. The `/mcp disable`
> toggle is per-project: even for a user-scope server it applies to the current project only […]
> Never use `claude mcp remove` to disable: it permanently deletes the server config (env vars,
> headers) and wipes its OAuth tokens."

**`/mcp disable` is per-project.** A skill that wants a machine-wide MCP trim must repeat it per
project directory, or use `disabledMcpjsonServers` where applicable. This is a genuine gap in the
native surface.

## MCP configuration scopes and precedence

Distinct from the settings scopes. From <https://code.claude.com/docs/en/mcp#mcp-installation-scopes>
and `#scope-hierarchy-and-precedence` (fetched 2026-08-17):

| Scope | Location | `claude mcp add -s` |
|---|---|---|
| Local | `~/.claude.json`, per-project entry | `local` (**default**) |
| Project | `.mcp.json` at repo root | `project` |
| User | `~/.claude.json` top level | `user` |
| Plugin-provided | plugin's `.mcp.json` / `plugin.json` | n/a — install/uninstall the plugin |
| claude.ai connectors | account | n/a |

Precedence, verbatim:

> "When the same server is defined in more than one place, Claude Code connects to it once, using
> the definition from the highest-precedence source. The entire server entry from that source is
> used; fields are not merged across scopes.
>
> 1. Local scope 2. Project scope 3. User scope 4. Plugin-provided servers 5. claude.ai connectors
> The three scopes match duplicates by name. Plugins and connectors match by endpoint, so one that
> points at the same URL or command as a server above is treated as a duplicate."

Tier-0 confirmation of the flag values (v2.1.232, 2026-08-17):
`claude mcp add --help` → `-s, --scope <scope>  Configuration scope (local, user, or project) (default: "local")`.

## Are MCP tools deferred by default? Yes — with named exceptions

> "Tool search keeps MCP context usage low by deferring tool definitions until Claude needs them.
> Only tool names and server instructions load at session start, so adding more MCP servers has
> minimal impact on your context window."
> — <https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search> (fetched 2026-08-17)

`ENABLE_TOOL_SEARCH` matrix, verbatim from the same page:

| Value | Behavior |
|---|---|
| (unset) | All MCP tools deferred and loaded on demand. Falls back to loading upfront on Google Cloud's Agent Platform models earlier than the Claude 4.5 generation, when `ANTHROPIC_BASE_URL` is a non-first-party host, or on a Microsoft Foundry deployment hosted on Azure |
| `true` | All MCP tools deferred, except the Foundry-on-Azure and older-Vertex cases |
| `auto` | Threshold: load upfront while definitions total < 10% of the context window; defer all once they reach 10% |
| `auto:N` | Same with a custom percentage, N = 0–100 |
| `false` | All MCP tools loaded upfront, no deferral |

**Requires a model that supports `tool_reference` blocks: Claude Sonnet 4.5, Haiku 4.5, Opus 4.5, and
later.** Also: `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` keeps tool search off and `ENABLE_TOOL_SEARCH`
cannot override that.

### The per-server opt-out: `alwaysLoad`

> "If a server's tools should always be visible to Claude without a search step, set `alwaysLoad` to
> `true` in that server's configuration. Every tool from that server then loads into context at
> session start regardless of the `ENABLE_TOOL_SEARCH` setting."
> — <https://code.claude.com/docs/en/mcp#exempt-a-server-from-deferral> (fetched 2026-08-17)

Also per-tool: an MCP server can mark individual tools with `"anthropic/alwaysLoad": true` in the
tool's `_meta` object. And `alwaysLoad: true` **makes startup wait** for that server's tools (capped
at the 5s connect timeout).

Corroborated independently by the upstream changelog fetched from GitHub this turn:
"Added `alwaysLoad` option to MCP server config — when `true`, all tools from that server skip
tool-search deferral and are always available"
(<https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md>, fetched 2026-08-17).

### The operational rule a trimming skill must encode

From `/doctor`'s Check 1 (Tier 0, binary-extracted 2026-08-17) — this is the most decision-relevant
paragraph in the whole research:

> "MCP tool schemas are deferred behind the ToolSearch tool by default: only the tool *name* sits in
> context; the schema is fetched on demand and costs nothing up front. Check your own context to
> verify: deferred tools appear as a names-only list in a system-reminder, while resident tools have
> full schemas in your tool list. **Never report a token cost for deferred MCP tools, and never
> recommend disabling an MCP server to 'save context' when its tools are deferred** — for those,
> invocation count is the only signal. Deferral is a context-accounting fact, not a keep verdict:
> tool calls still land in transcripts […] so a deferred server with zero invocations in the window
> still gets a disable recommendation — framed as decluttering (one less connection to maintain,
> authenticate, and keep updated), never as token savings."

## Falsification result — the hypothesis survives, but narrowly

The mandatory falsification query targeted "MCP tools are deferred by default, so disabling a server
rarely saves context." It found a **real counter-case**:

- **anthropics/claude-code issue #40314** — "[BUG] Tool Search (`ENABLE_TOOL_SEARCH`) does not defer
  HTTP/Streamable HTTP MCP tools — 120K tokens loaded upfront on every session"
  (<https://github.com/anthropics/claude-code/issues/40314>, fetched 2026-08-17). Reported against
  **v2.1.86** (also reproduced on v2.1.85), with `ENABLE_TOOL_SEARCH=auto:5`. Measured 290 tokens
  without the HTTP gateway vs **120.2K tokens (60.1% of context)** with it. **Closed as not
  planned.**
- **anthropics/claude-code issue #25894** — "MCP tools not loaded as deferred tools when using
  mcp-remote proxy" (surfaced by search 2026-08-17; not fetched individually).

**Verdict:** the documented default stands and is confirmed by the current docs, the changelog, and
live `/context` output on v2.1.232. But deferral has had **transport- and proxy-specific failure
modes**, and #40314 was closed without a fix. I could not confirm whether the HTTP-transport case is
resolved in 2.1.23x — the changelog entries I found about tool search since then concern Vertex AI,
mid-turn connections and proxy detection, not HTTP-transport deferral.

**Design consequence:** a trimming skill must **measure deferral, never assume it.** `/doctor`
prescribes exactly that ("Check your own context to verify"), and `/context` exposes a distinct
`System tools (deferred)` row that makes the check mechanical.

## Managed MCP

`managed-mcp` (fetched 2026-08-17) exposes `allowedMcpServers` / `deniedMcpServers` as managed-tier
allow/deny lists — a policy layer above the enablement keys above. A single invalid entry used to
discard all managed policy; per the changelog the bad entry is now dropped with a `claude doctor`
warning.

## What I could NOT verify

- Whether issue #40314's HTTP-transport deferral failure is fixed as of 2.1.232/2.1.233. Sources
  checked: the docs `mcp.md` page, `code.claude.com/docs/en/changelog`, the upstream raw
  `CHANGELOG.md`, and the issue thread itself. Unchecked: the issue's full comment history beyond
  the WebFetch summary, and any PR that references it.
- Whether `alwaysLoad` is settable on a *plugin-provided* server's `.mcp.json` in the same way. The
  doc says "The `alwaysLoad` field is available on all server types" (transport types), and plugin
  servers use "Standard MCP server configuration", which strongly implies yes — but no source states
  it for plugin servers explicitly.
