# Action: `edit`

Change an existing item: its title or body, its labels, a blocked-by edge, or add a comment. The
entry point for another plugin that maintains items it filed (a decision map's index, a rewritten
question) without naming a tracker's commands.

## Usage

```
/work-items:track edit <id> [--repo <owner>/<repo>] [--title-file <path>] [--body-file <path>] [--add-label <name>]... [--remove-label <name>]... [--blocked-by <id>] [--comment-file <path>]
```

`<id>` follows `view`'s rules ([view.md](view.md)). At least one change flag is required.

## Workflow

> **Authorization gate.** An edit changes a shared record. Run it on the user's explicit request,
> or as a step of a skill the user invoked that names this edit. Never on inferred intent.

1. **Validate** the reference as `view` does. Texts (title, body, comment) travel in files written with the Write tool,
   never typed into a command, because a body can hold quotes, backticks or `$()`.

1. **Labels first.** Check each `--add-label` against the live set (`labels <name> ...`,
   [labels.md](labels.md)); a missing one stops the edit before anything changes, reporting the
   full missing set.

1. **Apply each change**, in this order, stopping at the first failure and reporting what already
   applied:
   - `--title-file`, `--body-file` (adapter: "Edit title / body"). `--body-file` replaces the whole body;
     to change part of it, read it with `view` first and write back the whole result.
   - `--add-label`, `--remove-label` (adapter: "Edit labels / assignees").
   - `--blocked-by` through the seam, both IDs qualified:

     ```bash
     TRACKER="${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh"
     [[ -f "$TRACKER" ]] || TRACKER="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh"
     "$TRACKER" link-blocks '<id>' --blocked-by '<blocker-id>'
     ```

   - `--comment-file` (adapter: "Comment on item").

   Every write, and the label check, targets the item's own repository: the `<owner>/<repo>` of
   the qualified ID (or `--repo` for a bare number), passed as the adapter recipe's `--repo`, never
   the current checkout, which may hold a different item with the same number. Writes route
   through the adapter's identity policy. A provider whose operations reference has no
   section for a requested change cannot make it: say so for that change.

1. **Confirm** each applied change in one line.

Closing an item is `done`, claiming it is `start`; `edit` does neither.
