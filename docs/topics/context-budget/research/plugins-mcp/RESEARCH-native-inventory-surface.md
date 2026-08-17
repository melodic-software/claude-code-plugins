---
topic: plugins-mcp-context-budget
section: native-inventory-surface
abstract: Of the native inventory surfaces only /context and /mcp run under claude -p; the other six slash commands are interactive-only, so a headless skill must fall back to claude plugin/mcp subcommands.
claims:
  - claim: "Under `claude -p` on v2.1.232, /context and /mcp produce output while /status, /skills, /hooks, /permissions, /memory and /plugin all return \"isn't available in this environment\"."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "claude -p '<command>' --permission-mode dontAsk, nine probes run 2026-08-17 on v2.1.232"
        tier: 0
        pool: "installed Claude Code v2.1.232 on this machine"
      - url: "https://code.claude.com/docs/en/commands (interactive-dialog wording for /permissions, /plugin, /skills, /status)"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/headless ('Not every CLI option combines with -p')"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
  - claim: "/context reports a per-category breakdown that separates resident system tools from deferred ones, and itemises custom agents and skills with per-item token counts."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "claude -p '/context' live output, 2026-08-17, v2.1.232"
        tier: 0
        pool: "installed Claude Code v2.1.232 on this machine"
      - url: "https://code.claude.com/docs/en/debug-your-config#see-what-loaded-into-context"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/commands (/context row)"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
  - claim: "`claude --safe-mode` disables all customizations including plugins, MCP servers and skills, but admin-managed policy settings still apply."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "claude --help (v2.1.232) --safe-mode entry"
        tier: 0
        pool: "installed Claude Code v2.1.232 on this machine"
      - url: "https://code.claude.com/docs/en/debug-your-config#test-against-a-clean-configuration"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/cli-reference"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
produced_by: phase-2
---

# Q6 — The wider native inventory surface

Docs fetched **2026-08-17**. All headless results are **Tier 0**, from
`claude -p "<cmd>" --permission-mode dontAsk` run on **v2.1.232** on 2026-08-17 inside this
repository.

## The headless matrix — empirically probed, not inferred

| Surface | What it reports | Runs under `claude -p`? | Observed output |
|---|---|---|---|
| `/context` | Full context breakdown by category: system prompt, system tools, **system tools (deferred)**, custom agents (per agent, with source), skills (per skill, with source), messages, free space, autocompact buffer | **YES** | Complete markdown table, exit 0 |
| `/mcp` | Configured servers, status, tool counts; also a control surface | **YES** | `No MCP servers are configured…` + `Usage: /mcp [reconnect\|enable\|disable [<server>\|all]]` |
| `/status` | Active settings sources, incl. whether managed settings are in effect; version, model, account, connectivity | **NO** | `/status isn't available in this environment.` |
| `/skills` | Available skills from project, user and plugin sources; `t` sorts by token count; `Space` cycles visibility | **NO** | `/skills isn't available in this environment.` |
| `/hooks` | Active hook configurations, grouped by event | **NO** | `/hooks isn't available in this environment.` |
| `/permissions` | Resolved allow/ask/deny rules by scope | **NO** | `/permissions isn't available in this environment.` |
| `/memory` | Memory file locations across scopes, auto-memory folder and toggle | **NO** | `/memory isn't available in this environment.` |
| `/plugin` | Plugin manager; also accepts `list`, `install`, `enable`, `disable` subcommands | **NO** | `/plugin isn't available in this environment.` |
| `/doctor` | The setup checkup (see its own sidecar) | **NO** (not model-invocable either) | not a checkup |

