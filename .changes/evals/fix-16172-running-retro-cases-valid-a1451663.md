---
bump: patch
---

### Fixed

- `run-validity.py`: a denied Read, Grep, Glob or read-only Bash pipeline aimed only at the
  session's own transcript, `<sandbox>/config/projects/<project>/<session_id>.jsonl` or its
  `<session_id>/subagents/`, the id read from the trace's init line, is set aside as a warning
  like a read of the session's own tool results. A listing or glob of the projects tree, another
  session's file, or a compound call with any other part still counts.
