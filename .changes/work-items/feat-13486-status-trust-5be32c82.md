---
bump: minor
---

### Added

- The GitHub `get-statuses` read counts a Work status value only from a trusted setter when the binding sets `config.github.status_trust` (trust list, model and lanes App): a listed human or the lanes App for any state, a `models.issue-status` bot-setter for every state but `agent-ready`. The newest counted field event decides. A missing or invalid trust configuration exits `3`, so `list-frontier --autonomous` fails closed on it.

### Changed

- `attend-queue`, `triage`, `work-loop` and `work` read an item's status through one rule in the tracker seam reference ("Reading an item's status"): on Work status field storage an item is held by its hold label or its held status, and a set value places it in a queue over a disagreeing label. A person lifting a hold also writes the field: `attend-queue`'s flip sets `agent-ready`, `triage`'s sweep sets `confirmed`. The work-loop drain snapshot reads Work status, and a failed autonomous frontier read stops candidate selection instead of reading as an empty frontier.
- `morning-brief` reads the Work status field when the target repo's `docs/conventions/pr-pipeline.yaml` holds `models.issue-status`: Queues, Stuck and Parked place each open issue by its value when set, else by its labels, hold labels still holding, and Owner touches count the field's changes. It reads the plain value, with no setter check. Over REST, Queues and Parked print by label with a `PARTIAL` line; a failed field read, or a value the model has no option for, is `UNREADABLE`. A new `--status-json` fixture flag feeds the read.
