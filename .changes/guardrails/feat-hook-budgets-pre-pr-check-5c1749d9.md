---
bump: major
---

### Added

- `git-hooks/reference-verify.sh --base <ref>` checks every commit from HEAD's merge-base with `<ref>`, pushed ones included. The pre-PR check and CI run it this way.

### Changed

- A cli-flag finding names `git config checks.guardrails.reference-verify.declined true` as the way to stop the check in a clone.

### Removed

- The `reference-verify` git-hook entry. At about 10 s on a 44-file change it is over the check-placement convention's 3 s push budget, so `/source-control:pull-request` runs `git-hooks/reference-verify.sh` in its pre-PR check instead. `pre-push-content` is the one pre-push entry left. A lefthook remote stops running it on its next fetch; a local or shared copy an earlier `apply install-git-hooks` installed keeps running until you remove it: delete the `pre-push.d/guardrails.reference-verify` marker and the `guardrails/reference-verify.sh` copy under `git rev-parse --git-path hooks`, a `guardrails-reference-verify` job in `lefthook.yml` or `lefthook-local.yml`, a `.husky/pre-push` line that runs `reference-verify.sh`, and `.githooks/guardrails/reference-verify.sh` (the README's "Git hooks" section lists the same).
