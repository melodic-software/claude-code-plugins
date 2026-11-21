# Action: `dossier-branches`

Run the dossier-branch step for one owning item: delete its remote dossier branch when the user
confirms, or report it. For `/planning:wayfind`, whose map closes on a route that creates no
container.

## Usage

```
/work-items:track dossier-branches <item-id> [--unattended]
```

## Workflow

1. **Run the step** in
   [`reference/dossier-branch-step.md`](../../../reference/dossier-branch-step.md)
   with `<item-id>` as the one owning item: its branch is the one whose name starts
   `<prefix><key>-`. `--unattended`, or a run with no operator turn, deletes nothing.

1. **Print the step's report**: each branch deleted, each due for deletion, and each skipped, with
   the reason. The caller posts it; this action writes no comment.
