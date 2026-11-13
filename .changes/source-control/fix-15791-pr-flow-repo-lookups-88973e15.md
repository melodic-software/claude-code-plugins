---
bump: patch
---

### Fixed

- `/source-control:pull-request ready` resolves the repository and branch from `<checkout>` (`target-repo.sh --dir`, `git -C`), reads the base's rules, branch protection and reviews from `$REPO` instead of gh's `{owner}/{repo}` placeholders, and passes `--repo "$REPO"` to `review-venue.sh`. The GitHub review-venue reference names `<owner>/<repo>`, the script's `--repo` value.
- The shared review discipline's D5–D7 commands name `<owner>/<repo>` (`gh api` paths and `gh pr comment -R`), and its fix-commit check passes `--dir "<checkout>"` to `resolve-remote.sh` and runs git with `-C "<checkout>"`, as the monitor reference's copy does.
