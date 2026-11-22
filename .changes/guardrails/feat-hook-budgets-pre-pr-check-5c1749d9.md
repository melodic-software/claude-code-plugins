---
bump: major
---

### Removed

- The `reference-verify` git-hook entry. At about 10 s on a 44-file change it is over the check-placement convention's 3 s push budget, so `/source-control:pull-request` runs `git-hooks/reference-verify.sh` in its pre-PR check instead. `pre-push-content` is the one pre-push entry left. A lefthook remote stops running it on its next fetch; a local or shared copy an earlier `apply install-git-hooks` installed keeps running until you remove it.

### Changed

- A cli-flag finding names `git config checks.guardrails.reference-verify.declined true` as the way to stop the check in a clone.
