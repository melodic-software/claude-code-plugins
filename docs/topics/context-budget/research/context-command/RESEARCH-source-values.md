---
topic: context-command-output-contract
section: source-values
abstract: Source values come from one enum-to-label map; "claude.ai sync" marks skills synced from the user's claude.ai account, and no global off switch exists at 2.1.232 — only per-skill skillOverrides.
claims:
  - claim: "Skill Source strings are produced by one map from an internal enum, with the plugin name appended in parentheses only for plugin-sourced skills: built-in→Built-in, userSettings→User, projectSettings→Project, localSettings→Local, plugin→Plugin, mcp→MCP, memoryStore→Memory store, syncedSkills→claude.ai sync."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (function pwo and the skill row builder in aFn, 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
      - url: "local probe output showing \"Plugin (adhd)\" and \"User\", v2.1.232, run 2026-08-17"
        tier: 0
        pool: "empirical-cli-probe"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (v2.1.139 entry, fetched 2026-08-17)"
        tier: 1
        pool: "anthropic-github-changelog"
  - claim: "The Custom Agents table uses a SEPARATE inline mapping that never appends a plugin name, so plugin-provided agents render as bare \"Plugin\" while plugin-provided skills render as \"Plugin (name)\"."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (inline switch in aFn's agent loop, distinct from pwo, 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
      - url: "local probe output — all agents rendered as \"Plugin\" with no name, v2.1.232, run 2026-08-17"
        tier: 0
        pool: "empirical-cli-probe"
  - claim: "\"claude.ai sync\" marks skills synced from the user's claude.ai account; at v2.1.232 no global setting disables that sync — disableClaudeAiConnectors covers MCP connectors only and disableBundledSkills covers bundled skills only."
    confidence: HIGH
    tiers: [0, 1, 2]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (settings schema enumeration; syncedSkills is a loadedFrom value; no sync-disable key present, 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
      - url: "https://code.claude.com/docs/en/settings (fetched 2026-08-17)"
        tier: 1
        pool: "anthropic-docs"
      - url: "https://github.com/anthropics/claude-code/issues/39686 (fetched 2026-08-17)"
        tier: 2
        pool: "third-party-issue-reporter"
produced_by: phase-2-targeted + phase-3-fallback
---

# What the Source column means

## The skill mapping

Skill rows are built as `label(source) + (pluginName ? " (" + pluginName + ")" : "")`, where
`label` is a single switch over an internal enum:

| Internal enum | Rendered Source | Means |
|---|---|---|
| `built-in` | `Built-in` | Ships inside Claude Code itself — the bundled skill set |
| `userSettings` | `User` | From the user scope, i.e. `~/.claude/skills/` |
| `projectSettings` | `Project` | From the checked-in project scope |
| `localSettings` | `Local` | Project scope but gitignored (`.claude/settings.local.json`) |
| `flagSettings` | `Flag` | Supplied by a command-line argument |
| `policySettings` | `Managed` | Enterprise managed settings |
| `plugin` | `Plugin (<name>)` | From an installed plugin; the plugin's name is appended |
| `mcp` | `MCP` | Exposed by an MCP server as a prompt |
| `memoryStore` | `Memory store` | From the memory store |
| `syncedSkills` | `claude.ai sync` | Synced down from the user's claude.ai account |

The probe's four observed values map cleanly: `Plugin (adhd)`, `User`, and — had they been present
— `Built-in` and `claude.ai sync`.

**`Plugin (name)` is the only value carrying a parenthesised suffix.** A parser splitting the
Source cell must treat everything before the first `(` as the source kind and the parenthesised
remainder as the plugin name, and must not assume every value has one.

## The agent mapping is a different function — mind the trap

The Custom Agents table does **not** use the map above. The generator inlines its own switch for
agent rows, and that switch differs in two ways:

- It renders `policySettings` as **`Policy`**, where the skill map renders **`Managed`**.
- It **never appends a plugin name**. Plugin-provided agents render as bare `Plugin`.

The probe demonstrates this exactly: twelve agents, all from plugins, all rendered as `Plugin`
with no name — while skills from the very same plugins rendered as `Plugin (adhd)` and so on.

**Consequence for a measurement engine:** agent rows cannot be attributed to a specific plugin
from `/context` output alone. Only the `agentType` prefix (`discovery:explorer`) carries that
information, and only by convention. A third fallback exists in the agent switch — an unmatched
source is stringified raw — so an unexpected value can appear verbatim rather than as a label.

## "claude.ai sync" — what it is

`syncedSkills` is not a settings *scope* like the others; internally it is a `loadedFrom` value
distinguishing skills pulled from the user's claude.ai account from skills that exist on disk
because someone installed them. These are the Skills panel entries and Cowork plugin skills
associated with the logged-in account, delivered at session start without a local install step.

Anthropic has hardened them rather than removed them: changelog v2.1.228 records that skills
synced from claude.ai "no longer shadow local commands or MCP prompts, their descriptions are
sanitized and labeled, and on your machine their bodies don't run `!` commands or expand `@`
files". The `claude.ai sync` label in `/context` **is** that labelling.

## How an operator turns it off — the honest answer

**There is no global switch at v2.1.232.** The shipped settings schema was enumerated directly
from the binary. The two keys that sound like they would help do not:

| Setting | What it actually covers | Reaches synced skills? |
|---|---|---|
| `disableClaudeAiConnectors` (v2.1.182+) | claude.ai **MCP connectors** — "not auto-fetched or connected" | **No** |
| `disableBundledSkills` / `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` | **Bundled** skills and workflows shipped inside Claude Code | **No** |
| `deniedMcpServers` | MCP servers, managed-settings denylist | **No** |

The only lever that reaches them is **`skillOverrides`** — a settings map keyed by skill name with
values `on`, `off`, and `user-invocable-only`. The binary carries the matching user-facing
message: *"Skill \"…\" is disabled via skillOverrides. Re-enable it in /skills or remove the
override from your settings to run it."* So the practical procedure is:

1. Run `/skills` and toggle the unwanted synced skills off, **or** write the equivalent
   `skillOverrides` entries into `~/.claude/settings.json`.
2. Accept that this is **per skill, by name** — there is no `deniedSkillSources`-style bulk switch.
   That exact key was searched for in the binary and does not exist.

`--bare` suppresses them as a side effect (it "skips hooks, LSP, plugin sync ... and CLAUDE.md
auto-discovery"), but it is a scripted-`-p` flag that disables much else besides, and it is not an
opt-out for interactive use.

### Corroboration and its limits

Issue [#39686](https://github.com/anthropics/claude-code/issues/39686) is an independent
third-party report of exactly this: claude.ai Skills and Cowork plugins appearing in `/context`'s
Skills section (~5,970 tokens across 69 skills) with no working opt-out, having tried
`ENABLE_CLAUDEAI_MCP_SERVERS`, `deniedMcpServers`, a SessionStart hook, and `--bare`. It was filed
against **v2.1.84** and closed as **not planned / stale**.

That report corroborates the *absence of a global switch* from a genuinely independent publisher,
but it predates v2.1.232 by ~150 patch releases and does not mention `skillOverrides`. The
`skillOverrides` path is therefore sourced on the binary alone (Tier 0) plus the `/skills` UI it
references — **not** independently corroborated, and **not documented**: `skillOverrides` is
confirmed absent from `https://code.claude.com/docs/en/settings`, which does document its
neighbours `disableBundledSkills`, `disableClaudeAiConnectors`, and `deniedMcpServers`.

**Checked:** the shipped binary's settings schema, the official settings page, the official
commands page, the upstream changelog, and the upstream issue tracker. **Left unchecked:** the
`/en/env-vars` page in full, and `/en/skills`, either of which could document `skillOverrides`
without contradicting anything above.
