---
bump: major
---

### Changed

- **Breaking:** a recurring item links to its `.github/recurring-schedule.json` row by one body line, `<!-- recurring-schedule id=<row id> -->`, plus the recurring-maintenance label, never by title ([#13839](https://github.com/melodic-software/claude-code-plugins/issues/13839)). `track add --recurring` titles the item with the row's `title` verbatim and writes the marker; `track due`, `recheck`, `done`, `audit`, `work`'s recurring tiers and `setup`'s row reconciliation match by the marker's id. `setup` retitles an open item when its row's `title` changes and rewrites its marker when the row's `id` changes.

  Migration: an open item still titled `[Maintenance] {title}` with no marker is no longer matched, so the next `due` or `work` pass reports its row orphaned or files a duplicate. Add the marker line for its row's `id` to each such item's body, and retitle it to the row's `title`. Anything else that files recurring items, such as a scheduled workflow, must write the marker as well.
