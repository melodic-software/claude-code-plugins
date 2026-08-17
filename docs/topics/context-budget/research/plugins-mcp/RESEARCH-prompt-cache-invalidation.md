---
topic: plugins-mcp-context-budget
section: prompt-cache-invalidation
abstract: Enabling or disabling a plugin never invalidates the prompt cache except through its MCP servers, and even then only when those tools load into the prefix rather than being deferred.
claims:
  - claim: "The prompt-caching page enumerates exactly eight cache-invalidating actions, of which 'Connecting or disconnecting an MCP server' and 'Enabling or disabling a plugin' are two."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/prompt-caching#actions-that-invalidate-the-cache"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/context-window (links prompt-caching as 'which actions invalidate the cached prefix')"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/commands (/reload-plugins row: warns and skips when reload would invalidate the prompt cache)"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
  - claim: "A plugin's skills, commands, agents, hooks, LSP servers, monitors and themes NEVER invalidate the cache; only its MCP servers can."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/prompt-caching#enabling-or-disabling-a-plugin"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "claude plugin details — hooks annotated 'harness-only — no model context cost'"
        tier: 0
        pool: "installed Claude Code v2.1.232 on this machine"
      - url: "https://code.claude.com/docs/en/commands (/reload-plugins --force gate exists only for the MCP-tool-change case)"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
  - claim: "Whether an MCP change invalidates the cache depends on deferral: deferred tools append only and keep the cache; prefix-loaded tools invalidate everything after them."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/prompt-caching#connecting-or-disconnecting-an-mcp-server"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md ('Global system-prompt caching now works when ToolSearch is enabled')"
        tier: 1
        pool: "anthropics/claude-code GitHub repository"
produced_by: phase-1
---

# Q4 — Prompt-cache invalidation

Source: <https://code.claude.com/docs/en/prompt-caching>, **fetched 2026-08-17** via the verbatim
`.md` page variant. All block quotes below are verbatim from that fetch.

## The mechanism, first

> "The API caches by matching the start of each request, called the prefix, against content it
> recently processed. On a normal turn, the prefix is the entire previous request and only the
> latest exchange is new. The match is exact, so a change anywhere in the prefix recomputes
> everything after it. There is no per-file or per-segment caching."

The layer table:

| Layer | Content | Changes when |
|---|---|---|
| System prompt | Core instructions, tool definitions, output style | The set of loaded tool definitions changes, or Claude Code is upgraded |
| Project context | CLAUDE.md, auto memory, unscoped rules | Session starts, or after `/clear` or `/compact` |
| Conversation | Your messages, Claude's responses, tool results | Every turn |

> "A change to the conversation layer leaves the system prompt and project context cached. A change
> to the system prompt invalidates everything, because all later content now sits behind a different
> prefix."

> "The prefix-match rule explains most of the behaviors on this page. Plan mode and skill loading,
> for example, append their instructions as conversation messages, so the cached prefix stays
> intact."

Also part of the cache key but not the prompt text: **model** and **effort level**.

## "Actions that invalidate the cache" — the full enumerated list, verbatim

> ## Actions that invalidate the cache
>
> These actions cause the next request to miss part or all of the cache. You see a one-time slower,
> more expensive turn, after which the new prefix is cached. Most of them are avoidable mid-task
> once you know they have a cost. A model switch can feel free until you notice the slower turn that
> follows.
>
> - Switching models
> - Changing effort level
> - Turning on fast mode
> - Connecting or disconnecting an MCP server
> - Enabling or disabling a plugin
> - Denying an entire tool
> - Compacting the conversation
> - Upgrading Claude Code

## "Connecting or disconnecting an MCP server" — verbatim

> Tool definitions sit in the system prompt layer, so the cache invalidates when the set of tool
> definitions in the request changes between turns. Toggling the advisor tool is an exception: its
> definition sits after the cache breakpoint, so enabling or disabling `/advisor` keeps the cached
> prefix intact. Whether an MCP server change does this depends on whether its tools are deferred by
> tool search or loaded into the prefix:
>
> - **Deferred tools**, the default on supported models: a server connecting, disconnecting, or
>   changing its tool list only appends new content and doesn't disturb anything already cached.
> - **Tools loaded into the prefix**: any change to them invalidates the cache. This happens when
>   tool search is unavailable or disabled, such as on Google Cloud's Agent Platform models earlier
>   than the Claude 4.5 generation, with a custom `ANTHROPIC_BASE_URL` gateway, or on a Microsoft
>   Foundry deployment hosted on Azure once Claude Code detects that the deployment rejects tool
>   search. It also happens for a server or tool marked `alwaysLoad`, and for definitions kept
>   upfront by threshold-based loading.
>
> When tools load into the prefix, the most common cause of an invalidation is a server connecting or
> disconnecting mid-session, which can happen without any action on your part: a stdio server's
> process exits, an HTTP session expires, or a server reconnects automatically after a transient
> failure. A connected server can also push a dynamic tool update that changes its tool list.
>
> Editing your MCP config does not by itself change the cache. The new config takes effect only after
> a restart, which is when the server connects or disconnects.

