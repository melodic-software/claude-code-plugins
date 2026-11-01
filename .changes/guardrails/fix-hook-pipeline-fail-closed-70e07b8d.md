---
bump: patch
---

### Fixed

- The reference-verify pre-push check now fails, naming the tool and saying the change was not fully checked, when git or awk fails while it lists the lines a copied file adds, merges them into the changed lines, or narrows a branch that merged the default branch to its own lines. A crash in any of those steps used to leave findings filtered out and the push passing; the check now keeps the wider set of lines instead.
