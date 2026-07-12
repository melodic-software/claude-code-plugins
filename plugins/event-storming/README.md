# event-storming

A Claude Code plugin for **EventStorming** — Alberto Brandolini's workshop format for collaborative
domain discovery. It helps you explore a business domain, discover bounded contexts, and bridge the
resulting model to DDD tactical design.

It ships **two skills**, split by whether you want to *read* facilitation guidance or *run* an
agentic workshop:

| Skill | Invoke | Does |
|---|---|---|
| `methodology` | `/event-storming:methodology [--big-picture\|--process\|--design-level\|--patterns\|--glossary\|--notation\|--remote]` | Facilitation knowledge and reference across the three formats — notation, building blocks, patterns/anti-patterns, remote adaptations. No args runs an interactive discovery flow. |
| `simulation` | `/event-storming:simulation [--simulate\|--process-model\|--design-level\|--evaluate\|--retrospective\|--induction\|--value\|--crc\|--ux\|--discover-bcs] [domain]` | An agentic, multi-persona EventStorming workshop that produces a structured-markdown model by default, plus per-run scoring and bounded-context discovery. A live Miro-board rendering path is available when a compatible Miro MCP server is connected (see Requirements). |

## When to use which

- **methodology** is pure reference — you are facilitating (or learning) EventStorming yourself and
  want the format guidance, notation, and patterns at hand. It needs no external tools.
- **simulation** *runs* the workshop for you: it spins up 4–7 siloed personas, plays every Big
  Picture phase in order, discovers bounded contexts, and lets you drill into Process Modeling and
  Design-Level per context. By default it emits the model as structured markdown (event timeline,
  persona roster, bounded-context tables); with a compatible Miro MCP server connected it renders
  the same model onto a live Miro board instead.

Each skill auto-invokes on its own trigger phrases, or you can call it directly.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install event-storming@melodic-software
```

## Requirements

- **methodology** — none beyond Claude Code.
- **simulation** — no hard dependency. It runs out of the box in **structured-markdown mode** (the
  agentic workshop, emitting the model as an event timeline, persona roster, and bounded-context
  tables). Two optional surfaces enhance it, neither bundled:
  - A **Miro MCP server** for the live-board rendering path.
  - A **web-research surface** for domain context.

Both optional surfaces degrade gracefully:

- **Miro** — the live-board path currently expects a Miro MCP server exposing `miro_*` tool names
  (`miro_list_boards`, `miro_create_board`, `miro_bulk_create_sticky_notes`, …). Miro's official
  hosted server (`mcp.miro.com`) uses a **different** tool surface (`board_create` /
  `board_search_boards` / `layout_create`, OAuth 2.1), so the board path does **not** work against
  it yet — reconciling the skill to Miro's official tools (and recording the remote-MCP trust
  decision that entails) is a tracked **fast-follow**. Against any server whose tool names differ,
  `simulation` detects the mismatch at preflight and runs in structured-markdown mode instead of
  failing. Miro's own setup docs: <https://developers.miro.com/docs/mcp-intro> and
  <https://developers.miro.com/docs/connecting-miro-mcp-to-ai-coding-tools>.
- **Web research absent** — the skills use the Perplexity MCP tools if present, otherwise Claude
  Code's built-in `WebSearch` / `WebFetch`; with no research surface at all they ask you for the
  domain context rather than guessing.

Shareable exports (slides/docs/PDF) hand off to the `document-skills` plugin when it is installed,
and fall back to markdown otherwise.

## Configuration

This plugin has no `userConfig`. Its inputs are conversational (the domain and mode you pass) plus
the optional MCP servers above. Generated state (session archives, run history, comparison
baselines) is written to the plugin's own persistent data directory (`${CLAUDE_PLUGIN_DATA}`), never
into your project tree.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
