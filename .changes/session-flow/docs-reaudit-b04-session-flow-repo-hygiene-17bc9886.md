---
bump: patch
---

### Changed

- Skill bodies point at the live Claude Code docs sections for upstream behavior they used to
  restate (print-mode permission prompts, nested-session listing, command invocability, where a
  plugin variable expands, bare-mode credentials, subagent model and resume rules), and fix five
  internal inconsistencies: the handoff shape `continue-in-background` validates, the shapes that
  store a resume prompt in `find-handoff`, the "Suggested skills" section reference in
  `recommend-skills`, the workflow router's invocability wording, and the stage-skip rule's scope
  in the workflow checklist. No behavior change.
