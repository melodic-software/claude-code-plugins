# Action: `link`

Return the text that links a change to a work item, from the bound adapter. This is the entry
point for another plugin, such as `/source-control:pull-request`, that must not write a tracker's
grammar itself. Read-only.

## Usage

```
/work-items:track link <id> [--repo <owner>/<repo>]
/work-items:track link --branch <name> [--repo <owner>/<repo>]
/work-items:track link --branch-ref <ref> [--repo <owner>/<repo>]
```

`--repo` is the repository the change lives in. `--branch` resolves the item through the adapter's
branch grammar; `--branch-ref` takes a token the caller already captured with its own convention.

## Workflow

1. **Resolve the link.** Run the seam verb with the arguments as given:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh" change-link <args>
   ```

   Exit `5` (the branch names no item) or `2` (a token the provider cannot qualify, such as a
   number on a Linear binding): report "no linked item" and stop. Exit `6`: the bound adapter
   predates `change-link`; say so and stop, so the caller keeps its own default. Exit `3`: no
   tracker binding; say so and stop.

1. **Check the item is open.** When the manifest supports `get-item`, run
   `work-item-tracker.sh get-item <item_id>` and take its `state`. Exit `5` means the item does
   not exist: report `state: "missing"`. Otherwise report `state: null` (unchecked).

1. **Print one fenced JSON block**: the `change-link` object plus `state`, for example
   `{"item_id":"github:acme/webapp#42","closes":"Closes #42","refs":"Refs: #42","branch_ref":"42","state":"open"}`.

The caller writes `closes` only for an open item; `closes: null` means a merge never closes the
item on this provider, so it is closed with `/work-items:track done` after the merge. Field
meanings: `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md` "Change links".
