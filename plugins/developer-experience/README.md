# developer-experience

Helps a team build and maintain its own developer tooling: the scripts, command-line tools, hooks
and skills a repository ships so work runs the same way for every person and agent.

| Skill | What it does |
|---|---|
| `/developer-experience:setup` | Record the repository's tooling conventions as current fact and point `AGENTS.md` at them; `check` reports drift, `apply` writes after showing each change. You invoke it; the model does not |
| `/developer-experience:build-cli` | Build, extend, port or review a command-line tool or script against the CLI contract and the repository's conventions |
| `/developer-experience:audit-tools` | Inventory the repository's scripts, CLIs, skills, hooks, subagents and MCP configs and report findings; read-only unless you say yes |

## Install

```text
/plugin marketplace add melodic-software/claude-code-plugins
```

Then install `developer-experience` from that marketplace. Issues and questions:
<https://github.com/melodic-software/claude-code-plugins/issues>.

## What setup writes

`setup apply` writes a conventions file (`docs/conventions/developer-experience.md` by default) and
one pointer line in the repository's `AGENTS.md`, inside a shared `plugin-conventions` block. It
changes no other line there, and a second run with nothing changed writes nothing. With `--user` it
also writes `~/.config/developer-experience/developer-experience.md` and, after your yes, one
pointer line in each personal instructions file you confirm.

## Conventions

Research happens at run time from official sources and the project's own files; the plugin ships no
stack templates.
