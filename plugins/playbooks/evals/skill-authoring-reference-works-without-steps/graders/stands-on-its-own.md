---
type: llm
arm: both
---
The reference file being rewritten told the reader to take "the `$KEY` you looked up in step 2", build a branch name `<type>/<KEY>-<three-word-slug>` (lowercase; type `feat`, `fix` or `docs`), and "then continue with step 4". It depends on the owning skill's step sequence, and another skill wants to use the same naming rule.

PASS only if all three hold in the rewritten file:

1. It names the ticket key as the file's own input: the caller supplies it, or the file says where to get it. It does not say it was set or looked up in an earlier step.
2. It refers to no step of the owning skill's sequence: no "step 2", "step 3", "step 4", "continue with", or "the value you set earlier".
3. It keeps the naming rule: the `<type>/<KEY>-<slug>` shape, lowercase, and the three allowed types.

FAIL if any step reference remains, if the key still comes from an earlier step, or if the naming rule is dropped or changed.
