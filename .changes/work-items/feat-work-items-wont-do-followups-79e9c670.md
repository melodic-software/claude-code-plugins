---
bump: minor
---

### Added

- **Won't-do blockers.** The triage attention view has a fourth bucket, "blocked by won't-do": open items whose `blocked_by_wont_do_count` is above zero, whatever labels they carry, reported for the operator to drop the edge, re-scope, or close. The triage board accepts it as a `state`, and `/work-items:attend-queue` lists those items as report-only `[won't-do]` rows, taking `[intake]` from buckets 1-3 only.
- **Won't-do detection follows each tracker's own vocabulary, with no built-in list.** Jira: the optional team binding key `config.jira.resolutions` (`{"completed": [ids], "wont_do": [ids]}`) classifies resolution ids, so a renamed resolution keeps its class. Absent, detection is off and no lookup is made. Present, the adapter reads done blockers' resolutions in one extra search, counts a `wont_do` id as won't-do, and keeps a blocker with an unclassified id, a failed lookup, or a missing search result blocking, with a stderr warning. GitHub: the optional key `config.github.wont_do_labels` makes a closed blocker carrying a listed label (case-insensitive) won't-do whatever its close reason. `/work-items:setup apply` lists the Jira instance's resolutions or the repo's labels and writes the key only from the user's choice; `check` reports Jira resolutions the binding does not classify.
