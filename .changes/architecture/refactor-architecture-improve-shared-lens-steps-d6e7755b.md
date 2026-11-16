---
bump: major
---

### Removed

- **`/architecture:improve layout`.** The layout lens is no longer an action of
  `/architecture:improve`; run `/architecture:improve-layout` instead, with the same `--path` and
  one-run settings. `improve` keeps the `deepening`, `boundaries` and `conventions` lenses.

### Added

- **`/architecture:improve-layout`.** The co-change layout check as its own skill: the co-change
  script, its tests, its measures reference and its eval cases moved with it, and its trigger
  phrases ('do files that change together live together', 'co-change layout') moved from
  `improve`'s description to its own.
- **`reference/improvement-steps.md`.** One file owns the steps every lens takes the same way:
  base freshness, scope and fan-out, recorded decisions, the convention home with one table of the
  resolver's exit codes, the memory-tier write rules, badge bands and the hand-off. The lens
  playbooks cite it by section instead of citing the deepening playbook.
- **`improve`'s roster test.** `skills/improve/scripts/lens-roster.test.sh` fails when a lens
  playbook has no Actions-table row or `argument-hint` entry, or a row or entry has no playbook.

### Changed

- **Convention home in `boundaries` and `conventions`.** Both now read the architecture topic doc
  under the default home, `docs/conventions`, when the resolver exits 1 (no pointer) or 4 (home
  declined), as the settings cascade and the layout check already did; before, they read nothing
  on any exit but 0. Writes still happen only on exit 0.
- **Memory-tier writes in `deepening` and `improve-layout`.** They now follow the rules `boundaries`
  already had: no file when the memory root is the repository root or the slice name cannot be
  formed, never overwrite (`-2`, then `-3`), and a refused write puts the content in the report.
- **Scope in `conventions`.** Its scan now scopes as the other lenses do: a given spec or plan sets
  the areas, and the history step leaves out `[bot]` authors.
- **Roster.** The plugin description, the README and `improve`'s description, argument hint,
  summary, Purpose, reference index and `## Next` name the lenses that exist; "Adding a lens" lists
  every place a new lens must be added.
- **Plugin root in the `boundaries` and `conventions` playbooks.** The resolver call is written
  with the `<plugin-root>` placeholder `improve`'s `SKILL.md` renders, not a variable a read file
  does not expand.
