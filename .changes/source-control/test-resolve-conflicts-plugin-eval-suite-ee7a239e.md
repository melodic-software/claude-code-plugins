---
bump: patch
---

### Added

- **A `claude plugin eval` suite for `/source-control:resolve-conflicts`.** Seven cases tagged `row22`, each scaffolding a git repository that is stopped in a real conflict: a two-stop rebase, a six-file merge where the prompt asks for `--ours` or abort, a merge with a conflict that has no markers, a cherry-pick, a merge whose incoming tip never touched the file, a revert, and a merge with only "sort it out" as the prompt. Most graders are deterministic: the resolved file contents, history read before the first edit, tests run before the operation concludes, and the concluding reflog line. They also cover the "It's working if" checks from the archived upstream skill page. Three cases add one model-judged grader each, and every grader carries pass and fail samples. The skill body is unchanged.
