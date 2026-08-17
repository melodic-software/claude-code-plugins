---
topic: claude-ai-connectors-in-claude-code
section: disable-and-scope
abstract: Seven supported mechanisms — disableClaudeAiConnectors, ENABLE_CLAUDEAI_MCP_SERVERS, the /mcp per-project toggle writing disabledMcpServers, deniedMcpServers/allowedMcpServers, managed-mcp.json with allowAllClaudeAiMcps, and --mcp-config/--strict-mcp-config — each with a distinct scope and precedence.
claims:
  - claim: "disableClaudeAiConnectors is the settings key that turns off all claude.ai connectors; it is settable in any scope and uses any-source-true semantics, so a true anywhere wins and a project-level false cannot re-enable."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/settings.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (settings page)"
      - url: "https://code.claude.com/docs/en/mcp.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (mcp page)"
  - claim: "disableClaudeAiConnectors is a documented exception to managed-settings precedence: a true from any scope is honored even when a managed source sets false. It requires v2.1.182 or later."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/settings.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (settings page, Exceptions to managed settings precedence table)"
  - claim: "ENABLE_CLAUDEAI_MCP_SERVERS=false is the environment-variable equivalent, scoped to the shell session."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/env-vars.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (env-vars page)"
      - url: "https://code.claude.com/docs/en/mcp.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (mcp page)"
  - claim: "The /mcp panel toggle disables a single connector for the current project, persisted to disabledMcpServers in ~/.claude.json under the connector's display name."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/mcp.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (mcp page)"
  - claim: "disabledMcpServers/enabledMcpServers are distinct keys from enabledMcpjsonServers/disabledMcpjsonServers/enableAllProjectMcpServers, which govern .mcp.json approval and do NOT apply to connectors."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/mcp.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (mcp page)"
      - url: "https://code.claude.com/docs/en/settings.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (settings page)"
  - claim: "Individual connectors are blocked at policy level via deniedMcpServers with a serverName entry such as {\"serverName\": \"claude.ai Slack\"}, or more robustly a serverUrl pattern."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/managed-mcp"
        tier: 1
        pool: "Anthropic — code.claude.com docs (managed-mcp page)"
      - url: "https://code.claude.com/docs/en/mcp.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (mcp page)"
  - claim: "Deploying managed-mcp.json suppresses claude.ai connectors entirely unless allowAllClaudeAiMcps is set in an admin-controlled managed tier; that key is ignored in user or project settings."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/managed-mcp"
        tier: 1
        pool: "Anthropic — code.claude.com docs (managed-mcp page)"
      - url: "https://code.claude.com/docs/en/settings.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (settings page)"
  - claim: "In Claude Code on the web, connectors arrive as server-delivered --mcp-config entries, so disableClaudeAiConnectors does not apply and deniedMcpServers serverUrl patterns targeting vendor URLs do not match."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/mcp.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (mcp page)"
      - url: "https://code.claude.com/docs/en/managed-mcp"
        tier: 1
        pool: "Anthropic — code.claude.com docs (managed-mcp page)"
produced_by: phase-1-2-3
---

# Q4 — Every supported disable / scope mechanism

Seven mechanisms. The exact key spellings, files, and precedence follow. **All key spellings below
were read from the raw markdown of the docs pages, not from a summarizer**, because an intermediate
summary of the `env-vars` page inverted `ENABLE_CLAUDEAI_MCP_SERVERS`'s semantics during this run
(see `RESEARCH-gaps-and-unverified.md` § *A near-miss worth recording*).

## Summary table

| # | Mechanism | Exact spelling | Lives in | Granularity |
|---|---|---|---|---|
| 1 | Settings key, all connectors | `disableClaudeAiConnectors` | any settings scope | all connectors |
| 2 | Env var, all connectors | `ENABLE_CLAUDEAI_MCP_SERVERS=false` | shell environment | all connectors, this shell |
| 3 | `/mcp` panel toggle | writes `disabledMcpServers` | `~/.claude.json`, per project | one connector, per project |
| 4 | Policy denylist | `deniedMcpServers` | any settings file, merges from all | one connector |
| 5 | Policy allowlist | `allowedMcpServers` (+ `allowManagedMcpServersOnly`) | any settings file / managed | set of servers |
| 6 | Exclusive managed control | `managed-mcp.json` (+ `allowAllClaudeAiMcps`) | system path, admin only | all connectors |
| 7 | Session-scoped config | `--mcp-config` / `--strict-mcp-config` | CLI flags | session |

