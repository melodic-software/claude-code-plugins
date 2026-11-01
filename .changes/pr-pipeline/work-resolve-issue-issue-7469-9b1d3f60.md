---
bump: minor
---

### Changed

- `merge.rung` takes names for what each rung needs before the merge authority merges: `off`, `merge` and `merge-reviewed`. `C2` and `C3` stay accepted as aliases for `merge` and `merge-reviewed`, and each conditional rung requirement applies to both spellings. The example and this repository's config use `merge`, and the README names the rung first with its code in parentheses ([#7469](https://github.com/melodic-software/claude-code-plugins/issues/7469)).