## "Enabling or disabling a plugin" — verbatim, in full

This is the section the topic asked for. Quoted complete:

> ### Enabling or disabling a plugin
>
> Plugins bundle several component types, and the cost of a change depends on which components the
> plugin provides. Skills, commands, agents, hooks, LSP servers, monitors, and themes never
> invalidate the cache: anything they add to the request is appended after the existing conversation,
> so the next request pays for the new content but still reads everything before it from the cache.
>
> The exception is a plugin that provides MCP servers. Enabling or disabling one follows the same
> rules as connecting or disconnecting an MCP server: the cache survives when the server's tools are
> deferred, and the next request re-reads the entire conversation when they load into the prefix.
>
> Plugin changes apply when you run `/reload-plugins` or start a new session. For a plugin with a
> `command` source, Claude Code can reload the plugin itself. Claude Code can also activate a plugin
> you install from the `/plugin` interface during the install; the install summary tells you whether
> it did or whether to run `/reload-plugins`. If that reload would trigger the full re-read below,
> the command warns first and applies when you rerun it with `--force`.
>
> The cost, whether appended announcements or a full re-read, shows up on the first turn after the
> change applies, not when you run `/plugin enable` or `/plugin disable`. When a reload would trigger
> the full re-read, `/reload-plugins` shows a warning and doesn't apply the reload. Pass `--force` to
> apply anyway.
>
> Disabling a plugin you enabled earlier in the session restores the previous request shape. If that
> prefix is still within its cache lifetime, the next request reads the older cache entry instead of
> rebuilding.

## Adjacent section a trimming skill will trip over: "Denying an entire tool"

> Adding a bare tool name like `Bash` or `WebFetch` as a deny rule removes that tool from Claude's
> context entirely. Built-in tool definitions load into the system prompt layer, so adding or
> removing one of these rules mid-session invalidates the cache. […]
>
> Only a deny rule that matches in the tool-name position has this effect: a bare tool name, the
> equivalent `Bash(*)` form, or a tool-name glob like `"*"`. A glob that matches only MCP tools, such
> as `"mcp__*"`, removes those tools the same way but leaves the cache intact when the matched tools
> are deferred, the default, since deferred definitions were never in the cached prefix.

**This matters for the skill's design:** `permissions.deny: ["mcp__*"]` is a *cache-safe* blanket MCP
trim under deferral, whereas denying a built-in tool name is not.

## Practical summary for the skill author

1. **Trimming plugins is nearly free, cache-wise.** Six of a plugin's seven component types never
   invalidate the cache.
2. **The one dangerous case is an MCP-providing plugin whose tools are prefix-loaded** — i.e.
   `alwaysLoad`, `ENABLE_TOOL_SEARCH=false`/threshold-upfront, a non-first-party
   `ANTHROPIC_BASE_URL`, older Vertex models, or Foundry-on-Azure.
3. **Claude Code already guards this seam.** `/reload-plugins` "warns and skips unless you pass
   `--force`" when the reload would change loaded MCP tools and invalidate the cache
   (<https://code.claude.com/docs/en/commands>, fetched 2026-08-17). A trimming skill should route
   through `/reload-plugins` and surface that warning rather than reimplement the check.
4. **Batch changes; defer application.** The cost lands "on the first turn after the change applies,
   not when you run `/plugin enable` or `/plugin disable`" — so a skill can make many enablement
   edits cheaply and let them apply at next session start.
5. **Re-enabling within the cache lifetime is free.** Toggling back restores the previous prefix and
   can hit the older cache entry.

## What I could NOT verify

- The exact **cache lifetime / TTL** value. The page has a "Cache lifetime" section referenced
  repeatedly, but I did not extract it; it is on the same page and is one fetch away.
- Whether `/reload-plugins --force` reports the projected invalidation cost numerically, or only
  warns. Sources checked: `commands.md`, `prompt-caching.md`, `plugins.md`,
  `discover-plugins.md`. Unchecked: the live interactive `/reload-plugins` output (this session
  could not run interactive slash commands).
