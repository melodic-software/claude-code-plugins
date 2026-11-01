---
bump: minor
---

### Added

- The commit-convention gates, `block-convention-violation` and the `commit-msg` hook, enforce an operator's own `subject_pattern` in a repository whose team tracks none. The pattern lives in `docs/conventions/source-control.local.yaml`, which the resolver reads only while git ignores it (a `.gitignore` rule, `.git/info/exclude` or `core.excludesFile`) and only when the team layer supplies no `subject_pattern`. It is never merged with a team pattern: a team pattern always wins, and a broken or non-ERE team value disables enforcement rather than falling back to the personal one. PR titles never read it. A personal file git does not ignore, a tracked one included, is reported and not read. When the personal pattern rejects a subject, the `commit-msg` hook names the personal file to edit instead of asking for a pull request, and `block-convention-violation`'s pattern cache re-resolves when the file appears or changes.

### Changed

- `block-convention-violation` reports a rejected commit subject as not matching "the commit convention" rather than "the team convention", and asks for a subject that matches the printed pattern, since the pattern may be the operator's own and `/source-control:commit` drafts against the team convention only.
