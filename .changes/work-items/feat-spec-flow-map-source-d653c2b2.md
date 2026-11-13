---
bump: minor
---

### Added

- `track view` takes `--comments` and adds the item's comments to its JSON block, read through the adapter's paginated comment recipe, so another plugin can read a decision recorded in a comment without a provider command.
- `decompose` attaches native sub-items whenever its source is a tracker item: the created items become children of the source item, or, when a spec container is also published, the container sits under the source item.
- `decompose` closes its report with how the items run: at the keyboard, `/work-items:ship run` on the published container; otherwise the agent-ready items are left for the lanes.

### Changed

- `decompose` writes every tracker link as the item's title linked to its absolute URL, never a bare `#<n>`. The `## Parent` line keeps its `Refs #<parent>` opening, which the decomposed-parent close in `track done` and `track audit` still matches.
