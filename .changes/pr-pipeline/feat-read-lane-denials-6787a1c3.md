---
bump: patch
---

### Changed

- The skill-run diagnostics in both run-activity files (`act-turns.json` and the step summary) record `denied` as one `{tool_name, input}` per denied call, where `input` is the call's command, `file_path`, `path` or `pattern` cut to 300 characters; the read file gains `denied`, and a denied Read, Grep or Glob call now keeps its path or pattern. The step summary shows each as `tool: input`. In a PR-mode read run, `denied` travels in the sealed `act-turns.json` and reaches the step summary only after the scan job's leak scan.
- The `skill-reply-*` artifact is kept 7 days instead of 3 in both run-activity files, matching the patch and dependency-verdict artifacts.
