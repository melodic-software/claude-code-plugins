---
bump: patch
---

### Fixed

- `run-validity.py` treats a denied tool call in an invocation-probe case as a warning unless the denied call is the Skill call itself. The probe grades only whether that call fired, and loading a skill needs no Read, Glob or Grep, so trigger-measurement runs no longer fail validity when the agent searches outside an empty workspace.
