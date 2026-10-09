# developer-experience

Helps a team build and maintain its own developer tooling: the scripts, command-line tools, hooks
and skills a repository ships so work runs the same way for every person and agent.

| Skill | What it does |
|---|---|
| `/developer-experience:audit-tools` | Inventory the repository's scripts, CLIs, skills, hooks, subagents and MCP configs and report findings; read-only unless you say yes |

## Install

```text
/plugin marketplace add melodic-software/claude-code-plugins
```

Then install `developer-experience` from that marketplace. Issues and questions:
<https://github.com/melodic-software/claude-code-plugins/issues>.

## Conventions

Research happens at run time from official sources and the project's own files; the plugin ships no
stack templates. Further skills for recording a team's tooling conventions and for building
command-line tools follow in later releases.
