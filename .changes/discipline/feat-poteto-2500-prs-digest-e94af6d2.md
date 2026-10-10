---
bump: minor
---

### Added

- `/discipline:reuse-or-replace` reads the project's paved-path file on demand: when the standards index has a `paved-path` row and the work touches a concern it lists, the listed entry is the established way, and replacing it includes updating the entry.
- **`/discipline:script-the-deterministic-work lever-check <block summary>` and the `lever_scope` setting: `deterministic` (default) or `non-trivial`.** The mode answers `build-a-lever` or `edit-by-hand`, with its reason, for one change repeated across sites; `/implementation:implement` and `/implementation:implement-dispatch` call it before a multi-site block or a fan-out. `deterministic` builds a lever only for a mechanical change; `non-trivial` also builds one for judgment-bearing changes, using an established codemod or refactoring tool and never a refactoring script written for the occasion. Under either value the first site is edited by hand and the lever's result on it is diffed before the lever runs on the rest; for a fan-out the mode also answers whether one run of the lever covers every unit. `lever_scope` is set per user in the new user config option and per repository in `docs/conventions/discipline.yaml`, which wins; the schema ships at `schemas/discipline.schema.json`, and the new `reference/config.md` lists the key, its layers and the root rule. An invalid value is named with its file, key and value and that layer is dropped. The skill gains a `## Next` section and six eval cases.
- **`/discipline:setup apply lever_scope=<value>` writes `docs/conventions/discipline.yaml`.** `check` also reports `lever_scope` and the repository file (absent, valid, or each problem as a WARN); `apply` validates the whole result against the schema before writing, refuses a duplicate key, an empty or non-scalar value, a key outside the schema, a parse error, a symlinked, hard-linked or out-of-repository path, and a root that is `$HOME` or above it, writes through an exclusive temp file and a rename, and shows a diff and asks before it changes an existing file. Personal options still change only through `/plugin configure`.

### Changed

- **`/discipline:wait-what` states its description and opening instruction in this repository's own words.** A word-overlap check against the skill it was adapted from found both still followed the original's sentences. Behavior is unchanged: re-explain from the missing premise, in ASD-STE100 Simplified Technical English, with the project's domain terms.
