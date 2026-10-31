---
bump: minor
---

### Changed

- The `Stop` row now checks the Markdown in the uncommitted changes by default and reports what it finds to you. With `markdown_format_end_of_turn` unset, its new default, a turn that ends with markdownlint findings shows them in a warning (exit 0 with a `systemMessage`) and the turn ends; Claude does not see them. `true` keeps the hand-back: the findings exit 2 and Claude keeps working, at most once per turn. `false` runs no check. The option no longer declares `default: false`, and its launcher gate is now `--run-if-unset-or-true`, so a user who never set it gets the report. ([#11502](https://github.com/melodic-software/claude-code-plugins/issues/11502))
