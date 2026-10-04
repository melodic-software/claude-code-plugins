# user-interface

Front door for interface design. An agent building anything a person or agent interacts with (CLI
output, a TUI, a prompt theme, a Claude Code mod, web or app UI) gets guidance that keeps the
project's existing look, reuses the design tools already installed, and fills only the gaps.

| Skill | What it does |
|---|---|
| `/user-interface:design` | Detect the project's design system and the installed design tools, route each concern to the best present source, and supply the plugin's own guidance where nothing covers it |

## How it routes

For each concern the order is:

1. The project's own design system, conventions and MCP servers.
2. This repository's enabled plugins.
3. Official publishers.
4. Community tools, with adoption breaking ties.
5. This plugin's own guidance.

The routes live in [`reference/routing.json`](reference/routing.json), validated by
[`reference/routing.schema.json`](reference/routing.schema.json).
[`scripts/detect.mjs`](scripts/detect.mjs) reports what the project and machine have, and which
installed routes are reachable.

## Guidance

- [`reference/principles.md`](reference/principles.md): the working order, the usability heuristics,
  and the accessibility floor every medium keeps.
- [`reference/types/`](reference/types/): one file per interface type. The skill reads the file
  that matches, so a new type is a new file.
  - [`terminal.md`](reference/types/terminal.md): CLI output, TUIs, prompt themes, PowerShell,
    banners; `NO_COLOR`, non-TTY output and plain-text fallbacks.
  - [`mods.md`](reference/types/mods.md): Claude Code mod displays, building on terminal.md.
  - [`web.md`](reference/types/web.md) and [`app.md`](reference/types/app.md): project-first rules
    and pointers to platform guidelines.

## Options

| Option | Default | Effect |
|---|---|---|
| Account-bound tools (`account_tools_enabled`) | on | Off limits routing to tools that need no account, login or key |
