---
bump: patch
---

### Fixed

- **plugin-eval:** the validity gate now warns, instead of failing, on a denied `Read`, `Grep` or `Glob` aimed only at or under the plugin's directory. A negative control's broken copy makes this call when it searches itself for the text it lacks, which had left the broken side unmeasured. The warning applies only when the run's trace has a result line that is not an error and none that is, no `tool_used` grader of the case names that tool, and the case is not an invocation probe. A Bash call, a write, a path above or outside the plugin, and a `Glob` pattern holding `..` still fail. Compare a score taken under such a denial only with runs denied the same way.
