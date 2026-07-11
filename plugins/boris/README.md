# boris

A Claude Code plugin that ships Boris Cherny's Claude Code workflow tips
([howborisusesclaudecode.com](https://howborisusesclaudecode.com)) as an
on-demand knowledge skill — 107 tips across 95 sections covering parallel
sessions, planning, CLAUDE.md, skills, hooks, permissions, MCP, autonomy, and
multi-agent orchestration, compiled from Boris Cherny (Claude Code's creator)
and the Claude Code team.

Invoke it with `/boris:boris`, or let Claude load it automatically when you ask
about optimizing your Claude Code setup or workflows.

## What it provides

- **Topic Index** — a hub SKILL.md routes each question to one of eight topic
  reference files (foundations, customization, worktrees, workflows, advanced,
  favorites, autonomy, orchestration), so only the relevant slice loads.
- **Quick Reference** — a one-line-per-tip table for fast scanning without
  loading any reference file.
- **Vendored upstream baseline** — the verbatim upstream skill file is bundled
  for drift detection against the source site.

## Update workflow (maintainers)

`/boris:boris update` runs the bundled drift-check script: `--check` (default)
reports upstream version and vendor SHA drift read-only; `--apply` refreshes
the vendored baseline and frontmatter metadata. Integrating new tips into the
topic reference files stays a manual, reviewed step. Run it in a working-tree
checkout of this plugin (the marketplace clone, or a directory loaded via
`--plugin-dir`) — consumers receive updates through
`/plugin marketplace update` once a new plugin version is published.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install boris@melodic-software
```

## Configuration

This plugin has no `userConfig`. It is a pure knowledge skill: nothing to
configure, no state, no network access on normal invocation (only the
maintainer-facing update script fetches the upstream source).

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
