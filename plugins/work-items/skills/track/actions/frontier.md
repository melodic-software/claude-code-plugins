# Action: `frontier`

List the items ready to pick: open, with no open blocker, unassigned, and not a container. Scoped to
one container with `--parent`. Read-only.

## Usage

```
/work-items:track frontier [--parent <id>] [--autonomous]
```

`--autonomous` also drops items a human must work (`needs-human` and the human-floor work classes),
for a session nobody is watching. Filter semantics:
`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md` "Verbs" (`list-frontier`).

## Workflow

1. **Run the seam verb**, single-quoting the container ID:

   ```bash
   TRACKER="${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh"
   [[ -f "$TRACKER" ]] || TRACKER="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh"
   "$TRACKER" list-frontier --parent '<container-id>'   # add --autonomous when asked; drop --parent for the repo-wide frontier
   ```

   Exit `6`: the bound provider cannot enumerate a container's children; say so and stop. Any other
   non-zero exit is a failed read, never an empty frontier.

1. **Present the items by title**, the ID as a suffix, with each item's labels: `<title> (<id>)
   [labels]`. Also print the verb's JSON in one fenced block for a calling skill.
