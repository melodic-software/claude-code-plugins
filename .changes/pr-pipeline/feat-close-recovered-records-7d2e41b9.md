---
bump: minor
---

### Changed

- The `close-cleared` job runs on every completed scheduled full run on main, whatever it concluded. It closes each open, never-edited schedule or dispatch record that a later green full run on main cleared by the merge gate's own rule (`_recovered_at`): attempt 1, a schedule or a `github-actions[bot]` dispatch, created after the record, at a commit ahead of its SHA and on main. Before, only the triggering green scheduled attempt 1 could clear a record, so records that a dispatched green run had cleared stayed open.
