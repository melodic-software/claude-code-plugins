# Action: `changes`

List the change requests (pull requests, merge requests) the tracker links as closing an item, in
any state: the entry point for a skill that derives what shipped for an item or what is still in
flight. Read-only.

## Usage

```
/work-items:track changes <id> [--state open|merged|all] [--repo <owner>/<repo>]
```

`<id>` and `--repo` follow `view`'s rules ([view.md](view.md)). `--state` defaults to `all`.

## Workflow

1. **Validate the reference** as `view` does.

1. **Read the linkage** (adapter: "Linked changes", bare read). This is the provider's own computed
   close-linkage, not a text match: a change that only references the item (`refs`, in
   `change-link` terms) is not in it. When the bound adapter's operations reference has no "Linked
   changes" section, say the provider exposes no close-linkage and stop.

1. **Print one fenced JSON array** of `{"number", "url", "state", "isDraft"}`, `state` one of
   `OPEN`, `MERGED`, `CLOSED`, filtered by `--state`. A failed read exits with its error and is
   never reported as an empty array: a caller that reads a failure as "no changes" concludes an
   item shipped nothing.

Change titles are not returned; read a change's own facts through the forge (for example
`/source-control:pull-request view <number>`).
