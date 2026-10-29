---
bump: patch
---

### Added

- Eval cases `t1-setup-init` and `t2-setup-rerun`, ported from setup scenarios T1 and T2 of the eval scenario sources onto the shared tarnquill fixture, bare and converged. T1 grades setup apply with free graders: the conventions reach AGENTS.md and no scaffold AGENTS.md line changes, and in the plugin arm the conventions file exists with its front matter and section markers, names only fixture files, and AGENTS.md gains only the managed block with one pointer line. Two plugin-arm `llm` graders, whose samples are the labeled T1 C2 and C3 sets, check that the conventions name only real commands and keep `tq commit` interactive. T2 grades a re-run that leaves both files byte for byte as seeded, with no `Write`, no `Edit`, and no Bash call that writes or deletes a file, including one inside a compound command. ([#9988](https://github.com/melodic-software/claude-code-plugins/issues/9988))