**The six that fail are the interactive TUI panels.** The commands reference describes them with
dialog verbs — `/permissions` "Opens an interactive dialog", `/skills` "Press `t` to sort by token
count", `/status` "Open the Settings interface on the Status tab", `/plugin` "open the plugin menu"
(<https://code.claude.com/docs/en/commands>, fetched 2026-08-17). `/context` and `/mcp` are the two
that render as text.

### Headless fallbacks that DO work (Tier 0, v2.1.232)

For everything in the "NO" column there is a non-interactive equivalent:

| Interactive-only | Headless equivalent |
|---|---|
| `/plugin` | `claude plugin list` / `claude plugin list --json` / `claude plugin details <name>` / `claude plugin enable\|disable <p> -s <scope>` |
| `/mcp` (config view) | `claude mcp list`, `claude mcp get <name>` |
| `/status`, `/permissions`, `/hooks` | `claude doctor` (terminal, read-only installation + settings diagnostics, no session) |
| `/skills` token sort | `claude plugin details <name>` per plugin; `/context` Skills rows |

`claude plugin list --json` requires `--json` for `--available`
(`--available  Include available plugins from marketplaces (requires --json)`, `claude plugin list --help`,
v2.1.232, 2026-08-17).

## `/context` — the measurement primitive

Live Tier-0 output shape from this session (2026-08-17, model `claude-sonnet-5`, 967k window):

```text
### Estimated usage by category
| Category                 | Tokens | Percentage |
| System prompt            | 5.1k   | 0.5%  |
| System tools             | 18.1k  | 1.9%  |
| System tools (deferred)  | 17.8k  | 1.8%  |
| Custom agents            | 1.5k   | 0.2%  |
| Skills                   | 9.9k   | 1.0%  |
| Messages                 | 591    | 0.1%  |
| Free space               | 898.7k | 92.9% |
| Autocompact buffer       | 33k    | 3.4%  |

### Custom Agents      (per agent: type, Source=Plugin, tokens)
### Skills             (per skill: name, Source=Plugin (<name>), tokens)
```

Two things a trimming skill should note:

1. **`System tools (deferred)` is broken out as its own row.** This is exactly the check `/doctor`
   prescribes ("deferred tools appear as a names-only list … resident tools have full schemas") and
   it is machine-readable from `claude -p "/context"`. **This is the measurement seam.**
2. **Skills is 9.9k ≈ 1.0% of the window** — i.e. sitting right at `skillListingBudgetFraction`'s
   default. The listing is at its cap, which per the skills doc means descriptions are being
   truncated. Confirms the cap is the binding constraint, not raw growth.

Docs: "The `/context` command shows everything occupying the context window for the current session,
broken down by category: system prompt, system tools, MCP tools, custom subagents with the source
each loaded from, memory files, skills, and conversation messages."
(<https://code.claude.com/docs/en/debug-your-config>, fetched 2026-08-17.) `/context all` expands the
per-item breakdown in fullscreen mode.

## `claude --safe-mode`

Verbatim from `claude --help`, v2.1.232, 2026-08-17:

> `--safe-mode`  Start with all customizations (CLAUDE.md, skills, plugins, hooks, MCP servers,
> custom commands and agents, output styles, workflows, custom themes, keybindings, and more)
> disabled — useful for troubleshooting a broken configuration. Admin-managed (policy) settings still
> apply. Auth, model selection, built-in tools, and permissions work normally. Sets
> `CLAUDE_CODE_SAFE_MODE=1`.

The docs add the managed nuance: "Safe mode still applies managed hooks and settings policy from your
organization. **Managed plugins, skills, CLAUDE.md, and MCP servers are turned off.**"
(<https://code.claude.com/docs/en/debug-your-config#test-against-a-clean-configuration>, fetched
2026-08-17.)

**Use for the skill:** `claude --safe-mode -p "/context"` is a **floor measurement** — the startup
payload with every operator-controlled contributor removed. Differencing it against a normal
`claude -p "/context"` yields the total customization cost in one subtraction. I did **not** run this
combination, so treat it as a designed-but-unverified technique.

**Related, and stronger for a pure floor:** `--bare` (v2.1.232 help, 2026-08-17) — "Minimal mode:
skip hooks, LSP, plugin sync, attribution, auto-memory, background prefetches, keychain reads, and
CLAUDE.md auto-discovery. Sets `CLAUDE_CODE_SIMPLE=1`."

## `CLAUDE_CONFIG_DIR`

Verbatim from <https://code.claude.com/docs/en/env-vars> (fetched 2026-08-17):

> "Override the configuration directory (default: `~/.claude`). All settings, session history, and
> plugins are stored under this path, as are credentials on Linux and Windows; on macOS, credentials
> are in the system Keychain. Useful for running multiple accounts side by side: for example,
> `alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work claude'`"

The debug guide gives the clean-room recipe:
`cd /tmp && CLAUDE_CONFIG_DIR=/tmp/claude-clean claude` — "The clean session has no user or project
settings, hooks, MCP servers, plugins, or memory." Managed settings still apply (system path outside
`~/.claude`). Caveat: **first launch shows first-run setup screens**, which will block a naive
headless probe.

## Three surfaces the topic didn't name but the skill should use

1. **`claude plugin details <name>`** — per-plugin component inventory + `count_tokens`-derived
   `Always-on` figure. Headless. See `RESEARCH-plugin-payload-components.md`.
2. **`/usage`** — on Pro/Max/Team/Enterprise plans it shows **"recent usage attributed to skills,
   subagents, plugins, and individual MCP servers, each shown as a percentage of the total"**, with
   `d`/`w` toggles for 24h/7d (<https://code.claude.com/docs/en/costs>, fetched 2026-08-17). This is
   per-plugin/per-server *usage* attribution — the natural complement to `plugin details`'s cost
   side. **Unverified headlessly** (not probed; likely interactive).
3. **`--setting-sources <sources>`** — "Comma-separated list of setting sources to load (user,
   project, local)" (`claude --help`, v2.1.232). Lets a measurement run isolate one scope's
   contribution. Also `--strict-mcp-config` ("Only use MCP servers from `--mcp-config`, ignoring all
   other MCP configurations").

## What I could NOT verify

- Whether the six interactive-only commands behave differently under `--output-format stream-json`
  or in a TTY-attached headless harness. My probes used plain `-p` with `dontAsk`. The message
  "isn't available in this environment" is the harness's own wording and may be environment-specific
  rather than universal — **this session runs inside a Claude Code session**, which could itself be
  the "environment" constraining them.
- Whether `/usage` runs headlessly.
- Whether `claude --safe-mode -p "/context"` and `--bare -p "/context"` produce a usable floor
  measurement. Designed, not executed.
- `/memory`'s and `/hooks`' exact reported fields, since I could only read their doc descriptions,
  not their live output.
