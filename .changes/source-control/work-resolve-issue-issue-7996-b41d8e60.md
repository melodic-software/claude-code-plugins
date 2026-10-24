---
bump: none
---

### Changed

- The offline gh stand-in used by the pull-request evals now serves `gh pr merge`, `gh pr review`, `gh api user`, `gh search prs` and `gh api graphql` for review threads, so babysit eval cases never reach real GitHub. `pr merge`, `pr review` and a resolve-thread mutation only append a record to the forge state for a grader to read; `install.sh --thread <id>` seeds the review threads. Every other command still exits 1.
