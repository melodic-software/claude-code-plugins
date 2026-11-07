---
bump: minor
---

### Changed

- `save_point.py validate` fails an Open questions or Decisions in force entry without a `[Q<n>]` / `[D<n>]` id when the predecessor already carries the `next_question_id` / `next_decision_id` floor; chains started before the floors still validate. The goal, trail, question and decision slot texts name the `retire` refs, the retire headings and the ids (#13847).
- `/session-flow:handoff` checks each task notification, Monitor event, peer message or subagent result that lands after emit and until `/clear`, folds one that changes a section in with `save_point.py amend`, and ends the turn on the re-emitted rails. An amendment unit with a still-binding clause stays whole or is codified as `[R<n>]` first; a rule or preference leaves the hot file only when retired or promoted, never to meet the size cap. The save-point and structure references describe `amend`, the append-only hop file, the four retire headings, the ids and the retire pointer (#13847).

### Added

- Resume-eval cases `re-writer-keeps-binding-amendment` and `re-retired-amendment` on shape-3 predecessors, and the plugin-eval case `ho-late-event-amends` (#13847).
