---
bump: minor
---

### Added

- `/app-control:map check` reports where a control skill breaks the contract and edits nothing. A bundled script prints one `<rule> | <path> | <detail>` line per structural finding: an index line that is dead, duplicated, missing or miscounts its entry points, a source glob that matches no file, a feature README whose sections are missing, extra or out of order, an entry point with no `driven` marker or a `not driven` with no reason, a relative link that resolves to nothing, and a `shared/` item used by fewer than two features or lacking its `Why shared:` line. The model then reports any section that copies a recipe instead of naming it. The report carries no verdict word.
- The control-skill contract gains a "Shared items" section: `shared/` holds only what two or more features use, each item a direct child of `shared/` that a feature uses by naming `shared/<item>`, with a `Why shared: <reason>` line in its `README.md` or in the file itself.
