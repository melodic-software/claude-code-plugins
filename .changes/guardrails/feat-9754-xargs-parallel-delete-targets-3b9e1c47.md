---
bump: minor
---

### Added

- `block-root-delete-target` judges `xargs` and `parallel` running a recursive `rm` or a deleting `find` ([#9754](https://github.com/melodic-software/claude-code-plugins/issues/9754)). The command's own operands and parallel's `:::` items are judged as written. Items read from a pipe are judged only when a confined listing produced them: a `find` without `-printf`, `-ls` or an `-exec`-family action has its start points judged, and `git ls-files` is judged as a name under the directory it runs from, through `grep`, `sort`, `uniq`, `head` or `tail` at most. Items from a file, from the shell's own stdin or from any other command are refused, so `cat list | xargs rm -rf` is refused and `find build -name '*.o' | xargs rm -rf` passes.
