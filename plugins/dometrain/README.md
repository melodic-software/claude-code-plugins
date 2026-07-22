# dometrain

A Claude Code plugin that connects Claude to [Dometrain](https://dometrain.com)'s hosted course
content over a remote MCP server — search video-course lessons, pull curated lesson documents
with the exact on-screen code, and cite timestamped deep links so an implementation matches how
the user's courses teach it.

This is the marketplace's first plugin to ship a **remote** (not bundled/local) MCP server: the
server is Dometrain-hosted (`https://mcp.dometrain.com/mcp`), closed-source, and requires an
active [Dometrain Pro](https://dometrain.com/pro/) subscription — there is nothing to bundle,
unlike `miro`'s locally-run, self-contained Node server.

## Enabling and configuration

The plugin **installs disabled** (`defaultEnabled: false`) — a remote MCP server that connects
to an external, credentialed service is opt-in, not on by default. Enable it with
`claude plugin enable dometrain` or the `/plugin` interface, and provide a key:

| Option | Storage | Purpose |
|---|---|---|
| `dometrain_api_key` | Claude Code secure credential storage (never `settings.json`) | Dometrain account API key. Required — the server rejects requests without it. |

Get a key from <https://dometrain.com/dashboard/account/> ("MCP API keys" section). Claude Code
prompts for it at enable time (masked input). Sensitive values use the macOS Keychain, or
`~/.claude/.credentials.json` on platforms where no supported keychain is available; the key is
substituted into the server's `.mcp.json` `Authorization` header as a Bearer token.

Headless install with the key seeded on first install:

```shell
claude plugin install dometrain@melodic-software --config dometrain_api_key=<your-key>
```

Run `/dometrain:setup` to check enablement and MCP tool availability. The setup skill never
reads or exposes the key and never calls a Dometrain tool during setup — see
[Setup mechanism](#setup-mechanism) below for why.

## Tools

| Tool | What it does |
|---|---|
| `search_dometrain(query, tech?, max_results?)` | Search lessons for implementation guidance; hybrid keyword + semantic ranking — ranked excerpts with deep links |
| `search_code(query, language?, max_results?)` | Search the code shown on screen in lessons; snippets with a deep link to the exact moment the code appears |
| `get_lesson(lesson_id)` | Full curated lesson document: summary, key concepts, notes, on-screen code |
| `get_course(course_id_or_slug)` | Course overview + chapter/lesson tree |
| `list_courses(topic?)` | Published courses, optionally filtered by topic |
| `get_usage()` | Your monthly request usage, limit, and reset date |

All six tools are read-only — nothing to execute, nothing this plugin mutates.

## Quota

Requests are limited per calendar month per account (all your keys share the pool), with a
short per-minute burst cap. Figures change on Dometrain's side independently of this plugin, so
this README does not hardcode them — call `get_usage()`, or check your own
[Dometrain dashboard](https://dometrain.com/dashboard/account/), for current numbers.

## Why a remote server, not bundled

Unlike `miro`'s bundled local `stdio` server, Dometrain's server is hosted and closed-source —
there is no artifact to bundle. The plugin wires Claude Code's `http`-type MCP transport
directly at `https://mcp.dometrain.com/mcp` with a Bearer header sourced from `userConfig`,
never a locally-run process.

## Dometrain's own official plugin — and why this one exists too

Dometrain ships its own official Claude Code plugin and marketplace at
[github.com/Dometrain/mcp](https://github.com/Dometrain/mcp) (MIT licensed), installable via:

```shell
claude plugin marketplace add dometrain/mcp
claude plugin install dometrain@dometrain
```

That plugin's `.mcp.json` authenticates via a shell environment variable
(`${DOMETRAIN_API_KEY}`) — it declares no `userConfig` field at all. This plugin exists
specifically to provide the alternative: the key entered once through Claude Code's **native
masked `userConfig` prompt**, stored in secure credential storage, never a shell environment
variable you have to export yourself.

**Do not enable both plugins simultaneously.** Both share the identical plugin name
(`"dometrain"`) in their respective `plugin.json` manifests. Install identity is
marketplace-scoped (`dometrain@melodic-software` and `dometrain@dometrain` are distinct,
coexistable install identities), but skill and MCP-tool namespacing is driven by `plugin.json`
`name` alone — and Claude Code's documented behavior for two enabled plugins sharing an
identical name is genuinely undocumented. Pick one.

## Grounding skill

`/dometrain:grounding` carries usage guidance — when to consult Dometrain, the tool workflow,
citation format, and quota etiquette — adapted from Dometrain's own official
`dometrain-grounding` skill (same source repo as above, MIT licensed). Model-invocable: Claude
proactively consults it on a covered topic without an explicit command.

## Keeping the grounding skill in sync

The grounding skill's usage guidance is vendored, not hand-copied, from Dometrain's own skill
content. `/dometrain:sync` — **maintainer-only, never model-invocable, report-only for
consumers** — checks whether upstream has changed. See
[`skills/sync/context/update.md`](skills/sync/context/update.md) for the full integration
protocol; only a maintainer working in a clone of this repository refreshes the baseline.

## Setup mechanism

`/dometrain:setup check` reports one of `disabled`, `connected`, or `failed or unverified`,
derived from tool-inventory presence and Claude Code's own `ToolSearch`-surfaced connection
errors — not from reading `/mcp` connection status, which no callable tool exposes to a model
turn. See [`skills/setup/SKILL.md`](skills/setup/SKILL.md) for the full mechanism.

## Attribution

This plugin's `grounding` skill content is adapted from Dometrain's own official Claude Code
plugin ([github.com/Dometrain/mcp](https://github.com/Dometrain/mcp)), MIT licensed. The
Dometrain course content served by the MCP server itself is **not** covered by that license — it
remains Dometrain's proprietary content, accessible under your Dometrain Pro subscription and
[Dometrain's terms of service](https://dometrain.com/terms/).

## Development

This plugin ships no server code — the MCP server is Dometrain-hosted. There is no build step;
`claude plugin validate plugins/dometrain` is the only local check.
