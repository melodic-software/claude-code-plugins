# Action: `labels`

List the labels the tracker has, or report which of a named set are missing. Read-only: it never
creates a label.

## Usage

```
/work-items:track labels [<name> ...]
```

## Workflow

1. **Read the live set** (adapter: "List labels", bare read). A provider with no label listing
   (`local-markdown`, read-only `jira`) cannot answer: say so and stop.

1. **Without names**, print the set, one label per line. **With names**, print each missing one as
   `MISSING: <name>` and nothing else; no output means every name exists. Compare exact strings.

A missing label goes to whoever the consuming repository names as its label owner (a label-as-code
source of truth, or the user). Report the full missing set at once.
