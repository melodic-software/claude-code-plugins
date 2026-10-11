---
bump: minor
---

### Added

- **`explain_starting_rung` sets where `/education:explain` starts.** `plain` (the default) keeps
  today's ladder: an everyday analogy first, higher rungs on request. `peer` starts at rung 3 with
  one precise sentence of definition and full detail, and offers the plain version instead of a
  higher rung. Set it per user in `userConfig` or per repository in
  `docs/conventions/education.yaml` (schema `schemas/education.schema.json`), which wins and is
  read through a bundled copy of the shared reader. The reply's last line names the value and the
  layer that supplied it; a value outside the two is named with its file and key, that layer is
  dropped, and the run continues. Keys: `reference/config.md`.
- **`/education:setup apply` writes `docs/conventions/education.yaml`.** It writes only the keys
  named on the command line, after validating each value and the whole resulting file against the
  schema. An existing value that is empty, null or outside the list is replaced; a key set twice, an
  empty quoted string, a non-scalar value, a symlinked or hard-linked path, or a directory or file in
  the way is refused with one line and nothing written. Changing an existing
  file shows a diff and needs the operator's yes. `check` now also validates that file and reports
  the effective `explain_starting_rung`. The `userConfig` options still change only through Claude
  Code's plugin configuration prompt.

### Changed

- **`/education:explain` grounds a codebase subsystem through the discovery skills and drops
  framing labels.** When `/discovery:explore` and `/discovery:trace-intent` are available, an
  explanation of a subsystem uses explore's walkthrough for what the code does and trace-intent for why,
  keeping trace-intent's hedges on inferred reasons; without them it reads the files itself. The
  reply carries no framing labels, pacing narration or comprehension questions; the one-line rung
  offer and the `/education:teach` handoff line stay.

- **`/education:teach` workspace formats are written in this repository's own words.** A word-overlap check against the skill they were adapted from found long runs of its text in `context/mission.md`, `glossary.md`, `resources.md` and `assessment.md`, and in the lesson definitions in `pedagogy.md` and `lessons.md`. Each file now states the same rules with its own wording, order and examples; `pedagogy.md` drops a quoted phrase. File names and the rules themselves are unchanged; the template headings changed in the next entry.
- **`/education:teach` mission, glossary, resources and assessment formats are reorganized around how the skill coaches.** `context/mission.md` maps each opening-interview question to the part of the file it fills and uses a Result, Checks and Boundaries template; `glossary.md` becomes an entry procedure with a one-row-per-term table; `resources.md` opens with the readers that use the file, turns its trust rules into admission tests a source must pass, and uses Knowledge and Wisdom tables and a Not Yet Covered list; `assessment.md` lists the evidence each coaching moment (dialog, exercise, quiz, session close) produces and moves the `Status: superseded by` line into its Supersession section. Workspaces written in the earlier layout are read as they are and converted when next edited. Every rule, the `# Mission: {Topic}` title, the `Repo Sources` heading and the supersession status line are unchanged.

### Fixed

- **`/education:setup` runs the shared `lib/setup-apply.mjs`.** A key the schema does not list in `docs/conventions/education.yaml` is named in one warning and ignored: `--check` still prints the valid keys (exit 1), and `apply` writes beside it and keeps its line as written; such a key set twice or holding a map or list is still refused. A symlinked `--root` is resolved first and every path check applies to the resolved directory, `apply` and `--check` now refuse a root that is `$HOME` or an ancestor of it, a CRLF file is written back with CRLF instead of being read as a key set twice (one mixing CRLF and LF is refused), and the shared parser now refuses a tab indent and an unquoted colon followed by a space in a value (`key: a: b`).
