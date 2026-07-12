# event-storming

A Claude Code plugin for **EventStorming** — Alberto Brandolini's workshop format for collaborative
domain discovery. It helps you explore a business domain, discover bounded contexts, and bridge the
resulting model to DDD tactical design.

It ships **two skills**, split by whether you want to *read* facilitation guidance or *run* an
agentic workshop:

| Skill | Invoke | Does |
|---|---|---|
| `methodology` | `/event-storming:methodology [--big-picture\|--process\|--design-level\|--patterns\|--glossary\|--notation\|--remote]` | Facilitation knowledge and reference across the three formats — notation, building blocks, patterns/anti-patterns, remote adaptations. No args runs an interactive discovery flow. |
| `simulation` | `/event-storming:simulation [--simulate\|--process-model\|--design-level\|--evaluate\|--retrospective\|--induction\|--value\|--crc\|--ux\|--discover-bcs] [domain]` | An agentic, multi-persona EventStorming workshop driven onto a Miro board, plus per-run scoring and bounded-context discovery. |

## When to use which

- **methodology** is pure reference — you are facilitating (or learning) EventStorming yourself and
  want the format guidance, notation, and patterns at hand. It needs no external tools.
- **simulation** *runs* the workshop for you: it spins up 4–7 siloed personas, plays every Big
  Picture phase in order, discovers bounded contexts, and lets you drill into Process Modeling and
  Design-Level per context — placing the model on a Miro board as it goes.

Each skill auto-invokes on its own trigger phrases, or you can call it directly.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install event-storming@melodic-software
```

## Requirements

- **methodology** — none beyond Claude Code.
- **simulation** — a **Miro MCP server** for board placement, and a web-research surface for domain
  context.

Neither dependency is bundled (a plugin does not ship a remote MCP server), and both degrade
gracefully:

- **Miro absent** — `simulation` detects it at preflight and offers to run in **structured-markdown
  mode** (the same agentic workshop, emitting the model as an event timeline, persona roster, and
  bounded-context tables instead of board stickies) or to pause while you connect Miro. Set up the
  Miro MCP server per Miro's own docs: <https://developers.miro.com/docs/mcp-intro> and
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
