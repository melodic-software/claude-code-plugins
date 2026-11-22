---
bump: major
---

### Added

- `git-hooks/lint-full.sh --base <ref>` lints the scripts over 2,000 lines the branch changes from HEAD's merge-base with `<ref>`, pushed commits included. The pre-PR check and CI run it this way.

### Removed

- The `lint-full` pre-push git-hook entry. At 11.8 s on a 44-file change it is over the check-placement convention's 3 s push budget, so `/source-control:pull-request` runs `git-hooks/lint-full.sh` in its pre-PR check instead. A lefthook remote stops running it on its next fetch; a local or shared copy an earlier `apply install-git-hooks` installed keeps running until you remove it: delete the `pre-push.d/bash-format.lint-full` marker and the `bash-format/lint-full.sh` copy under `git rev-parse --git-path hooks`, a `bash-format-lint-full` job in `lefthook.yml` or `lefthook-local.yml`, a `.husky/pre-push` line that runs `lint-full.sh`, and `.githooks/bash-format/lint-full.sh` (the README's "Git hook entries" section lists the same).