## 1. `disableClaudeAiConnectors` — the primary switch

From <https://code.claude.com/docs/en/settings.md>, fetched 2026-08-17, verbatim:

> `disableClaudeAiConnectors` — Disable [claude.ai MCP connectors](/docs/en/mcp#use-mcp-servers-from-claude-ai)
> so they are not auto-fetched or connected. Set in any settings scope. `true` in any source takes
> precedence, so a checked-in project `.claude/settings.json` can opt a repo out of cloud
> connectors, but a project-level `false` cannot override a user- or policy-level `true`. Servers
> passed explicitly via `--mcp-config` are unaffected. To deny individual connectors instead of all
> of them, use [`deniedMcpServers`](/docs/en/managed-mcp). **Requires Claude Code v2.1.182 or later**

Usage, from <https://code.claude.com/docs/en/mcp.md>:

```json
{
  "disableClaudeAiConnectors": true
}
```

**Precedence exception — this is the unusual part.** The settings page's *Exceptions to managed
settings precedence* table lists it explicitly:

| Key | Value Claude Code honors | Notes |
|---|---|---|
| `disableClaudeAiConnectors` | `true` from any scope | Honored even when a managed source sets `false` |

So this is one of a handful of security-sensitive keys where a *user* can out-restrict their *admin*.
For the skill: a user can always turn connectors off for themselves, and no org policy can force
them back on. That is a genuinely safe thing for the skill to promise.

Settings-file locations and the general precedence ladder (managed > command line > local > project >
user) are on the same page; the relevant files are `~/.claude/settings.json` (user),
`.claude/settings.json` (project, checked in), `.claude/settings.local.json` (local, not checked in),
and `managed-settings.json` (managed).

## 2. `ENABLE_CLAUDEAI_MCP_SERVERS` — the env-var equivalent

From <https://code.claude.com/docs/en/env-vars.md> raw markdown, fetched 2026-08-17, verbatim:

> `ENABLE_CLAUDEAI_MCP_SERVERS` — Set to `false` to disable
> [claude.ai MCP servers](/docs/en/mcp#use-mcp-servers-from-claude-ai) in Claude Code. Enabled by
> default for logged-in users. To disable per-project or per-org, set
> [`disableClaudeAiConnectors`](/docs/en/settings#available-settings) in settings instead

The `mcp` page gives the invocation:

```bash
ENABLE_CLAUDEAI_MCP_SERVERS=false claude
```

described as having "the same effect for the current shell session."

## 3. The `/mcp` toggle — per-connector, per-project

From <https://code.claude.com/docs/en/mcp.md>, fetched 2026-08-17:

> Toggle a server off in the `/mcp` panel to stop Claude Code from connecting to it without losing
> its configuration. Claude Code still lists the server in `/mcp`, marked as disabled.
>
> When you toggle a server, Claude Code records your choice per project in `~/.claude.json`, in one
> of two lists…
>
> - `disabledMcpServers`: an opt-out list for user-configured servers, plugin servers, claude.ai
>   connectors, and built-in servers that default to on. … When you disable a claude.ai connector
>   with the per-project `/mcp` toggle …, Claude Code writes it to this list under its display name,
>   for example `claude.ai Slack`.
> - `enabledMcpServers`: an opt-in list for built-in servers that default to off, such as
>   `computer-use`.

**This is the only per-connector, per-project mechanism**, and it is the one the skill will most
often want to drive.

## 4-5. `deniedMcpServers` / `allowedMcpServers`

From <https://code.claude.com/docs/en/managed-mcp>, fetched 2026-08-17. Entries are objects with one
of three keys: `serverUrl` (exact or `*` wildcards), `serverCommand` (exact argv match), `serverName`
(exact, no wildcards).

For connectors specifically:

> In `deniedMcpServers`, `serverName` accepts any non-empty string, so you can block
> [claude.ai connectors](/docs/en/mcp#use-mcp-servers-from-claude-ai) by their display name. For
> example, `{ "serverName": "claude.ai Slack" }` blocks the Slack connector. Prefer a `serverUrl`
> entry when you need the deny to be robust to renames, or when a connector name collides and gains
> a `(N)` suffix.
>
> In `allowedMcpServers`, `serverName` is limited to letters, numbers, hyphens, and underscores. Use
> `serverUrl` to allowlist a claude.ai connector.

Note the asymmetry — `"claude.ai Slack"` contains a dot and a space, so it is a legal *deny* name but
an illegal *allow* name. Evaluation order:

> 1. **Merge the lists.** … When `allowManagedMcpServersOnly` is `true`, only the managed allowlist
>    is kept; the denylist always merges from every source.
> 2. **Check the denylist.** A server that matches any denylist entry … is blocked. Nothing overrides
>    a denylist match.
> 3. **Check the allowlist.** If `allowedMcpServers` isn't set anywhere, every server that passed the
>    denylist loads.

Unset ≠ empty array: unset `allowedMcpServers` allows all; `[]` allows none.

A documented warning the skill should relay:

> A `serverName` entry, in either list, is not a security control. … For claude.ai connectors the
> name is the display name returned by claude.ai, which can change.

## 6. `managed-mcp.json` + `allowAllClaudeAiMcps`

From <https://code.claude.com/docs/en/managed-mcp>, fetched 2026-08-17. Paths:

| Platform | Path |
|---|---|
| macOS | `/Library/Application Support/ClaudeCode/managed-mcp.json` |
| Linux and WSL | `/etc/claude-code/managed-mcp.json` |
| Windows | `C:\Program Files\ClaudeCode\managed-mcp.json` |

> If you deploy a `managed-mcp.json` file, Claude Code loads only the servers that file defines …
> The file also suppresses claude.ai connectors unless you allow them alongside the managed set.

and:

> Deploying `managed-mcp.json` suppresses claude.ai connectors by default, including connectors an
> administrator configured for the organization in the claude.ai admin console. To load those
> connectors alongside the servers in `managed-mcp.json`, set `"allowAllClaudeAiMcps": true` in a
> managed settings source. **Requires Claude Code v2.1.149 or later.**
>
> Claude Code reads this setting only from admin-controlled policy tiers: server-managed settings,
> an MDM-deployed plist or HKLM registry key, or a system `managed-settings.json` file. Placing it
> in user or project settings has no effect.

`{"mcpServers": {}}` is the documented "disable MCP entirely" configuration.

## 7. `--mcp-config` / `--strict-mcp-config`

`disableClaudeAiConnectors` explicitly does **not** affect servers passed via `--mcp-config`. This
matters because of the web-session carve-out below.

## The Claude Code on the web carve-out

From <https://code.claude.com/docs/en/mcp.md>, fetched 2026-08-17 — the single most important
exception for a skill that might run in a cloud session:

> These client-side settings govern local Claude Code sessions. In
> [Claude Code on the web](/docs/en/claude-code-on-the-web) sessions, claude.ai connectors are
> provisioned by the remote host and arrive as explicit `--mcp-config` entries, so
> `disableClaudeAiConnectors` doesn't apply there. Connector URLs are also rewritten through the
> session proxy, so a `deniedMcpServers` `serverUrl` pattern targeting the vendor URL won't match.
> Manage which connectors a cloud session can use from your claude.ai organization settings.

**So in a web/cloud session, mechanisms 1, 2 and the URL form of 4 are all inert.** The skill must
detect the surface before promising a disable will work. The `/mcp` per-project toggle
(mechanism 3) is not called out as inert there, but neither is it affirmed to work —
see `RESEARCH-gaps-and-unverified.md`.

## Keys that look relevant and are NOT

From <https://code.claude.com/docs/en/mcp.md>, verbatim:

> `disabledMcpServers` and `enabledMcpServers` are unrelated to `enabledMcpjsonServers` and
> `disabledMcpjsonServers`, which control approval of servers defined in a project's `.mcp.json`
> file.

The `.mcp.json`-approval family — exact spellings from
<https://code.claude.com/docs/en/settings.md>, fetched 2026-08-17 — is:

- `enabledMcpjsonServers` — "List of specific MCP servers from `.mcp.json` files to approve"
  (example value `["memory", "github"]`)
- `disabledMcpjsonServers` — "List of specific MCP servers from `.mcp.json` files to reject"
  (example value `["filesystem"]`)
- `enableAllProjectMcpServers` — "Automatically approve all MCP servers defined in project
  `.mcp.json` files"

**None of these three apply to connectors.** A skill that offers them as a connector control would
be wrong. They also interact with workspace trust: as of v2.1.196, `enableAllProjectMcpServers` or
`enabledMcpjsonServers` committed to a project's `.claude/settings.json` is ignored in an untrusted
folder.
