---
bump: patch
---

### Fixed

- **`pull-request` `create` writes the `Siblings:` line when a pull request closes an issue that earlier pull requests delivered part of** ([#13068](https://github.com/melodic-software/claude-code-plugins/issues/13068)). The new `scripts/siblings-line.sh` lists the merged pull requests whose body has a `Refs: #N` line for an issue the pull request closes and that close no issue, the 10 newest. §2.4.0 then writes `Siblings: #<a>, #<b>` directly below the closing line, so pr-verify judges the diff only for what those pull requests left. With none, no line is written.
