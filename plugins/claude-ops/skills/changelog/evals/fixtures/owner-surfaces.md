# Owner surfaces

| Owner surface | What it states or does |
|---|---|
| `plugins/hooks-kit/skills/elicitation-hooks/SKILL.md` | States that a `{"decision":"block"}` return from an Elicitation hook is ignored and only exit code 2 declines the elicitation |
| `plugins/hooks-kit/scripts/rerun-failed-hook.sh` | Re-runs a failed hook by hand to capture the stderr that the debug log drops when the hook also writes to stdout |
| `plugins/mcp-tools/scripts/reconnect-servers.sh` | Loops over `claude mcp list` and reconnects each failed or unauthenticated server one at a time |
| `plugins/hooks-kit/README.md` | Describes the plugin; no claim about dialogs, tab bars or terminal layout |
