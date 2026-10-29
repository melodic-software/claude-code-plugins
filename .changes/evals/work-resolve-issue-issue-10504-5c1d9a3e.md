---
bump: patch
---

### Fixed

- **plugin-eval:** the validity gate's new `scaffold` check marks a run INVALID when a case's `case.yaml` sets `context.scaffold_script` and the gate was not given `--scaffolded`. Without `--scaffold` the eval skips such a case's script, both arms run in an empty workspace, and the gate had still printed `verdict: VALID`. Pass `--scaffolded` when the eval ran with `--scaffold`, since no documented result field records it. A `case.yaml` or case directory the gate cannot read, or a result with no suite root or case directory to find it by, leaves the check unchecked. A `case.yaml` that starts with a UTF-8 byte order mark, or puts the `scaffold_script` value on the next line, still counts as setting a script. ([#10504](https://github.com/melodic-software/claude-code-plugins/issues/10504))
