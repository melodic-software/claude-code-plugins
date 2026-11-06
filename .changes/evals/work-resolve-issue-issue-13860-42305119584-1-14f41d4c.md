---
bump: patch
---

### Fixed

- `/evals:validate` (`validate-cases.py`) FAILs a case.yaml `context.history_file` with more than one record unless the records form one chain: a `uuid` on each, `parentUuid: null` on the first, and the previous record's `uuid` on each later one. An unchained transcript loads, but the resume walks `parentUuid` back from the last record, so the run resumes with only the last record and silently drops every earlier turn the case depends on. A record that is not JSON also FAILs.
