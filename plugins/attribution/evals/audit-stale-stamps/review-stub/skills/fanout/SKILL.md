---
description: "Eval-only stand-in for the review plugin's fanout: breadth review of a change, one ranked report on disk."
user-invocable: true
disable-model-invocation: false
---

# Fanout (eval stand-in)

## Shared inputs

- **Findings location**. `<memory_dir>/reviews/<branch-slug>/`, never committed. `<memory_dir>` is
  `.work/`. `<branch-slug>` is the branch name lowercased, with `/` and every other
  non-`[a-z0-9._-]` character replaced by `-`. The first write verifies the memory root contains a
  `.gitignore` with `*`, creating it when absent.
